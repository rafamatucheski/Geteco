extends Node2D
## Três operadores no convés, caixas e gaivotas com orçamento fixo.
const WORKER := preload("res://world/harbor/HarborDockWorker.gd")
const AUDIO := preload("res://audio/living_city/LivingCityAudio.gd")
var ROUTES := [
	# Circuitos separados na área de triagem, entre contêineres e alojamento.
	# Os corredores laterais e a passarela permanecem livres para o jogador.
	PackedVector2Array([Vector2(3442,1702),Vector2(3498,1702),Vector2(3498,1768),Vector2(3442,1768)]),
	PackedVector2Array([Vector2(3552,1702),Vector2(3608,1702),Vector2(3608,1768),Vector2(3552,1768)]),
	PackedVector2Array([Vector2(3662,1702),Vector2(3718,1702),Vector2(3718,1768),Vector2(3662,1768)]),
]
var workers: Array[Node2D] = []
var gull: AudioStreamPlayer2D
var handling: AudioStreamPlayer2D
var active := false
var _gull_clock := 1.2
var _gull_variant := 0
var _budget_clock := 0.0
var _draw_clock := 0.0
var _rng := RandomNumberGenerator.new()
var _focus := 1.0
var _dark := false

func _ready() -> void:
	_rng.randomize()
	for i in ROUTES.size():
		var worker := WORKER.new()
		worker.name = "DockOperator%d" % (i+1)
		worker.worker_index = i
		for point in ROUTES[i]: worker.work_route.append(to_global(point))
		worker.work_points = PackedVector2Array([worker.work_route[0], worker.work_route[2]])
		worker.station_points = PackedVector2Array([worker.work_points[0]+Vector2(0,-12), worker.work_points[1]+Vector2(0,12)])
		add_child(worker)
		worker.crate_handled.connect(_on_crate_handled)
		workers.append(worker)
		worker.set_physics_process(false)
	gull = AudioStreamPlayer2D.new()
	gull.name = "ShipGulls"
	gull.bus = &"Ambient"
	gull.max_distance = 1050
	gull.volume_db = -5
	add_child(gull)
	handling = AudioStreamPlayer2D.new()
	handling.name = "CrateHandling"
	handling.bus = &"SFX"
	handling.stream = load("res://audio/combat/wood_0.wav")
	handling.pitch_scale = .72
	handling.volume_db = -21
	handling.max_distance = 430
	add_child(handling)

func _process(delta: float) -> void:
	_budget_clock -= delta
	if _budget_clock <= 0:
		_budget_clock = .25
		_update_presence()
	if not active: return
	_draw_clock += delta
	if _draw_clock >= .1:
		_draw_clock = 0
		queue_redraw()
	_gull_clock -= delta
	if _gull_clock <= 0 and not gull.playing and _focus > .8:
		gull.position = Vector2(3570 + _rng.randf_range(-90,190), _rng.randf_range(1510,1820))
		gull.stream = AUDIO.detail("gull", _gull_variant)
		_gull_variant = (_gull_variant+1)%3
		gull.volume_db = (-11.0 if _dark else -5.0)
		gull.play()
		_gull_clock = _rng.randf_range(24,38) if _dark else _rng.randf_range(8,15)
	# Desenho e mixagem seguem a pausa da árvore e a distância, sem novos players.
	gull.volume_db = (-11.0 if _dark else -5.0) + linear_to_db(_focus)
	handling.volume_db = -21 + linear_to_db(_focus)

func _update_presence() -> void:
	var world := get_parent().get_parent()
	var actor := world.get_node_or_null("Player") as Node2D
	if actor == null: return
	var focus_point := actor.global_position
	if not actor.visible:
		for car in get_tree().get_nodes_in_group("vehicle"):
			if car.get("is_driven_by_player") == true:
				focus_point = car.global_position
				break
	var was_active := active
	active = focus_point.distance_to(to_global(Vector2(3570,1620))) < 1150
	_focus = .25 if actor.get("is_in_dialogue") == true else 1.0
	var weather = world.get("weather")
	_dark = weather != null and bool(weather.is_dark)
	if active and not was_active: _gull_clock = 1.2
	if not active:
		gull.stop()
		handling.stop()
	for worker in workers:
		if not worker.has_meta("medical_witness") and not (worker.has_meta("medical_pending") and not worker.visible):
			worker.set_physics_process(active or worker.is_scared or worker.is_flying)

func _on_crate_handled(point: Vector2) -> void:
	queue_redraw()
	if active and not handling.playing:
		handling.global_position = point
		handling.play()

func _draw() -> void:
	for worker in workers:
		for i in 2:
			var point := to_local(worker.station_points[i])
			draw_rect(Rect2(point-Vector2(13,9),Vector2(26,18)),Color("615140"))
			for count in worker.crate_stock[i]:
				_draw_crate(point+Vector2(0,-count*5))
		for point in worker.dropped_crates: _draw_crate(to_local(point))

func _draw_crate(point: Vector2) -> void:
	preload("res://world/harbor/DockCrateDrawing.gd").draw_crate(self,point)
