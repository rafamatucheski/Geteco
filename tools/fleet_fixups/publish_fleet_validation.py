"""Build a local evidence index only. Does not run Godot, encode or grant approval."""
from pathlib import Path
from html import escape
from urllib.parse import quote
from datetime import datetime
import json
import os

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "evidence/fleet-redesign-20261011"
OUT = EVIDENCE / "validation"
PERFORMANCE = OUT / "performance"
EXPECTED = ("union_sedan", "atlas_crew_pickup", "police_cruiser", "medic_box", "american_tanker_truck", "armored_truck", "beach_cabriolet")
LABELS = {"union_sedan": "Union Sedan", "atlas_crew_pickup": "Atlas Crew", "police_cruiser": "Police Cruiser", "medic_box": "Medic Box", "american_tanker_truck": "Caminhão-tanque", "armored_truck": "Carro-forte", "beach_cabriolet": "Beach Cabriolet"}


def read(path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError) as error:
        return {"_read_error": str(error)}


def href(path):
    return escape(quote(Path(os.path.relpath(path, OUT)).as_posix(), safe="/.-_"), quote=True)


def link(path, label):
    return f'<a href="{href(path)}">{escape(label)}</a>' if path.is_file() else f'{escape(label)} <small>(pendente)</small>'


def num(value, digits=3):
    return f"{value:.{digits}f}".replace(".", ",") if isinstance(value, (float, int)) else "—"


def pair(row, key, digits=3):
    return num(row.get("baseline", {}).get(key), digits) + " → " + num(row.get("final", {}).get(key), digits)


def render_pair(row, kind, quantile="mean"):
    return " → ".join(num(row.get(f"{variant}_viewport_{kind}_ms", {}).get(quantile)) for variant in ("baseline", "final"))


def table(headers, rows):
    return '<div class="scroll"><table><thead><tr>' + ''.join(f'<th>{escape(h)}</th>' for h in headers) + '</tr></thead><tbody>' + ''.join('<tr>' + ''.join(f'<td>{v}</td>' for v in row) + '</tr>' for row in rows) + '</tbody></table></div>'


def discover_runs(comparison):
    runs = {name: dict(row) for name, row in comparison.get("runs", {}).items()}
    for path in sorted(PERFORMANCE.glob("*/paired-summary.json")):
        data = read(path)
        name = path.parent.name
        if name not in runs:
            runs[name] = {"cases": data.get("cases", {}), "valid": data.get("measurement_valid", False)}
        runs[name].update(path=path, raw=data, mtime=path.stat().st_mtime)
    for name, run in runs.items():
        run.setdefault("path", PERFORMANCE / name / "paired-summary.json")
        run.setdefault("mtime", 0)
        run.setdefault("raw", {})
        run["post_fix"] = name.startswith("ten-cars-rolefix-")
        expected = 4 if run["raw"].get("confirm_case") else 8
        run["complete"] = run.get("valid") is True and run["raw"].get("completed_samples") == expected
    return runs


def run_section(name, run, selected=False):
    version = "APÓS CORREÇÃO DAS LENTES" if run["post_fix"] else "BEFORE_LENS_ROLE_FIX — histórico"
    state = "coleta completa" if run["complete"] else "coleta incompleta ou inválida"
    rows, tails = [], []
    for case, row in run.get("cases", {}).items():
        rows.append(["Dia" if case == "day" else "Noite", pair(row, "fps", 2), pair(row, "p95_ms"), pair(row, "p99_ms"), render_pair(row, "cpu"), render_pair(row, "gpu"), num(row.get("p99_change_percent"), 2) + "%"])
        tails.append(["Dia" if case == "day" else "Noite", pair(row, "max_ms"), pair(row, "over_33_3_ms", 0), pair(row, "over_66_7_ms", 0), render_pair(row, "gpu", "p95"), render_pair(row, "gpu", "p99")])
    content = f'<article><h3>{escape(name)}</h3><p><b>{version}</b> · {state}' + (' · referência atual desta revisão' if selected else '') + '</p>'
    content += table(["Cenário", "FPS antes → depois", "p95 ms", "p99 ms", "CPU render média ms", "GPU render média ms", "Δ p99"], rows) if rows else '<p>Nenhuma janela comparável concluída.</p>'
    if tails:
        content += '<details><summary>Picos e percentis da GPU</summary>' + table(["Cenário", "Máximo ms", "Quadros >33,3 ms", "Quadros >66,7 ms", "GPU p95 ms", "GPU p99 ms"], tails) + '</details>'
    content += '<p>' + link(run["path"], "Dados brutos desta rodada") + '</p>'
    photos = sorted(run["path"].parent.glob("*-final-gameplay.png"))
    if photos:
        content += '<details><summary>Fotos da cena medida</summary><div class="photos">' + ''.join(f'<a href="{href(p)}"><img loading="lazy" src="{href(p)}" alt="{escape(p.stem)}"></a>' for p in photos) + '</div></details>'
    return content + '</article>'


def temporal_card(folder):
    path = folder / "flow.json"
    flow = read(path)
    review_path = folder / "visual-review.json"
    review = read(review_path)
    movie = folder / "drive.mp4"
    video_exists = movie.is_file() and movie.stat().st_size > 0
    functional = "Passou nos estados registrados" if flow.get("ok") is True else ("Falhou" if flow.get("ok") is False else "Pendente — flow.json ainda não concluído")
    if review.get("status") == "rejected":
        visual = "REPROVADO na revisão visual"
    elif review.get("status") == "reviewed_with_limitations":
        visual = "Inspecionado com limitações — sem aprovação global"
    elif review.get("visual_approved") is False:
        visual = "Não aprovado na revisão visual"
    elif review.get("visual_approved") is True and flow.get("ok") is True and video_exists:
        visual = "Inspecionado no escopo descrito no relatório visual"
    else:
        visual = "PENDENTE — sem aprovação visual registrada"
    title = LABELS.get(folder.name, folder.name) + " · " + folder.parent.name
    result = f'<article id="{escape(folder.parent.name + "-" + folder.name)}"><h3>{escape(title)}</h3><p><b>{visual}</b></p><p>Fluxo automático: {functional}. Vídeo: {"arquivo disponível" if video_exists else "PENDENTE — arquivo não disponível"}.</p>'
    if flow.get("continuous_seconds") is not None:
        result += f'<p>{num(flow["continuous_seconds"], 2)} s; {len(flow.get("frames", []))} quadros registrados; {flow.get("skipped_rendered_frames", "—")} quadros renderizados sem captura. Cadência de captura não é FPS do jogo.</p>'
    if flow.get("failures"):
        result += '<ul>' + ''.join(f'<li>{escape(str(f))}</li>' for f in flow["failures"]) + '</ul>'
    result += '<p>' + link(path, "Estados e tentativas") + ' · ' + link(review_path, "Inspeção visual e limites") + '</p>'
    if video_exists:
        result += f'<video controls preload="none" src="{href(movie)}"></video><p>{link(movie, "Abrir vídeo")}</p>'
    photos = sorted(folder.glob("[0-9][0-9]-*.png"))
    if photos:
        result += '<details><summary>Fotos desta tentativa</summary><div class="photos">' + ''.join(f'<a href="{href(p)}"><img loading="lazy" src="{href(p)}" alt="{escape(p.stem)}"></a>' for p in photos) + '</div></details>'
    findings = review.get("findings", [])
    if findings:
        result += '<details><summary>Achados da inspeção</summary><ul>' + ''.join(f'<li><b>{escape(str(f.get("subject", "Achado")))}</b>: {escape(str(f.get("description", "")))}</li>' for f in findings) + '</ul></details>'
    if review.get("limitations"):
        result += '<details open><summary>Limites da inspeção</summary><ul>' + ''.join(f'<li>{escape(str(limit))}</li>' for limit in review['limitations']) + '</ul></details>'
    return result + '</article>'


def main():
    comparison = read(PERFORMANCE / "comparison.json")
    review_summary = read(OUT / "summary.json")
    runs = discover_runs(comparison)
    # Select at most one complete ABBA and its later finite confirmation. Never
    # pool windows from different runtime revisions or separate executions here.
    current = [(name, run) for name, run in runs.items() if run["post_fix"] and run["complete"]]
    abba = [(name, run) for name, run in current if not run["raw"].get("confirm_case")]
    latest = max(abba, key=lambda item: item[1]["mtime"], default=None)
    selected = [latest] if latest else []
    if latest:
        confirmations = [(name, run) for name, run in current if run["raw"].get("confirm_case") and run["mtime"] > latest[1]["mtime"]]
        if confirmations:
            selected.append(max(confirmations, key=lambda item: item[1]["mtime"]))
    selected_names = {name for name, _ in selected}
    status = "Performance atual pendente — sem ABBA completo após a correção das lentes."
    if selected:
        exceeded = any(case.get("p95_change_percent", 0) > 5 or case.get("p99_change_percent", 0) > 5 for _, run in selected for case in run.get("cases", {}).values())
        status = "Ganho geral de performance não aprovado — percentil acima da tolerância em parte das janelas." if exceeded else "Dados pós-correção disponíveis — aprovação depende do parecer integrado no relatório."
    # The integrated review interprets the finite confirmation without erasing
    # the initial result or automatically approving a favorable second run.
    if review_summary.get("performance_runs") == sorted(selected_names):
        status = review_summary.get("performance_verdict", status)
    status = escape(status)
    sections = [f'<header><small>GETECO · 11/10/2026</small><h1>Validação da frota</h1><p class="status">{status}</p><p>O histórico anterior foi reprovado: p99 diurno piorou 5,24% e 5,19% nas duas rodadas. Esses resultados são anteriores à correção das lentes e não medem o runtime atual.</p><p>{link(EVIDENCE / "review.html", "Galeria antes/depois dos 59 carros")} · {link(ROOT / "docs/reviews/fleet-redesign-validation-20261011.md", "Relatório completo")} · {link(OUT / "lens-role-fix/review.md", "Correção das lentes")}</p></header>']
    sections.append('<section><h2>Performance na cena real</h2><p>Dez carros estacionados em Main, cidade ativa, Godot .NET / Mobile, 1920 × 1080, RTX 4060 Laptop. Aquecimento de 10 s e coleta de pelo menos 30 s por janela; diagnósticos sem limite de FPS/VSync. Hora e clima fixos por cenário, tráfego variável. CPU/GPU são tempos do viewport e não devem ser somados. Percentis são dos quadros concatenados de cada rodada, não médias de percentis.</p><p>Menos malhas e triângulos não significa ganho proporcional de FPS. A variação da cidade limita atribuir diferenças exclusivamente aos modelos. As versões abaixo são mantidas separadas; este índice não concede aprovação automática.</p>')
    for name, run in selected:
        sections.append(run_section(name, run, True))
    if not selected:
        sections.append('<p class="status">Nova coleta pós-correção: pendente ou incompleta.</p>')
    sections.append('<details><summary>Histórico completo de performance e tentativas</summary>')
    for name, run in sorted(runs.items()):
        if name not in selected_names:
            sections.append(run_section(name, run))
    sections.append('</details><p>' + link(PERFORMANCE / "comparison.json", "Comparação numérica original") + '</p></section>')
    temporal = EVIDENCE / "temporal"
    folders = sorted(p for p in temporal.glob("*/*") if p.is_dir() and p.name in EXPECTED)
    sections.append('<section><h2>Vídeos e fotos de gameplay</h2><p>Sete modelos: seis famílias iniciais e o conversível acrescentado após o diagnóstico da cabine. Todas as tentativas permanecem listadas, inclusive falhas. <code>flow.ok</code> informa estados do roteiro; não aprova imagem, encaixes ou ausência de flickering.</p><p class="status">A leitura e gravação das imagens reduz a cadência. O contador de FPS no HUD destes vídeos e fotos em movimento NÃO é benchmark. A comparação de performance vem de outra execução, sem capturas durante a coleta.</p><p>' + link(EVIDENCE / 'utility/validation-summary.md', 'Fluxos funcionais e diagnóstico atualizado das tentativas de saída') + '</p>')
    rows = []
    for model in EXPECTED:
        attempts = [p for p in folders if p.name == model]
        rows.append([escape(LABELS[model]), ' · '.join(f'<a href="#{escape(p.parent.name + "-" + model)}">{escape(p.parent.name)}</a>' for p in attempts) if attempts else '<b>PENDENTE — nenhuma captura registrada</b>'])
    sections.append(table(["Modelo", "Tentativas preservadas"], rows))
    sections.extend(temporal_card(folder) for folder in folders)
    sections.append('</section><footer><p>Índice local gerado em ' + datetime.now().astimezone().isoformat(timespec="seconds") + '. Regerar: <code>python tools/fleet_fixups/publish_fleet_validation.py</code>.</p></footer>')
    css = '*{box-sizing:border-box}body{margin:auto;max-width:1280px;padding:28px;background:#11191f;color:#e8edf0;font:16px/1.55 system-ui}a{color:#8dd6f0}h1{font-size:36px}h2{margin-top:38px}p{max-width:1080px;color:#c3d0d6}.status{padding:15px;border-left:4px solid #eead76;background:#322a24;color:#ffddbd}article{margin:20px 0;padding:20px;background:#1b272f;border:1px solid #3b505d;border-radius:8px}h3{margin:0 0 10px;overflow-wrap:anywhere}small,footer{color:#9fb1bc}.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{text-align:left;vertical-align:top;padding:10px;border-bottom:1px solid #3b505d;white-space:nowrap}th{color:#a7bfd0}details{margin:15px 0}summary{cursor:pointer;color:#c9e3f1}video{display:block;max-width:100%;width:960px;background:#080b0d}.photos{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:10px;margin-top:15px}.photos img{width:100%;display:block}li{margin:8px 0}@media(max-width:700px){body{padding:16px}article{padding:12px}h1{font-size:28px}}'
    page = '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Geteco — validação da frota</title><style>' + css + '</style></head><body>' + ''.join(sections) + '</body></html>'
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "review.html").write_text(page, encoding="utf-8")
    print(json.dumps({"page": str(OUT / "review.html"), "performance_runs": len(runs), "current_complete_runs": sorted(selected_names), "temporal_attempts": len(folders)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
