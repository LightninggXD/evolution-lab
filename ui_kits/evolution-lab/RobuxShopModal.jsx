function RobuxShopModal({onClose}){
  const { Modal, Button } = window.EvolutionLabDesignSystem_cb9a2a;
  const items = [
    {icon:'🧬',label:'1,000 DNA'},{icon:'🧬',label:'10,000 DNA'},
    {icon:'🧪',label:'3 Potions'},{icon:'🧪',label:'10 Potions'},
    {icon:'💎',label:'10 Diamonds'},{icon:'💎',label:'50 Diamonds'},
  ];
  return React.createElement(Modal,{title:'Robux Shop',icon:'🛍️',accent:'green',onClose},
    React.createElement('div',{style:{display:'grid',gridTemplateColumns:'repeat(2,1fr)',gap:10,width:340}},
      items.map((it,i)=>React.createElement('div',{key:i,style:{background:'var(--cream-panel)',border:'3px solid var(--outline)',borderRadius:'var(--radius-lg)',padding:14,display:'flex',flexDirection:'column',gap:8,alignItems:'center',boxShadow:'var(--shadow-panel)'}},
        React.createElement('div',{style:{fontWeight:800,fontSize:14}}, `${it.icon} ${it.label}`),
        React.createElement(Button,{variant:'primary',size:'sm'}, 'Buy with R$')
      ))
    )
  );
}
window.RobuxShopModal = RobuxShopModal;
