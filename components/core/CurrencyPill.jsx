import React from 'react';
export function CurrencyPill({icon='💎', value, accent='blue'}){
  const bg = accent==='blue' ? 'var(--blue-500)' : accent==='gold' ? 'var(--gold-500)' : 'var(--green-500)';
  return React.createElement('div',{style:{display:'inline-flex',alignItems:'center',gap:8,background:bg,border:'4px solid var(--outline)',borderRadius:'var(--radius-pill)',padding:'8px 10px 8px 8px',fontFamily:'var(--font-display)',boxShadow:'0 5px 0 var(--outline)'}},
    React.createElement('span',{style:{fontSize:26,background:'var(--cream-panel)',borderRadius:'50%',width:38,height:38,display:'flex',alignItems:'center',justifyContent:'center',border:'3px solid var(--outline)'}}, icon),
    React.createElement('span',{style:{color:'#fff',fontWeight:800,fontSize:20,WebkitTextStroke:'0.6px rgba(0,0,0,.25)',paddingRight:6}}, value)
  );
}
