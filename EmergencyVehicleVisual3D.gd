extends Node

const DOOR := preload("res://prototypes/living_cast/VehicleDoor3D.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
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
var lightbar := preload("res://world/shared/emergency/EmergencyLightbar3D.gd").new()
var render_requests := 0
var _lamp_mounts: Array[Vector3] = []
var second_headlight: PointLight2D
var wheel_rig := WHEEL_RIG.new()
var _last_render_steer := INF
var motorcycle := false
var _last_rider_occupied := true

func configure(owner_vehicle: CharacterBody2D, service: int) -> void:
	vehicle = owner_vehicle
	motorcycle = service == 0 and vehicle.get("police_variant") == "motorcycle"
	var ids := ["police_cruiser", "medic_box", "rescue_pumper", "courier_van"]
	var spec := VehicleCatalog.get_vehicle_spec(vehicle.police_archetype if service == 0 and not motorcycle else ids[service])
	viewport = SubViewport.new()
	viewport.name = "Emergency3DWorld"
	viewport.size = Vector2i(192, 192) if service == 0 else Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	model = preload("res://world/shared/emergency/PoliceMotorcycleModel.gd").new() if motorcycle else load(spec.model_class).new()
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
	vehicle.set_meta("emergency_visual_half_size", Vector2(bounds.size.z,bounds.size.x)*PPM*.5)
	if collision and collision.shape is RectangleShape2D:
		collision.shape.size = Vector2(bounds.size.z * PPM * 0.9, maxf(28.0, bounds.size.x * PPM * 0.9))
		if service == 1: collision.shape.size = Vector2(bounds.size.z,bounds.size.x)*PPM
		if motorcycle: collision.shape.size = Vector2(37, 19)
	if service == 0: model.paint.albedo_color = Color("e5e9ed")
	elif service == 3: model.paint.albedo_color = Color("292d34")
	if service == 3:
		model.add_lightbar(2.16, -1.05, Color("ffb329"), Color("a855f7"), 1.3)
	lightbar.bind(model)
	# Viatura usa os mesmos modelos do catálogo civil, mas até aqui nunca extraía
	# as rodas: pneu ficava soldado na lataria, sem giro e sem esterço. Montar
	# depois da AABB e dos faróis (que varrem os filhos) e antes do batcher.
	wheel_rig.mount(model)
	preload("res://cars/VehicleMeshBatcher.gd").batch_model(model)
	for side in [-1.0, 1.0]:
		if motorcycle: continue
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
	preload("res://ContactShadow.gd").add_vehicle(vehicle, Vector2(40,20) if motorcycle else Vector2(bounds.size.z, bounds.size.x) * PPM * 1.06)
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
	if motorcycle: return
	var door: Node3D = doors[side]
	door.play(hold)
	_door_motion = 0.35 if hold > 10.0 else hold + 0.6

func door_floor_hinge(side: float) -> Vector2:
	if motorcycle: return Vector2(-5, side * 12)
	var door: Node3D = doors[side]
	if door.hinge == null: return Vector2(-8.0, side * 16.0)
	return Vector2(-door.hinge.position.z, door.hinge.position.x) * PPM

func close_door(side: float, immediate := false) -> void:
	if motorcycle: return
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
	if model.has_method("set_rear_doors"): model.set_rear_doors(false, true)

func set_rear_doors(open: bool) -> void:
	if model.has_method("set_rear_doors"):
		model.set_rear_doors(open)
		_door_motion = 0.9
		_was_visible = false

func _process(delta: float) -> void:
	if not is_instance_valid(vehicle) or model == null: return
	var rider_changed := false
	model.rotation.y = -vehicle.global_rotation - PI * 0.5
	# A IA de emergência persegue o alvo por lerp_angle sobre `rotation`, sem
	# volante: o esterço vem da guinada. Atualizado mesmo fora de tela para o
	# rig não deduzir uma curva falsa do salto de proa ao reaparecer.
	wheel_rig.update(delta, vehicle.velocity.dot(vehicle.global_transform.x) / PPM, vehicle.global_rotation)
	if motorcycle:
		var occupied: bool = not vehicle.is_broken and vehicle._police_available_seats > 0 and (vehicle.deployed_officers == 0 or vehicle.returned_officers >= vehicle.deployed_officers)
		rider_changed = occupied != _last_rider_occupied
		_last_rider_occupied = occupied
		model.set_rider_state(occupied, false)
		model.rider_jacket.albedo_color = Color("19304b")
		model.rider_helmet.albedo_color = Color("edf0f2")
		rider_changed = model.update_riding_pose(delta, vehicle.velocity.length() / PPM, wheel_rig.steering_angle, occupied) or rider_changed
		if rider_changed: _door_motion = maxf(_door_motion, 0.10)
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
	var flash := int(Time.get_ticks_msec() / 160) % 2 if vehicle.lights.visible and not vehicle.is_broken else -1
	var changed := not _was_visible or absf(angle_difference(_last_heading, vehicle.global_rotation)) > 0.005 or _door_motion > 0.0 or flash != _last_flash or absf(wheel_rig.steering_angle - _last_render_steer) > 0.004
	if changed and _clock >= 1.0 / 30.0:
		lightbar.update(flash >= 0, Time.get_ticks_msec())
		_last_flash = flash
		_last_heading = vehicle.global_rotation
		_last_render_steer = wheel_rig.steering_angle
		_clock = 0.0
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		render_requests += 1
	_was_visible = true
