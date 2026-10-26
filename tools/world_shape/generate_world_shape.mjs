// Gera world/shape/world_shape.json: o contorno das ilhas do mundo orgânico (plano de 26/10/2026,
// etapa 0). O campo de terra é o mesmo da maquete aprovada (docs/design/mapa-3d-tecla-m-20261026.html):
// distância arredondada até as áreas jogáveis, ondulada por ruído, com os canais das pontes. As áreas
// jogáveis nunca viram mar. O contorno sai por marching squares e é simplificado; cada vértice recebe o
// tipo de costa (cais, praia, penhasco, pedra).
// Entrada: o JSON de tests/tools/export_world_map_data.gd (geografia preparada do jogo), copiado para
// tools/world_shape/world_geography.json para a geração ser repetível (evidence/ fica fora do Git).
// Uso: node tools/world_shape/generate_world_shape.mjs [tools/world_shape/world_geography.json] [world/shape/world_shape.json]
import fs from "node:fs";

const [input = "tools/world_shape/world_geography.json", output = "world/shape/world_shape.json"] = process.argv.slice(2);
const DATA = JSON.parse(fs.readFileSync(input, "utf8"));

/* ---------- mesmo ruído e geometria da maquete ---------- */
function hash(x,y){let h=Math.imul(x|0,374761393)^Math.imul(y|0,668265263);h=Math.imul(h^(h>>>13),1274126177);return ((h^(h>>>16))>>>0)/4294967295;}
function vnoise(x,y){const xi=Math.floor(x),yi=Math.floor(y),xf=x-xi,yf=y-yi;const u=xf*xf*(3-2*xf),v=yf*yf*(3-2*yf);
  const a=hash(xi,yi),b=hash(xi+1,yi),c=hash(xi,yi+1),d=hash(xi+1,yi+1);return a+(b-a)*u+(c-a)*v+(a-b-c+d)*u*v;}
function fbm(x,y,o){let s=0,a=.5,f=1,n=0;for(let i=0;i<o;i++){s+=a*vnoise(x*f,y*f);n+=a;f*=2.03;a*=.5;}return s/n;}
function ridged(x,y){let s=0,a=.55,f=1;for(let i=0;i<5;i++){const n=1-Math.abs(vnoise(x*f,y*f)*2-1);s+=a*n*n;f*=2.1;a*=.5;}return s;}
const ss=(a,b,x)=>{const t=Math.min(1,Math.max(0,(x-a)/(b-a)));return t*t*(3-2*t);};
function pip(x,z,p){let c=false;for(let i=0,j=p.length-2;i<p.length;j=i,i+=2){const xi=p[i],zi=p[i+1],xj=p[j],zj=p[j+1];if((zi>z)!==(zj>z)&&x<(xj-xi)*(z-zi)/(zj-zi)+xi)c=!c;}return c;}
function segDist(x,z,ax,az,bx,bz){const dx=bx-ax,dz=bz-az,L=dx*dx+dz*dz;let t=L?((x-ax)*dx+(z-az)*dz)/L:0;t=Math.max(0,Math.min(1,t));const px=ax+dx*t-x,pz=az+dz*t-z;return Math.sqrt(px*px+pz*pz);}
function sdPoly(x,z,p){let d=1e9;for(let i=0,j=p.length-2;i<p.length;j=i,i+=2)d=Math.min(d,segDist(x,z,p[j],p[j+1],p[i],p[i+1]));return pip(x,z,p)?d:-d;}
function sdRoundRect(x,z,x0,z0,x1,z1,r){const cx=(x0+x1)/2,cz=(z0+z1)/2,hx=(x1-x0)/2-r,hz=(z1-z0)/2-r;const qx=Math.abs(x-cx)-hx,qz=Math.abs(z-cz)-hz;
  const out=Math.hypot(Math.max(qx,0),Math.max(qz,0))+Math.min(Math.max(qx,qz),0)-r;return -out;}
function polyline(x,z,pts){let d=1e9;for(let i=2;i<pts.length;i+=2)d=Math.min(d,segDist(x,z,pts[i-2],pts[i-1],pts[i],pts[i+1]));return d;}
function bbox(p){let a=1e9,b=-1e9,c=1e9,d=-1e9;for(let i=0;i<p.length;i+=2){a=Math.min(a,p[i]);b=Math.max(b,p[i]);c=Math.min(c,p[i+1]);d=Math.max(d,p[i+1]);}return [a,b,c,d];}

/* ---------- campo de terra (igual à maquete; ver PROTECT abaixo) ---------- */
const harborLands = DATA.lands.filter(l=>l.biome==="city"||l.biome==="forest");
const cityLands = DATA.lands.filter(l=>l.biome==="city");
const mountainPoly = (DATA.lands.find(l=>l.biome==="mountain")||{points:[]}).points;
const D = {x0:-1340,x1:440,z0:-1230,z1:-374}; // DesertLayout.BOUNDS
const STRAITS = [
  {pts:[-120,-338, 160,-330, 380,-326, 468,-300, 470,-560, 472,-780, 478,-1050], half:26},
  {pts:[468,-300, 560,-246, 700,-200, 900,-170], half:30},
  // Contrato do canal Harbor–serra (≥ 40 m): sem este, a ponta leste de Harbor e a ponta sul da serra
  // ficavam a 29 m uma da outra a sudeste da cabeceira da ponte leste. Passa colado ao sul da serra
  // para não sobrar a tira fina de terra que ficava entre este canal e o anterior.
  {pts:[470,-210, 540,-165, 700,-140, 900,-115], half:30}
];
// Folga mínima de terra em volta do que é jogável (metros). A maquete usava 10/−18/−55; os contratos
// (tests/test_world_shape.gd) é que decidem estes valores.
// Serra (etapa 4): o contorno do terreno jogável pode recuar até 40 m onde não há nada, para o canal até o
// deserto fazer curva; trilhas, estradas e lugares da serra ficam a MOUNTAIN_CLEAR m da costa, onde
// cabe o muro de pedra que acompanha a costa (ScenarioBoundary3D.build_mountain_coast).
const PROTECT = {harbor:10, mountain:-40, desert:12};
const MOUNTAIN_CLEAR = 18; // 14 m do contrato + simplificação da trilha exportada e da costa (até 1,2 m cada)
const MOUNTAIN_BRIDGES = ["mountain_bridge_outbound","mountain_bridge_inbound","mountain_pass"];
const mountainSegs = [];
for (const r of DATA.roads) {
  if (r.region !== "mountain" || MOUNTAIN_BRIDGES.includes(r.id)) continue;
  for (let i = 2; i < r.points.length; i += 2) mountainSegs.push([r.points[i-2], r.points[i-1], r.points[i], r.points[i+1]]);
}
for (const m of DATA.markers) if (m.region === "mountain") mountainSegs.push([m.x, m.z, m.x + .1, m.z + .1]);
function mountainContentSD(x, z) {
  let d = 1e9;
  for (const s of mountainSegs) d = Math.min(d, segDist(x, z, s[0], s[1], s[2], s[3]));
  return MOUNTAIN_CLEAR - d;
}
// Cabeceiras de ponte em terra firme: a ponte norte chega ao deserto em DesertLayout.BRIDGE_END.
// A leste, a cabeceira da ponte da serra (as árvores editadas à mão ali ficam em terra firme, longe do muro).
const ABUTMENTS = [{x:342.5,z:-378,r:16},{x:600,z:-284,r:36}];
const harborBoxes = harborLands.map(l=>bbox(l.points));
const cityBoxes = cityLands.map(l=>bbox(l.points));
function unionSD(x,z,lands,boxes,reach){let best=-1e9;for(let k=0;k<lands.length;k++){const b=boxes[k];if(x<b[0]-reach||x>b[1]+reach||z<b[2]-reach||z>b[3]+reach)continue;best=Math.max(best,sdPoly(x,z,lands[k].points));}return best;}
const harborSD=(x,z)=>unionSD(x,z,harborLands,harborBoxes,260);
const citySD=(x,z)=>unionSD(x,z,cityLands,cityBoxes,80);
const desertSD=(x,z)=>sdRoundRect(x,z,D.x0-250,D.z0-260,D.x1+10,D.z1+20,170);
const mountainSD=(x,z)=>mountainPoly.length?sdPoly(x,z,mountainPoly):-1e9;
function warp(x,z){return (fbm(x*.0042+5.2,z*.0042-1.7,4)-.5)*150+(fbm(x*.017,z*.017,3)-.5)*34;}
function rawField(x,z){
  const hs=harborSD(x,z)+34, ds=desertSD(x,z), ms=mountainSD(x,z)+50;
  let f=Math.max(hs,ds,ms)+warp(x,z);
  const sx=x+(fbm(x*.004,z*.0055+7,3)-.5)*110, sz=z+(fbm(x*.0055+3,z*.004,3)-.5)*70;
  for(const s of STRAITS)f=Math.min(f,polyline(sx,sz,s.pts)-s.half-(fbm(x*.009+1,z*.009,3)-.5)*46);
  return f;}
// Etapa 3 (frente sul e porto): cais reto. Dentro de QUAY_ZONES a costa é a borda da terra jogável de
// Harbor (retângulos e terra extra), sem folga; a QUAY_RAMP m da zona a curva natural volta aos poucos, e é
// assim que a costa da mata e a do parque descem até os cantos do cais. O jogo lê as mesmas zonas
// (HarborCoast) para não pôr chão natural na frente do cais.
const QUAY_ZONES = [[-100,150, 440,150, 440,1200, -100,1200]];
const QUAY_RAMP = 50;
// Folga mínima no cais: onde dois pedaços de terra dividem uma borda (a passarela e o porto em z = 200), o
// máximo das distâncias dá zero exato na borda, e o contorno separava o porto da cidade ali.
const QUAY_SLACK = 0.6;
// Bacia do navio entre os quarteirões (x 200–273,8): água, sem a folga de terra em volta (ela fechava a
// bacia). Ao norte o jogo fecha a bacia num cais em z = −6,2; ao sul ela segue no canal, dentro do cais.
const CARVES = [[200,-6.2, 273.8,-6.2, 273.8,150, 200,150]];
const zoneDepth=(x,z,zones)=>{let best=-1e9;for(const p of zones)best=Math.max(best,sdPoly(x,z,p));return best;};
function quayWeight(x,z){const d=zoneDepth(x,z,QUAY_ZONES);return d>=0?1:1-ss(0,QUAY_RAMP,-d);}
const carved=(x,z)=>zoneDepth(x,z,CARVES);
// Puxa a costa para a borda exata da terra nas zonas de cais e abre a bacia.
function quays(x,z,f){
  const w=quayWeight(x,z);
  if(w>0)f+=(Math.min(f,harborSD(x,z)+QUAY_SLACK)-f)*w;
  return Math.min(f,-carved(x,z));}
// O que é jogável nunca vira mar; vem depois da suavização para ela não comer essas folgas. A folga de
// Harbor some no cais e na beira da bacia.
function protect(x,z,f){
  const slack=Math.max(QUAY_SLACK,PROTECT.harbor*(1-quayWeight(x,z))*ss(0,12,-carved(x,z)));
  f=Math.max(f,harborSD(x,z)+slack,mountainSD(x,z)+PROTECT.mountain,sdRoundRect(x,z,D.x0,D.z0,D.x1,D.z1,6)+PROTECT.desert);
  for(const a of ABUTMENTS)f=Math.max(f,a.r-Math.hypot(x-a.x,z-a.z));
  if(x>420&&z<-100)f=Math.max(f,mountainContentSD(x,z));
  return f;}
function owner(x,z){const hs=harborSD(x,z)+34, ds=desertSD(x,z), ms=mountainSD(x,z)+50;return hs>=ds&&hs>=ms?"harbor":(ds>=ms?"desert":"mountain");}
function ridgeStrength(x,z){const wx=x+(fbm(x*.003,z*.003+9,3)-.5)*240, wz=z+(fbm(x*.003+4,z*.003,3)-.5)*240;
  const out=Math.max(D.x0-wx,D.z0-wz,0);return Math.pow(ridged(x*.0058,z*.0058),1.35)*ss(0,170,out);}

/* ---------- grade e marching squares ---------- */
const CELL=4, X0=-1700, X1=1060, Z0=-1620, Z1=560;
const NX=Math.round((X1-X0)/CELL)+1, NZ=Math.round((Z1-Z0)/CELL)+1;
const F=new Float32Array(NX*NZ);
for(let iz=0;iz<NZ;iz++)for(let ix=0;ix<NX;ix++)F[iz*NX+ix]=rawField(X0+ix*CELL,Z0+iz*CELL);
// Suavização (média 9×9 células, ~36 m, duas passadas): some com penínsulas e canais finos que a
// maquete deixava, como o rabo de terra ao sul da serra que estreitava o canal até Harbor.
function boxBlur(src,r){const tmp=new Float32Array(src.length),out=new Float32Array(src.length);
  for(let iz=0;iz<NZ;iz++){let acc=0;for(let ix=-r;ix<=r;ix++)acc+=src[iz*NX+Math.min(NX-1,Math.max(0,ix))];
    for(let ix=0;ix<NX;ix++){tmp[iz*NX+ix]=acc/(2*r+1);acc+=src[iz*NX+Math.min(NX-1,ix+r+1)]-src[iz*NX+Math.max(0,ix-r)];}}
  for(let ix=0;ix<NX;ix++){let acc=0;for(let iz=-r;iz<=r;iz++)acc+=tmp[Math.min(NZ-1,Math.max(0,iz))*NX+ix];
    for(let iz=0;iz<NZ;iz++){out[iz*NX+ix]=acc/(2*r+1);acc+=tmp[Math.min(NZ-1,iz+r+1)*NX+ix]-tmp[Math.max(0,iz-r)*NX+ix];}}
  return out;}
const SMOOTH=boxBlur(boxBlur(F,4),4);
for(let iz=0;iz<NZ;iz++)for(let ix=0;ix<NX;ix++){
  const i=iz*NX+ix,edge=ix===0||iz===0||ix===NX-1||iz===NZ-1;
  F[i]=edge?-1:protect(X0+ix*CELL,Z0+iz*CELL,quays(X0+ix*CELL,Z0+iz*CELL,SMOOTH[i]));}
function field(x,z){const fx=Math.min(NX-2,Math.max(0,(x-X0)/CELL)),fz=Math.min(NZ-2,Math.max(0,(z-Z0)/CELL));const ix=Math.floor(fx),iz=Math.floor(fz),u=fx-ix,w=fz-iz;
  const a=F[iz*NX+ix],b=F[iz*NX+ix+1],c=F[(iz+1)*NX+ix],d=F[(iz+1)*NX+ix+1];return a*(1-u)*(1-w)+b*u*(1-w)+c*(1-u)*w+d*u*w;}
const v=(ix,iz)=>F[iz*NX+ix];
// Pontos de cruzamento em arestas: "h,ix,iz" (entre ix e ix+1) e "v,ix,iz" (entre iz e iz+1).
const cross=new Map();
function point(key){if(cross.has(key))return cross.get(key);const [t,a,b]=key.split(",");const ix=+a,iz=+b;let p;
  if(t==="h"){const f0=v(ix,iz),f1=v(ix+1,iz),k=f0/(f0-f1);p=[X0+(ix+k)*CELL,Z0+iz*CELL];}
  else{const f0=v(ix,iz),f1=v(ix,iz+1),k=f0/(f0-f1);p=[X0+ix*CELL,Z0+(iz+k)*CELL];}
  cross.set(key,p);return p;}
const next=new Map();
function link(a,b){next.set(a,b);}
for(let iz=0;iz<NZ-1;iz++)for(let ix=0;ix<NX-1;ix++){
  const a=v(ix,iz)>0,b=v(ix+1,iz)>0,c=v(ix+1,iz+1)>0,d=v(ix,iz+1)>0;
  const code=(a?1:0)|(b?2:0)|(c?4:0)|(d?8:0);
  if(code===0||code===15)continue;
  const T="h,"+ix+","+iz, R="v,"+(ix+1)+","+iz, Bo="h,"+ix+","+(iz+1), L="v,"+ix+","+iz;
  // Terra à esquerda de cada segmento: o contorno sai num sentido só e fecha em laço.
  switch(code){
    case 1:link(L,T);break; case 2:link(T,R);break; case 3:link(L,R);break; case 4:link(R,Bo);break;
    case 6:link(T,Bo);break; case 7:link(L,Bo);break; case 8:link(Bo,L);break; case 9:link(Bo,T);break;
    case 11:link(Bo,R);break; case 12:link(R,L);break; case 13:link(R,T);break; case 14:link(T,L);break;
    case 5:{const center=(v(ix,iz)+v(ix+1,iz)+v(ix+1,iz+1)+v(ix,iz+1))/4;if(center>0){link(L,Bo);link(R,T);}else{link(L,T);link(R,Bo);}break;}
    case 10:{const center=(v(ix,iz)+v(ix+1,iz)+v(ix+1,iz+1)+v(ix,iz+1))/4;if(center>0){link(T,L);link(Bo,R);}else{link(T,R);link(Bo,L);}break;}
  }
}
const loops=[];const seen=new Set();
for(const start of next.keys()){if(seen.has(start))continue;const loop=[];let k=start;
  while(k&&!seen.has(k)){seen.add(k);loop.push(point(k));k=next.get(k);}
  if(loop.length>8)loops.push(loop);}
const area=p=>{let s=0;for(let i=0;i<p.length;i++){const a=p[i],b=p[(i+1)%p.length];s+=a[0]*b[1]-b[0]*a[1];}return s/2;};

/* ---------- simplificação ---------- */
function rdp(pts,tol){if(pts.length<3)return pts;const a=pts[0],b=pts[pts.length-1];let worst=-1,idx=0;
  for(let i=1;i<pts.length-1;i++){const d=segDist(pts[i][0],pts[i][1],a[0],a[1],b[0],b[1]);if(d>worst){worst=d;idx=i;}}
  if(worst<=tol)return [a,b];return rdp(pts.slice(0,idx+1),tol).slice(0,-1).concat(rdp(pts.slice(idx),tol));}
function simplifyClosed(loop,tol){let far=0,fd=-1;for(let i=1;i<loop.length;i++){const d=Math.hypot(loop[i][0]-loop[0][0],loop[i][1]-loop[0][1]);if(d>fd){fd=d;far=i;}}
  const a=rdp(loop.slice(0,far+1),tol),b=rdp(loop.slice(far).concat([loop[0]]),tol);return a.slice(0,-1).concat(b.slice(0,-1));}

/* ---------- ilhas e tipo de costa ---------- */
const big=loops.map(l=>({l,a:area(l)})).filter(o=>Math.abs(o.a)>1500);
const flat=l=>l.flatMap(p=>[p[0],p[1]]);
const outers=big.filter(o=>!big.some(other=>other!==o&&Math.abs(other.a)>Math.abs(o.a)&&pip(o.l[0][0],o.l[0][1],flat(other.l))));
function inward(x,z){const e=2,gx=field(x+e,z)-field(x-e,z),gz=field(x,z+e)-field(x,z-e),L=Math.hypot(gx,gz)||1;return [gx/L,gz/L];}
function coastKind(x,z,island){
  // Cais: a costa encosta na terra jogável de Harbor (zonas de cais, bacia e o começo das rampas).
  if(island==="harbor")return Math.abs(harborSD(x,z))<2.5?"quay":"beach";
  if(island==="mountain")return "rock";
  const n=inward(x,z);const ix=x+n[0]*40,iz=z+n[1]*40;
  if(island==="desert"&&ridgeStrength(ix,iz)>.3)return "cliff";
  return "beach";}
const islands=[];
for(const o of outers){
  let pts=simplifyClosed(o.l,1.2);
  if(area(pts)<0)pts.reverse(); // sentido anti-horário no plano XZ (x para a direita, z para baixo)
  const votes={};for(const p of pts){const w=owner(p[0],p[1]);votes[w]=(votes[w]||0)+1;}
  const id=Object.entries(votes).sort((a,b)=>b[1]-a[1])[0][0];
  const coast=[];let last="";
  pts.forEach((p,i)=>{const k=coastKind(p[0],p[1],id);if(k!==last){coast.push([i,k]);last=k;}});
  islands.push({id,area_m2:Math.round(Math.abs(area(pts))),points:pts.flatMap(p=>[Math.round(p[0]*10)/10,Math.round(p[1]*10)/10]),coast});
}
islands.sort((a,b)=>b.area_m2-a.area_m2);
const names={};for(const isl of islands){names[isl.id]=(names[isl.id]||0)+1;if(names[isl.id]>1)isl.id=isl.id+"_islet_"+(names[isl.id]-1);}
// Distância com sinal até a costa da serra numa grade de 4 m (decímetros, presa em ±80 m): o terreno da
// serra lê em trabalhador, sem percorrer polígono (MountainTerrain3D._calculate_height).
const fields={};
for(const isl of islands){
  if(isl.id!=="mountain")continue;
  const pts=isl.points, poly=pts;
  let a=1e9,b=-1e9,c=1e9,d=-1e9;for(let i=0;i<pts.length;i+=2){a=Math.min(a,pts[i]);b=Math.max(b,pts[i]);c=Math.min(c,pts[i+1]);d=Math.max(d,pts[i+1]);}
  const step=4, x0=Math.floor((a-80)/step)*step, z0=Math.floor((c-80)/step)*step, nx=Math.ceil((b+80-x0)/step)+1, nz=Math.ceil((d+80-z0)/step)+1;
  const values=[];
  for(let iz=0;iz<nz;iz++)for(let ix=0;ix<nx;ix++){const v=sdPoly(x0+ix*step,z0+iz*step,poly);values.push(Math.round(Math.max(-80,Math.min(80,v))*10));}
  fields[isl.id]={origin:[x0,z0],step,size:[nx,nz],decimetres:values};
}
const out={version:1,generated:"2026-10-26",source:"docs/design/mapa-3d-tecla-m-20261026.html",generator:"tools/world_shape/generate_world_shape.mjs",
  cell_m:CELL,protect_m:PROTECT,abutments:ABUTMENTS,straits:STRAITS,quay_zones:QUAY_ZONES,quay_ramp_m:QUAY_RAMP,carves:CARVES,islands,distance_fields:fields};
fs.mkdirSync(output.substring(0,output.lastIndexOf("/")),{recursive:true});
fs.writeFileSync(output,JSON.stringify(out));
console.log("WORLD_SHAPE ilhas=%d", islands.length, islands.map(i=>`${i.id}:${i.points.length/2} vértices, ${(i.area_m2/1e6).toFixed(2)} km², costa ${i.coast.map(c=>c[1]).join("/")}`).join(" | "));
