import React from 'react'
import "./SidePanel.css";

export default function SidePanel() {
  return (
    <div className="SidePanel">
      <div className="Content">
        <button className="NewNote">+ Создать новую запись</button>
        <input type="text" className='Search' />
      </div>

    </div>
  )
}
