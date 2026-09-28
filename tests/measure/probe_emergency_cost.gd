extends SceneTree
## Custo frio da 1ª ocorrência de emergência: viatura x equipe, por papel.
## Renderizado, sem --headless. Cada papel roda duas vezes (fria e quente).
const VEHICLE = preload("res://scripts/Vehicle.gd")
const RESPONDER = preload("res://gameplay/emergency/Responder.gd")
var world: Node3D
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	for i in 120: await process_frame
	var spot: Vector3 = world.player.global_position + Vector3(0, 0, 25)
	var keep: Array = []
	for pass_index in 2:
		for role in ["medic", "fire", "mortician"]:
			var t0 := Time.get_ticks_usec()
			var unit := VEHICLE.new()
			unit.archetype = "medic_box" if role == "medic" else ("rescue_pumper" if role == "fire" else "station_wagon")
			unit.vehicle_id = "probe_%s_%d" % [role, pass_index]
			world.add_child(unit)
			unit.place(spot, 0)
			var t1 := Time.get_ticks_usec()
			var crew := RESPONDER.new()
			crew.manager = world.gameplay.emergency
			crew.role = role
			crew.vehicle = unit
			crew.set_physics_process(false)
			world.add_child(crew)
			crew.global_position = spot + Vector3(3, 0, 0)
			var t2 := Time.get_ticks_usec()
			var worst := 0.0
			var prev := Time.get_ticks_usec()
			for i in 6:
				await process_frame
				var now := Time.get_ticks_usec()
				worst = maxf(worst, (now - prev) / 1000.0)
				prev = now
			print("EMERG pass=%d %-9s vehicle=%.1f ms crew=%.1f ms worst_next6=%.1f ms" % [pass_index, role, (t1-t0)/1000.0, (t2-t1)/1000.0, worst])
			keep.append([unit, crew])
	quit(0)
