extends SceneTree
## GETECO-PERF-03A-R2 — PREPARADO, NAO EXECUTADO NESTA RODADA.
## Observa (sem nenhum atraso artificial) o estado real de
## SouthPort.sites/port_ready no instante em que HarborMinimap._ready()
## roda dentro do fluxo real de _start_gameplay(), usando a mesma tecnica
## de marcador por node_added das rodadas 01/02B/03A (não modifica
## produção; só escuta sinais da própria SceneTree). Uso pretendido, só
## depois da janela de edição/teste ficar livre:
##   Godot..._console.exe --path . --script res://tests/perf_audit_claude/probe_minimap_south_port_race_r2.gd
## Isolamento: seguir o mesmo padrão de APPDATA por execução usado em
## measure_loading_03a.gd (não reaproveitado aqui para manter o script
## mínimo e de leitura fácil).

var _south_port: Node
var _reported := false

func _initialize() -> void:
	node_added.connect(_on_node_added)
	_run.call_deferred()

func _on_node_added(node: Node) -> void:
	if node.name == "SouthPort":
		_south_port = node
	if node.name == "Minimap" and not _reported:
		_reported = true
		# Lido no MESMO instante em que HarborMinimap.gd:93-96 leria, antes
		# de qualquer await ser inserido — reproduz o estado real do jogo
		# sem nenhuma modificação de produção.
		if _south_port == null:
			print("PROBE_R2 SouthPort node not found at Minimap creation time")
		else:
			var sites_value = _south_port.get("sites")
			var sites_count: int = sites_value.size() if sites_value != null else -1
			var ready_flag = _south_port.get("port_ready")
			print("PROBE_R2 at_minimap_creation south_port_sites=%d port_ready=%s (esperado: sites=5, port_ready=true)" % [sites_count, str(ready_flag)])

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	var saves := root.get_node("SaveManager")
	saves.set("_save_dir", "user://r2_probe_isolated/")
	saves.set("_save_directory_ready", false)
	saves.clear_pending_save()
	var world: Node = load("res://world/harbor/HarborGame.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	var deadline := Time.get_ticks_msec() + 60000
	while not bool(world.get("gameplay_ready")) and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 10: await process_frame
	if not _reported:
		print("PROBE_R2 Minimap never observed added (timeout ou nome mudou)")
	quit(0)
