import React from 'react';
const VARIANT_COLOR = {primary:'var(--green-500)',secondary:'#d8d2c2',locked:'#b9b2a3',evolve:'var(--purple-500)',danger:'var(--red-500)',info:'var(--blue-500)'};
export function Button({children, variant='primary', size='md', disabled=false, icon, onClick}){
  const c = disabled ? '#c7c0b2' : VARIANT_COLOR[variant] || VARIANT_COLOR.primary;
  const bg = `linear-gradient(180deg,color-mix(in srgb,${c} 70%,white) 0%,${c} 55%,color-mix(in srgb,${c} 75%,black) 100%)`;
  const color = variant==='secondary' ? 'var(--text-primary)' : '#fff';
  const pad = size==='sm' ? '8px 16px' : size==='lg' ? '14px 30px' : '11px 22px';
  const fontSize = size==='sm' ? 14 : size==='lg' ? 20 : 16;
  return React.createElement('button',{onClick,disabled,style:{position:'relative',overflow:'hidden',background:bg,color,border:'4px solid var(--outline)',borderRadius:'var(--radius-pill)',padding:pad,fontFamily:'var(--font-display)',fontWeight:800,fontSize,cursor:disabled?'default':'pointer',display:'inline-flex',alignItems:'center',gap:8,letterSpacing:.3,boxShadow:disabled?'none':'0 5px 0 var(--outline)',transition:'transform var(--transition-fast)',WebkitTextStroke: disabled?'none':'0.6px rgba(0,0,0,.3)'},
    onMouseDown:e=>{if(!disabled)e.currentTarget.style.transform='translateY(3px)'},
    onMouseUp:e=>{e.currentTarget.style.transform='translateY(0)'},
    onMouseLeave:e=>{e.currentTarget.style.transform='translateY(0)'}
  },
    React.createElement('span',{style:{position:'absolute',top:'10%',left:'10%',right:'10%',height:'38%',background:'linear-gradient(180deg,rgba(255,255,255,.8),rgba(255,255,255,0))',borderRadius:'50%',pointerEvents:'none'}}),
    icon && React.createElement('span',{style:{fontSize:fontSize*1.2,position:'relative'}},icon),
    React.createElement('span',{style:{position:'relative'}},children)
  );
}
