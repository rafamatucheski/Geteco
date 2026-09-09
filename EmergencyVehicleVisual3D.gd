extends Node

const DOOR := preload("res://prototypes/living_cast/VehicleDoor3D.gd")
const PPM := 74.0 / 4.46
var model: Node3D
var viewport: SubViewport
var camera: Camera3D
var vehicle: CharacterBody2D
var doors := {}
var _clock := 0.0
var _door_motion := 0.0
var _last_heading := INF
var _was_visible := false
var _last_flash := -1
var _lamps: Array[StandardMaterial3D] = []
var render_requests := 0
var _lamp_mounts: Array[Vector3] = []
var second_headlight: PointLight2D

func configure(owner_vehicle: CharacterBody2D, service: int) -> void:
	vehicle = owner_vehicle
	var ids := ["police_cruiser", "medic_box", "rescue_pumper", "courier_van"]
	var spec := VehicleCatalog.get_vehicle_spec(ids[service])
	viewport = SubViewport.new()
	viewport.name = "Emergency3DWorld"
	viewport.size = Vector2i(192, 192) if service == 0 else Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	model = load(spec.model_class).new()
	viewport.add_child(model)
	var bounds := AABB()
	var first := true
	for mesh in model.get_children():
		if not mesh is MeshInstance3D or mesh.mesh == null: continue
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		if mesh.material_override == model.materials.get("headlight"):
			_lamp_mounts.append(mesh.position)
	var collision := vehicle.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision and collision.shape is RectangleShape2D:
		collision.shape.size = Vector2(bounds.size.z * PPM * 0.9, maxf(28.0, bounds.size.x * PPM * 0.9))
	if service == 0: model.paint.albedo_color = Color("e5e9ed")
	elif service == 3: model.paint.albedo_color = Color("292d34")
	# Police identification belongs to the actual mesh, not a floating 2D bar.
	if service == 0:
		var navy: StandardMaterial3D = model.mat("police_navy", "19314e", 0.3, 0.35)
		model.box(Vector3(0, 0.815, -1.5), Vector3(1.73, 0.035, 1.45), navy)
		model.box(Vector3(0, 0.84, 1.65), Vector3(1.7, 0.035, 1.2), navy)
		model.box(Vector3(0, 1.43, 0.05), Vector3(1.1, 0.08, 0.22), navy)
		for side in [-1.0, 1.0]:
			var lens: StandardMaterial3D = model.mat("police_beacon_%s" % side, "e83c42" if side < 0 else "3689ef", 0.1, 0.2, 0.4)
			_lamps.append(lens)
			model.box(Vector3(side * 0.32, 1.52, 0.05), Vector3(0.48, 0.12, 0.22), lens)
	preload("res://VehicleMeshBatcher.gd").batch_model(model)
	for side in [-1.0, 1.0]:
		var door := DOOR.new()
		model.add_child(door)
		door.configure(model, side)
		door.set_process(false) # This presenter owns the 30Hz visible render budget.
		doors[side] = door
	model.rotation.y = -PI * 0.5
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 8, 4)
	camera.look_at(Vector3(0, 0.45, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(6.0, Vector2(bounds.size.x, bounds.size.z).length() * 1.3)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.0
	viewport.add_child(sun)
	vehicle.visual.texture = viewport.get_texture()
	vehicle.visual.region_enabled = false
	vehicle.visual.scale = Vector2.ONE * (PPM * camera.size / float(viewport.size.x))
	vehicle.visual.global_rotation = 0.0
	vehicle.visual.modulate = Color.WHITE
	_lamp_mounts.sort_custom(func(a: Vector3, b: Vector3): return a.x < b.x)
	if vehicle.headlight and _lamp_mounts.size() >= 2:
		_lamp_mounts = [_lamp_mounts[0], _lamp_mounts[-1]]
		second_headlight = vehicle.headlight.duplicate()
		second_headlight.name = "RightHeadlight"
		vehicle.add_child(second_headlight)
	for light in [vehicle.headlight, second_headlight]:
		if light:
			light.offset = Vector2(95, 0)
			light.texture_scale = 0.6
			light.energy = 0.7

func open_door(side: float, hold: float = 3600.0) -> void:
	var door: Node3D = doors[side]
	door.play(hold)
	_door_motion = 0.35 if hold > 10.0 else hold + 0.6

func door_floor_hinge(side: float) -> Vector2:
	var door: Node3D = doors[side]
	if door.hinge == null: return Vector2(-8.0, side * 16.0)
	return Vector2(-door.hinge.position.z, door.hinge.position.x) * PPM

func close_door(side: float, immediate := false) -> void:
	var door: Node3D = doors[side]
	if door.animation: door.animation.kill()
	if door.hinge == null: return
	if immediate:
		door.hinge.rotation.y = 0.0
	else:
		door.create_tween().tween_property(door.hinge, "rotation:y", 0.0, 0.26)
	_door_motion = 0.35

func reset_doors() -> void:
	for side in doors: close_door(side, true)

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or model == null: return
	model.rotation.y = -vehicle.global_rotation - PI * 0.5
	vehicle.visual.global_rotation = 0.0
	if vehicle.headlight and second_headlight:
		for i in 2:
			var light: PointLight2D = vehicle.headlight if i == 0 else second_headlight
			var pixel := camera.unproject_position(model.to_global(_lamp_mounts[i]))
			light.global_position = vehicle.visual.to_global(pixel - Vector2(viewport.size) * 0.5)
		second_headlight.visible = vehicle.headlight.visible
	var screen: Vector2 = vehicle.get_canvas_transform() * vehicle.global_position
	var on_screen := vehicle.is_visible_in_tree() and vehicle.get_viewport().get_visible_rect().grow(140).has_point(screen)
	_clock += delta
	_door_motion = maxf(0.0, _door_motion - delta)
	if not on_screen:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_was_visible = false
		if vehicle.headlight and vehicle.headlight.visible: vehicle.headlight.visible = false
		if second_headlight and second_headlight.visible: second_headlight.visible = false
		return
	if vehicle.headlight:
		var lights_on: bool = vehicle.is_night_or_storm and not vehicle.is_broken and vehicle.visible
		if vehicle.headlight.visible != lights_on:
			vehicle.headlight.visible = lights_on
			if second_headlight: second_headlight.visible = lights_on
	var flash := int(Time.get_ticks_msec() / 240) % 2 if vehicle.lights.visible else -1
	var changed := not _was_visible or absf(angle_difference(_last_heading, vehicle.global_rotation)) > 0.005 or _door_motion > 0.0 or flash != _last_flash
	if changed and _clock >= 1.0 / 30.0:
		for i in _lamps.size():
			_lamps[i].emission_enabled = flash == i
			_lamps[i].emission_energy_multiplier = 1.4
		_last_flash = flash
		_last_heading = vehicle.global_rotation
		_clock = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		render_requests += 1
	_was_visible = true
