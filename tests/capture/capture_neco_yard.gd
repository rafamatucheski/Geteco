extends SceneTree
## Pátio do Neco na Main real: vista ampla e recortes da rua, do Neco e da prensa.
## Saída em evidence/neco-yard-20260925. --no-save --skip-arrival obrigatórios.

const OUTPUT := "res://evidence/neco-yard-20260925/"
var world

func _initialize() -> void: run.call_deferred()

func shot(file_name: String, focus: Vector3, half := Vector2(420, 260)) -> void:
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var center: Vector2 = world.camera.unproject_position(focus)
	var factor := Vector2(image.get_size()) / Vector2(root.get_visible_rect().size)
	var rect := Rect2i(Vector2i((center - half) * factor), Vector2i(half * 2.0 * factor)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image.get_region(rect).save_png(ProjectSettings.globalize_path(OUTPUT + file_name))
	print("CAPTURE ", file_name)

func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	create_timer(200).timeout.connect(func(): quit(3))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1600, 900)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for tick in 1500:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	await create_timer(1.0).timeout
	var bay: Vector3 = world.session.mission_world.targets.neco_bay
	var yards: Array = world.find_children("*", "Node3D", true, false).filter(func(n): return n.get_script() == preload("res://world/places/SalvageYardNative.gd"))
	print("BAY ", bay, " YARDS ", yards.size())
	world.player.teleport(bay + Vector3(0, 0.1, 4))
	world.session.weather.time_of_day = 0.45
	await create_timer(3.0).timeout
	var yard: Node3D = null
	for candidate in world.find_children("*", "Node3D", true, false):
		if candidate.get_script() == preload("res://world/places/SalvageYardNative.gd"): yard = candidate
	print("YARD ", yard.global_position if yard != null else "none")
	await shot("wide.png", world.player.global_position, Vector2(800, 450))
	if yard != null:
		await shot("press.png", yard.to_global(yard.PRESS), Vector2(260, 160))
		await shot("neco.png", yard.npc_point(), Vector2(160, 100))
		await _scrap_flow(yard)
	# Cemitério: portão norte e gramado.
	var cemetery: Vector3 = preload("res://world/regions/OriginalCemetery3D.gd").world_position()
	world.player.teleport(cemetery + Vector3(0, 0.1, -24))
	await create_timer(3.0).timeout
	await shot("cemetery_gate.png", world.player.global_position, Vector2(800, 450))
	world.player.teleport(cemetery + Vector3(-6, 0.1, 0))
	await create_timer(2.0).timeout
	await shot("cemetery_inside.png", world.player.global_position, Vector2(800, 450))
	print("FLOW ", "PASS" if flow_failures.is_empty() else "FAIL " + str(flow_failures))
	quit(0)

var flow_failures: Array[String] = []
func flow_check(ok: bool, label: String) -> void:
	print(("FLOW_PASS " if ok else "FLOW_FAIL ") + label)
	if not ok: flow_failures.append(label)

func _scrap_flow(yard: Node3D) -> void:
	var rewards = world.session.garage_rewards
	world.player.teleport(yard.button_point() + Vector3(0.9, 0.1, 0))
	await create_timer(0.5).timeout
	var empty: Dictionary = rewards.nearest_action()
	flow_check(empty.get("target", "") == "neco_press", "botão oferece a prensa perto dele")
	flow_check(rewards.perform("neco_press"), "apertar sem carro não quebra nada")
	var car: CharacterBody3D = world.production.spawn_vehicle("union_sedan", yard.dock_point() + Vector3.UP * 0.1, 0.0)
	flow_check(car != null, "carro de teste na baia")
	if car == null: return
	await create_timer(1.0).timeout
	var offer: Dictionary = rewards.nearest_action()
	flow_check(str(offer.get("label", "")).contains("R$"), "oferta mostra o valor: " + str(offer.get("label", "")))
	var balance_before: int = world.session.state.economy.balance
	var expected: int = rewards.scrap_value(car)
	flow_check(rewards.perform("neco_press"), "botão manda o carro para a prensa")
	flow_check(not car.visible, "carro real sai de cena durante a prensa")
	await create_timer(1.6).timeout
	await shot("press_running.png", yard.to_global(yard.PRESS), Vector2(300, 190))
	for tick in 900:
		await process_frame
		if not is_instance_valid(car): break
	flow_check(not is_instance_valid(car), "carro removido ao fim da prensa")
	flow_check(world.session.state.economy.balance == balance_before + expected, "Neco pagou R$ %d (saldo %d -> %d)" % [expected, balance_before, world.session.state.economy.balance])
	var second: CharacterBody3D = world.production.spawn_vehicle("union_sedan", yard.dock_point() + Vector3.UP * 0.1, 0.0)
	await create_timer(1.0).timeout
	second.set_meta("garage_reward", true)
	var before_protected: int = world.session.state.economy.balance
	rewards.perform("neco_press")
	await create_timer(0.3).timeout
	flow_check(is_instance_valid(second) and second.visible and world.session.state.economy.balance == before_protected, "carro protegido não vai para a prensa")
	second.queue_free()

func _probe(label: String, point: Vector3) -> void:
	var found := []
	for mesh in world.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if box.size.x < 2.0 and box.size.z < 2.0: continue
		if point.x < box.position.x or point.x > box.end.x or point.z < box.position.z or point.z > box.end.z: continue
		if box.end.y < -1.0 or box.position.y > 0.6: continue
		var material = mesh.material_override if mesh.material_override != null else (mesh.get_active_material(0))
		var desc := "none"
		if material is StandardMaterial3D: desc = "std albedo=%s tex=%s shading=%d" % [material.albedo_color.to_html(false), material.albedo_texture != null, material.shading_mode]
		elif material is ShaderMaterial: desc = "shader " + str(material.shader.resource_path)
		found.append("%s top=%.2f %s" % [str(mesh.get_path()).right(60), box.end.y, desc])
	print("PROBE ", label, " ", point)
	for line in found: print("   ", line)
