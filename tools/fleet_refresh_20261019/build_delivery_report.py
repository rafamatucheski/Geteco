"""Indexa as evidências reais da frota. Rode depois da validação renderizada e do benchmark."""
import html
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'artifacts/car-fleet-implementation-20261019'
NEW = ROOT / 'artifacts/car-design-implementation-20261019'
NAMES = {'besouro_1300':'Besouro 1300','mare_microvan':'Maré','toco_minitruck':'Toco',
         'sedan_classic':'Premier','union_sedan':'Union','aurora_executive':'Aurora',
         'metro_hatch':'Metro','station_wagon':'Station Wagon','desert_faisca':'Faísca',
         'desert_faisca_rally':'Faísca RX','ranch_pickup':'Ranch cabine dupla','ranch_single':'Ranch cabine simples'}

def href(path):
    return html.escape(os.path.relpath(path, OUT).replace('\\','/'), quote=True)

def link(path, text):
    return f'<a href="{href(path)}">{html.escape(text)}</a>'

def photo(path, caption):
    return f'<figure><a href="{href(path)}"><img loading="lazy" src="{href(path)}" alt="{html.escape(caption)}"></a><figcaption>{html.escape(caption)}</figcaption></figure>'

def table(headers, rows):
    return '<div class="scroll"><table><thead><tr>'+''.join(f'<th>{h}</th>' for h in headers)+'</tr></thead><tbody>'+''.join('<tr>'+''.join(f'<td>{v}</td>' for v in row)+'</tr>' for row in rows)+'</tbody></table></div>'

parts = ['''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Geteco — frota 19/10/2026</title><style>
body{font:16px/1.55 system-ui;background:#151a1d;color:#e9eceb;max-width:1280px;margin:40px auto;padding:0 24px}a{color:#a7d3bb}h1,h2{line-height:1.2}h2{margin-top:48px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px}figure{margin:0;background:#232b30;padding:8px}img{width:100%;display:block}figcaption{padding:8px}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{padding:10px;text-align:left;border-bottom:1px solid #425048}.scroll{overflow:auto}.note{border-left:4px solid #e6ba69;padding:12px 20px;background:#28271f}code{font-size:13px}details{margin:18px 0}small{color:#b6c0bc}</style><h1>Frota Geteco · 19/10/2026</h1>
<p>Três modelos civis novos e nove apresentações existentes revisadas. Autoria dividida entre três agentes; integração e validação no Godot 4.7.2 .NET.</p>
<p class="note">A comparação de FPS tem limitação de isolamento: o usuário autorizou continuar com outras sessões executando Godot. Houve também mudanças externas em sombras e renderer: o baseline inicial usou Mobile e a validação final abriu em Forward+. O bloco pareado usa as duas versões visuais na mesma cena atual; mede o custo dessas apresentações, sem certificar toda a simulação ou FPS universal.</p>
<h2>Novos modelos</h2><div class="grid">''']
for ident in list(NAMES)[:3]:
    parts.append(photo(NEW/'new-model-photos'/f'{ident}-front.png', NAMES[ident]))
parts.append('</div><p>Besouro: compacto arredondado; Maré: microvan de passageiros; Toco: utilitário de cabine avançada. Portas, bancos, rodas, pintura, lentes e colisão seguem o sistema existente.</p>')
manifest = json.loads((OUT/'current-installed-manifest.json').read_text(encoding='utf-8-sig'))
rows=[]
for ident, data in manifest.items():
    rows.append([NAMES.get(ident,ident),int(data['before']['triangles']),int(data['after']['triangles']),f"{int(data['before']['meshes'])} → {int(data['after']['meshes'])}"])
parts.append('<h2>Carros atuais</h2><p>Silhuetas, rodas e lanternas foram diferenciadas por família. Os nove carros passaram de 31.628 para 29.056 triângulos (−8,1%); 65 para 59 malhas, mantendo 206 superfícies.</p>')
parts.append(table(['Modelo','Triângulos antes','Triângulos depois','Malhas'],rows))
for ident in list(NAMES)[3:]:
    parts.append(f'<details><summary>{NAMES[ident]} — antes/depois e vistas finais</summary><div class="grid">')
    for prefix, view, caption in [('before-','side','Antes'),('','side','Depois'),('','front','Frente final'),('','rear','Traseira final')]:
        parts.append(photo(OUT/'refreshed'/f'{prefix}{ident}-{view}.png',f'{NAMES[ident]} · {caption}'))
    parts.append('</div></details>')
parts.append('<h2>Integração e testes</h2><p>Distribuição por cinco perfis de região/via, 27 modelos civis possíveis, sem aumentar os limites de população. Os três novos IDs participam de estacionamento e persistência. Veículos narrativos continuam reservados aos seus contextos.</p>')
test_paths = [NEW/'civilian-roster-contract.log',NEW/'vehicle-doors-12.log',NEW/'aurora-cabin-floor-production.log',OUT/'ranch-contracts-fixed.log',NEW/'fleet-contracts-12.log']
parts.append('<ul>'+''.join('<li>'+link(path,path.name)+'</li>' for path in test_paths if path.exists())+'</ul>')
parts.append('<p>O consolidado inicial teve duas falhas de aliases de materiais das Ranch, corrigidas e revalidadas em teste dirigido. O log inicial foi preservado. Build C# final: 0 avisos, 0 erros. Geometria, cabine, portas e persistência são contratos; sua aprovação não substitui as evidências renderizadas abaixo.</p>')
parts.append('<h2>Jogo real · entrada, direção, freios e saída</h2><p>Primeira tentativa final-a preservada: Besouro concluiu o fluxo, mas registrou nove quadros de freio contra mínimo dez. A observação foi prolongada na tentativa final-b sem reduzir o critério. A primeira transição noturna da tentativa A teve um intervalo de 17,793s entre frames renderizados; captura, primeira visita, compilação gráfica e concorrência estão misturadas, sem causa isolada. Isso não é evidência de noite fluida. '+link(OUT/'temporal/final-a/besouro_1300/flow.json','Tentativa A completa')+'</p>')
flows={}
for path in sorted((OUT/'temporal').glob('*/*/flow.json'), key=lambda p:p.stat().st_mtime):
    data=json.loads(path.read_text(encoding='utf-8-sig'))
    if data.get('ok'): flows[path.parent.name]=(path,data)
rows=[]
for ident in NAMES:
    if ident in flows:
        path,data=flows[ident]
        rows.append([NAMES[ident],link(path,'PASS — JSON completo'),len(data.get('frames',[])),f"{data.get('continuous_seconds',0):.1f} s",data.get('skipped_rendered_frames','ver JSON')])
    else: rows.append([NAMES[ident],'Não concluído','—','—','—'])
parts.append(table(['Modelo','Resultado','Frames','Duração','Frames omitidos'],rows))
parts.append('<p>Capturas da Main real, rota autorada admitida por colisão, comandos normais de entrada/aceleração/direção/frenagem/saída. Dia e noite secos, baixa velocidade. O readback JPEG aumenta o tempo de frame: sua cadência não é benchmark de FPS. Estado das lâmpadas não certifica pixels do feixe. Chuva, túneis, velocidade máxima, todos os mapas e todas as fronteiras de streaming não foram certificados. O marcador legado normal_settings_skipped=true da rodada final-a foi herdado incorretamente: o autoload V2Settings aplicou preferências; prevalecem renderer, resolução, MSAA e VSync efetivamente registrados. O runner foi corrigido para as próximas rodadas.</p>')
for ident,(path,data) in flows.items():
    parts.append(f'<details><summary>{NAMES.get(ident,ident)} — frames reais</summary><div class="grid">')
    for snap in sorted(path.parent.glob('*.png')):
        parts.append(photo(snap,snap.stem))
    parts.append('</div>'+link(path,'Frames, timestamps e estados completos'))
    if (path.parent/'drive.mp4').exists(): parts.append('<p>'+link(path.parent/'drive.mp4','Vídeo com timestamps originais')+'</p>')
    parts.append('</details>')
parts.append('<h2>Performance renderizada</h2>')
paired=OUT/'performance/paired-final/paired-summary.json'
if paired.exists():
    data=json.loads(paired.read_text(encoding='utf-8-sig'))
    parts.append(f'<p>Bloco ABBA: {data.get("completed_samples",0)}/8 amostras; contrato interno válido: {data.get("measurement_valid")}. Dez corpos fixos, câmera e sombras atuais iguais; somente as apresentações alternam. Dois recursos residentes por corpo, um visível. Três slots substituem modelos doadores pelos novos.</p>')
    rows=[]
    for case,values in data.get('cases',{}).items():
        for key in ['baseline','final']:
            s=values[key]
            rows.append([case,key,f"{s['fps']:.2f}",f"{s['p50_ms']:.2f}",f"{s['p95_ms']:.2f}",f"{s['p99_ms']:.2f}",f"{s['max_ms']:.2f}",f"{s['over_33_3_ms']} / {s['over_66_7_ms']}",f"{s['frames']} / {s['seconds']:.1f}s"])
    parts.append(table(['Cenário','Versão','FPS','p50 ms','p95 ms','p99 ms','Máx ms','>33,3 / >66,7ms','Frames/tempo'],rows))
    parts.append('<p>'+link(paired,'Comparação pareada e deltas completos')+'</p>')
rows=[]
for label in ['before-diagnostic','paired-final']:
    for case in (['day','night','normal-day'] if label=='before-diagnostic' else ['normal-day']):
        path=OUT/'performance'/label/f'{case}.json'
        if not path.exists(): continue
        data=json.loads(path.read_text(encoding='utf-8-sig')); s=data['summary']
        rows.append([label,case,html.escape(data['renderer']),html.escape(data['resolution']),f"{s['fps']:.2f}",f"{s['p95_ms']:.2f}",f"{s['p99_ms']:.2f}",link(path,'Dados brutos')])
parts.append('<h3>Diagnóstico inicial e configuração normal</h3><p>Essas janelas separadas têm tráfego vivo, fontes globais alteradas e concorrência externa. Não atribuir sua diferença somente aos carros.</p>')
parts.append(table(['Rodada','Cenário','Renderer','Resolução','FPS','p95 ms','p99 ms','Dados'],rows))
parts.append('<p>Hardware observado no baseline: RTX 4060 Laptop / i7-13650HX, Vulkan Mobile, 3440×1440. Alvo provisório: 60 FPS / 16,67 ms. Cada janela aceita ≥30s de intervalos reais após 10s de aquecimento; cidade estabilizada por 60s. Cap normal observado: 144 / VSync. As configurações efetivas e população real de cada janela constam nos JSON.</p>')
parts.append('<p>'+link(OUT/'validation-plan.json','Plano e limites definidos antes das medições')+' · '+link(OUT/'current-installed-manifest.json','Manifesto instalado e hashes')+'</p><p><small>Escopo local da frota. Aprovação funcional, apresentação estática, observação temporal e desempenho são resultados distintos. Evidências de tentativas com falha foram preservadas.</small></p></html>')
(OUT/'review.html').write_text('\n'.join(parts),encoding='utf-8')
print(OUT/'review.html')
