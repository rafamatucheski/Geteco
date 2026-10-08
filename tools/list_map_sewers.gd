extends SceneTree
## Lista os marcadores de bueiro que o mapa 2D do jogo recebe (WorldMapData).
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var world = load("res://Main.tscn").instantiate(); world.set_meta("skip_arrival", true); root.add_child(world)
	for i in 1800:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	var data = load("res://ui/hud/WorldMapData.gd").new()
	data.collect(world.session.controller)
	var count := 0
	for marker in data.markers:
		if marker.kind == "sewer":
			count += 1
			print("MARCADOR ", marker.id, " | ", marker.title, " | ", marker.point, " | ", marker.detail)
	print("TOTAL_BUEIROS ", count)
	quit()
