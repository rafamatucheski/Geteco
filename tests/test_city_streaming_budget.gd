extends SceneTree
## Regressao de agendamento: exercita o metodo produtivo sem construir o mundo.
const NATIVE_REGION := preload("res://world/regions/NativeRegion.gd")
const CITY_STEP_COUNT := 12

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", label)
	if not condition:
		failures.append(label)

func run() -> void:
	# Fora da arvore: _ready nao prepara dados nem inicia o streaming do mundo.
	var region := NATIVE_REGION.new()
	region.region_id = "harbor"
	region.records.clear()
	region.buildings.clear()
	region.harbor_road_geometry = null
	var chunk := Node3D.new()
	# A celula (0,0) termina em x=64; os recortes do canal comecam apos x=140.
	var job: Dictionary = {
		"key": Vector2i.ZERO,
		"chunk": chunk,
		"rect": Rect2(0.0, 0.0, NATIVE_REGION.CELL, NATIVE_REGION.CELL),
		"stage": 3,
		"index": 0,
		"warming": false,
	}
	check(not region.is_inside_tree() and not chunk.is_inside_tree(), "fixture permanece fora da arvore")
	check(not region.data_prepared and not region.prepared, "fixture nao inicializa o mundo")

	# O limite e independente de conferir o budget antes ou depois do primeiro passo.
	var completed: bool = region._run_build_job(job, 0.0)
	var state: Dictionary = job.get("dressing", {})
	var first_step := int(state.get("step", 0))
	check(not completed, "orcamento zero devolve trabalho ainda pendente")
	check(int(job.stage) == 3, "orcamento zero preserva o estagio de acabamento")
	check(first_step >= 0 and first_step <= 1, "orcamento zero avanca no maximo um passo atomico")
	check(not chunk.has_meta("vegetation_ready_frame"), "acabamento parcial nao publica conclusao")

	# Retoma o mesmo job produtivo; limite finito cobre ausencia de progresso.
	var resume_calls := 0
	for attempt in range(CITY_STEP_COUNT):
		resume_calls += 1
		completed = region._run_build_job(job, INF)
		if completed:
			break
	state = job.get("dressing", {})
	check(completed, "acabamento retoma e conclui em ate doze chamadas")
	check(int(job.stage) == 4, "conclusao publica o estagio terminal")
	check(int(state.get("step", -1)) == CITY_STEP_COUNT, "retomada conclui os doze passos sem reiniciar estado")
	check(job.chunk == chunk and state.get("chunk") == chunk and int(job.index) == 0 and chunk.get_child_count() == 0, "retomada preserva o chunk vazio original")
	check(chunk.has_meta("vegetation_ready_frame"), "conclusao publica o marcador do chunk")
	check(region._run_build_job(job, INF), "job concluido aceita nova consulta")
	check(int(state.get("step", -1)) == CITY_STEP_COUNT, "nova consulta nao repete acabamento")
	check(not region.is_inside_tree() and not region.data_prepared, "teste termina sem inicializar a regiao")
	chunk.free()
	region.free()
	print("CITY_STREAMING_BUDGET checks=%d failures=%d first_step=%d resume_calls=%d" % [checks, failures.size(), first_step, resume_calls])
	quit(0 if failures.is_empty() else 1)
