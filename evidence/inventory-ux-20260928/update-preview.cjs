const fs=require('fs');
const path='C:/Users/rafae/.codex/visualizations/2026/09/28/01a0e8c3-7584-76e3-a3e5-9cb4ff43e218/inventario.html';
let html=fs.readFileSync(path,'utf8');
if(html.includes('id="inventory-ux-v2"'))process.exit(0);
function replace(before,after){if(!html.includes(before))throw Error('Missing expected source: '+before.slice(0,70));html=html.replace(before,after)}
replace('function fits(c,i,x,y,ignore=null){','function fits(c,i,x,y,ignore=null){if(c===\'trunk\'&&(![\'rifle\',\'pistol\',\'ammo\'].includes(i.id)||(i.id===\'ammo\'&&bags.trunk.filter(o=>o.id===\'ammo\'&&o.uid!==ignore).length>=6)))return false;');
replace('const i=src[index];if(at){',"const i=src[index];if(to==='trunk'&&!['rifle','pistol','ammo'].includes(i.id)){notify('A Monaliza guarda apenas armas e munição.');return false}if(at){");
replace("create('ammo',99,0,1),create('med',2,1,1)","create('ammo',99,0,1)");
replace("selected=kind!=='start'?{c:'bag',uid:bags.bag[0].uid}:null;","selected=null;");
replace("else $('details').innerHTML='<div class=\"label\">Organização</div><h3>Selecione um item</h3><p>Arraste para posicionar. O espaço precisa estar livre e ser contíguo.</p>';","else $('details').innerHTML='';");
replace('<p class="status">O acesso é verificado a cada transferência.</p>','<p class="status">Armas e munição · 24 espaços · até 6 pilhas</p>');
replace('Soltar bagagem no chão','↓ Soltar mochila · G');
replace("$('drop').hidden=!bagKind;","$('drop').hidden=!bagKind;$('drop').textContent='↓ Soltar '+(bagKind==='handbag'?'mala':'mochila')+' · G';");
replace("b.onclick=()=>{selected={c,uid:i.uid};render()};","b.onclick=e=>{if(e.shiftKey){move(c,i.uid,c==='trunk'?'bag':trunkShown?'trunk':c==='bag'?'pockets':'bag');return}selected={c,uid:i.uid};render()};b.oncontextmenu=e=>{e.preventDefault();if(!editable(c))return;if(d.heal&&health<100){health=Math.min(100,health+d.heal);i.n--;if(!i.n)bags[c].splice(bags[c].indexOf(i),1);render();notify('Item consumido.')}};");
replace("(c!=='trunk'||trunkShown)","(c!=='trunk'||trunkShown&&['rifle','pistol','ammo'].includes(i.id))");
replace("notify('Bagagem solta. Os bolsos e a arma permanecem com você.')","notify('Bagagem no chão.');setOpen(false)");
replace("if(e.key==='Escape')setOpen(false);","if(e.key.toLowerCase()==='g'&&!$('panel').hidden){e.preventDefault();$('drop').click()}if(e.key==='Escape')setOpen(false);");
replace('</style>',`</style><style id="inventory-ux-v2">
:root{--amber:#d0ac72;--muted:#a4aaa5}.panel{background:#151d18f5;border-color:#51594d;border-radius:14px}.grid{background-color:#1c2520;background-image:linear-gradient(to right,#52604a66 1px,transparent 1px),linear-gradient(to bottom,#52604a66 1px,transparent 1px)}.item{background:#29332c;border-color:#56634f}.drop{background:#493a2b;border-color:#9f8058;color:#f3e4cf;font-size:15px;padding:13px;font-weight:600}.drop:hover{background:#695035}.details{min-height:0;padding-top:8px;margin-top:10px}.details:empty{display:none}.details p,.details>.label,.prototype-note,.legend{display:none}.details h3{font-size:15px;margin:4px 0 10px}.equipment b{display:none}.equipment small{font-size:11px}.warn{font-size:11px}.head h1{font-size:20px}.status{font-size:11px}#toast:empty{min-height:0;padding:0}.ground{background:#18231cf0}.text-btn,.actions button{background:#29332c}.world{filter:saturate(.78)}
</style>`);
fs.writeFileSync(path,html);
console.log('Preview updated: finite weapons-only trunk, six ammo stacks, direct use and visible drop.');
