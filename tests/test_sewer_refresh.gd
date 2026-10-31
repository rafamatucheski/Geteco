extends SceneTree
## As fixtures físicas usam os corpos reais do Dante e dos moradores do esgoto, não consultas de ponto.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const NETWORK := preload("res://world/places/sewers/SewerNetwork.gd")
const RESIDENT := preload("res://world/places/sewers/SewerResident.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func sweep(actor: CharacterBody3D, room: Node3D) -> int:
	var tested := 0
	for bounds in room.solid_bounds:
		if bounds.size.x > 4 or bounds.size.z > 4: continue
		for direction in [Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.FORWARD]:
			var center: Vector3 = bounds.get_center()
			center.y = .04
			var extent: float = (bounds.size.x if direction.x != 0 else bounds.size.z) * .5
			var start: Vector3 = center + direction * (extent + .7)
			if not room.is_floor_clear(start, .34): continue
			actor.position = start
			var hit := actor.move_and_collide(-direction * (extent + 1.0))
			check(hit != null and actor.position.distance_to(center) > .15,
				str(room.definition.id) + ": " + actor.name + " bloqueado em sólido/canto")
			tested += 1
			break
	return tested

func run() -> void:
	var dante = preload("res://scripts/Actor.gd").new()
	dante.is_player = true
	root.add_child(dante)
	dante.set_physics_process(false)
	for id in NETWORK.ids():
		var room = CATALOG.create_place(id)
		root.add_child(room)
		for i in 3: await physics_frame
		var resident = RESIDENT.new()
		resident.definition = room.definition.npcs[0]
		room.add_child(resident)
		resident.set_physics_process(false)
		for i in 3: await physics_frame
		var dante_cases := sweep(dante, room)
		var resident_cases := sweep(resident, room)
		check(dante_cases > 0 and resident_cases == dante_cases, id + ": jogador e NPC reais varridos")
		# As tags de sólido precisam cobrir a malha transformada depois das rotações de caixa/banco.
		var inventory_ok := true
		var tags := 0
		for mesh in room.model.find_children("*", "MeshInstance3D", true, false):
			if str(mesh.get_meta("interior_solid_id", "")).is_empty(): continue
			tags += 1
			var bounds: AABB = (room.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
			if bounds.position.y > 2.1 or bounds.end.y < .06: continue
			var found := false
			for solid in room.solid_bounds:
				if Rect2(solid.position.x, solid.position.z, solid.size.x, solid.size.z).grow(.002).encloses(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)):
					found = true
			if not found: inventory_ok = false
		check(inventory_ok, id + ": malhas sólidas cobertas após transformações (%d)" % tags)
		check(room.is_floor_clear(room.definition.spawn, .3), id + ": entrada livre")
		for spec in room.definition.npcs:
			check(room.is_floor_clear(spec.local_position, .3), id + ": morador em piso livre")
		for point in room.reward_points:
			check(room.is_floor_clear(room.to_local(point.position), .3), id + ": coleta fora dos móveis")
		var audio: Node = room.model.get_node_or_null("SewerAmbience")
		check(audio != null and audio.channel.playing, id + ": ambiência ativa")
		room.set_active(false)
		await create_timer(.3).timeout
		check(not audio.channel.playing, id + ": sala inativa sem áudio residual")
		room.set_active(true)
		await create_timer(.3).timeout
		check(audio.channel.playing, id + ": reativação retoma áudio")
		room.free()
		await process_frame
	dante.free()
	print("SEWER_REFRESH checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
