import React from 'react';
export function RewardTile({day, reward, bonus, claimed=false, big=false, bg, highlight=false}){
  const defaultBg = big
    ? 'linear-gradient(180deg,#2b2140,#1a1430)'
    : highlight
      ? 'linear-gradient(180deg,#8be84a,#4fc21f)'
      : 'linear-gradient(180deg,#dfe6fb,#b9c6f2)';
  return React.createElement('div',{style:{position:'relative',background:bg||defaultBg,border:highlight?'4px solid #2ecc59':'4px solid var(--outline)',borderRadius:14,padding:big?'22px 14px 16px':'20px 8px 10px',display:'flex',flexDirection:'column',alignItems:'center',gap:4,gridRow:big?'span 2':undefined,justifyContent:'center',boxShadow:'0 5px 0 var(--outline)',overflow:'hidden'}},
    big && React.createElement('div',{style:{position:'absolute',inset:0,background:'repeating-conic-gradient(from 0deg,rgba(255,255,255,.08) 0deg 6deg,transparent 6deg 18deg)'}}),
    React.createElement('div',{style:{position:'relative',color:'#fff',fontWeight:800,fontSize:big?22:16,WebkitTextStroke:'2px var(--outline)',paintOrder:'stroke fill',textShadow:'0 2px 0 rgba(0,0,0,.25)',whiteSpace:'nowrap',marginBottom:4}}, `Day ${day}`),
    React.createElement('div',{style:{position:'relative',fontSize:big?52:30}}, reward.icon),
    React.createElement('div',{style:{position:'relative',color:'#fff',fontWeight:800,fontSize:big?17:14,WebkitTextStroke:'1.5px var(--outline)',paintOrder:'stroke fill',textAlign:'center',lineHeight:1.15}}, reward.label),
    reward.sub && React.createElement('div',{style:{position:'relative',color:'#fff',fontWeight:800,fontSize:big?17:14,WebkitTextStroke:'1.5px var(--outline)',paintOrder:'stroke fill',textAlign:'center',lineHeight:1.15}}, reward.sub),
    claimed && React.createElement('div',{style:{position:'relative',background:'var(--green-500)',border:'2px solid var(--outline)',borderRadius:8,color:'#fff',fontSize:11,fontWeight:800,padding:'2px 8px'}}, '✓'),
    bonus && React.createElement('div',{style:{position:'relative',color:'#fff',fontSize:11,fontWeight:700,WebkitTextStroke:'1px var(--outline)',paintOrder:'stroke fill'}}, bonus)
  );
}
