function CombatScreen(){
  const { ProgressBar, Button, DamageText } = window.EvolutionLabDesignSystem_cb9a2a;
  const [hits,setHits] = React.useState([]);
  const [hp,setHp] = React.useState(80);
  function hit(){
    const dmg = Math.floor(Math.random()*8)+2;
    setHp(h=>Math.max(0,h-dmg));
    const id = Date.now();
    setHits(hs=>[...hs,{id,val:`-${dmg} HP`,x:Math.random()*140,y:Math.random()*30}]);
    setTimeout(()=>setHits(hs=>hs.filter(h=>h.id!==id)),900);
  }
  return React.createElement('div',{style:{position:'relative',background:'#7fbf6b',border:'3px solid var(--outline)',borderRadius:'var(--radius-lg)',padding:20,width:360,boxShadow:'var(--shadow-panel)'}},
    React.createElement('div',{style:{fontWeight:800,color:'#fff',WebkitTextStroke:'1.5px var(--outline)',fontSize:16,marginBottom:8}}, '💀 Brute (Forest)'),
    React.createElement(ProgressBar,{value:hp,max:100,color:'var(--red-500)'}),
    React.createElement('div',{style:{position:'relative',height:60,marginTop:10}}, hits.map(h=>React.createElement(DamageText,{key:h.id,value:h.val,x:h.x,y:h.y}))),
    React.createElement(Button,{variant:'danger',onClick:hit}, 'Attack'),
    React.createElement('div',{style:{marginTop:12}}, React.createElement(Button,{variant:'evolve',size:'lg'}, 'EVOLVE to Wolf (12/1.20K DNA)'))
  );
}
window.CombatScreen = CombatScreen;
