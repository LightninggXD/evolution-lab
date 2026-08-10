import React from 'react';
const COLORS = {new:'var(--red-500)',op:'var(--gold-500)',free:'var(--green-500)',limited:'var(--purple-500)'};
export function Tag({children, variant='new'}){
  const c = COLORS[variant]||COLORS.new;
  return React.createElement('div',{style:{position:'relative',overflow:'hidden',display:'inline-block',background:`linear-gradient(180deg,color-mix(in srgb,${c} 70%,white) 0%,${c} 55%,color-mix(in srgb,${c} 75%,black) 100%)`,color:'#fff',fontFamily:'var(--font-display)',fontWeight:800,fontSize:12,padding:'4px 14px',border:'3px solid var(--outline)',borderRadius:'var(--radius-pill)',boxShadow:'0 3px 0 var(--outline)',WebkitTextStroke:'0.6px rgba(0,0,0,.25)'}},
    React.createElement('span',{style:{position:'absolute',top:'12%',left:'10%',right:'10%',height:'34%',background:'linear-gradient(180deg,rgba(255,255,255,.75),rgba(255,255,255,0))',borderRadius:'50%',pointerEvents:'none'}}),
    React.createElement('span',{style:{position:'relative'}},children)
  );
}
