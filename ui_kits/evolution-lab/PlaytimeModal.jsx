function PlaytimeModal({onClose}){
  const { Modal, ProgressBar } = window.EvolutionLabDesignSystem_cb9a2a;
  const tiers = [
    {t:'10 min',r:'1.00K DNA',eta:'in 8m 16s'},
    {t:'20 min',r:'2.50K DNA x1',eta:'in 18m 16s'},
    {t:'30 min',r:'6.00K DNA x2',eta:'in 28m 16s'},
    {t:'45 min',r:'15.00K DNA 💎x1',eta:'in 43m 16s'},
    {t:'60 min',r:'35.00K DNA 💎x2',eta:'in 58m 16s'},
  ];
  return React.createElement(Modal,{title:'Playtime Gifts',icon:'⏰',accent:'blue',onClose,footer:'The longer you stay, the better the gift!'},
    React.createElement('div',{style:{display:'flex',gap:10,width:420}},
      tiers.map((tier,i)=>React.createElement('div',{key:i,style:{flex:1,background:'var(--cream-panel)',border:'3px solid var(--outline)',borderRadius:'var(--radius-md)',padding:10,display:'flex',flexDirection:'column',gap:6,alignItems:'center',boxShadow:'var(--shadow-panel)'}},
        React.createElement('div',{style:{fontWeight:800,fontSize:12}}, tier.t),
        React.createElement('div',{style:{fontWeight:800,fontSize:11,color:'var(--gold-600)',textAlign:'center'}}, tier.r),
        React.createElement('div',{style:{fontSize:10,color:'var(--text-tertiary)'}}, tier.eta)
      ))
    )
  );
}
window.PlaytimeModal = PlaytimeModal;
