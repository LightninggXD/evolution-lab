import React from 'react';
import { Tag } from '../feedback/Tag.jsx';
const CYCLE = ['var(--green-500)','var(--blue-500)','var(--pink-500)','var(--orange-500)','var(--purple-500)','var(--teal-500)'];
export function IconBadge({icon, label, tag, timer, size=68, index=0}){
  const bg = CYCLE[index%CYCLE.length];
  const tilt = index%2===0 ? -4 : 4;
  return React.createElement('div',{style:{display:'flex',flexDirection:'column',alignItems:'center',gap:5,width:size+24,position:'relative',fontFamily:'var(--font-body)'}},
    tag && React.createElement('div',{style:{position:'absolute',top:-12,left:'50%',transform:`translateX(-50%) rotate(${tilt}deg)`,zIndex:1}}, React.createElement(Tag,{variant:tag.variant||'new'}, tag.label)),
    React.createElement('div',{style:{width:size,height:size,borderRadius:'50%',background:bg,border:'4px solid var(--outline)',boxShadow:'0 5px 0 var(--outline)',display:'flex',alignItems:'center',justifyContent:'center',fontSize:size*0.5,transform:`rotate(${tilt/2}deg)`}}, icon),
    React.createElement('div',{style:{color:'#fff',fontWeight:800,fontSize:13,WebkitTextStroke:'2px var(--outline)',paintOrder:'stroke fill',textAlign:'center'}}, label),
    timer && React.createElement('div',{style:{color:'var(--text-primary)',fontSize:10,fontWeight:700,background:'var(--cream-panel)',border:'2px solid var(--outline)',borderRadius:8,padding:'1px 6px'}}, timer)
  );
}
