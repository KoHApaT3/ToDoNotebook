import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main(List<String> arguments) {
  final ArgParser parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      defaultsTo: false,
      negatable: false,
      help: 'Показать помощь',
    );

  // Subcommands
  final ArgParser addCmd = ArgParser()
    ..addOption('file', abbr: 'f', help: 'Путь к .txt файлу книги')
    ..addOption('title', abbr: 't', help: 'Название книги (по умолчанию — имя файла)')
    ..addOption('author', abbr: 'a', help: 'Автор книги (необязательно)');

  final ArgParser showCmd = ArgParser()
    ..addOption('id', help: 'ID книги', valueHelp: 'ID', mandatory: true)
    ..addOption('lines', abbr: 'n', help: 'Сколько строк показывать', valueHelp: 'N', defaultsTo: '25');

  final ArgParser nextCmd = ArgParser()
    ..addOption('id', help: 'ID книги', valueHelp: 'ID', mandatory: true)
    ..addOption('lines', abbr: 'n', help: 'Сколько строк пролистать вперёд', valueHelp: 'N', defaultsTo: '25');

  final ArgParser prevCmd = ArgParser()
    ..addOption('id', help: 'ID книги', valueHelp: 'ID', mandatory: true)
    ..addOption('lines', abbr: 'n', help: 'Сколько строк пролистать назад', valueHelp: 'N', defaultsTo: '25');

  final ArgParser progressCmd = ArgParser()
    ..addOption('id', help: 'ID книги (если не задан, показать прогресс по всем)');

  final ArgParser removeCmd = ArgParser()
    ..addOption('id', help: 'ID книги для удаления', valueHelp: 'ID', mandatory: true);

  parser
    ..addCommand('add', addCmd)
    ..addCommand('list')
    ..addCommand('show', showCmd)
    ..addCommand('next', nextCmd)
    ..addCommand('prev', prevCmd)
    ..addCommand('progress', progressCmd)
    ..addCommand('remove', removeCmd);

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Ошибка парсинга аргументов: $e');
    _printUsage(parser);
    exitCode = 64; // EX_USAGE
    return;
  }

  if (argResults['help'] == true || argResults.command == null) {
    _printUsage(parser);
    return;
  }

  // Ensure DB and run the selected command
  final File dbFile = _getDatabaseFile();
  dbFile.parent.createSync(recursive: true);
  final Database db = sqlite3.open(dbFile.path);
  try {
    _ensureMigrations(db);
    switch (argResults.command!.name) {
      case 'add':
        _handleAdd(db, argResults.command!);
        break;
      case 'list':
        _handleList(db);
        break;
      case 'show':
        _handleShow(db, argResults.command!);
        break;
      case 'next':
        _handleNext(db, argResults.command!);
        break;
      case 'prev':
        _handlePrev(db, argResults.command!);
        break;
      case 'progress':
        _handleProgress(db, argResults.command!);
        break;
      case 'remove':
        _handleRemove(db, argResults.command!);
        break;
      default:
        _printUsage(parser);
        break;
    }
  } finally {
    db.dispose();
  }
}

void _printUsage(ArgParser parser) {
  print('BookLib — простая CLI-библиотека для чтения .txt книг на SQLite');
  print('Использование:');
  print('  booklib <команда> [опции]');
  print('Команды:');
  print('  add       — добавить книгу из .txt файла');
  print('  list      — список книг');
  print('  show      — показать текущую страницу без изменения прогресса');
  print('  next      — показать следующую страницу и сохранить прогресс');
  print('  prev      — вернуться на страницу назад и сохранить прогресс');
  print('  progress  — показать прогресс чтения');
  print('  remove    — удалить книгу');
  print('Опции справки: -h, --help');
}

File _getDatabaseFile() {
  final String? xdg = Platform.environment['XDG_DATA_HOME'];
  final String baseDir;
  if (xdg != null && xdg.isNotEmpty) {
    baseDir = xdg;
  } else {
    final String? home = Platform.environment['HOME'];
    baseDir = home != null && home.isNotEmpty
        ? p.join(home, '.local', 'share')
        : Directory.current.path;
  }
  return File(p.join(baseDir, 'booklib', 'booklib.db'));
}

void _ensureMigrations(Database db) {
  db.execute('PRAGMA foreign_keys = ON;');
  db.execute('''
    CREATE TABLE IF NOT EXISTS books (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      author TEXT,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL
    );
  ''');
  db.execute('''
    CREATE TABLE IF NOT EXISTS reading_progress (
      book_id INTEGER PRIMARY KEY,
      line_index INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE
    );
  ''');
}

void _handleAdd(Database db, ArgResults cmd) {
  final String? filePath = cmd['file'] as String? ?? (cmd.rest.isNotEmpty ? cmd.rest.first : null);
  if (filePath == null) {
    stderr.writeln('Укажите путь к .txt файлу через --file или позиционным аргументом');
    exitCode = 64;
    return;
  }
  final File file = File(filePath);
  if (!file.existsSync()) {
    stderr.writeln('Файл не найден: $filePath');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final String rawContent = file.readAsStringSync(encoding: utf8);
  final String content = rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final String title = (cmd['title'] as String?)?.trim().isNotEmpty == true
      ? (cmd['title'] as String).trim()
      : p.basenameWithoutExtension(file.path);
  final String? author = (cmd['author'] as String?)?.trim().isNotEmpty == true
      ? (cmd['author'] as String).trim()
      : null;

  final stmt = db.prepare('INSERT INTO books (title, author, content, created_at) VALUES (?, ?, ?, datetime("now"))');
  ResultSet rs;
  try {
    stmt.execute([title, author, content]);
  } finally {
    stmt.dispose();
  }

  // Get last insert id
  rs = db.select('SELECT last_insert_rowid() AS id');
  final int newId = rs.first['id'] as int;

  // Init progress
  final initStmt = db.prepare('INSERT INTO reading_progress (book_id, line_index, updated_at) VALUES (?, 0, datetime("now"))');
  try {
    initStmt.execute([newId]);
  } finally {
    initStmt.dispose();
  }

  print('Книга добавлена: ID=$newId, "$title"${author != null ? ' — $author' : ''}');
}

void _handleList(Database db) {
  final ResultSet rs = db.select('SELECT id, title, author, created_at FROM books ORDER BY id ASC');
  if (rs.isEmpty) {
    print('Книг нет. Добавьте через: booklib add --file <путь>');
    return;
  }
  print('ID | Название | Автор | Дата');
  for (final Row row in rs) {
    final int id = row['id'] as int;
    final String title = row['title'] as String;
    final String? author = row['author'] as String?;
    final String createdAt = row['created_at'] as String;
    print('$id | $title | ${author ?? '-'} | $createdAt');
  }
}

void _handleShow(Database db, ArgResults cmd) {
  final int bookId = int.tryParse(cmd['id'] as String? ?? '') ?? -1;
  final int linesCount = int.tryParse(cmd['lines'] as String? ?? '25') ?? 25;
  if (bookId <= 0) {
    stderr.writeln('Некорректный ID книги');
    exitCode = 64;
    return;
  }
  final _BookData data = _loadBook(db, bookId);
  if (data.id == null) {
    stderr.writeln('Книга с ID=$bookId не найдена');
    exitCode = 65;
    return;
  }
  final int start = data.lineIndex ?? 0;
  _printPage(data, start, linesCount, updateProgress: false);
}

void _handleNext(Database db, ArgResults cmd) {
  final int bookId = int.tryParse(cmd['id'] as String? ?? '') ?? -1;
  final int linesCount = int.tryParse(cmd['lines'] as String? ?? '25') ?? 25;
  if (bookId <= 0) {
    stderr.writeln('Некорректный ID книги');
    exitCode = 64;
    return;
  }
  final _BookData data = _loadBook(db, bookId);
  if (data.id == null) {
    stderr.writeln('Книга с ID=$bookId не найдена');
    exitCode = 65;
    return;
  }
  final int start = data.lineIndex ?? 0;
  final int shown = _printPage(data, start, linesCount, updateProgress: true, db: db);
  if (shown == 0) {
    print('Достигнут конец книги.');
  }
}

void _handlePrev(Database db, ArgResults cmd) {
  final int bookId = int.tryParse(cmd['id'] as String? ?? '') ?? -1;
  final int linesCount = int.tryParse(cmd['lines'] as String? ?? '25') ?? 25;
  if (bookId <= 0) {
    stderr.writeln('Некорректный ID книги');
    exitCode = 64;
    return;
  }
  final _BookData data = _loadBook(db, bookId);
  if (data.id == null) {
    stderr.writeln('Книга с ID=$bookId не найдена');
    exitCode = 65;
    return;
  }
  int start = (data.lineIndex ?? 0) - linesCount;
  if (start < 0) start = 0;
  final int shown = _printPage(data, start, linesCount, updateProgress: true, db: db);
  if (shown == 0) {
    print('Начало книги.');
  }
}

void _handleProgress(Database db, ArgResults cmd) {
  final String? idStr = cmd['id'] as String?;
  if (idStr == null || idStr.trim().isEmpty) {
    // All
    final ResultSet rs = db.select('SELECT id, title FROM books ORDER BY id ASC');
    if (rs.isEmpty) {
      print('Книг нет.');
      return;
    }
    for (final Row row in rs) {
      final int id = row['id'] as int;
      final String title = row['title'] as String;
      final _BookData data = _loadBook(db, id);
      final _ProgressInfo info = _calcProgress(data);
      print('[$id] $title — ${info.percent.toStringAsFixed(1)}% (${info.current}/${info.total} строк)');
    }
  } else {
    final int bookId = int.tryParse(idStr) ?? -1;
    if (bookId <= 0) {
      stderr.writeln('Некорректный ID книги');
      exitCode = 64;
      return;
    }
    final _BookData data = _loadBook(db, bookId);
    if (data.id == null) {
      stderr.writeln('Книга с ID=$bookId не найдена');
      exitCode = 65;
      return;
    }
    final _ProgressInfo info = _calcProgress(data);
    print('[${data.id}] ${data.title} — ${info.percent.toStringAsFixed(1)}% (${info.current}/${info.total} строк)');
  }
}

void _handleRemove(Database db, ArgResults cmd) {
  final int bookId = int.tryParse(cmd['id'] as String? ?? '') ?? -1;
  if (bookId <= 0) {
    stderr.writeln('Некорректный ID книги');
    exitCode = 64;
    return;
  }
  final stmt = db.prepare('DELETE FROM books WHERE id = ?');
  try {
    stmt.execute([bookId]);
  } finally {
    stmt.dispose();
  }
  print('Книга удалена: ID=$bookId');
}

class _BookData {
  final int? id;
  final String? title;
  final String? author;
  final List<String> lines;
  final int? lineIndex;

  _BookData({
    required this.id,
    required this.title,
    required this.author,
    required this.lines,
    required this.lineIndex,
  });
}

_BookData _loadBook(Database db, int id) {
  final ResultSet rs = db.select(
    'SELECT b.id, b.title, b.author, b.content, IFNULL(r.line_index, 0) AS line_index '
    'FROM books b LEFT JOIN reading_progress r ON r.book_id = b.id WHERE b.id = ?',
    [id],
  );
  if (rs.isEmpty) {
    return _BookData(id: null, title: null, author: null, lines: const [], lineIndex: 0);
  }
  final Row row = rs.first;
  final String content = (row['content'] as String?) ?? '';
  final List<String> lines = content.isEmpty ? <String>[] : content.split('\n');
  return _BookData(
    id: row['id'] as int,
    title: row['title'] as String,
    author: row['author'] as String?,
    lines: lines,
    lineIndex: row['line_index'] as int,
  );
}

int _printPage(
  _BookData data,
  int start,
  int linesPerPage, {
  required bool updateProgress,
  Database? db,
}) {
  final int total = data.lines.length;
  if (total == 0) {
    print('Книга пуста.');
    return 0;
  }
  if (start >= total) {
    print('Достигнут конец книги.');
    return 0;
  }
  final int end = (start + linesPerPage) > total ? total : (start + linesPerPage);
  final String pageText = data.lines.sublist(start, end).join('\n');
  stdout.writeln(pageText);
  final double percent = total == 0 ? 0 : (end * 100.0 / total);
  stdout.writeln('\n-- [${data.id}] ${data.title}${data.author != null ? ' — ${data.author}' : ''}');
  stdout.writeln('-- Строки ${start + 1}..$end из $total (${percent.toStringAsFixed(1)}%)');

  if (updateProgress && db != null && data.id != null) {
    final stmt = db.prepare('REPLACE INTO reading_progress (book_id, line_index, updated_at) VALUES (?, ?, datetime("now"))');
    try {
      stmt.execute([data.id, end]);
    } finally {
      stmt.dispose();
    }
  }
  return end - start;
}

class _ProgressInfo {
  final int current;
  final int total;
  final double percent;
  _ProgressInfo(this.current, this.total, this.percent);
}

_ProgressInfo _calcProgress(_BookData data) {
  final int total = data.lines.length;
  final int current = (data.lineIndex ?? 0).clamp(0, total);
  final double percent = total == 0 ? 0 : (current * 100.0 / total);
  return _ProgressInfo(current, total, percent);
}
