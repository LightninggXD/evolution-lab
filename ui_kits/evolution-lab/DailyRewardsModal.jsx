function DailyRewardsModal({onClose}){
  const { Modal, RewardTile } = window.EvolutionLabDesignSystem_cb9a2a;
  const days = [
    {day:1,reward:{icon:'✅',label:'200 DNA'},claimed:true},
    {day:2,reward:{icon:'💵',label:'450 DNA'}},
    {day:3,reward:{icon:'🧪',label:'1.00K DNA'},bonus:'x1'},
    {day:4,reward:{icon:'🧪',label:'2.20K DNA'},bonus:'x2'},
    {day:5,reward:{icon:'🧪',label:'4.80K DNA'},bonus:'x3'},
    {day:6,reward:{icon:'🧪',label:'10.50K DNA'},bonus:'x4 💎x1'},
  ];
  return React.createElement(Modal,{title:'Daily Rewards!',icon:'📅',accent:'blue',onClose,footer:'Come back tomorrow for Day 2!'},
    React.createElement('div',{style:{color:'var(--text-secondary)',fontWeight:700,marginBottom:10,fontSize:13}}, 'Streak: 1 day'),
    React.createElement('div',{style:{display:'grid',gridTemplateColumns:'repeat(4,80px)',gridTemplateRows:'repeat(2,80px)',gap:8}},
      days.map(d=>React.createElement(RewardTile,{key:d.day,...d})),
      React.createElement(RewardTile,{day:7,reward:{icon:'✨',label:'23.00K DNA'},bonus:'x5 💎x3 💎x2',big:true})
    )
  );
}
window.DailyRewardsModal = DailyRewardsModal;
