import React from 'react';
export function ZoneRow({icon, name, requirement, unlocked=false, onGo}){
  return React.createElement('div',{style:{display:'flex',alignItems:'center',justifyContent:'space-between',background:'var(--cream-panel)',border:'3px solid var(--outline)',borderRadius:'var(--radius-lg)',padding:'12px 16px',boxShadow:'var(--shadow-panel)'}},
    React.createElement('div',{style:{display:'flex',flexDirection:'column',gap:2}},
      React.createElement('div',{style:{color:'var(--text-primary)',fontWeight:800,fontSize:15,display:'flex',alignItems:'center',gap:6}}, icon, name),
      !unlocked && requirement && React.createElement('div',{style:{color:'var(--text-secondary)',fontSize:12,fontWeight:700}}, `Requires: ${requirement}`)
    ),
    React.createElement('button',{style:{background:unlocked?'var(--green-500)':'#b9b2a3',color:'#fff',border:'3px solid var(--outline)',borderRadius:'var(--radius-pill)',padding:'8px 18px',fontFamily:'var(--font-display)',fontWeight:800,fontSize:13,boxShadow:'var(--shadow-btn)'}}, unlocked?'Go':'🔒')
  );
}
