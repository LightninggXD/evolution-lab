import React from 'react';
export function ProgressBar({value=0, max=100, color='var(--green-500)', height=14, trackColor='var(--cream-panel)'}){
  const pct = Math.max(0,Math.min(100,(value/max)*100));
  return React.createElement('div',{style:{width:'100%',height,background:trackColor,border:'2.5px solid var(--outline)',borderRadius:height/2,overflow:'hidden'}},
    React.createElement('div',{style:{width:pct+'%',height:'100%',background:color,transition:'width var(--transition-med)'}})
  );
}
