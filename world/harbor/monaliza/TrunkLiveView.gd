extends SubViewportContainer
signal weapon_inspected(id: String)
## The simulation stays in its original World2D. A second, live view of that
## world is projected into the temporary 3D scene; no screenshot or pause.
const MODEL = preload("res://world/harbor/monaliza/MonalizaModel.gd")
var car: Node2D
var live_world: SubViewport
var stage: SubViewport
var model: Node3D
var camera: Camera3D
var weapons: Node3D
var elapsed := 0.0
var mirrors: Dictionary = {}
var scan_timer := 0.0
var rain: CPUParticles3D
var weather_emitters: Dictionary = {}
var weather: DayNightWeatherManager
var hand: Node3D
var fingers: Array[Node3D] = []
var displayed: Dictionary = {}
var requested: Dictionary = {}
var slot_models: Dictionary = {}
var swapping := false
var selection_audio: AudioStreamPlayer
var cutouts: Dictionary = {}
var trunk_light: OmniLight3D
var lamp_material: StandardMaterial3D
var sun: DirectionalLight3D
var scene_environment: Environment
var night_blend := 0.0
const WEAPON = preload("res://scripts/player/ArsenalWeapon3D.gd")
const SLOT_POSITIONS = {"longa": Vector3(0.12, 0.67, 1.66), "curta": Vector3(-0.38, 0.67, 1.97), "corpo": Vector3(0.35, 0.67, 1.97), "granada": Vector3(-0.02, 0.70, 1.96)}
const LIVE_HIDDEN_LAYER := 1 << 19

func setup(vehicle: Node2D) -> void:
	car = vehicle
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stretch = true
	stage = SubViewport.new()
	stage.size = Vector2i(960, 720)
	stage.own_world_3d = true
	stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(stage)
	live_world = SubViewport.new()
	live_world.size = Vector2i(1536, 1536)
	live_world.world_2d = car.get_viewport().world_2d
	live_world.disable_3d = true
	live_world.canvas_cull_mask = 0xfffff & ~LIVE_HIDDEN_LAYER
	live_world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stage.add_child(live_world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 90)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = live_world.get_texture()
	ground.material_override = material
	ground.position.y = -0.03
	stage.add_child(ground)
	model = MODEL.new()
	stage.add_child(model)
	model.paint.albedo_color = car.paint_color
	# Replace the closed storage cases with an open, padded weapon tray.
	for part in model.get_children():
		if part is MeshInstance3D and part.position.y > 0.52 and part.position.y < 0.66 and part.position.z > 1.6 and part.position.z < 2.0:
			part.hide()
	var foam := StandardMaterial3D.new()
	foam.albedo_color = Color("303a39")
	foam.roughness = 0.98
	var grain := NoiseTexture2D.new()
	grain.width = 256
	grain.height = 256
	var noise := FastNoiseLite.new()
	noise.frequency = 0.65
	grain.noise = noise
	foam.albedo_texture = grain
	_hand_box(model, Vector3(0, 0.60, 1.80), Vector3(1.49, 0.08, 0.76), foam)
	_build_trunk_details()
	weapons = Node3D.new()
	model.add_child(weapons)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	stage.add_child(light)
	sun = light
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("18202a")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	scene_environment = environment.environment
	stage.add_child(environment)
	camera = Camera3D.new()
	camera.fov = 38
	stage.add_child(camera)
	_build_hand()
	_build_selection_audio()
	for node in car.get_tree().current_scene.find_children("*", "DayNightWeatherManager", true, false):
		weather = node
		break
	rain = CPUParticles3D.new()
	rain.amount = 220
	rain.lifetime = 0.7
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(7, 0.1, 7)
	rain.position = Vector3(0, 6, 0)
	rain.direction = Vector3(-0.15, -1, 0)
	rain.initial_velocity_min = 9
	rain.initial_velocity_max = 13
	var streak := BoxMesh.new()
	streak.size = Vector3(0.008, 0.18, 0.008)
	rain.mesh = streak
	rain.color = Color(0.65, 0.78, 0.9, 0.45)
	rain.emitting = false
	stage.add_child(rain)
	weather_emitters["rain_particles"] = rain
	for kind in ["snow_particles", "sand_particles", "leaf_particles", "spray_particles"]:
		var particles := CPUParticles3D.new()
		particles.emitting = false
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = Vector3(3, 1.4, 3)
		particles.position = Vector3(0, 2.1, 1)
		particles.gravity = Vector3.ZERO
		particles.scale_amount_min = 0.65
		particles.scale_amount_max = 1.35
		var flake := SphereMesh.new()
		flake.radius = 0.012 if kind == "snow_particles" else 0.007
		flake.height = flake.radius * 2.0
		flake.radial_segments = 6
		flake.rings = 3
		particles.mesh = flake
		if kind == "leaf_particles":
			var leaf := BoxMesh.new()
			leaf.size = Vector3(0.035, 0.003, 0.06)
			particles.mesh = leaf
			particles.angular_velocity_min = -90
			particles.angular_velocity_max = 90
		stage.add_child(particles)
		weather_emitters[kind] = particles
	for particles in weather_emitters.values():
		var particle_material := StandardMaterial3D.new()
		particle_material.vertex_color_use_as_albedo = true
		particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		particles.material_override = particle_material
	_process(0.0)

func _sync_weather() -> void:
	# Read the existing emitters, including biome, intensity and shelter changes.
	# Ambient audio remains owned by the running world; this view never restarts it.
	for kind in weather_emitters:
		var target: CPUParticles3D = weather_emitters[kind]
		var source: CPUParticles2D = weather.get(kind) if is_instance_valid(weather) else null
		if not is_instance_valid(source):
			target.emitting = false
			continue
		target.visible = source.emitting
		target.emitting = source.emitting
		if target.amount != source.amount: target.amount = source.amount
		target.color = source.color
		target.spread = source.spread
		target.initial_velocity_min = source.initial_velocity_min / 75.0
		target.initial_velocity_max = source.initial_velocity_max / 75.0
		target.direction = Vector3(source.direction.x, -absf(source.direction.y), 0.12).normalized()
		if kind != "rain_particles": target.lifetime = source.lifetime

func _process(delta: float) -> void:
	if not is_instance_valid(car) or camera == null: return
	elapsed += delta
	# Model forward is -Z; gameplay forward is +X. Rotate the live map around
	# the actual parked position, so the surroundings work at every heading.
	var transform := Transform2D(-car.global_rotation - PI / 2, Vector2.ZERO)
	transform.origin = Vector2(768, 768) - transform.basis_xform(car.global_position)
	live_world.canvas_transform = transform
	var blend := smoothstep(0.0, 1.0, minf(elapsed / 1.1, 1.0))
	camera.position = Vector3(0, 2.95, 2.95).lerp(Vector3(0, 2.68, 2.82), blend)
	camera.look_at(Vector3(0, 0.81, 1.72))
	model.trunk_pivot.rotation.x = move_toward(model.trunk_pivot.rotation.x, -2.15, delta * 2.4)
	if elapsed >= 1.1 and not requested.is_empty(): _next_swap()
	_sync_weather()
	_sync_trunk_light(delta)
	scan_timer -= delta
	if scan_timer <= 0:
		scan_timer = 0.5
		_scan_actors()
	for actor in mirrors.keys():
		if not is_instance_valid(actor):
			mirrors[actor].root.queue_free()
			mirrors.erase(actor)
			continue
		var entry: Dictionary = mirrors[actor]
		var point: Vector2 = transform * actor.global_position - Vector2(768, 768)
		entry.root.position = Vector3(point.x, 0, point.y) * (90.0 / 1536.0)
		entry.root.rotation.y = car.global_rotation + PI / 2
		entry.root.visible = actor.is_visible_in_tree()
		for pair in entry.meshes:
			if is_instance_valid(pair[0]) and pair[0].is_inside_tree():
				pair[1].transform = pair[0].global_transform
				pair[1].visible = pair[0].is_visible_in_tree()
			else: pair[1].hide()

func _scan_actors() -> void:
	var candidates: Array[Node] = []
	for group in ["pedestrian", "vehicle"]:
		candidates.append_array(get_tree().get_nodes_in_group(group))
	for actor in mirrors.keys():
		if is_instance_valid(actor) and actor.global_position.distance_to(car.global_position) > 650:
			_release_actor(actor)
	for actor in candidates:
		if actor == car or actor.is_in_group("player") or mirrors.has(actor) or not actor is Node2D: continue
		if actor.global_position.distance_to(car.global_position) > 600 or mirrors.size() >= 24: continue
		var source: Node3D
		if "model_root" in actor: source = actor.model_root
		elif "body_model" in actor: source = actor.body_model
		if not is_instance_valid(source): continue
		var holder := Node3D.new()
		stage.add_child(holder)
		var pairs := []
		for original in source.find_children("*", "MeshInstance3D", true, false):
			var copy := MeshInstance3D.new()
			copy.mesh = original.mesh
			copy.material_override = original.material_override
			for surface in original.get_surface_override_material_count():
				copy.set_surface_override_material(surface, original.get_surface_override_material(surface))
			holder.add_child(copy)
			pairs.append([original, copy])
		var layers := []
		for item in actor.find_children("*", "CanvasItem", true, false):
			layers.append([item, item.visibility_layer])
			item.visibility_layer = LIVE_HIDDEN_LAYER
		mirrors[actor] = {"root": holder, "meshes": pairs, "layers": layers}

func _release_actor(actor) -> void:
	var entry: Dictionary = mirrors[actor]
	for pair in entry.layers:
		if is_instance_valid(pair[0]): pair[0].visibility_layer = pair[1]
	entry.root.queue_free()
	mirrors.erase(actor)

func _exit_tree() -> void:
	for actor in mirrors.keys(): _release_actor(actor)

func set_loadout(slots: Dictionary) -> void:
	requested = slots.duplicate(true)
	if displayed.is_empty():
		for slot in SLOT_POSITIONS:
			_replace_weapon(slot, String(requested.get(slot, "")))
		return
	_next_swap()

func _replace_weapon(slot: String, id: String) -> void:
	if slot_models.has(slot): slot_models[slot].free()
	var weapon := Node3D.new()
	weapon.name = "Trunk_" + id
	weapon.set_meta("weapon_id", id)
	weapons.add_child(weapon)
	if not id.is_empty(): WEAPON.build(weapon, id)
	weapon.rotation_degrees = Vector3(0, -90, 90)
	weapon.position = SLOT_POSITIONS[slot]
	if slot != "longa": weapon.scale = Vector3.ONE * 1.25
	slot_models[slot] = weapon
	displayed[slot] = id
	_rebuild_cutout(slot, weapon)

func _next_swap() -> void:
	if swapping or elapsed < 1.1: return
	for slot in SLOT_POSITIONS:
		var id := String(requested.get(slot, ""))
		if id == String(displayed.get(slot, "")): continue
		swapping = true
		var weapon: Node3D = slot_models[slot]
		var rest: Vector3 = SLOT_POSITIONS[slot]
		var grip := rest + Vector3(0, 0.075, 0)
		hand.position = Vector3(0.55, 0.85, 2.75)
		hand.show()
		var motion := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		motion.tween_property(hand, "position", grip, 0.28)
		motion.tween_method(_grasp, 0.0, 1.0, 0.12)
		motion.tween_property(hand, "position", grip + Vector3(0.1, 0.18, 0.75), 0.30)
		motion.parallel().tween_property(weapon, "position", rest + Vector3(0.1, 0.18, 0.75), 0.30)
		motion.tween_callback(func():
			_replace_weapon(slot, id)
			slot_models[slot].position = rest + Vector3(0.1, 0.18, 0.75))
		motion.tween_property(hand, "position", grip, 0.30)
		motion.parallel().tween_method(func(t: float): slot_models[slot].position = (rest + Vector3(0.1, 0.18, 0.75)).lerp(rest, t), 0.0, 1.0, 0.30)
		motion.tween_method(_grasp, 1.0, 0.0, 0.12)
		motion.tween_property(hand, "position", Vector3(0.55, 0.85, 2.75), 0.28)
		motion.tween_callback(func():
			hand.hide()
			swapping = false
			_next_swap())
		return

func _grasp(amount: float) -> void:
	for finger in fingers: finger.rotation.x = -amount * 0.85

func _hand_box(parent: Node3D, pos: Vector3, dimensions: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	part.mesh = mesh
	part.material_override = material
	part.position = pos
	parent.add_child(part)

func _build_hand() -> void:
	hand = Node3D.new()
	hand.name = "DanteHandlingHand"
	stage.add_child(hand)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("b97b51")
	skin.roughness = 0.8
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_texture = preload("res://scripts/player/DanteVisualAdapter.gd").get_plaid_texture()
	sleeve.albedo_color = Color("8798ad")
	sleeve.roughness = 0.95
	_hand_box(hand, Vector3(0, 0, 0.04), Vector3(0.09, 0.037, 0.115), skin)
	_hand_box(hand, Vector3(0, -0.005, 0.14), Vector3(0.07, 0.045, 0.12), skin)
	_hand_box(hand, Vector3(0, 0, 0.36), Vector3(0.095, 0.075, 0.36), sleeve)
	for i in 4:
		var finger := Node3D.new()
		finger.position = Vector3(-0.032 + i * 0.021, 0, -0.018)
		hand.add_child(finger)
		var length := 0.068 - absf(i - 1.3) * 0.011
		_hand_box(finger, Vector3(0, 0, -length / 2), Vector3(0.017, 0.023, length), skin)
		fingers.append(finger)
	var thumb := Node3D.new()
	thumb.position = Vector3(-0.052, -0.005, 0.03)
	thumb.rotation.y = 0.55
	hand.add_child(thumb)
	_hand_box(thumb, Vector3(0, 0, -0.025), Vector3(0.024, 0.028, 0.065), skin)
	fingers.append(thumb)
	hand.hide()

func _build_selection_audio() -> void:
	selection_audio = AudioStreamPlayer.new()
	selection_audio.bus = &"SFX"
	selection_audio.volume_db = -15
	add_child(selection_audio)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(2205 * 2)
	for i in 2205:
		var t := float(i) / 22050.0
		var pulse := sin(TAU * 1450 * t) * exp(-t * 110) + sin(TAU * 410 * t) * exp(-t * 55) * 0.45
		bytes.encode_s16(i * 2, int(clampf(pulse * 0.65, -1, 1) * 32767))
	stream.data = bytes
	selection_audio.stream = stream

func play_selection() -> void:
	selection_audio.play()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		inspect_at(event.position)
		accept_event()

func inspect_at(point: Vector2) -> String:
	if swapping or elapsed < 1.1: return ""
	var viewport_point := point * Vector2(stage.size) / size
	for slot in slot_models:
		var weapon: Node3D = slot_models[slot]
		var bounds := Rect2()
		var first := true
		for part in weapon.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = part.get_aabb()
			for index in 8:
				var projected := camera.unproject_position(part.global_transform * box.get_endpoint(index))
				if first:
					bounds = Rect2(projected, Vector2.ZERO)
					first = false
				else: bounds = bounds.expand(projected)
		if not first and bounds.grow(12).has_point(viewport_point):
			var id := String(displayed[slot])
			play_selection()
			weapon_inspected.emit(id)
			return id
	return ""

func _rebuild_cutout(slot: String, weapon: Node3D) -> void:
	if cutouts.has(slot): cutouts[slot].free()
	var inset := Node3D.new()
	model.add_child(inset)
	inset.position = weapon.position
	inset.position.y = 0.643
	var shadow := StandardMaterial3D.new()
	shadow.albedo_color = Color("0c1113")
	shadow.roughness = 1.0
	# Flatten the actual mesh into the foam, retaining each weapon's outline.
	inset.scale = Vector3(1.10, 0.025, 1.10)
	for part in weapon.find_children("*", "MeshInstance3D", true, false):
		var silhouette := MeshInstance3D.new()
		silhouette.mesh = part.mesh
		silhouette.material_override = shadow
		silhouette.transform = Transform3D(weapon.basis, Vector3.ZERO) * (weapon.global_transform.affine_inverse() * part.global_transform)
		inset.add_child(silhouette)
	cutouts[slot] = inset

func _detail_mat(color: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.85
	return material

func _sticker(parent: Node3D, text: String, pos: Vector3, angle: float, color: String) -> void:
	var sticker := Node3D.new()
	parent.add_child(sticker)
	sticker.position = pos
	sticker.rotation.y = angle
	_hand_box(sticker, Vector3.ZERO, Vector3(0.23, 0.003, 0.075), _detail_mat(color))
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.pixel_size = 0.00085
	label.modulate = Color("14232b")
	label.outline_size = 0
	label.rotation_degrees.x = -90
	label.position.y = 0.003
	sticker.add_child(label)

func _build_trunk_details() -> void:
	var trim := _detail_mat("161e23")
	var thread := _detail_mat("8a8065")
	var steel := _detail_mat("879094")
	_hand_box(model.trunk_pivot, Vector3(0, -0.123, 0.35), Vector3(1.55, 0.012, 0.52), trim)
	for x in [-0.62, 0, 0.62]:
		_hand_box(model.trunk_pivot, Vector3(x, -0.135, 0.35), Vector3(0.027, 0.018, 0.45), steel)
	_hand_box(model.trunk_pivot, Vector3(0, -0.145, 0.58), Vector3(0.12, 0.035, 0.05), steel)
	_build_warning_triangle(trim)
	_hand_box(model, Vector3(-0.735, 0.73, 1.79), Vector3(0.025, 0.075, 0.16), trim)
	lamp_material = _detail_mat("e8dcc1")
	lamp_material.emission_enabled = true
	lamp_material.emission = Color("ffdc9b")
	lamp_material.emission_energy_multiplier = 0.0
	_hand_box(model, Vector3(-0.716, 0.73, 1.79), Vector3(0.008, 0.037, 0.105), lamp_material)
	trunk_light = OmniLight3D.new()
	trunk_light.name = "TrunkCourtesyLight"
	trunk_light.position = Vector3(-0.64, 0.86, 1.79)
	trunk_light.light_color = Color("ffdfab")
	trunk_light.omni_range = 1.55
	trunk_light.omni_attenuation = 1.6
	trunk_light.light_energy = 0.0
	model.add_child(trunk_light)
	for x in [-0.72, 0.72]:
		_hand_box(model, Vector3(x, 0.648, 1.80), Vector3(0.025, 0.018, 0.73), trim)
		for i in 23:
			_hand_box(model, Vector3(x, 0.66, 1.46 + i * 0.030), Vector3(0.010, 0.003, 0.013), thread)
	for z in [1.44, 2.15]:
		_hand_box(model, Vector3(0, 0.648, z), Vector3(1.45, 0.018, 0.025), trim)
	for x in [-0.58, 0.57]:
		_hand_box(model, Vector3(x, 0.65, 1.79), Vector3(0.075, 0.012, 0.11), trim)
		_hand_box(model, Vector3(x, 0.66, 1.80), Vector3(0.082, 0.010, 0.018), steel)
	_sticker(model, "MONALIZA", Vector3(-0.46, 0.665, 1.49), -0.10, "dcad56")
	_sticker(model, "WESTGATE", Vector3(0.45, 0.665, 1.49), 0.12, "ced7ca")
	_sticker(model, "DANTE", Vector3(0.04, 0.665, 2.09), -0.06, "b7ba9e")
	_hand_box(model, Vector3(0.10, 0.648, 1.96), Vector3(0.18, 0.015, 0.16), trim)
	for z in [1.875, 2.045]:
		_hand_box(model, Vector3(0.10, 0.66, z), Vector3(0.18, 0.015, 0.014), steel)

func _sync_trunk_light(delta: float) -> void:
	var at_night := is_instance_valid(weather) and (weather.time_of_day < 0.28 or weather.time_of_day > 0.78)
	var target := 1.0 if at_night else 0.0
	night_blend = target if elapsed == 0.0 else move_toward(night_blend, target, delta * 1.5)
	trunk_light.light_energy = 0.55 * night_blend
	lamp_material.emission_energy_multiplier = 1.1 * night_blend
	# Keep the small courtesy lamp visible against the actual night lighting.
	var outdoors := is_instance_valid(weather) and not weather.is_inside_interior
	var darkness := night_blend if outdoors else 0.0
	sun.light_energy = lerpf(1.0, 0.18, darkness)
	scene_environment.ambient_light_energy = lerpf(0.65, 0.28, darkness)

func _build_warning_triangle(trim: Material) -> void:
	var triangle := Node3D.new()
	triangle.name = "EmergencyWarningTriangle"
	model.trunk_pivot.add_child(triangle)
	triangle.position = Vector3(0.28, -0.16, 0.33)
	var red := _detail_mat("d93620")
	red.metallic = 0.3
	red.roughness = 0.25
	var reflective := _detail_mat("ff7645")
	reflective.metallic = 0.5
	reflective.roughness = 0.18
	var points := [Vector3(-0.20, 0, 0.13), Vector3(0.20, 0, 0.13), Vector3(0, 0, -0.19)]
	for i in 3:
		var edge := Node3D.new()
		triangle.add_child(edge)
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % 3]
		edge.position = (a + b) * 0.5
		edge.rotation.y = atan2(b.x - a.x, b.z - a.z)
		_hand_box(edge, Vector3.ZERO, Vector3(0.042, 0.016, a.distance_to(b) + 0.025), red)
		_hand_box(edge, Vector3(0, -0.010, 0), Vector3(0.016, 0.006, a.distance_to(b)), reflective)
	for x in [-0.14, 0.14]:
		_hand_box(triangle, Vector3(x, -0.02, 0.13), Vector3(0.03, 0.028, 0.068), trim)
