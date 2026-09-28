const fs=require('fs');
const root='C:/Users/rafae/.codex/visualizations/2026/09/28/01a0e8c3-7584-76e3-a3e5-9cb4ff43e218';
let script=fs.readFileSync(root+'/review-field.cjs','utf8');
script=script.replace('const root=__dirname;','const root='+JSON.stringify(root)+';');
script=script.replace("scenario('backpack');near=false;trunkShown=true;render();return results",`
scenario('backpack');near=true;trunkShown=true;render();
const unchanged=JSON.stringify(bags);check('Monaliza recusa comida mesmo próxima',!move('pockets',bags.pockets[1].uid,'trunk')&&JSON.stringify(bags)===unchanged);
check('estoque da Monaliza contém só armas e munição',bags.trunk.every(i=>['rifle','pistol','ammo'].includes(i.id)));
bags.trunk=Array.from({length:6},(_,i)=>create('ammo',99,i%4,Math.floor(i/4)));const ammoBefore=JSON.stringify(bags);
const ammoItem=bags.bag.find(i=>i.id==='ammo');check('sétima pilha de munição recusada',!move('bag',ammoItem.uid,'trunk')&&JSON.stringify(bags)===ammoBefore);
scenario('backpack');setOpen(true);document.dispatchEvent(new KeyboardEvent('keydown',{key:'g'}));check('G solta mochila e fecha HUD',bagKind===''&&ground!==null&&$('panel').hidden);
scenario('backpack');setOpen(true);near=false;trunkShown=true;render();return results`);
// Run the reviewed CDP harness with the extra constraints; it closes only its
// own isolated Chrome instance and saves screenshots in the preview folder.
eval(script);
