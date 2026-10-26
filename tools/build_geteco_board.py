"""Build the offline GETECO inventory board from reviewed data and source indexes."""
from pathlib import Path
import json
import re
import html

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'

def read(path):
    return (ROOT / path).read_text(encoding='utf-8-sig')

def build():
    data = json.loads(read('docs/board-inventario-20261007.json'))
    story = json.loads(read('docs/board-historia-20261007.json'))
    data['cards'].extend(story['cards'])
    # Every docs/board-atualizacoes-<date>.json, oldest first: each one updates the cards seen so
    # far, adds its own and removes what it lists. The newest one dates the board. (The two files
    # used to be hard-coded, so a new day's file was silently ignored.)
    latest = None
    for path in sorted(DOCS.glob('board-atualizacoes-*.json')):
        changes = json.loads(read(path.relative_to(ROOT).as_posix()))
        for card in data['cards']:
            card.update(changes.get('updates', {}).get(card['id'], {}))
        data['cards'].extend(changes.get('cards', []))
        removed = set(changes.get('remove', []))
        data['cards'] = [c for c in data['cards'] if c['id'] not in removed]
        latest = changes
    data['date'] = latest['date']
    data['update_scope'] = latest['scope']
    data['catalogs'] = story.get('catalogs', {})
    fleet = json.loads(read('assets/fleet/catalog.json'))['vehicles']
    catalogs = []
    catalogs.append({'title': 'Frota base — 49 modelos exportados', 'note': 'Catálogo de modelos; não significa 49 carros simultâneos nem comprova disponibilidade de cada modelo no trânsito.', 'rows': [{'id': k, 'name': v.get('label', k), 'source': 'assets/fleet/catalog.json'} for k, v in fleet.items()]})
    extra = []
    for source in ['gameplay/desert_cars/DesertCarCatalog.gd', 'gameplay/mining/MiningFleet.gd']:
        for key, label in re.findall(r'"([a-z0-9_]+)"\s*:\s*\{\s*(?:"base_id"\s*:\s*"[^"]+",\s*)?"label"\s*:\s*"([^"]+)"', read(source)):
            extra.append({'id': key, 'name': label, 'source': source})
    for key, label, source in [
        ('police_transport','Camburão tático','runtime/FleetCatalog.gd'),('bike_police','Moto policial','runtime/FleetCatalog.gd'),('army_tank','Blindado do Exército','runtime/FleetCatalog.gd'),
        ('armored_truck','Carro-forte','gameplay/armored/ArmoredTruckModel.gd'),('digo_gol_1993','Gol 1993 do Digo','gameplay/digo/DigoCarSpec.gd'),('digo_amarok_2014','Amarok 2014 do Digo','gameplay/digo/DigoAmarokSpec.gd'),('jessica_jetta_gli','Jetta GLI da Jessica','gameplay/jessica/JessicaCarSpec.gd'),('cobra_boss_ironback','Ironback V8','runtime/GarageRewardFleet.gd')]:
        extra.append({'id': key, 'name': label, 'source': source})
    catalogs.append({'title':'Frota adicional — IDs especializados', 'note':'Extensões da frota base. Trem, BRT e veículos de exposição possuem controladores próprios e não entram nessa soma.', 'rows':extra})
    source = 'world/places/PlaceCatalog.gd'
    places = [{'id':i,'name':n,'source':source} for i,n in re.findall(r'\["([a-z0-9_]+)","([^"]+)","(?:harbor|mountain)"',read(source))]
    places += [{'id':f'mountain_cabin_village_{i}','name':f'Chalé {i:02d}','source':source} for i in range(1,5)]
    catalogs.append({'title':'Lugares do catálogo principal', 'note':'Lista literal mais quatro chalés gerados. Catálogos especializados de prédios, deserto, mina, QG e serviços ampliam esta lista; ela não é a contagem total de interiores.', 'rows':places})
    original = json.loads(read('world/regions/OriginalWorldData.json'))
    for key,title in [('harbor_buildings','Edifícios da base de Harbor'),('harbor_roads','Ruas da base de Harbor')]:
        catalogs.append({'title':title,'note':'Base autorada, antes das alterações do editor. Não somar esta lista aos edifícios acessíveis: há sobreposição e exclusões.', 'rows':[{'id':r['id'],'name':r.get('name') or r.get('kind') or r['id'],'source':'world/regions/OriginalWorldData.json'} for r in original[key]]})
    edits=json.loads(read('world/editing/world_edits.json'))
    rows=[]
    for region, records in edits.get('regions',{}).items():
        for key,r in records.items():
            rows.append({'id':region+'/'+key,'name': ('Removido: ' if r.get('deleted') else '')+str(r.get('name') or r.get('model') or r.get('type') or key),'source':'world/editing/world_edits.json'})
    catalogs.append({'title':'Objetos e alterações do editor', 'note':'Registros do documento compartilhado no momento da geração. Alteração não equivale a objeto novo; itens removidos são identificados.', 'rows':rows})
    data['source_catalogs']=catalogs
    index=[]
    roots=['activities','assets','audio','cutscenes','data','gameplay','migration','runtime','scripts','systems','ui','world']
    extensions={'.gd','.cs','.tscn','.scn','.tres','.gdshader','.json','.glb','.gltf','.obj','.fbx','.blend','.wav','.ogg','.mp3','.png','.jpg','.webp','.svg','.flac','.ttf','.otf','.gdshaderinc','.res','.srt','.ogv','.mp4','.webm','.txt','.md','.py','.html'}
    for folder in roots:
        for p in sorted((ROOT/folder).rglob('*')):
            if p.is_file() and p.suffix.lower() in extensions and not p.name.startswith(('test_', 'validate_')):
                index.append({'path':p.relative_to(ROOT).as_posix(),'kind':p.suffix[1:], 'group':folder})
    data['file_index']=index
    payload=json.dumps(data,ensure_ascii=False).replace('</','<\\/')
    page=TEMPLATE.replace('__DATA__',payload).replace('__AGENTS__',str(data.get('extra_agents',1))).replace('__DATE__', '17/10/2026')
    (DOCS/'painel-geteco.html').write_text(page,encoding='utf-8')
    print(json.dumps({'cards':len(data['cards']),'catalog_rows':sum(len(c['rows']) for c in catalogs),'indexed_files':len(index)},ensure_ascii=False))

TEMPLATE='''<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>GETECO — inventário e board</title><style>
:root{color-scheme:dark;--bg:#10151c;--panel:#19222d;--line:#354352;--muted:#adbccd;--text:#eef4fa;--accent:#ffc078}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.6 system-ui,sans-serif}main{max-width:1600px;margin:auto;padding:32px 24px}h1{font-size:38px;line-height:1.15;margin:10px 0}h2{font-size:23px}h3{font-size:17px;margin:5px 0}p{margin:8px 0}a{color:#9cd5ff;overflow-wrap:anywhere}small,.muted{color:var(--muted)}.eyebrow{color:var(--accent);letter-spacing:.14em;font-weight:700}.intro{max-width:1050px}.notice{border-left:3px solid var(--accent);padding:12px 18px;background:var(--panel);margin:22px 0}.toolbar{display:flex;flex-wrap:wrap;gap:12px;margin:20px 0;position:sticky;top:0;background:var(--bg);padding:12px 0;z-index:2}input,select,button{font:inherit;color:var(--text);background:var(--panel);border:1px solid var(--line);padding:10px 12px;border-radius:7px}input{flex:1;min-width:220px}button{cursor:pointer}button:hover{border-color:var(--accent)}:focus-visible{outline:3px solid var(--accent);outline-offset:2px}.stats{display:flex;flex-wrap:wrap;gap:10px}.stat{padding:10px 15px;background:var(--panel);border:1px solid var(--line);border-radius:8px}.stat b{font-size:23px;padding-right:7px}.board{display:flex;gap:18px;align-items:start;overflow-x:auto;padding-bottom:14px}.column{flex:1;min-width:280px}.column>h2{position:relative;font-size:18px;border-bottom:3px solid var(--stripe);padding-bottom:10px}.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:16px;margin:12px 0;overflow-wrap:anywhere}.card p{font-size:14px;color:#d0dce8}.tag{color:var(--accent);font-size:12px;text-transform:uppercase;letter-spacing:.06em}.sources{font-size:12px;border-top:1px solid var(--line);margin-top:12px;padding-top:8px;display:grid;gap:4px}.next{font-size:13px;color:#ffd496}details{border:1px solid var(--line);border-radius:8px;padding:12px 16px;margin:12px 0}summary{cursor:pointer;font-weight:600}table{border-collapse:collapse;width:100%;font-size:13px}th,td{border-bottom:1px solid var(--line);padding:8px;text-align:left;overflow-wrap:anywhere}th{color:var(--accent)}.tablewrap{overflow:auto;max-height:520px}.empty{padding:20px;color:var(--muted)}footer{border-top:1px solid var(--line);margin-top:36px;padding-top:20px}pre{white-space:pre-wrap;overflow-wrap:anywhere}section{scroll-margin-top:95px}@media(max-width:1000px){.column{min-width:310px}}@media(max-width:650px){main{padding:20px 14px}.column{min-width:310px}h1{font-size:30px}.toolbar{position:static}}@media print{.toolbar{display:none}.board{display:block}.card{break-inside:avoid}body{color:#111;background:white}.card{background:white;color:#111}.card p{color:#111}}
</style></head><body><main>
<header><div class="eyebrow">GETECO / LEVANTAMENTO DO PROJETO</div><h1>O que existe. O que falta. O que precisa de revisão.</h1><p class="muted">Atualizado em __DATE__ · código local + documentação · Godot 4.7.2 .NET · __AGENTS__ agentes extras</p></header>
<div class="intro"><p>Inventário de funcionalidades, mundo, objetos, prédios, veículos, personagens, armas, áudio, missões e história. Inclui o trabalho local ainda não commitado. Os estados abaixo descrevem a evidência encontrada; não são uma aprovação global do jogo.</p>
<div class="notice"><b>Como ler:</b> “Implementado” significa código/conteúdo conectado ou execução documentada. “Parcial” inclui conteúdo existente com escopo ou validação pendente. “Problema documentado” exige resolução ou investigação. Registros antigos sem confirmação atual ficam em “A reconfirmar”. Arquivos, modelos, falas, vínculos de voz, acessos e interiores são contagens diferentes. O inventário inicial foi documental; validações posteriores estão identificadas nos cards, com seu escopo e evidências.</div></div>
<nav><a href="#board">Board</a> · <a href="#catalogs">Catálogos</a> · <a href="#files">Índice de arquivos</a> · <a href="historico/painel-geteco-antes-20261007.html">Board anterior preservado</a></nav>
<div class="stats" id="stats"></div>
<div class="toolbar"><input id="search" aria-label="Buscar no board e catálogos" placeholder="Buscar missão, objeto, carro, personagem, problema…"><select id="area" aria-label="Área"><option value="all">Todas as áreas</option></select><select id="status" aria-label="Estado"><option value="all">Todos os estados</option></select><button id="clear">Limpar filtros</button></div>
<p id="result" role="status" aria-live="polite"></p><section id="board" class="board"></section>
<section id="catalogs"><h2>Catálogos e objetos identificados</h2><p class="muted">Busca por texto também filtra estas listas. Os filtros de área/estado se aplicam aos cards. Fontes preservam os IDs técnicos; alguns nomes históricos vêm diretamente dos arquivos.</p><div id="catalog-content"></div><div id="story-catalogs"></div></section>
<section id="files"><h2>Índice de arquivos de conteúdo e fontes</h2><p class="muted">Fontes, modelos, cenas, texturas, sons e dados nas 12 pastas de produção. Exclui caches/importações, evidências, builds, testes, ferramentas e a árvore duplicada geteco_v2. A presença no disco não comprova uso no jogo. Objetos procedurais podem representar milhares de instâncias em um único arquivo; contagem exata de instâncias ativas exige levantamento em runtime.</p><select id="file-group" aria-label="Pasta do índice"><option value="all">Todas as pastas</option></select><p id="file-count"></p><div class="tablewrap"><table><thead><tr><th>Arquivo</th><th>Tipo</th></tr></thead><tbody id="file-rows"></tbody></table></div><button id="more">Mostrar mais arquivos</button></section>
<footer><b>Escopo e manutenção</b><p>Fotografia documental de __DATE__, incluindo trabalho de 07–17/10. Alterações de outras sessões podem avançar após a coleta. Evidências anteriores valem somente para seus cenários e versões. Pendências de performance, colisão, oclusão, áudio percebido e iluminação temporal continuam explícitas.</p><p>Dados revisáveis: <a href="board-inventario-20261007.json">mundo e sistemas</a> · <a href="board-historia-20261007.json">história, elenco e áudio</a> · <a href="board-atualizacoes-20261008.json">atualizações de 07–08/10</a> · <a href="board-atualizacoes-20261017.json">atualizações de 08–17/10</a>. Para reconstruir o HTML: <code>python tools/build_geteco_board.py</code>. Não calcula automaticamente o estado de uma feature.</p><p>Validação futura do jogo: compilar <code>Harbor.csproj</code> e usar a instalação Godot 4.7.2 <b>.NET</b> do projeto. Testes headless não certificam FPS. As correções e validações posteriores estão identificadas nos cards; este painel não certifica todo o jogo.</p></footer>
</main><script id="board-data" type="application/json">__DATA__</script><script>
'use strict';
const data=JSON.parse(document.getElementById('board-data').textContent);
const states={implemented:'Implementado',partial:'Parcial / validação pendente',issue:'Problema documentado',planned:'Planejado / não implementado',unverified:'A reconfirmar',cancelled:'Backlog: cancelado / removido'};
const colors={implemented:'#65d795',partial:'#e8bc62',issue:'#ed8080',planned:'#92b9fc',unverified:'#b7a1d6',cancelled:'#8b949e'};
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const norm=s=>String(s).normalize('NFD').replace(/[\\u0300-\\u036f]/g,'').toLowerCase();
const link=p=>'<a href="../'+esc(p)+'">'+esc(p)+'</a>';
const search=document.getElementById('search'),area=document.getElementById('area'),status=document.getElementById('status'),group=document.getElementById('file-group');
let limit=150;
for(const a of [...new Set(data.cards.map(c=>c.area))].sort())area.insertAdjacentHTML('beforeend','<option>'+esc(a)+'</option>');
for(const [k,v]of Object.entries(states))status.insertAdjacentHTML('beforeend','<option value="'+k+'">'+v+'</option>');
for(const a of [...new Set(data.file_index.map(f=>f.group))].sort())group.insertAdjacentHTML('beforeend','<option>'+esc(a)+'</option>');
document.getElementById('stats').innerHTML=Object.entries(states).map(([k,v])=>'<div class="stat"><b>'+data.cards.filter(c=>c.status===k).length+'</b>'+v+'</div>').join('');
function render(){
 const q=norm(search.value);const matches=x=>!q||norm(JSON.stringify(x)).includes(q);
 const cards=data.cards.filter(c=>(area.value==='all'||c.area===area.value)&&(status.value==='all'||c.status===status.value)&&matches(c));
 document.getElementById('result').textContent=cards.length+' de '+data.cards.length+' cards exibidos';
 document.getElementById('board').innerHTML=Object.entries(states).filter(([k])=>status.value==='all'||status.value===k).map(([k,v])=>{const rows=cards.filter(c=>c.status===k);return '<div class="column" style="--stripe:'+colors[k]+'"><h2>'+v+' · '+rows.length+'</h2>'+rows.map(c=>'<article class="card" id="'+esc(c.id)+'"><div class="tag">'+esc(c.area)+'</div><h3>'+esc(c.title)+'</h3><p>'+esc(c.description)+'</p>'+(c.cancel_reason?'<div class="next">Por que saiu: '+esc(c.cancel_reason)+(c.cancelled_on?' ('+esc(c.cancelled_on)+')':'')+'</div>':'')+(c.next?'<div class="next">Próximo passo: '+esc(c.next)+'</div>':'')+'<div class="sources">'+c.sources.map(link).join('')+'</div></article>').join('')+(rows.length?'':'<p class="empty">Nenhum card neste filtro.</p>')+'</div>'}).join('');
 document.getElementById('catalog-content').innerHTML=data.source_catalogs.map(c=>{const rows=c.rows.filter(matches);if(!rows.length)return '';return '<details'+(q?' open':'')+'><summary>'+esc(c.title)+' · '+rows.length+'</summary><p class="muted">'+esc(c.note)+'</p><div class="tablewrap"><table><thead><tr><th>ID</th><th>Nome / tipo</th><th>Fonte</th></tr></thead><tbody>'+rows.map(r=>'<tr><td>'+esc(r.id)+'</td><td>'+esc(r.name)+'</td><td>'+link(r.source)+'</td></tr>').join('')+'</tbody></table></div></details>'}).join('');
 document.getElementById('story-catalogs').innerHTML=Object.entries(data.catalogs).filter(([k,v])=>matches([k,v])).map(([k,v])=>'<details'+(q?' open':'')+'><summary>'+esc(k)+'</summary><pre>'+esc(typeof v==='string'?v:JSON.stringify(v,null,2))+'</pre></details>').join('');
 const files=data.file_index.filter(f=>(group.value==='all'||group.value===f.group)&&matches(f));
 document.getElementById('file-count').textContent=files.length+' arquivos encontrados · '+Math.min(limit,files.length)+' exibidos';
 document.getElementById('file-rows').innerHTML=files.slice(0,limit).map(f=>'<tr><td>'+link(f.path)+'</td><td>'+esc(f.kind)+'</td></tr>').join('');
 document.getElementById('more').hidden=limit>=files.length;
}
for(const el of [search,area,status,group])el.addEventListener('input',()=>{limit=150;render()});
document.getElementById('clear').addEventListener('click',()=>{search.value='';area.value=status.value=group.value='all';limit=150;render()});
document.getElementById('more').addEventListener('click',()=>{limit+=300;render()});render();
</script></body></html>'''

if __name__=='__main__':
    build()
