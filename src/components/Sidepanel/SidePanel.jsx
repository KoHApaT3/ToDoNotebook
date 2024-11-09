import React, { useEffect, useState } from 'react'
import "./SidePanel.css";

export default function SidePanel() {
  const [inputValue, setInputValue] = useState ('')
  const [notes, setNotes] = useState ([])
  
  useEffect(() => {
    const SavedNotes = localStorage.getItem('notes')
    if (SavedNotes) {
      setNotes(JSON.parse(SavedNotes))
    }
  },[])

  useEffect(() => {
    localStorage.setItem('notes',JSON.stringify(notes))
  },[notes])

  const InputChange = (e) => {
    setInputValue(e.target.value)
  }
  
  const ButtonClick = () => {
    setNotes([...notes,inputValue]) 
    setInputValue('')
  }
  return (
    <div className="SidePanel">
      <div className="Content">
        <button className="NewNote" onClick={ButtonClick}>+ Создать новую запись</button>
        <input type="text" className='NoteName' value={inputValue} onChange={InputChange} />
          <div className="NotesList">
            {notes.map ((note,id) =>(
              <div key={id} className="NoteItem">
                {note}
              </div>
            ))}
          </div>
      </div>
    </div>
  )
}