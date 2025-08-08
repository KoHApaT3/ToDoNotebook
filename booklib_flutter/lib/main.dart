import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LibraryModel()..initialize()),
      ],
      child: MaterialApp(
        title: 'BookLib',
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: const HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const CatalogScreen(),
      const BookmarksScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Каталог' : 'Закладки'),
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Каталог'),
          NavigationDestination(icon: Icon(Icons.bookmark_outline), selectedIcon: Icon(Icons.bookmark), label: 'Закладки'),
        ],
        onDestinationSelected: (i) => setState(() => _index = i),
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.read<LibraryModel>().addBookFromPicker(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('Добавить книгу'),
            )
          : null,
    );
  }
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryModel>(
      builder: (context, model, _) {
        if (!model.ready) {
          return const Center(child: CircularProgressIndicator());
        }
        if (model.books.isEmpty) {
          return const Center(child: Text('Книг пока нет. Нажмите “Добавить книгу”.'));
        }
        return ListView.separated(
          itemCount: model.books.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final book = model.books[index];
            final progress = model.progressMap[book.id] ?? 0;
            final total = book.totalLines;
            final percent = total == 0 ? 0 : (progress * 100 / total);
            return ListTile(
              leading: const Icon(Icons.menu_book),
              title: Text(book.title),
              subtitle: Text(book.author?.isNotEmpty == true ? book.author! : 'Без автора'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${percent.toStringAsFixed(0)}%'),
                  Text('$progress/$total строк', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              onTap: () async {
                final lib = context.read<LibraryModel>();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReaderScreen(bookId: book.id!),
                ));
                await lib.refresh();
              },
              onLongPress: () async {
                final lib = context.read<LibraryModel>();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Удалить книгу'),
                    content: Text('Удалить "${book.title}"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                      FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await lib.removeBook(book.id!);
                }
              },
            );
          },
        );
      },
    );
  }
}

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryModel>(
      builder: (context, model, _) {
        if (!model.ready) {
          return const Center(child: CircularProgressIndicator());
        }
        if (model.bookmarks.isEmpty) {
          return const Center(child: Text('Закладок пока нет.'));
        }
        return ListView.separated(
          itemCount: model.bookmarks.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final bm = model.bookmarks[index];
            final book = model.booksById[bm.bookId];
            return ListTile(
              leading: const Icon(Icons.bookmark),
              title: Text(book?.title ?? 'Книга #${bm.bookId}'),
              subtitle: Text('Строка ${bm.lineIndex + 1}${bm.note != null ? ' — ${bm.note}' : ''}'),
              onTap: () async {
                final lib = context.read<LibraryModel>();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReaderScreen(bookId: bm.bookId, initialLine: bm.lineIndex),
                ));
                await lib.refresh();
              },
              onLongPress: () async {
                final lib = context.read<LibraryModel>();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Удалить закладку'),
                    content: Text('Удалить закладку в книге "${book?.title ?? bm.bookId}" на строке ${bm.lineIndex + 1}?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                      FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
                    ],
                  ),
                );
                if (confirm == true) {
                  await lib.removeBookmark(bm.id!);
                }
              },
            );
          },
        );
      },
    );
  }
}

class ReaderScreen extends StatefulWidget {
  final int bookId;
  final int? initialLine;
  const ReaderScreen({super.key, required this.bookId, this.initialLine});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final model = context.read<LibraryModel>();
      await model.ensureBookLoaded(widget.bookId);
      if (!context.mounted) return;
      final lineIndex = widget.initialLine ?? (model.progressMap[widget.bookId] ?? 0);
      _scrollToLine(lineIndex);
    });
  }

  void _scrollToLine(int lineIndex) {
    // Approximate 20px per line for initial jump; after build list aligns.
    _controller.jumpTo(lineIndex * 20);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryModel>(builder: (context, model, _) {
      final book = model.booksById[widget.bookId];
      final lines = model.bookLines[widget.bookId] ?? const <String>[];
      if (book == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(book.title),
          actions: [
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: () async {
                final pos = _estimateCurrentLineIndex();
                final note = await _promptText(context, title: 'Примечание (необязательно)');
                await model.addBookmark(widget.bookId, pos, note: note);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Закладка добавлена')));
              },
              tooltip: 'Добавить закладку',
            ),
          ],
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollUpdateNotification) {
              final line = _estimateCurrentLineIndex();
              model.updateProgress(widget.bookId, line);
            }
            return false;
          },
          child: ListView.builder(
            controller: _controller,
            itemCount: lines.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  lines[index].isEmpty ? ' ' : lines[index],
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
                ),
              );
            },
          ),
        ),
      );
    });
  }

  int _estimateCurrentLineIndex() {
    // Estimate based on scroll offset and default line height ~28
    final offset = _controller.offset;
    return (offset / 28).floor();
  }

  Future<String?> _promptText(BuildContext context, {required String title}) async {
    final controller = TextEditingController();
    return showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim().isEmpty ? null : controller.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
  }
}

// Data layer
class LibraryModel extends ChangeNotifier {
  bool ready = false;
  late Database _db;

  final List<Book> books = [];
  final Map<int, Book> booksById = {};
  final Map<int, List<String>> bookLines = {};
  final Map<int, int> progressMap = {}; // bookId -> lineIndex
  final List<Bookmark> bookmarks = [];

  Future<void> initialize() async {
    final dbPath = await getDatabasesPath();
    final dbFile = p.join(dbPath, 'booklib_mobile.db');
    _db = await openDatabase(dbFile, version: 1, onCreate: (db, version) async {
      await db.execute('''
        CREATE TABLE books (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          author TEXT,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE reading_progress (
          book_id INTEGER PRIMARY KEY,
          line_index INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE bookmarks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id INTEGER NOT NULL,
          line_index INTEGER NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL
        );
      ''');
    });
    await refresh();
    ready = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    final booksRows = await _db.rawQuery('SELECT id, title, author, content, created_at FROM books ORDER BY id ASC');
    books
      ..clear()
      ..addAll(booksRows.map((r) => Book(
            id: r['id'] as int,
            title: r['title'] as String,
            author: r['author'] as String?,
            content: r['content'] as String,
            createdAt: r['created_at'] as String,
          )));
    booksById
      ..clear()
      ..addEntries(books.map((b) => MapEntry(b.id!, b)));

    bookLines.clear();
    progressMap.clear();

    final progressRows = await _db.rawQuery('SELECT book_id, line_index FROM reading_progress');
    for (final r in progressRows) {
      progressMap[r['book_id'] as int] = r['line_index'] as int;
    }

    final bmRows = await _db.rawQuery('SELECT id, book_id, line_index, note, created_at FROM bookmarks ORDER BY created_at DESC');
    bookmarks
      ..clear()
      ..addAll(bmRows.map((r) => Bookmark(
            id: r['id'] as int,
            bookId: r['book_id'] as int,
            lineIndex: r['line_index'] as int,
            note: r['note'] as String?,
            createdAt: r['created_at'] as String,
          )));
  }

  Future<void> ensureBookLoaded(int bookId) async {
    if (bookLines.containsKey(bookId)) return;
    final book = booksById[bookId];
    if (book == null) return;
    bookLines[bookId] = book.content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    notifyListeners();
  }

  Future<void> addBookFromPicker(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['txt']);
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final file = File(path);
    final content = await file.readAsString();
    final title = p.basenameWithoutExtension(path);
    await _db.transaction((txn) async {
      final id = await txn.rawInsert(
          'INSERT INTO books (title, author, content, created_at) VALUES (?, ?, ?, datetime("now"))',
          [title, null, content]);
      await txn.rawInsert(
          'INSERT INTO reading_progress (book_id, line_index, updated_at) VALUES (?, 0, datetime("now"))',
          [id]);
    });
    await refresh();
    notifyListeners();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Книга "$title" добавлена')));
  }

  Future<void> removeBook(int id) async {
    await _db.transaction((txn) async {
      await txn.delete('bookmarks', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('reading_progress', where: 'book_id = ?', whereArgs: [id]);
      await txn.delete('books', where: 'id = ?', whereArgs: [id]);
    });
    await refresh();
    notifyListeners();
  }

  Future<void> updateProgress(int bookId, int lineIndex) async {
    await _db.rawInsert(
      'INSERT INTO reading_progress (book_id, line_index, updated_at) VALUES (?, ?, datetime("now"))\n       ON CONFLICT(book_id) DO UPDATE SET line_index = excluded.line_index, updated_at = excluded.updated_at',
      [bookId, lineIndex],
    );
    progressMap[bookId] = lineIndex;
  }

  Future<void> addBookmark(int bookId, int lineIndex, {String? note}) async {
    await _db.rawInsert(
      'INSERT INTO bookmarks (book_id, line_index, note, created_at) VALUES (?, ?, ?, datetime("now"))',
      [bookId, lineIndex, note],
    );
    await refresh();
    notifyListeners();
  }

  Future<void> removeBookmark(int id) async {
    await _db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
    await refresh();
    notifyListeners();
  }
}

class Book {
  final int? id;
  final String title;
  final String? author;
  final String content;
  final String createdAt;

  Book({this.id, required this.title, this.author, required this.content, required this.createdAt});

  int get totalLines => content.isEmpty ? 0 : content.split('\n').length;
}

class Bookmark {
  final int? id;
  final int bookId;
  final int lineIndex;
  final String? note;
  final String createdAt;

  Bookmark({this.id, required this.bookId, required this.lineIndex, this.note, required this.createdAt});
}
