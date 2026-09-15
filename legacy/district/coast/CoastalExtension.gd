class_name CoastalExtension
extends Node2D

## Fixed east-coast extension for the authored central district.
## Suggested placement: Vector2(1800, 0), immediately after the current map.

const EXTENT := Vector2(640.0, 1280.0)
const SEA_START_X := 310.0
const PROMENADE_RECT := Rect2(202.0, 0.0, 92.0, 1280.0)
const ROAD_RECT := Rect2(0.0, 510.0, 202.0, 180.0)
const PIGEON_SCRIPT := preload("res://legacy/district/coast/CoastalPigeon.gd")
const WAVE_AUDIO_SCRIPT := preload("res://legacy/district/coast/CoastalWaveAudio.gd")
const PROCEDURAL_TREE := preload("res://geodata/nature/ProceduralStreetTree.gd")
const PROCEDURAL_ROCK := preload("res://geodata/nature/ProceduralUrbanRock.gd")

const ROCKS := [
	{"at": Vector2(302, 76), "size": Vector2(20, 15), "tone": Color("#4d5558")},
	{"at": Vector2(298, 182), "size": Vector2(15, 22), "tone": Color("#596164")},
	{"at": Vector2(304, 314), "size": Vector2(24, 18), "tone": Color("#41494d")},
	{"at": Vector2(299, 444), "size": Vector2(16, 21), "tone": Color("#646a68")},
	{"at": Vector2(302, 725), "size": Vector2(24, 17), "tone": Color("#4d5558")},
	{"at": Vector2(297, 842), "size": Vector2(17, 23), "tone": Color("#606665")},
	{"at": Vector2(303, 1018), "size": Vector2(25, 19), "tone": Color("#444c50")},
	{"at": Vector2(298, 1172), "size": Vector2(18, 22), "tone": Color("#5b6262")}
]

var _wave_phase := 0.0


func _ready() -> void:
	z_index = 0
	_create_sea_barrier()
	_create_coastal_nature()
	_create_pigeons()
	_create_wave_audio()
	queue_redraw()


func _process(delta: float) -> void:
	_wave_phase = fmod(_wave_phase + delta * 18.0, 32.0)
	queue_redraw()


func _create_sea_barrier() -> void:
	# A continuous blocker is safer than relying on individual rock colliders.
	# Layer 1 matches the district buildings and blocks both on-foot and cars.
	var body := StaticBody2D.new()
	body.name = "InaccessibleSeaBarrier"
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector2(SEA_START_X - 5.0, EXTENT.y * 0.5)
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(28.0, EXTENT.y)
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)


func _create_pigeons() -> void:
	var flock := Node2D.new()
	flock.name = "AmbientPigeons"
	flock.z_index = 8
	add_child(flock)
	var positions := [Vector2(242, 210), Vector2(264, 248), Vector2(226, 776), Vector2(268, 824), Vector2(236, 1092)]
	for index in positions.size():
		var pigeon: Node2D = PIGEON_SCRIPT.new()
		pigeon.name = "Pigeon_%02d" % (index + 1)
		pigeon.position = positions[index]
		pigeon.variant_seed = index + 3
		flock.add_child(pigeon)


func _create_wave_audio() -> void:
	var ambience: AudioStreamPlayer2D = WAVE_AUDIO_SCRIPT.new()
	ambience.name = "ProceduralSeaAmbience"
	ambience.position = Vector2(SEA_START_X + 30.0, EXTENT.y * 0.5)
	ambience.volume_db = -16.0
	ambience.max_distance = 760.0
	ambience.attenuation = 1.35
	add_child(ambience)


func _create_coastal_nature() -> void:
	var nature := Node2D.new()
	nature.name = "ProceduralCoastalNature"
	nature.z_index = 5
	add_child(nature)
	for index in ROCKS.size():
		var rock_data: Dictionary = ROCKS[index]
		var rock := PROCEDURAL_ROCK.new() as ProceduralUrbanRock
		rock.name = "BreakwaterRock_%02d" % (index + 1)
		rock.position = rock_data.at
		var coastal_rock_size: Vector2 = rock_data.size
		rock.rock_size = coastal_rock_size * 2.0
		var coastal_rock_tone: Color = rock_data.tone
		rock.base_color = coastal_rock_tone
		rock.variant_seed = 500 + index
		nature.add_child(rock)
	var tree_positions := [Vector2(152, 118), Vector2(148, 336), Vector2(154, 872), Vector2(146, 1115)]
	for index in tree_positions.size():
		var tree := PROCEDURAL_TREE.new() as ProceduralStreetTree
		tree.name = "CoastalTree_%02d" % (index + 1)
		tree.position = tree_positions[index]
		tree.tree_style = ProceduralStreetTree.TreeStyle.COASTAL
		tree.crown_scale = 0.92 + float(index % 3) * 0.07
		tree.variant_seed = 600 + index
		tree.leaf_color = Color("#3f704c")
		nature.add_child(tree)


func _draw() -> void:
	# Urban verge, pale promenade and a narrow natural stone edge.
	draw_rect(Rect2(0, 0, SEA_START_X, EXTENT.y), Color("#4b5351"))
	draw_rect(PROMENADE_RECT, Color("#aaa99f"))
	draw_rect(PROMENADE_RECT, Color("#70777a"), false, 3.0)
	_draw_prominent_paving()

	# The east-west avenue ends at a broad overlook instead of falling into sea.
	draw_rect(ROAD_RECT, Color("#222b35"))
	draw_circle(Vector2(196, 600), 79.0, Color("#222b35"))
	for x in range(6, 160, 54):
		draw_line(Vector2(x, 550), Vector2(x + 28, 550), Color("#e8cd4d"), 4.0)
		draw_line(Vector2(x, 650), Vector2(x + 28, 650), Color("#e8cd4d"), 4.0)
	draw_arc(Vector2(196, 600), 51.0, -1.28, 1.28, 18, Color("#e8cd4d"), 3.0)

	# Stylised animated water, entirely drawn by the engine.
	draw_rect(Rect2(SEA_START_X, 0, EXTENT.x - SEA_START_X, EXTENT.y), Color("#236879"))
	for band in range(-1, 42):
		var y := float(band * 32) + _wave_phase
		var points := PackedVector2Array()
		for x in range(int(SEA_START_X + 8), int(EXTENT.x), 18):
			points.append(Vector2(x, y + sin(float(x) * 0.045 + band) * 3.0))
		if points.size() > 1:
			draw_polyline(points, Color(0.42, 0.78, 0.82, 0.28), 2.0)

	_draw_guardrail()
	_draw_inaccessible_pier()


func _draw_prominent_paving() -> void:
	for y in range(12, int(EXTENT.y), 26):
		draw_line(Vector2(PROMENADE_RECT.position.x + 6, y), Vector2(PROMENADE_RECT.end.x - 6, y), Color("#92958f"), 1.0)
	for y in range(0, int(EXTENT.y), 52):
		draw_line(Vector2(248, y), Vector2(248, y + 26), Color("#c4c1b5"), 1.0)


func _draw_rock_breakwater() -> void:
	for rock_data in ROCKS:
		var at: Vector2 = rock_data.at
		var size: Vector2 = rock_data.size
		var points := PackedVector2Array([
			at + Vector2(-size.x, size.y * 0.35),
			at + Vector2(-size.x * 0.55, -size.y * 0.8),
			at + Vector2(size.x * 0.22, -size.y),
			at + Vector2(size.x, -size.y * 0.18),
			at + Vector2(size.x * 0.62, size.y * 0.72),
			at + Vector2(-size.x * 0.18, size.y)
		])
		draw_colored_polygon(points, rock_data.tone)
		draw_polyline(points, Color("#292f32"), 2.0)
		draw_line(at - size * 0.36, at + size * 0.16, Color(0.78, 0.81, 0.78, 0.36), 2.0)


func _draw_guardrail() -> void:
	for y in range(18, int(EXTENT.y), 52):
		draw_line(Vector2(289, y), Vector2(289, y + 36), Color("#30383c"), 4.0)
		draw_circle(Vector2(289, y), 4.2, Color("#768084"))
		draw_line(Vector2(286, y), Vector2(292, y), Color("#b2b9b7"), 2.0)


func _draw_inaccessible_pier() -> void:
	# Decorative old pier sits behind the barrier, adding a coastal landmark
	# without becoming a walkable/nav area in this phase.
	var pier := Rect2(294, 918, 196, 54)
	draw_rect(pier, Color("#624a35"))
	for x in range(int(pier.position.x + 8), int(pier.end.x), 18):
		draw_line(Vector2(x, pier.position.y + 3), Vector2(x, pier.end.y - 3), Color("#8a6846"), 3.0)
	for x in [312.0, 468.0]:
		draw_circle(Vector2(x, pier.end.y + 7), 6.0, Color("#302b27"))
