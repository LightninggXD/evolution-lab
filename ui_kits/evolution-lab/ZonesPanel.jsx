function ZonesPanel({onClose}){
  const { Modal, ZoneRow } = window.EvolutionLabDesignSystem_cb9a2a;
  const zones = [
    {icon:'🌲',name:'Forest',unlocked:true},
    {icon:'🦠',name:'Desert',requirement:'Bacteria'},
    {icon:'🌊',name:'Ocean',requirement:'Worm'},
    {icon:'🌋',name:'Volcano',requirement:'Lizard'},
    {icon:'🌙',name:'Moon',requirement:'Wolf'},
    {icon:'🔴',name:'Mars',requirement:'???'},
  ];
  return React.createElement(Modal,{title:'Zones',icon:'🗺️',accent:'blue',onClose},
    React.createElement('div',{style:{display:'flex',flexDirection:'column',gap:8,width:340,maxHeight:320,overflowY:'auto'}},
      zones.map((z,i)=>React.createElement(ZoneRow,{key:i,...z}))
    )
  );
}
window.ZonesPanel = ZonesPanel;
