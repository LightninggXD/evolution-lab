import React from 'react';
const CYCLE = ['var(--green-500)','var(--blue-500)','var(--pink-500)','var(--orange-500)','var(--purple-500)','var(--teal-500)'];
function colorFor(label){ let h=0; for(let i=0;i<label.length;i++) h=(h*31+label.charCodeAt(i))>>>0; return CYCLE[h%CYCLE.length]; }
export function StatCard({icon, label, level, cost, costIcon='💎', wide=false}){
  const chip = colorFor(label);
  return React.createElement('div',{style:{background:'var(--cream-panel)',border:'3px solid var(--outline)',borderRadius:'var(--radius-lg)',padding:'14px 16px',minWidth:wide?220:150,display:'flex',flexDirection:'column',gap:8,fontFamily:'var(--font-body)',boxShadow:'var(--shadow-panel)'}},
    React.createElement('div',{style:{display:'flex',alignItems:'center',gap:8}},
      React.createElement('div',{style:{width:30,height:30,borderRadius:10,background:chip,border:'2px solid var(--outline)',display:'flex',alignItems:'center',justifyContent:'center',fontSize:16,flex:'none'}}, icon),
      React.createElement('div',{style:{color:'var(--text-primary)',fontWeight:800,fontSize:15}}, label)
    ),
    level!=null && React.createElement('div',{style:{color:'var(--text-secondary)',fontSize:13,fontWeight:700}}, `Level ${level}`),
    cost!=null && React.createElement('div',{style:{color:'var(--gold-600)',fontSize:14,fontWeight:800,marginTop:'auto'}}, `${costIcon} ${cost}`)
  );
}
