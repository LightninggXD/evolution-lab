import React from 'react';
export function DamageText({value, x=0, y=0}){
  return React.createElement('div',{style:{position:'absolute',left:x,top:y,background:'var(--red-500)',color:'#fff',fontFamily:'var(--font-display)',fontWeight:800,fontSize:14,padding:'6px 14px',border:'2.5px solid var(--outline)',borderRadius:'var(--radius-pill)',boxShadow:'var(--shadow-panel)'}}, `Ouch! ${value}`);
}
