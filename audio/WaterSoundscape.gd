extends Node
## Água doce por distância à margem real; o ouvinte é informado pelo mundo.
const RECORDED := preload("res://audio/living_city/LivingCityAudio.gd")
var beds: Dictionary = {}
var gains := {"lake": 0.0, "stream": 0.0, "fountain": 0.0}
var targets := {"lake": 0.0, "stream": 0.0, "fountain": 0.0}
var _sample_clock := 1.0

func _ready() -> void:
	for kind in gains:
		var audio := AudioStreamPlayer.new()
		audio.name = String(kind).capitalize() + "Water"
		audio.bus = &"SFX"
		audio.stream = RECORDED.bed("water", 1) if kind == "lake" else preload("res://audio/water/flow.ogg")
		if audio.stream is AudioStreamOggVorbis: audio.stream.loop = true
		audio.pitch_scale = 1.15 if kind == "fountain" else 1.0
		audio.volume_db = -80
		add_child(audio)
		beds[kind] = audio

static func path_distance(point: Vector2, points: PackedVector2Array, closed: bool = false) -> float:
	if points.is_empty(): return INF
	if closed and Geometry2D.is_point_in_polygon(point, points): return 0.0
	var distance := point.distance_to(points[0])
	for i in range(points.size() if closed else points.size() - 1):
		distance = minf(distance, point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[i], points[(i + 1) % points.size()])))
	return distance

static func coast_weight(point: Vector2) -> float:
	# Margens navegáveis dos bairros e da península. A ponte da rodovia tem sua
	# própria gravação em RegionalSoundscape; não somamos uma segunda ali.
	var shores: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(3200,-2400), Vector2(3200,3500), Vector2(3010,3500), Vector2(2890,3330), Vector2(2853,2480), Vector2(-100,2480)]),
		PackedVector2Array([Vector2(4380,-2400), Vector2(4380,2600), Vector2(6760,2600), Vector2(6760,-2400), Vector2(6300,-2400)]),
		PackedVector2Array([Vector2(4380,-2400), Vector2(5700,-2400)]),
		PackedVector2Array([Vector2(5700,-2400), Vector2(5700,-4387)]),
		PackedVector2Array([Vector2(6300,-2400), Vector2(6300,-4387)]),
		PackedVector2Array([Vector2(8950,-9960), Vector2(8950,40)]),
	]
	var distance := INF
	for shore in shores: distance = minf(distance, path_distance(point, shore))
	return 1.0 - smoothstep(60, 480, distance)

func update_context(point: Vector2, inside: bool, focus: float, delta: float) -> void:
	_sample_clock += delta
	if inside or _sample_clock >= 0.2:
		_sample_clock = 0.0
		for kind in targets: targets[kind] = 0.0
		if not inside:
			for surface in get_tree().get_nodes_in_group("water_sound_zone"):
				if not surface is Node2D or not surface.is_visible_in_tree() or not surface.can_process(): continue
				var kind: String = surface.get_meta("water_sound_kind", "lake")
				var distance := INF
				if surface is Polygon2D:
					distance = path_distance(surface.to_local(point), surface.polygon, true)
				elif surface is Line2D:
					distance = maxf(0.0, path_distance(surface.to_local(point), surface.points) - surface.width * 0.5)
				var reach := 220.0 if kind == "fountain" else 420.0
				targets[kind] = maxf(targets[kind], 1.0 - smoothstep(25, reach, distance))
	for kind in gains:
		gains[kind] = move_toward(gains[kind], targets[kind], delta * 0.8)
		var gain: float = gains[kind] * focus
		var audio: AudioStreamPlayer = beds[kind]
		audio.volume_db = (-14.0 if kind == "lake" else -12.0) + linear_to_db(maxf(gain, 0.0001))
		if gain > 0.001 and not audio.playing: audio.play()
		elif gain <= 0.001 and audio.playing: audio.stop()
