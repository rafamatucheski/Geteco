"""Publish local geometry inventory, lazy runtime registry and photographic review.

Reads offline authoring reports; performs no gameplay tests or FPS measurement.
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "evidence/fleet-redesign-20261011"
DERIVED_LABELS = {"armored_truck": "Carro-forte", "police_transport": "Camburão tático"}


def read(path):
    return json.loads((EVIDENCE / path).read_text(encoding="utf-8-sig"))


def metrics(row):
    return {key: int(row[key]) for key in ("meshes", "surfaces", "triangles")}


def main():
    catalog = json.loads((ROOT / "assets/fleet/catalog.json").read_text(encoding="utf-8-sig"))["vehicles"]
    vehicles = {}
    for group in ("passenger", "utility", "service", "special"):
        if group == "utility":
            before = read("utility/baseline.json")
            after = read("utility/after.json")
        elif group == "service":
            rows = read("service/report.json")["vehicles"]
            before = {key: row["before"] for key, row in rows.items()}
            after = {key: row["after"] for key, row in rows.items()}
        else:
            before = read(f"{group}/original-inventory.json")
            after = read(f"{group}/production.json")
        for key, row in after.items():
            asset = ROOT / f"assets/fleet/redesigned/{key}.scn"
            source_spec = before[key].get("spec", catalog.get(key, {}))
            vehicles[key] = {
                "group": group,
                "label": source_spec.get("label", DERIVED_LABELS.get(key, key)),
                "before": metrics(before[key]),
                "after": metrics(row),
                "asset": asset.relative_to(ROOT).as_posix(),
                "bytes": asset.stat().st_size,
                "sha256": hashlib.sha256(asset.read_bytes()).hexdigest(),
                "photos": {variant: {angle: f"{group}/{variant}/{key}-{angle}.png" for angle in ("front", "rear")} for variant in ("before", "after")},
            }
            if key == "metro_hatch":
                vehicles[key]["note"] = "Meshy removido a pedido do usuário. Novo hatch baseado na carroceria Metro; 7 malhas contra 5 do Meshy (exceção explícita), com menos triângulos. Dimensões retomam o catálogo Metro."
    totals = {variant: {key: sum(row[variant][key] for row in vehicles.values()) for key in ("meshes", "surfaces", "triangles")} for variant in ("before", "after")}
    validation_path = EVIDENCE / "validation/summary.json"
    validation = json.loads(validation_path.read_text(encoding="utf-8")) if validation_path.exists() else None
    manifest = {
        "date": "2026-10-11", "count": len(vehicles),
        "scope": "59 modelos dirigíveis: passeio, esportivos, utilitários, serviço, deserto e personagens; Infernus GT mantém o redesenho anterior. Motos, ônibus, tanque, empilhadeira e máquinas de mineração ficam fora deste lote de carros.",
        "validation": validation["status"] if validation else "Autoria, contagem de geometria e inspeção de fotos. Testes funcionais, condução, iluminação temporal e benchmark não executados, por pedido explícito do usuário.",
        "validation_report": "../../docs/reviews/fleet-redesign-validation-20261011.md" if validation else None,
        "totals": totals, "vehicles": vehicles,
    }
    (EVIDENCE / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    registry = ['extends RefCounted', '## Baked presentation only. Physics/handling remain in the existing catalogs.', '## Lazy loading keeps the full roster out of startup memory.', 'static var enabled := true', 'static var _scenes: Dictionary = {}', 'const MESH_COUNTS := {']
    registry += [f'\t"{key}":{row["after"]["meshes"]},' for key, row in sorted(vehicles.items())]
    registry += ['}', '', 'static func contains(id: String) -> bool:', '\treturn enabled and MESH_COUNTS.has(id)', '', 'static func scene_path(id: String) -> String:', '\treturn "res://assets/fleet/redesigned/"+id+".scn"', '', 'static func create(id: String) -> Node3D:', '\tif not contains(id): return null', '\tif not _scenes.has(id): _scenes[id]=load(scene_path(id)) as PackedScene', '\tvar packed: PackedScene=_scenes[id]', '\treturn packed.instantiate() as Node3D if packed!=null else null', '']
    (ROOT / "runtime/RedesignedFleet.gd").write_text("\n".join(registry), encoding="utf-8")
    build_review(manifest)
    build_report(manifest)
    print(json.dumps({"count":len(vehicles),"totals":totals}, ensure_ascii=False))


def build_report(manifest):
    def fmt(value):
        return f"{value:,}".replace(",", ".")

    lines = [
        "# Redesenho da frota — 11/10/2026",
        "",
        "59 apresentações de veículos instaladas pelo `FleetCatalog.create`, além do Infernus GT anterior. "
        "O usuário pediu três agentes e fotos durante a autoria. Depois da dispensa inicial, "
        "solicitou testes funcionais e de performance; a cobertura atual consta abaixo.",
        "",
        "[Galeria com 236 fotos reais, antes/depois e frente/traseira](../../evidence/fleet-redesign-20261011/review.html) "
        "· [Inventário por veículo e hashes](../../evidence/fleet-redesign-20261011/manifest.json)",
        "",
        "Fotos adicionais da variante de sorvete: "
        "[frente](../../evidence/fleet-redesign-20261011/utility/icecream/front.png), "
        "[traseira](../../evidence/fleet-redesign-20261011/utility/icecream/rear.png) e "
        "[junção no teto](../../evidence/fleet-redesign-20261011/utility/icecream/roof.png).",
        "",
        "## Resultado de geometria",
        "",
        "| Inventário dos 59 modelos | Antes | Depois | Redução |",
        "|---|---:|---:|---:|",
    ]
    for key, label in (("meshes", "Malhas"), ("triangles", "Triângulos"), ("surfaces", "Superfícies")):
        before = manifest["totals"]["before"][key]
        after = manifest["totals"]["after"][key]
        reduction = f"{100 * (1 - after / before):.1f}".replace(".", ",")
        lines.append(f"| {label} | {fmt(before)} | {fmt(after)} | {reduction}% |")
    lines += [
        "",
        "As contagens usam a apresentação completa, incluindo acabamentos do factory original. "
        "58 modelos reduzem malhas e triângulos individualmente. O Metro substitui o hatch Meshy rejeitado: "
        "passa de 5 para 7 malhas, mas reduz os triângulos. A diferença de malhas está exposta na galeria. "
        "O novo Metro retoma as dimensões do catálogo do hatch; não usa a colisão curta do piloto Meshy.",
        "",
        "## Design e construção",
        "",
        "- Utilitários e serviços receberam carrocerias autoradas por família, com caixas de roda abertas, "
        "cabines, caçambas e equipamentos legíveis. Os demais mantêm sua identidade de carroceria e receberam "
        "rodas, acabamento frontal/traseiro e detalhes específicos.",
        "- Pneus foscos, aros com raios, discos/pinças, molduras de faróis, grades, saias e difusores "
        "distribuem detalhe onde aparece na silhueta e na câmera. Materiais fixos usam cores por vértice.",
        "- A revisão fotográfica corrige apoios de bagageiros, suporte de equipamentos, junções de cabine "
        "e painéis de fechamento. Pequenas peças e painéis de vidro são preservados durante a redução; "
        "reduzir uma malha inteira sem separar componentes havia apagado alguns desses detalhes.",
        "- Geometria estática é consolidada fora do runtime. Rodas preservam pivôs; detalhes de porta "
        "ficam separados quando necessários. O blindado preserva os ramos do cofre. A intenção de manter "
        "essas funções não substitui teste de abertura, animação ou interação.",
        "- `runtime/RedesignedFleet.gd` carrega os recursos sob demanda. Não foram adicionados loops por "
        "quadro, luzes de jogo ou alterações de dirigibilidade para produzir o acabamento.",
        "- O Supra exposto pelo Takeshi também usa o modelo novo, mantendo a mesma apresentação antes "
        "e depois de ser obtido. A variante de sorvete recebe adaptação do vidro e do ornamento ao novo Courier.",
        "",
        "## Processo reproduzível",
        "",
        "Os autoradores ficam em `tools/fleet_fixups/`: `build_passenger_batch.gd`, "
        "`build_utility_batch.gd`, `build_service_batch.gd` e `build_special_batch.gd`. "
        "Usam `FleetBatchMesh.gd`, `PassengerDesign.gd`, `ServiceMeshKit.gd`, "
        "`SpecialFleetDesign.gd` e `SpecialMeshReduction.gd`. Os resultados são "
        "`assets/fleet/redesigned/<id>.scn`. Os originais e os inventários de partida foram preservados.",
        "",
        "`capture_fleet_batch.gd` fotografa os recursos no Godot 4.7.2 .NET, com câmera, luz e pintura "
        "comparáveis. `--variant=after --production` usa o factory ativo; `--variant=before` "
        "seleciona o original apenas naquele processo. O Metro mudou de dimensões por substituir o Meshy, "
        "portanto o enquadramento acompanha sua nova carroceria.",
        "",
        "`python tools/fleet_fixups/publish_fleet_redesign.py` recompõe o registro, o manifesto, "
        "esta revisão e a galeria a partir dos relatórios de autoria. Depois de alterar um asset, "
        "refotografar o respectivo carro e republicar para manter contagens e evidência alinhadas.",
        "",
        "## Cobertura e limites",
        "",
        manifest["scope"],
        "",
        manifest["validation"],
        "",
        "[Resultados, tentativas e limites da validação](fleet-redesign-validation-20261011.md).",
        "",
        "Menos triângulos reduz o trabalho geométrico da GPU; menos instâncias e superfícies pode "
        "reduzir trabalho de preparação/submissão da renderização na CPU. Isso não reduz na mesma "
        "proporção física, IA, tráfego, iluminação ou o custo dos pixels. Os percentuais acima são "
        "de geometria, não ganho de FPS. O contador presente nas fotos inclui carregamento e captura "
        "do showroom; não é benchmark do jogo.",
        "",
        "O padrão visual continua em [vehicle-art-standard.md](../vehicle-art-standard.md). "
        "Esta entrega não certifica o funcionamento ou a performance dos 59 veículos em gameplay.",
        "",
    ]
    (ROOT / "docs/reviews/fleet-redesign-20261011.md").write_text("\n".join(lines), encoding="utf-8")


def build_review(manifest):
    data = json.dumps(manifest, ensure_ascii=False).replace("</", "<\\/")
    page = '''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Frota Geteco — 59 redesenhos</title>
<style>*{box-sizing:border-box}body{margin:0;background:#11171b;color:#ecede9;font:16px system-ui}header{padding:38px max(4vw,20px) 20px;background:#1c282e}h1{font-size:clamp(26px,4vw,46px);margin:8px 0}p{max-width:920px;line-height:1.5;color:#b9c8ce}small{color:#a2b6bf}nav{position:sticky;top:0;background:#11171bef;backdrop-filter:blur(10px);padding:16px 4vw;z-index:2;display:flex;gap:10px;flex-wrap:wrap}input,select,button{font:inherit;color:inherit;background:#24353e;border:1px solid #4b626e;padding:10px 14px;border-radius:6px}input{flex:1;min-width:180px}main{padding:20px 4vw 60px;display:grid;gap:28px}article{background:#1b272e;border:1px solid #334a55;border-radius:10px;overflow:hidden}article h2{margin:20px 24px 8px;font-size:22px}.info{margin:0 24px 18px;display:flex;flex-wrap:wrap;gap:12px;color:#bfced4}.info b{color:#89dfae}.photos{display:grid;grid-template-columns:1fr 1fr;gap:2px}.photos figure{margin:0;position:relative}.photos img{width:100%;display:block;cursor:zoom-in}.photos figcaption{position:absolute;left:12px;top:10px;background:#111c24d9;padding:5px 9px;border-radius:4px;font-size:13px}.note{margin:16px 24px;color:#f1cc8e;font-size:14px}.totals{display:flex;gap:30px;flex-wrap:wrap;margin:24px 0}.totals strong{display:block;font-size:25px}dialog{padding:8px;border:0;background:#10202b;max-width:98vw;max-height:98vh}dialog::backdrop{background:#000e}dialog img{display:block;max-width:94vw;max-height:90vh}a{color:#98d8ee}.group{color:#8ba6b2;font-size:13px;margin:18px 24px 0;text-transform:uppercase;letter-spacing:.08em}@media(max-width:760px){.photos{grid-template-columns:1fr}header{padding-top:24px}}</style>
<header><small>GETECO · AUTORIA DE FROTA · 11/10/2026</small><h1>59 modelos, redesenhados e mais leves</h1><p>Fotos reais dos recursos do Godot, com câmera, iluminação e pintura de comparação. O Infernus GT continua como referência do primeiro lote.</p><div class="totals" id="totals"></div><p>Estes números descrevem a geometria dos modelos. O contador nas fotos inclui o carregamento e a captura do showroom; não representa uma medição do jogo.</p><p id="validation">VALIDATION_STATUS</p><p><a href="validation/review.html">Vídeos, testes e performance</a> · <a href="../../docs/reviews/fleet-redesign-validation-20261011.md">Relatório e limites da validação</a></p><p><a href="manifest.json">Inventário completo e hashes dos arquivos</a> · <a href="../sport-coupe-redesign/review.html">Primeiro Infernus GT</a></p></header>
<nav><input id="search" placeholder="Procurar carro…" aria-label="Procurar carro"><select id="group"><option value="">Todos os grupos</option><option value="passenger">Passeio e esportivos</option><option value="utility">Utilitários</option><option value="service">Serviços</option><option value="special">Deserto e personagens</option></select><select id="angle"><option value="front">Frente</option><option value="rear">Traseira</option></select><button id="mode">Comparar antes / depois</button></nav><main id="cars"></main><dialog id="zoom"><img alt="Fotografia ampliada"></dialog>
<script>const data=DATA;let compare=true;const $=id=>document.getElementById(id),fmt=n=>n.toLocaleString('pt-BR'),labels={passenger:'Passeio e esportivos',utility:'Utilitários',service:'Serviços',special:'Deserto e personagens'};for(const [key,label] of [['meshes','malhas'],['triangles','triângulos'],['surfaces','superfícies']]){const a=data.totals.before[key],b=data.totals.after[key];$('totals').insertAdjacentHTML('beforeend',`<div><small>${label}</small><strong>${fmt(a)} → ${fmt(b)}</strong><span>−${((1-b/a)*100).toFixed(1)}%</span></div>`)}function show(){$('cars').textContent='';for(const [id,c]of Object.entries(data.vehicles)){if($('group').value&&c.group!==$('group').value)continue;if(!(`${id} ${c.label}`.toLocaleLowerCase().includes($('search').value.toLocaleLowerCase())))continue;const a=document.createElement('article');a.innerHTML=`<div class="group">${labels[c.group]}</div><h2>${c.label}</h2><div class="info"><span>Malhas: ${fmt(c.before.meshes)} → <b>${fmt(c.after.meshes)}</b></span><span>Triângulos: ${fmt(c.before.triangles)} → <b>${fmt(c.after.triangles)}</b></span><span>Superfícies: ${fmt(c.before.surfaces)} → <b>${fmt(c.after.surfaces)}</b></span></div><div class="photos" style="${compare?'':'grid-template-columns:1fr'}">${(compare?['before','after']:['after']).map(v=>`<figure><img loading="lazy" src="${c.photos[v][$('angle').value]}" alt="${c.label}, ${v==='before'?'antes':'depois'}"><figcaption>${v==='before'?'Antes':'Depois'}</figcaption></figure>`).join('')}</div>${c.note?`<p class="note">${c.note}</p>`:''}`;$('cars').append(a)}document.querySelectorAll('article img').forEach(i=>i.onclick=()=>{$('zoom').querySelector('img').src=i.src;$('zoom').showModal()})}for(const id of ['search','group','angle'])$(id).addEventListener('input',show);$('mode').onclick=()=>{compare=!compare;show()};$('zoom').onclick=()=>$('zoom').close();show();</script></html>'''.replace("DATA", data).replace("VALIDATION_STATUS", manifest["validation"])
    (EVIDENCE / "review.html").write_text(page, encoding="utf-8")


if __name__ == "__main__":
    main()
