extends SceneTree
## Túnel do canal no jogo real: tiro dentro do túnel acerta, a câmera aproxima
## lá dentro, e a polícia chamada com o jogador no fundo do túnel desce até ele
## (antes o caminho a pé parava no cais, em cima). Rodar com --no-save.
const TUNNEL := preload("res://world/urban_detail/CanalTunnel3D.gd")
var failures: Array[String] = []
var world
var player
var gameplay
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func _initialize() -> void: run.call_deferred()
func point_mouse(target: Vector3) -> void:
	var flat: Vector3 = target - player.global_position
	flat.y = 0.0
	flat = flat.normalized()
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0.0
	down.y = 0.0
	get_root().get_node("GameInput").touch_aim = Vector2(flat.dot(right.normalized()), flat.dot(down.normalized()))
	await process_frame
	await process_frame
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	player = world.player
	gameplay = world.gameplay
	var production = world.production
	var bottom := Vector3(236.0, TUNNEL.floor_y(236.0) + .2, TUNNEL.CENTER_Z)
	if "--surface" in OS.get_cmdline_user_args(): bottom = Vector3(110.0, 0.2, 78.0)
	player.teleport(bottom)
	production.region.set_focus(bottom)
	for i in 900:
		await process_frame
		if production.region.is_streaming_idle(): break
	await frames(60)
	check(TUNNEL.below_grade(player.global_position), "Jogador de pé no fundo do túnel (y=%.2f)" % player.global_position.y)
	# Câmera: zoom mais próximo no túnel.
	var cam_size: float = world.camera.size
	print("TUNNEL_COMBAT camera size=%.1f" % cam_size)
	check(world.camera._tunnel_blend > .9, "Câmera reconheceu o túnel")
	# Tiro: pistola num civil 5 m à frente, dentro do túnel.
	world.session.state.grant_weapon("pistol")
	world.session.state.equip_weapon("pistol")
	await frames(5)
	var npc := preload("res://scripts/Actor.gd").new()
	npc.identity = 3
	world.add_child(npc)
	npc.global_position = bottom + Vector3(5.0, 0, 0)
	await frames(10)
	var before: float = npc.health
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var line := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.2, npc.global_position + Vector3.UP * 1.0, 0xFFFF)
	line.exclude = [player.get_rid()]
	var seen := space.intersect_ray(line)
	print("TUNNEL_COMBAT linha de tiro atinge: %s em %s; npc em %s" % [str(seen.collider.name) if not seen.is_empty() else "-", str(seen.position.snapped(Vector3.ONE*.01)) if not seen.is_empty() else "-", npc.global_position.snapped(Vector3.ONE*.01)])
	print("TUNNEL_COMBAT arma=%s permitido=%s armas_ok=%s place=%s" % [world.session.state.equipped_weapon, gameplay.attack_allowed(), world.session.state.weapons_allowed(), world.session.state.place_id])
	# Mesmo caminho do clique (FullSession chama fire_at com o ponto de mira).
	for shot in 3:
		gameplay.fire_at(npc.global_position + Vector3.UP * 1.0)
		await frames(20)
	print("TUNNEL_COMBAT civil vida %.0f -> %.0f" % [before, npc.health])
	check(npc.health < before, "Tiro dentro do túnel acerta o civil")
	# Polícia: procurado com o jogador no fundo; alguém chega perto, lá embaixo.
	if is_instance_valid(world.dispatch):
		world.dispatch.dispatch_event.connect(func(event_name: String, data: Dictionary):
			if true:
				var copy := {}
				for key in data: copy[key] = str(data[key]).substr(0, 60)
				print("DISPATCH ", event_name, " ", copy))
	gameplay.register_crime(400, player.global_position)
	print("TUNNEL_COMBAT após crime: estrelas=%d pontos=%d despacho_por_viatura=%s" % [gameplay.stars, gameplay.crime_points, gameplay.dispatch_owned])
	var closest := INF
	var below := false
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 200000:
		await frames(30)
		player.global_position = bottom
		player.velocity = Vector3.ZERO
		# Testemunhas continuam denunciando: sem contato o procurado zera antes de a polícia chegar.
		if Time.get_ticks_msec() % 10000 < 600: gameplay.register_crime(30, player.global_position)
		var everyone: Array = gameplay.police.duplicate()
		if is_instance_valid(world.dispatch):
			for unit in world.dispatch.units: everyone.append_array(unit.officers)
		for officer in everyone:
			if not is_instance_valid(officer) or not officer.is_inside_tree(): continue
			var d: float = officer.global_position.distance_to(player.global_position)
			if d < closest: closest = d
			if d < 12.0 and TUNNEL.below_grade(officer.global_position): below = true
		if below: break
		if Time.get_ticks_msec() - start > 20000 and int(Time.get_ticks_msec() / 1000) % 15 == 0 and is_instance_valid(world.dispatch):
			for unit in world.dispatch.get("units") if world.dispatch.get("units") != null else []:
				var car = unit.get("vehicle")
				if is_instance_valid(car): print("TUNNEL_COMBAT viatura %s em %s vel=%.1f" % [str(unit.get("state")), car.global_position.snapped(Vector3.ONE*.1), car.velocity.length()])
	print("TUNNEL_COMBAT estrelas=%d pontos=%d" % [gameplay.stars, gameplay.crime_points])
	print("TUNNEL_COMBAT policiais=%d mais_perto=%.1f m no_fundo=%s" % [gameplay.police.size(), closest, below])
	check(below, "Polícia desce ao túnel e chega a menos de 12 m do jogador")
	print("TUNNEL_COMBAT failures=", failures)
	quit(0 if failures.is_empty() else 1)
