import React from 'react';
const CYCLE = ['var(--green-500)','var(--blue-500)','var(--pink-500)','var(--orange-500)','var(--purple-500)','var(--teal-500)'];
export function NavRail({items, activeIndex=0, onSelect}){
  return React.createElement('div',{style:{display:'flex',flexDirection:'column',gap:8,background:'var(--cream-panel)',border:'3px solid var(--outline)',borderRadius:'var(--radius-lg)',padding:10,width:96,boxShadow:'var(--shadow-panel)'}},
    items.map((it,i)=>React.createElement('button',{key:i,onClick:()=>onSelect&&onSelect(i),style:{display:'flex',flexDirection:'column',alignItems:'center',gap:2,background:i===activeIndex?CYCLE[i%CYCLE.length]:'transparent',border:i===activeIndex?'2px solid var(--outline)':'2px solid transparent',borderRadius:10,padding:'8px 4px',cursor:'pointer'}},
      React.createElement('span',{style:{fontSize:20}}, it.icon),
      React.createElement('span',{style:{fontSize:11,fontWeight:800,color:i===activeIndex?'#fff':'var(--text-primary)'}}, it.label)
    ))
  );
}
