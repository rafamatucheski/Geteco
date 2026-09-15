class_name AmbientTrain
extends Node2D

## Trem ambiental inteiramente desenhado pela engine. Cada peça segue a curva
## do trilho de forma independente: isso deixa a composição articulada nas
## curvas sem usar sprites ou imagens externas.

@export_range(0.0, 160.0, 1.0) var speed := 72.0
@export_range(2, 7, 1) var freight_car_count := 5
@export var start_progress := 180.0

const ENGINE_LENGTH := 76.0
const WAGON_LENGTH := 52.0
const COUPLER_GAP := 5.0
const WAGON_STEP := WAGON_LENGTH + COUPLER_GAP
const TRAIN_RENDER_Z := 4

var _rail_line: DistrictRailLine
var _progress := 0.0
var _route_length := 0.0
var _freight_visuals: Array[Node2D] = []
var _train_audio: AudioStreamPlayer2D
var _audio_playback: AudioStreamGeneratorPlayback
var _audio_clock := 0.0


func configure(rail_line: DistrictRailLine, configured_speed: float, configured_cars: int) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rail_line = rail_line
	speed = configured_speed
	freight_car_count = clampi(configured_cars, 2, 7)
	_route_length = rail_line.get_route_length()
	_progress = fposmod(start_progress, maxf(_route_length, 1.0))
	# Absolute canvas order prevents the rail root's relative Z from being added
	# a second time: rail bed (3) < complete train (4) < elevated deck (6).
	z_as_relative = false
	z_index = TRAIN_RENDER_Z
	_rebuild_freight_visuals()
	_setup_train_audio()
	_update_pose()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_instance_valid(_rail_line) or _route_length <= 0.0:
		return
	_progress = fposmod(_progress + speed * delta, _route_length)
	_update_pose()
	_update_train_audio(delta)


func get_rail_state() -> Dictionary:
	return {
		"active": is_visible_in_tree() and is_instance_valid(_rail_line) and _route_length > 0.0,
		"progress": _progress,
		"speed": speed,
		"consist_length": ENGINE_LENGTH + float(freight_car_count) * WAGON_STEP,
		"route_length": _route_length,
	}


func _update_pose() -> void:
	var route := _rail_line.get_route_curve()
	var point := route.sample_baked(_progress, true)
	var next_point := route.sample_baked(fposmod(_progress + 6.0, _route_length), true)
	global_position = _rail_line.to_global(point)
	var direction := point.direction_to(next_point)
	if direction.length_squared() > 0.001:
		global_rotation = direction.angle()
	_update_freight_poses()


func _rebuild_freight_visuals() -> void:
	for visual in _freight_visuals:
		if is_instance_valid(visual):
			visual.queue_free()
	_freight_visuals.clear()
	for index in freight_car_count:
		var visual := TrainFreightCarVisual.new()
		visual.name = "FreightWagon_%02d" % (index + 1)
		visual.wagon_index = index
		# Wagons inherit the locomotive's absolute order instead of adding 4 again.
		visual.z_index = 0
		add_child(visual)
		_freight_visuals.append(visual)


func _update_freight_poses() -> void:
	if not is_instance_valid(_rail_line) or _route_length <= 0.0:
		return
	var route := _rail_line.get_route_curve()
	for index in _freight_visuals.size():
		# The wagon spacing matches the visible draw length plus coupler gap.
		var wagon_progress := fposmod(_progress - ENGINE_LENGTH * 0.5 - WAGON_LENGTH * 0.5 - COUPLER_GAP - float(index) * WAGON_STEP, _route_length)
		var point := route.sample_baked(wagon_progress, true)
		var next_point := route.sample_baked(fposmod(wagon_progress + 6.0, _route_length), true)
		var visual := _freight_visuals[index]
		visual.global_position = _rail_line.to_global(point)
		var direction := point.direction_to(next_point)
		if direction.length_squared() > 0.001:
			visual.global_rotation = direction.angle()


func _setup_train_audio() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(_train_audio):
		return
	_train_audio = AudioStreamPlayer2D.new()
	_train_audio.name = "TrainEngineAndRailSound"
	_train_audio.max_distance = 920.0
	_train_audio.attenuation = 0.7
	_train_audio.volume_db = -17.0
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.45
	_train_audio.stream = stream
	add_child(_train_audio)
	_train_audio.play()
	_audio_playback = _train_audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _update_train_audio(delta: float) -> void:
	if not is_instance_valid(_audio_playback):
		return
	_audio_clock += delta
	var frames := _audio_playback.get_frames_available()
	var sample_rate := 22050.0
	for frame_index in frames:
		var time := _audio_clock + float(frame_index) / sample_rate
		# Low diesel rumble, metallic wheel hum and regular sleeper clacks.
		var diesel := sin(time * TAU * 39.0) * 0.16 + sin(time * TAU * 77.0) * 0.055
		var wheel := sin(time * TAU * 7.4) * 0.035
		var clack := pow(maxf(0.0, sin(time * TAU * 2.8)), 24.0) * 0.18
		var sample := clampf(diesel + wheel + clack, -0.78, 0.78)
		_audio_playback.push_frame(Vector2(sample, sample))
	_audio_clock += float(frames) / sample_rate


func _draw() -> void:
	# Compact projected shadow directly below the diesel locomotive.
	draw_rect(Rect2(-42.0, -15.0, 88.0, 33.0), Color(0.01, 0.02, 0.03, 0.34), true)
	_draw_locomotive()


func _draw_locomotive() -> void:
	# Front faces right in local rail direction. Dark outline makes it legible at
	# gameplay zoom, with a separate cab, hood, roof, grills and bogies.
	draw_rect(Rect2(-39, -17, 87, 34), Color("#151a1c"), true)
	draw_rect(Rect2(-36, -14, 81, 28), Color("#bd4b28"), true)
	draw_rect(Rect2(-34, -11, 42, 22), Color("#d35b2c"), true)
	draw_rect(Rect2(7, -14, 20, 28), Color("#e0a72d"), true)
	draw_rect(Rect2(9, -11, 16, 22), Color("#293c49"), true)
	draw_rect(Rect2(29, -12, 14, 24), Color("#3c4648"), true)
	# Cabin windshield, roof hardware and side stripes.
	draw_rect(Rect2(11, -9, 11, 8), Color("#99c9db"), true)
	draw_rect(Rect2(11, 1, 11, 8), Color("#99c9db"), true)
	draw_rect(Rect2(-25, -12, 28, 4), Color("#e8b92e"), true)
	draw_rect(Rect2(-25, 8, 28, 4), Color("#e8b92e"), true)
	for grill_x in [-31.0, -26.0, -21.0, -16.0]:
		draw_line(Vector2(grill_x, -7), Vector2(grill_x, 7), Color("#753022"), 1.5)
	draw_circle(Vector2(45, -8), 3.0, Color("#fff1ae"))
	draw_circle(Vector2(45, 8), 3.0, Color("#fff1ae"))
	_draw_bogies(-22.0, 22.0)
	# Rear coupler connects visually with the first articulated wagon.
	draw_line(Vector2(-45, 0), Vector2(-53, 0), Color("#141718"), 4.0)
	draw_circle(Vector2(-54, 0), 3.0, Color("#30383a"))


func _draw_bogies(first_x: float, second_x: float) -> void:
	for x_pos in [first_x, second_x]:
		draw_rect(Rect2(x_pos - 7, -18, 14, 36), Color("#15191a"), true)
		draw_rect(Rect2(x_pos - 4, -16, 8, 32), Color("#30383a"), true)
		draw_circle(Vector2(x_pos, -16), 3.0, Color("#0e1011"))
		draw_circle(Vector2(x_pos, 16), 3.0, Color("#0e1011"))


class TrainFreightCarVisual:
	extends Node2D
	var wagon_index := 0

	func _ready() -> void:
		queue_redraw()

	func _draw() -> void:
		var palette := [Color("#426f86"), Color("#7c6145"), Color("#536f54"), Color("#8a3d36"), Color("#666d76")]
		var body_color: Color = palette[wagon_index % palette.size()]
		# Shadow and dark underframe make each wagon read as a separate vehicle.
		draw_rect(Rect2(-29, -15, 58, 30), Color(0.01, 0.02, 0.03, 0.31), true)
		draw_rect(Rect2(-27, -13, 54, 26), Color("#171b1d"), true)
		match wagon_index % 4:
			0:
				_draw_container(body_color)
			1:
				_draw_tank_car(body_color)
			2:
				_draw_hopper(body_color)
			_:
				_draw_open_freight(body_color)
		_draw_wheels()
		# Couplers on both ends deliberately bridge the short gaps between pieces.
		draw_line(Vector2(-32, 0), Vector2(-26, 0), Color("#111415"), 4.0)
		draw_line(Vector2(26, 0), Vector2(32, 0), Color("#111415"), 4.0)
		draw_circle(Vector2(-33, 0), 2.5, Color("#3a4143"))
		draw_circle(Vector2(33, 0), 2.5, Color("#3a4143"))

	func _draw_container(color: Color) -> void:
		draw_rect(Rect2(-24, -11, 48, 22), color, true)
		draw_rect(Rect2(-21, -8, 42, 16), color.lightened(0.12), true)
		for rib in range(1, 6):
			var x_pos := -21.0 + float(rib) * 7.0
			draw_line(Vector2(x_pos, -9), Vector2(x_pos, 9), color.darkened(0.34), 1.5)

	func _draw_tank_car(color: Color) -> void:
		draw_rect(Rect2(-23, -9, 46, 18), color.darkened(0.18), true)
		draw_circle(Vector2(-18, 0), 9, color)
		draw_circle(Vector2(18, 0), 9, color)
		draw_rect(Rect2(-18, -9, 36, 18), color, true)
		draw_line(Vector2(-16, -5), Vector2(16, -5), color.lightened(0.24), 2.0)
		draw_rect(Rect2(-3, -12, 6, 4), Color("#272e30"), true)

	func _draw_hopper(color: Color) -> void:
		var points := PackedVector2Array([Vector2(-24, -10), Vector2(24, -10), Vector2(18, 10), Vector2(-18, 10)])
		draw_colored_polygon(points, color)
		draw_polyline(PackedVector2Array([Vector2(-24, -10), Vector2(24, -10), Vector2(18, 10), Vector2(-18, 10), Vector2(-24, -10)]), Color("#202628"), 2.0, true)
		for x_pos in [-10.0, 0.0, 10.0]:
			draw_line(Vector2(x_pos, -8), Vector2(x_pos, 8), color.darkened(0.32), 1.5)

	func _draw_open_freight(color: Color) -> void:
		draw_rect(Rect2(-24, -11, 48, 22), color.darkened(0.24), true)
		draw_rect(Rect2(-21, -8, 42, 16), Color("#252a2b"), true)
		for crate_x in [-12.0, 1.0, 12.0]:
			draw_rect(Rect2(crate_x - 5, -6, 10, 12), color.lightened(0.10), true)
			draw_line(Vector2(crate_x - 4, -5), Vector2(crate_x + 4, 5), color.darkened(0.35), 1.0)

	func _draw_wheels() -> void:
		for x_pos in [-17.0, 17.0]:
			draw_rect(Rect2(x_pos - 5, -16, 10, 32), Color("#141819"), true)
			draw_circle(Vector2(x_pos, -15), 3.0, Color("#090b0c"))
			draw_circle(Vector2(x_pos, 15), 3.0, Color("#090b0c"))
