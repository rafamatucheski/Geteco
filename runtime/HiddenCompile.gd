extends RefCounted
## Compilação em paralelo antes do desenho dos pré-aquecimentos (22/10, 3ª rodada de desempenho).
##
## Medido no editor com shaders de código único (cache de shader frio para eles): 12 materiais desenhados
## direto travaram 4,3–4,8 s num quadro (o shader compila na thread principal, um depois do outro, quando o
## desenho precisa dele); as mesmas 12 peças com visible=false ficaram prontas em 0,6 s, porque a pipeline
## "ubershader" de cada superfície criada é compilada pelos trabalhadores do motor, em paralelo, mesmo sem
## desenho, e ao aparecer não houve nenhuma pipeline `surface` nova. Aqui o pré-aquecimento monta as peças
## escondidas, espera as compilações pararem (contador de pipelines `surface` parado por alguns quadros, com
## teto de tempo) e só então mostra e desenha como antes. Com cache quente custa ~3 quadros.
## DESLIGADO por padrão (GETECO_HIDDEN_COMPILE=1 liga): a carga não ficou mais curta em medição limpa (22/10,
## docs/perf-playthrough-20261021.md §8); sem ele os pré-aquecimentos desenham direto, como antes.
const QUIET_FRAMES := 2
const MAX_MSEC := 4000

static func enabled() -> bool:
	return OS.get_environment("GETECO_HIDDEN_COMPILE") == "1"

static func _surface_count() -> int:
	return int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))

## Espera o contador de pipelines `surface` ficar parado por QUIET_FRAMES quadros (no máximo MAX_MSEC).
static func settle(tree: SceneTree) -> void:
	var last := _surface_count()
	var quiet := 0
	var deadline := Time.get_ticks_msec() + MAX_MSEC
	while quiet < QUIET_FRAMES and Time.get_ticks_msec() < deadline:
		await tree.process_frame
		var now := _surface_count()
		if now == last: quiet += 1
		else:
			quiet = 0
			last = now

## Esconde `node` (já na árvore e montado), deixa as pipelines compilarem e devolve a visibilidade.
static func prepare(node: Node3D, tree: SceneTree) -> void:
	if not enabled() or not is_instance_valid(node) or tree == null: return
	var was := node.visible
	node.visible = false
	await settle(tree)
	if is_instance_valid(node): node.visible = was
