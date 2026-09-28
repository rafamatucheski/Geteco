extends SceneTree
## Isola o quadro ruim da 1ª emergência da sessão. Uma ação por processo (fria):
##   --action=explode | ignite | kill | none
## Imprime todo quadro > 25 ms nos 8 s seguintes, com o instante.
var world: Node3D
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var action := "explode"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--action="): action = a.trim_prefix("--action=")
	if DisplayServer.get_name() == "headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	for frame in 2400:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	for i in 240: await process_frame
	var g: Node3D = world.gameplay
	if "--prewarm-inview" in OS.get_cmdline_user_args():
		await preload("res://gameplay/emergency/EffectsPrewarm.gd").run(g)
		for i in 60: await process_frame
	g.health = 100.0
	if "--no-dispatch" in OS.get_cmdline_user_args(): world.dispatch.set_physics_process(false)
	if "--no-emergency-tick" in OS.get_cmdline_user_args(): g.emergency.set_physics_process(false)
	var point: Vector3 = world.player.global_position + Vector3(18, 0, 0)
	var began := Time.get_ticks_usec()
	match action:
		"explode": g.explode(point, 6.0, 60.0, null)
		"ignite":
			var fire = g.emergency.ignite(point, null, 1.0)
			if "--nolight" in OS.get_cmdline_user_args() and fire != null: fire.light.visible = false
			if "--nothing" in OS.get_cmdline_user_args() and fire != null:
				fire.light.visible = false
				fire.glow.visible = false
				for n in [fire.flames, fire.embers, fire.smoke]: n.visible = false
			if "--noparticles" in OS.get_cmdline_user_args() and fire != null:
				for n in [fire.flames, fire.embers, fire.smoke]: n.visible = false
		"dispatch":
			var fire2 = g.emergency.ignite(point, null, 1.0)
			var d = world.dispatch
			print("FIRST dispatch_node=", d != null)
			var key := -1
			for k in g.emergency.incidents.keys(): key = k
			var a0 := Time.get_ticks_usec()
			var res = d.dispatch_service_to(key)
			print("FIRST dispatch_service_to=%.1f ms result=%s" % [float(Time.get_ticks_usec() - a0) / 1000.0, res != null])
			var b0 := Time.get_ticks_usec()
			var res2 = d.router.plan(point + Vector3(60, 0, 0), point, Vector3.FORWARD)
			print("FIRST router.plan(1 chamada quente?)=%.1f ms" % [float(Time.get_ticks_usec() - b0) / 1000.0])
		"vehicle":
			var VEH = preload("res://scripts/Vehicle.gd")
			var far_arg := "--far" in OS.get_cmdline_user_args()
			for round in 3:
				var car = VEH.new()
				car.archetype = "rescue_pumper"
				car.vehicle_id = "probe_%d" % round
				world.add_child(car)
				var spot: Vector3 = point + (Vector3(0, 0, 400) if far_arg else Vector3(0, 0, 0))
				car.place(spot + Vector3(0, 0, round * 8.0), 0.0)
				car.ensure_equipment(world)
				var worst := 0.0
				var prev := Time.get_ticks_usec()
				for i in 30:
					await process_frame
					var t := Time.get_ticks_usec()
					worst = maxf(worst, float(t - prev) / 1000.0)
					prev = t
				print("FIRST vehicle round=%d far=%s worst_next30=%.1f ms" % [round, far_arg, worst])
		"plan":
			var d4 = world.dispatch
			var cands = d4._depot_candidates("fire", point)
			cands.append_array(d4.router.spawn_candidates(point, 40.0, 120.0))
			var total := 0.0
			var n := 0
			for c in cands:
				if n >= 8: break
				var p0 := Time.get_ticks_usec()
				var pl = d4.router.plan(c.point, point, Vector3.FORWARD)
				var ms := float(Time.get_ticks_usec() - p0) / 1000.0
				total += ms
				n += 1
				print("FIRST plan #%d = %.1f ms" % [n, ms])
			print("FIRST plan total(%d) = %.1f ms" % [n, total])
		"cone":
			var c0 := Time.get_ticks_usec()
			preload("res://gameplay/VehicleEquipment.gd")._cone_texture()
			print("FIRST _cone_texture=%.1f ms" % [float(Time.get_ticks_usec() - c0) / 1000.0])
		"audio":
			var AU = preload("res://gameplay/VehicleEquipmentAudio.gd")
			var q0 := Time.get_ticks_usec()
			AU.horn_stream()
			print("FIRST horn_stream=%.1f ms" % [float(Time.get_ticks_usec() - q0) / 1000.0])
			q0 = Time.get_ticks_usec()
			AU.siren_stream()
			print("FIRST siren_stream=%.1f ms" % [float(Time.get_ticks_usec() - q0) / 1000.0])
			q0 = Time.get_ticks_usec()
			AU.alarm_stream()
			print("FIRST alarm_stream=%.1f ms" % [float(Time.get_ticks_usec() - q0) / 1000.0])
		"bank":
			var NEAR = preload("res://audio/vehicle_ambience/NearbyVehicleAudio.gd")
			var mixer = NEAR.new()
			for arch in ["rescue_pumper", "rescue_pumper", "medic_box", "station_wagon", "police_cruiser"]:
				var k0 := Time.get_ticks_usec()
				var fam = mixer._resolve_family(arch)
				print("FIRST bank %s family=%s = %.1f ms" % [arch, fam, float(Time.get_ticks_usec() - k0) / 1000.0])
		"kill":
			g.dispatch_owned = false
			g.last_known = world.player.global_position
			g.last_known_valid = true
			g.stars = 3
			var o = g.spawn_officer()
			if o != null: o.receive_damage(9999.0, world.player)
	var call_ms := float(Time.get_ticks_usec() - began) / 1000.0
	var last := Time.get_ticks_usec()
	var bad := 0
	var units_seen := 0
	var searching_seen := false
	for i in 480:
		await process_frame
		var now := Time.get_ticks_usec()
		var ms := float(now - last) / 1000.0
		if world.dispatch != null:
			if world.dispatch.units.size() != units_seen:
				units_seen = world.dispatch.units.size()
				print("FIRST   event t=%.2fs units=%d frame=%.1f ms" % [float(now - began) / 1e6, units_seen, ms])
				if "--freeze-dispatch" in OS.get_cmdline_user_args(): world.dispatch.set_physics_process(false)
			var searching := false
			for k in g.emergency.incidents: if g.emergency.incidents[k].has("search"): searching = true
			if searching != searching_seen:
				searching_seen = searching
				print("FIRST   event t=%.2fs searching=%s frame=%.1f ms" % [float(now - began) / 1e6, searching, ms])
		if "--trace" in OS.get_cmdline_user_args() and float(now - began) / 1e6 < 0.7: print("FIRST   frame t=%.3f %.1f ms units=%d" % [float(now - began) / 1e6, ms, world.dispatch.units.size() if world.dispatch != null else -1])
		if ms > 25.0:
			bad += 1
			print("FIRST %s t=%.2fs frame=%.1f ms | process=%.1f physics=%.1f objs=%d nodes=%d draw=%d" % [action, float(now - began) / 1e6, ms, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
		last = now
	print("FIRST %s call=%.2f ms bad_frames=%d" % [action, call_ms, bad])
	quit(0)
