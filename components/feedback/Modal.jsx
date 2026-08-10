import React from 'react';
export function Modal({title, icon, onClose, accent='blue', children, footer, banner}){
  const glow = accent==='blue' ? '#2fc0f2' : accent==='green' ? 'var(--green-500)' : 'var(--purple-500)';
  return React.createElement('div',{style:{position:'relative',background:'#ffffff',border:`3px solid ${glow}`,borderRadius:24,padding:banner?0:'28px 28px 20px',minWidth:340,boxShadow:`0 0 0 5px rgba(47,192,242,.18), 0 14px 0 var(--outline)`,fontFamily:'var(--font-body)',overflow:banner?'hidden':'visible'}},
    banner ? React.createElement('div',{style:{background:banner,borderBottom:'4px solid var(--outline)',padding:'14px 18px',display:'flex',alignItems:'center',justifyContent:'space-between'}},
      React.createElement('div',{style:{fontSize:26,fontFamily:'var(--font-display)',fontWeight:800,color:'#fff',WebkitTextStroke:'2px var(--outline)',paintOrder:'stroke fill',textShadow:'0 3px 0 rgba(0,0,0,.25)',display:'flex',alignItems:'center',gap:8}}, icon, title),
      React.createElement('button',{onClick:onClose,style:{width:40,height:40,borderRadius:10,background:'#fff',color:'var(--outline)',border:'3px solid var(--outline)',fontWeight:900,cursor:'pointer',fontSize:18,boxShadow:'0 3px 0 var(--outline)',flex:'none'}}, '✕')
    ) : React.createElement(React.Fragment,null,
      React.createElement('button',{onClick:onClose,style:{position:'absolute',top:-18,right:-18,width:44,height:44,borderRadius:12,background:'linear-gradient(180deg,color-mix(in srgb,var(--red-500) 70%,white),var(--red-500) 55%,color-mix(in srgb,var(--red-500) 75%,black))',color:'#fff',border:'4px solid var(--outline)',fontWeight:900,cursor:'pointer',fontSize:18,boxShadow:'0 5px 0 var(--outline)'}}, '✕'),
      React.createElement('div',{style:{fontSize:'var(--text-modal-title)',fontFamily:'var(--font-display)',fontWeight:800,color:'#fff',WebkitTextStroke:'2.5px var(--outline)',paintOrder:'stroke fill',textShadow:'0 3px 0 rgba(0,0,0,.25)',marginBottom:18,display:'flex',alignItems:'center',gap:10}}, icon, title)
    ),
    React.createElement('div',{style:{padding:banner?18:0}}, children),
    footer && React.createElement('div',{style:{marginTop:18,marginBottom:banner?18:0,color:'#fff',fontSize:22,textAlign:'center',fontWeight:800,fontFamily:'var(--font-display)',WebkitTextStroke:'2px var(--outline)',paintOrder:'stroke fill',textShadow:'0 3px 0 rgba(0,0,0,.25)'}}, footer)
  );
}
