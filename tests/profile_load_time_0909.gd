extends SceneTree

## Perfil de tempo de carregamento da cena principal real (HarborGame.tscn).
## As medições da Etapa 1 mostraram load_ms entre 23.816 e 28.849 -- ou seja,
## ~25 segundos até a partida ficar utilizável. Este script separa esse tempo
## em fases para dizer ONDE ele é gasto, em vez de adivinhar:
##   1. load()          -- ler/parsear o .tscn e todas as dependências
##   2. instantiate()   -- construir a árvore de nós
##   3. add_child()     -- _ready() síncrono
##   4. frames pós-add  -- geração procedural diferida (call_deferred/_start_review)
## Também conta nós, SubViewports e nós por classe, para mostrar o que a
## construção procedural realmente cria.
##
## Uso: Godot..._console.exe --path . --script res://tests/profile_load_time_0909.gd

const GAME_SCENE := "res://world/harbor/HarborGame.tscn"

var _log_lines: PackedStringArray = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var t0 := Time.get_ticks_msec()
	var packed := load(GAME_SCENE) as PackedScene
	var t_load := Time.get_ticks_msec() - t0

	var t1 := Time.get_ticks_msec()
	var game := packed.instantiate() as Node2D
	var t_instantiate := Time.get_ticks_msec() - t1

	var t2 := Time.get_ticks_msec()
	root.add_child(game)
	current_scene = game
	var t_add_child := Time.get_ticks_msec() - t2

	# Fases diferidas: HarborPreview._ready() faz call_deferred("_start_review"),
	# que constrói distritos, emergência, frota e auditorias. Medir frame a frame
	# mostra em qual frame o custo aparece.
	var frame_times: Array[float] = []
	var t3 := Time.get_ticks_msec()
	for i in 180:
		var f0 := Time.get_ticks_usec()
		await process_frame
		frame_times.append((Time.get_ticks_usec() - f0) / 1000.0)
	var t_deferred := Time.get_ticks_msec() - t3

	_log("LOAD_PROFILE load_ms=%d instantiate_ms=%d add_child_ms=%d first180frames_ms=%d total_ms=%d" % [
		t_load, t_instantiate, t_add_child, t_deferred,
		t_load + t_instantiate + t_add_child + t_deferred,
	])

	# Quais frames custaram mais (picos = trabalho diferido pesado)
	var worst: Array[String] = []
	for i in frame_times.size():
		if frame_times[i] > 100.0:
			worst.append("frame%d=%.0fms" % [i, frame_times[i]])
	_log("LOAD_PROFILE_SPIKES " + (" ".join(worst) if not worst.is_empty() else "nenhum frame acima de 100ms"))

	# Composição da árvore construída
	var counts := {}
	_count_classes(game, counts)
	var pairs: Array = []
	for k in counts:
		pairs.append([k, counts[k]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	var top: Array[String] = []
	for i in mini(18, pairs.size()):
		top.append("%s=%d" % [pairs[i][0], pairs[i][1]])
	_log("LOAD_PROFILE_NODES total=%d " % [_count_nodes(game)] + " ".join(top))

	_log("LOAD_PROFILE_MONITORS nodes=%d orphans=%d draw_calls=%d video_mem_mb=%.1f static_mem_mb=%.1f" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		OS.get_static_memory_usage() / 1048576.0,
	])

	_write_report()
	quit(0)

func _count_nodes(node: Node) -> int:
	var n := 1
	for c in node.get_children():
		n += _count_nodes(c)
	return n

func _count_classes(node: Node, counts: Dictionary) -> void:
	var key := node.get_class()
	counts[key] = int(counts.get(key, 0)) + 1
	for c in node.get_children():
		_count_classes(c, counts)

func _log(line: String) -> void:
	print(line)
	_log_lines.append(line)

## Saida vai para docs/measurements/review-0909/ dentro do projeto, como o
## resto dos scripts de captura deste repositorio ja faz -- e nao para uma
## pasta absoluta fora dele, que nao seria versionada nem encontrada por
## quem clonasse o projeto.
const DEFAULT_OUT_DIR := "res://docs/measurements/review-0909"

## Resolve res:// para caminho de sistema; DirAccess/FileAccess de escrita
## precisam do caminho absoluto.
static func _resolve_out_dir(dir: String) -> String:
	return ProjectSettings.globalize_path(dir) if dir.begins_with("res://") else dir

func _write_report() -> void:
	var out_dir := _resolve_out_dir(DEFAULT_OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var f := FileAccess.open(out_dir.path_join("load_profile.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log_lines))
		f.close()
