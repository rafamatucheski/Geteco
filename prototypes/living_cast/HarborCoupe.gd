extends "res://PlayerCar.gd"

## Same 2D controller and interaction contract as every PlayerCar.
## 3D renders only when appearance changes, not once per frame/per vehicle.
const MODEL := preload("res://prototypes/living_cast/CoupeDamageModel.gd")
const WHEEL_RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
const PALETTE := [Color("b83632"),Color("263f73"),Color("35604a"),Color("d5d1c5"),Color("24272c"),Color("b3b9bd"),Color("d6a335"),Color("814862")]
const PIXELS_PER_METRE := 74.0 / 4.46
const WHEELBASE := 2.50 * PIXELS_PER_METRE
const STEER_LOW_SPEED := 0.52
const STEER_HIGH_SPEED := 0.16
var steering_angle := 0.0
var last_visual_steering := INF
var body_model: Node3D
var body_viewport: SubViewport
var paint_color := Color("b83632")
var second_headlight: PointLight2D
var appearance_updates := 0
var _visual_damage_cooldown := 0.0
var wheel_rig := WHEEL_RIG.new()
var wheels: Array[Node3D] = []
var spinners: Array[Node3D] = []
var animation_clock := 0.0
var last_heading := INF
var brake_glows: Array[Sprite2D] = []
var high_beam := false
var _authored_lamp_mounts: Array[Vector3] = []

func _create_body_model() -> Node3D:
	return MODEL.new()

func _wheel_axles() -> PackedFloat32Array:
	return PackedFloat32Array([-1.28,1.22])

func _wheel_track() -> float:
	return 0.86

func _steering_wheelbase() -> float:
	return WHEELBASE

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_K and is_driven_by_player:
		high_beam = not high_beam
		for light in [headlight,second_headlight]:
			light.texture_scale = 0.9 if high_beam else 0.6
			light.offset = Vector2(150 if high_beam else 100,0)
			light.energy = 1.7 if high_beam else 1.35

func _ready() -> void:
	super._ready()
	# Preserve existing Harbor pacing (600 * .75 = 450 px/s), rather than
	# introducing the much faster lab controller/catalog tuning.
	body_viewport = SubViewport.new()
	body_viewport.name = "CoupeRender"
	body_viewport.size = Vector2i(192,192)
	body_viewport.transparent_bg = true
	body_viewport.own_world_3d = true
	body_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(body_viewport)
	body_model = _create_body_model()
	body_viewport.add_child(body_model)
	var lens: Material = body_model.materials.get("headlight")
	for mesh in body_model.get_children():
		if mesh is MeshInstance3D and lens != null and mesh.material_override == lens:
			_authored_lamp_mounts.append(mesh.position)
	_authored_lamp_mounts.sort_custom(func(a: Vector3, b: Vector3): return a.x < b.x)
	if _authored_lamp_mounts.size() >= 2:
		_authored_lamp_mounts = [_authored_lamp_mounts[0], _authored_lamp_mounts[-1]]
	# Os cubos vêm do metadado autoral do modelo. A geometria declarada aqui em
	# baixo só cobre modelo sem metadado: quando ela era a fonte principal, todo
	# modelo que montava a roda fora de y=0.36 (a picape em 0.44, o furgão em
	# 0.38) ficava sem pivô e com a roda soldada na lataria.
	var fallback_centers: Array[Vector3] = []
	for side in [-1.0,1.0]:
		for wheel_z in _wheel_axles():
			fallback_centers.append(Vector3(side*_wheel_track(),0.36,wheel_z))
	wheel_rig.mount(body_model, fallback_centers)
	wheels = wheel_rig.pivots
	spinners = wheel_rig.spinners
	body_model.rotation.y = -PI/2
	var view := Camera3D.new()
	body_viewport.add_child(view)
	view.position = Vector3(0,8,4)
	view.look_at(Vector3(0,0.45,0))
	view.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.size = 5.8
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	body_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-30,0)
	sun.light_energy = 1.0
	body_viewport.add_child(sun)
	sprite.texture = body_viewport.get_texture()
	uniform_scale = PIXELS_PER_METRE * view.size / 192.0
	sprite.scale = Vector2.ONE * uniform_scale
	sprite.rotation = 0
	sprite.modulate = Color.WHITE
	# Ground contact follows the physical footprint, not the elevated roof.
	preload("res://ContactShadow.gd").add_vehicle(self, Vector2(78, 35))
	# Full physical footprint inside the visible body (not the old atlas crop).
	$Collision.shape.size = Vector2(72,31)
	$BumperHitbox.get_child(0).shape.size = Vector2(74,33)
	# Exhaust is behind the rear axle, never in the centre of the roof.
	backfire_emitter.position = Vector2(-2.23 * PIXELS_PER_METRE, 0)
	backfire_emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	backfire_emitter.emission_points = PackedVector2Array([Vector2(0, -0.55 * PIXELS_PER_METRE), Vector2(0, 0.55 * PIXELS_PER_METRE)])
	nitro_emitter.position = backfire_emitter.position
	smoke_emitter.position = Vector2(-20, 0)
	flame_particles.position = smoke_emitter.position
	headlight.position = Vector2(30,-11)
	headlight.offset = Vector2(100,0)
	headlight.texture_scale = 0.6
	second_headlight = headlight.duplicate()
	second_headlight.name = "RightHeadlight"
	second_headlight.position.y = 11
	add_child(second_headlight)
	for side in [-1.0,1.0]:
		var glow := Sprite2D.new()
		glow.texture = _make_soft_particle_texture()
		glow.position = Vector2(-34,side*11)
		# Ground spill is occluded by the opaque 3D body, including its roof.
		glow.z_index = -1
		glow.scale = Vector2.ONE * 0.22
		glow.modulate = Color(1,0.08,0.04,0.25)
		var unshaded := CanvasItemMaterial.new()
		unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		glow.material = unshaded
		add_child(glow)
		brake_glows.append(glow)
	preload("res://VehicleMeshBatcher.gd").batch_model(body_model)
	repaint_vehicle(paint_color)
	_prepare_native_door()

func request_appearance_update() -> void:
	if body_viewport:
		body_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		appearance_updates += 1

func repaint_vehicle(new_color: Color = Color.TRANSPARENT) -> void:
	paint_color = PALETTE.pick_random() if new_color == Color.TRANSPARENT else new_color
	if body_model:
		body_model.paint.albedo_color = paint_color
		request_appearance_update()
	if sprite: sprite.modulate = Color.WHITE

var _door_3d: Node3D
var _side_doors := {}
func _prepare_native_door(side: float = -1.0) -> void:
	if not is_instance_valid(body_model): return
	_door_3d = _side_doors.get(side)
	if not is_instance_valid(_door_3d):
		_door_3d = preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
		body_model.add_child(_door_3d)
		_door_3d.configure(body_model, side)
		_side_doors[side] = _door_3d

func _animate_car_door(side: float = -1.0, hold_seconds: float = 0.42) -> void:
	_prepare_native_door(side)
	if not is_instance_valid(_door_3d): return
	_door_3d.play(hold_seconds)
	var audio := AudioStreamPlayer2D.new()
	audio.stream = ProceduralAudio.get_car_door_open_stream()
	audio.bus = &"SFX"
	audio.max_distance = 500
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _apply_steering_motion(turn_input: float, delta: float) -> void:
	var longitudinal := velocity.dot(global_transform.x)
	var lateral := velocity.dot(global_transform.y)
	var speed_fraction := clampf(absf(longitudinal) / maxf(max_speed, 1.0), 0.0, 1.0)
	var maximum_angle := lerpf(STEER_LOW_SPEED, STEER_HIGH_SPEED, speed_fraction)
	steering_angle = move_toward(steering_angle, clampf(turn_input, -1.0, 1.0) * maximum_angle, (4.0 if is_zero_approx(turn_input) else 3.2) * delta)
	# Bicycle-model yaw: no pivoting at rest, natural reverse steering and a
	# wider turn radius at speed. Rotate velocity with the rolling direction.
	var incoming := velocity
	var slide := clampf(handbrake_slide / 0.35, 0.0, 1.0)
	var heading: float = rotation + longitudinal / _steering_wheelbase() * tan(steering_angle) * _drivetrain.steer_scale * delta * lerpf(1.0, 2.25, slide)
	preload("res://VehicleMotionSafety.gd").rotate_clear(self, heading)
	var rolling := global_transform.x * longitudinal + global_transform.y * lateral * exp(-8.0 / (1.0 + maxf(0.0, _drivetrain.drift_bias) * 5.0) * delta)
	# Locked rear wheels preserve world momentum; grip returns progressively.
	velocity = rolling.lerp(incoming, slide)

## Alinha sprite e modelo 3D ao rumo atual. O _physics_process faz isso a cada
## quadro, mas com a árvore pausada (entrega da Monaliza na garagem, diálogo)
## o carro ficava de lado até a física voltar.
func sync_presentation_heading() -> void:
	if not body_model: return
	body_model.rotation.y = -global_rotation - PI/2
	sprite.global_rotation = 0
	if has_method("request_appearance_update"): request_appearance_update()

func _physics_process(delta: float) -> void:
	_visual_damage_cooldown = maxf(0,_visual_damage_cooldown-delta)
	super._physics_process(delta)
	_apply_headlight_state()
	if not body_model: return
	# A fixed world-facing camera preserves 3D sides as the 2D car turns.
	body_model.rotation.y = -global_rotation - PI/2
	_update_projected_lamps()
	sprite.global_rotation = 0
	preload("res://world/harbor/urban_transit/UrbanVehicleDepth.gd").update(self, sprite)
	var moving := velocity.length() > 1
	var signed_speed := velocity.dot(global_transform.x)
	var braking_now := is_driven_by_player and Input.get_axis("ui_down","ui_up") * signed_speed < -10
	for i in brake_glows.size():
		var glow := brake_glows[i]
		var broken: bool = is_broken or is_exploded or body_model.broken_tail_lamps[mini(i,1)]
		glow.modulate.a = 0.0 if broken else (0.85 if braking_now else (0.22 if is_headlight_on() else 0.0))
	# Dirigido pelo jogador existe ângulo de volante de verdade; sob IA (Cobras,
	# empurrão, reboque) o esterço é deduzido da guinada da própria carroceria.
	wheel_rig.update(delta, signed_speed / PIXELS_PER_METRE, global_rotation, steering_angle if is_driven_by_player else INF)
	# Keep the driven car's steering/body pose in step with 60Hz physics.
	# Preserve fractional time instead of dropping it on every render request.
	var visual_interval := 1.0 / (60.0 if is_driven_by_player else 30.0)
	animation_clock = minf(animation_clock + delta, visual_interval * 2.0)
	var camera_2d := get_viewport().get_camera_2d()
	var near := camera_2d == null or global_position.distance_to(camera_2d.get_screen_center_position()) < 1000
	if near and is_visible_in_tree() and animation_clock + 0.000001 >= visual_interval and (moving or not is_equal_approx(last_heading,global_rotation) or not is_equal_approx(last_visual_steering, wheel_rig.steering_angle)):
		animation_clock = fposmod(animation_clock + 0.000001, visual_interval)
		last_heading = global_rotation
		last_visual_steering = wheel_rig.steering_angle
		request_appearance_update()

func _apply_headlight_state() -> void:
	super._apply_headlight_state()
	if not body_model or not second_headlight: return
	var enabled := is_headlight_on() and not is_broken
	headlight.visible = enabled and not body_model.broken_lamps[0]
	second_headlight.visible = enabled and not body_model.broken_lamps[1]

func _apply_crash_deformation(normal: Vector2, force: float, world_hit: Vector2 = Vector2.ZERO, is_post: bool = false) -> void:
	if _visual_damage_cooldown > 0: return
	_visual_damage_cooldown = 0.25
	super._apply_crash_deformation(normal,force,world_hit,is_post)
	if not body_model: return
	var hit := to_local(world_hit) / PIXELS_PER_METRE
	var inward := global_transform.basis_xform_inv(normal)
	# Original 3D model forward=-Z; vehicle forward=+X in the 2D world.
	body_model.apply_impact(Vector3(hit.y,0.81,-hit.x),Vector3(inward.y,0,-inward.x),force/PIXELS_PER_METRE)
	sprite.modulate = Color.WHITE
	request_appearance_update()
	_apply_headlight_state()

func _clear_all_dents() -> void:
	super._clear_all_dents()
	if body_model:
		body_model.repair()
		request_appearance_update()
	_apply_headlight_state()

func _explode() -> void:
	if is_exploded: return
	super._explode()
	if body_model:
		body_model.char_body()
		sprite.modulate = Color.WHITE
		request_appearance_update()

func repair_vehicle() -> void:
	super.repair_vehicle()
	repaint_vehicle(paint_color)

func _headlamp_mounts() -> Array[Vector3]:
	return _authored_lamp_mounts

func _update_projected_lamps() -> void:
	var mounts := _headlamp_mounts()
	if mounts.is_empty() or not second_headlight:
		return
	var view := body_viewport.get_camera_3d()
	if not view:
		return
	for i in 2:
		var pixel := view.unproject_position(body_model.to_global(mounts[i]))
		var light: PointLight2D = headlight if i == 0 else second_headlight
		light.global_position = sprite.to_global(pixel - Vector2(body_viewport.size) * 0.5)
