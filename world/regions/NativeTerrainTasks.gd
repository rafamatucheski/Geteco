extends RefCounted
## Tarefas do WorkerThreadPool que calculam o terreno da serra (MountainTerrain3D.prepare_task),
## separadas do NativeRegion em 01/11 (Onda 1). O estado (_terrain_tasks, terrain, build_jobs, o job)
## continua no NativeRegion, que mantém cada função como delegação de uma linha; testes leem
## `region._terrain_tasks` e chamam `_prefetch_terrain_tasks` pelo dono.
## Só a thread principal passa por aqui: o trabalhador recebe o mesmo Callable estático de antes
## (TERRAIN.prepare_task com terrain, rect e o dicionário de resultado) e não toca na árvore nem
## neste auxiliar. A espera (wait_for_task_completion) continua do mesmo lado e na mesma hora.
## `g` fica como Node3D, e não como o script do NativeRegion, para não criar preload cíclico.
## Até as chamadas entre funções deste arquivo passam por `g.`: EditableRegion e as subclasses de
## teste sobrescrevem funções do dono (`_hold_file_resources`, `_build_record`, `_run_build_job`...),
## e o despacho tem de continuar o de antes.
const TERRAIN := preload("res://world/regions/MountainTerrain3D.gd")

var g: Node3D

func _init(host: Node3D) -> void:
	g = host

## Estágio 0 da serra: alturas, malha e máscara das trilhas saem prontas de um WorkerThreadPool
## (MountainTerrain3D.chunk_data) e aqui fica só a montagem (malha, colisão, nós). Devolve true enquanto o
## trabalhador calcula: o trecho cede a vez sem gastar o orçamento esperando. Sem orçamento (0 ou INF: chão
## agora para um veículo, ou trecho imediato) espera a tarefa já começada ou deixa build_chunk calcular aqui.
func _terrain_chunk_pending(job: Dictionary, budget_usec: float) -> bool:
	if job.has("terrain_data") or not g._terrain_task_wanted(job): return false
	var now := budget_usec <= 0.0 or is_inf(budget_usec)
	if not job.has("terrain_task"):
		if now: return false
		g._start_terrain_task(job)
	var task: int = job.terrain_task
	if g._terrain_tasks.has(task):
		if not now and not WorkerThreadPool.is_task_completed(task):
			job.waiting_worker = true
			return true
		WorkerThreadPool.wait_for_task_completion(task)
		g._terrain_tasks.erase(task)
	job.terrain_data = job.terrain_result
	job.erase("terrain_task")
	job.erase("terrain_result")
	job.erase("waiting_worker")
	return false

func _terrain_task_wanted(job: Dictionary) -> bool:
	return g.region_id == "mountain" and g.terrain != null and int(job.stage) == 0 and g._mountain_owns_terrain(job.key)

func _start_terrain_task(job: Dictionary) -> void:
	if job.has("terrain_task") or job.has("terrain_data") or not g._terrain_task_wanted(job): return
	var result := {}
	var task := WorkerThreadPool.add_task(Callable(TERRAIN,"prepare_task").bind(g.terrain,job.rect,result),false,"mountain terrain chunk")
	g._terrain_tasks[task] = true
	job.terrain_task = task
	job.terrain_result = result

## Os próximos trechos da fila já calculam no trabalhador enquanto o da frente monta.
func _prefetch_terrain_tasks() -> void:
	if g.region_id != "mountain" or g.terrain == null: return
	for index in mini(g.build_jobs.size(),g.TERRAIN_PREFETCH_JOBS): g._start_terrain_task(g.build_jobs[index])

## Libera as tarefas terminadas (inclusive as de trechos já descartados); o resultado fica no job.
func _collect_terrain_tasks() -> void:
	if g._terrain_tasks.is_empty(): return
	for task in g._terrain_tasks.keys():
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			g._terrain_tasks.erase(task)
