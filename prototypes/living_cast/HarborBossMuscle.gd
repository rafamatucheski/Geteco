extends "res://prototypes/living_cast/HarborCoupe.gd"

## Standalone reward vehicle. Geometry/audio vary; interaction, rendering LOD,
## damage, garage paint and road handling remain the proven PlayerCar contract.
const BOSS_MODEL := preload("res://prototypes/living_cast/BossMuscleModel.gd")
const BOSS_CAMERA := preload("res://DynamicCamera.gd")
static var _v8_stream: AudioStreamWAV
static var v8_stream_builds := 0

func _init() -> void:
	max_speed = 560.0
	has_nitro = false
	paint_color = Color("49252d")

func _enter_tree() -> void:
	# Reward instances arrive after Player in the tree: process the parked car
	# first so one E press cannot both board and immediately leave it.
	process_physics_priority = -1
	if not has_node("Collision"):
		var collider := CollisionShape2D.new()
		collider.name = "Collision"
		collider.shape = RectangleShape2D.new()
		collider.shape.size = Vector2(82,35)
		add_child(collider)
	if not has_node("Camera"):
		var camera_node := Camera2D.new()
		camera_node.set_script(BOSS_CAMERA)
		camera_node.name = "Camera"
		camera_node.enabled = false
		camera_node.ignore_rotation = true
		add_child(camera_node)
	if not has_node("InteractArea"):
		var area := Area2D.new()
		area.name = "InteractArea"
		area.collision_layer = 0
		area.collision_mask = 4
		var shape := CollisionShape2D.new()
		shape.shape = CircleShape2D.new()
		shape.shape.radius = 60.0
		area.add_child(shape)
		add_child(area)
	collision_mask = 23
	z_index = 8

func _create_body_model() -> Node3D:
	return BOSS_MODEL.new()

func enter_vehicle(player_body: CharacterBody2D) -> void:
	# Keep parked rewards from stealing the active camera when they spawn.
	if is_driven_by_player or player_body == null or health <= 0:
		return
	$Camera.enabled = true
	super.enter_vehicle(player_body)


func _animate_car_door(side: float = -1.0, hold_seconds: float = 0.42) -> void:
	if _door_visual == null:
		_door_visual = VEHICLE_DOOR_VISUAL.new()
		_door_visual.name = "ProceduralVehicleDoor"
		_door_visual.configure(Vector2(0.58,-0.945)*PIXELS_PER_METRE,1.66*PIXELS_PER_METRE)
		add_child(_door_visual)
	super._animate_car_door(side, hold_seconds)

func _wheel_axles() -> PackedFloat32Array:
	return PackedFloat32Array([-1.50,1.35])

func repair_vehicle() -> void:
	super.repair_vehicle()
	# Destruction sets max_speed to zero; every repair entry point must restore
	# this vehicle's own pacing, not just the reward garage's UI callback.
	max_speed = 560.0

func _wheel_track() -> float:
	return 0.94

func _steering_wheelbase() -> float:
	return 2.85 * PIXELS_PER_METRE

func _ready() -> void:
	super._ready()
	max_speed = 560.0
	has_nitro = false
	$Collision.shape.size = Vector2(82,35)
	$BumperHitbox.get_child(0).shape.size = Vector2(84,37)
	$ContactShadow.scale = Vector2(84,37) / $ContactShadow.texture.get_size()
	headlight.position = Vector2(39,-12)
	second_headlight.position = Vector2(39,12)
	for index in brake_glows.size():
		brake_glows[index].position = Vector2(-40,-12 if index == 0 else 12)
	backfire_emitter.position.x = -41
	nitro_emitter.position = backfire_emitter.position
	engine_audio.stream = get_v8_stream()
	set_meta("display_name", "Ironback V8")

static func get_v8_stream() -> AudioStreamWAV:
	if _v8_stream != null:
		return _v8_stream
	# Band-limited, periodic four-stroke rumble. Cached once for every reward
	# instance, with the controller supplying RPM pitch and distance attenuation.
	const SAMPLE_RATE := 22050
	const FRAMES := SAMPLE_RATE * 2
	var data := PackedByteArray()
	data.resize(FRAMES * 2)
	for i in FRAMES:
		var t := float(i) / SAMPLE_RATE
		var pulse := sin(TAU*48*t) * 0.42 + sin(TAU*96*t)*0.24
		pulse += sin(TAU*144*t)*0.13 + sin(TAU*192*t)*0.065
		pulse *= 0.82 + 0.12*sin(TAU*12*t) + 0.06*sin(TAU*24*t)
		data.encode_s16(i*2,int(clampf(pulse,-1,1)*23000))
	_v8_stream = AudioStreamWAV.new()
	_v8_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_v8_stream.mix_rate = SAMPLE_RATE
	_v8_stream.data = data
	_v8_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_v8_stream.loop_end = FRAMES
	v8_stream_builds += 1
	return _v8_stream
