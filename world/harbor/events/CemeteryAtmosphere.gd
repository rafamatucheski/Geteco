extends Node
## Local wind and a bounded visiting groundskeeper, independent of the player.
var wind: AudioStreamPlayer2D
var keeper: Node2D
var visit_in := 45.0
var work_left := 22.0
var leaving := false
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	wind = AudioStreamPlayer2D.new()
	wind.name = "CemeteryWind"
	wind.stream = _wind_stream()
	wind.bus = "SFX"
	wind.max_distance = 650
	wind.volume_db = -15
	get_parent().add_child.call_deferred(wind)
	wind.play.call_deferred()

static func _wind_stream() -> AudioStreamWAV:
	var rate := 22050
	var count := rate * 12
	var data := PackedByteArray()
	data.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 7341
	var filtered := 0.0
	for i in count:
		var t := float(i) / rate
		filtered += (noise.randf_range(-1,1) - filtered) * 0.065
		var fade := minf(1.0, minf(t,12.0-t) / 0.8)
		var gust := 0.55 + 0.30 * sin(TAU*t/6.0) + 0.15*sin(TAU*t/4.0)
		var sample := (filtered*1.5 + sin(TAU*173*t+0.8*sin(TAU*t/12.0))*0.035) * gust * fade
		data.encode_s16(i*2,clampi(int(sample*32767),-32768,32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream

func _process(delta: float) -> void:
	if is_instance_valid(keeper):
		if keeper.is_dead:
			keeper.queue_free()
			visit_in = rng.randf_range(180,300)
		elif keeper.finished:
			if leaving:
				keeper.queue_free()
				visit_in = rng.randf_range(180,300)
			else:
				work_left -= delta
				if work_left <= 0:
					leaving = true
					var origin: Vector2 = get_parent().global_position
					keeper.set_route(PackedVector2Array([origin+Vector2(0,290),origin+Vector2(0,-410)]))
	else:
		visit_in -= delta
		if visit_in <= 0: start_visit()

func start_visit() -> void:
	if is_instance_valid(keeper): return
	var cemetery := get_parent() as Node2D
	keeper = preload("res://world/harbor/events/WorldEventResident.gd").new()
	keeper.coat_color = Color("555a40")
	keeper.lines.clear()
	keeper.position = Vector2(0,-410)
	cemetery.add_child(keeper)
	keeper.add_to_group("cemetery_keeper")
	# A visible shovel distinguishes the worker from mourners.
	var shovel := Line2D.new()
	shovel.points = PackedVector2Array([Vector2(12,-25),Vector2(12,6)])
	shovel.width = 3
	shovel.default_color = Color("877455")
	keeper.add_child(shovel)
	var blade := Polygon2D.new()
	blade.polygon = PackedVector2Array([Vector2(7,2),Vector2(17,2),Vector2(16,10),Vector2(12,13),Vector2(8,10)])
	blade.color = Color("777e7d")
	keeper.add_child(blade)
	keeper.set_route(PackedVector2Array([cemetery.global_position+Vector2(0,-330),cemetery.global_position+Vector2(0,290),cemetery.global_position+Vector2(90,290)]))
	leaving = false
	work_left = 22
