extends RefCounted
## Authored activity zones with shared static batches, human-scale furniture and
## exact envelopes for the native collision adapter. No per-frame decoration loop.
const CONTENT := preload("res://world/places/harbor_buildings/HarborBuildingContent.gd")
const MATERIALS := preload("res://world/places/harbor_buildings/HarborBuildingMaterials.gd")
var _model: Node3D
var _spec: Dictionary
var _batches: Dictionary = {}
var _solids: Dictionary = {}
var _palette: Dictionary
var _frame := Transform3D.IDENTITY
var _extra_stations := 0
## Sorteio estável da decoração deste andar (semente do prédio/andar).
var _rng := RandomNumberGenerator.new()
var _layout := 0
var _decor: Array[String] = []
var _beds: Array[Transform3D] = []
var _decor_count := 0

static func populate(model: Node3D, definition: Dictionary, floor_index: int) -> Dictionary:
	var builder := new()
	builder._model = model
	builder._spec = CONTENT.floor_spec(definition, floor_index)
	builder._palette = builder._spec.palette
	builder._build()
	builder._flush()
	return builder._spec

func _build() -> void:
	var x: float = _spec.x
	var back: float = _spec.back
	var front: float = _spec.front
	var program: String = _spec.program
	_layout = int(_spec.get("layout", 0))
	_rng.seed = int(_spec.get("decor_seed", _spec.seed))
	var right := Vector3(x + float(_spec.get("work_dx", 0.0)), 0, back)
	var arrangement: int = _layout % 4
	var left := Vector3(-x, 0, back + [0.0, -.15, .20, -.05][arrangement])
	var near := Vector3(x * _spec.front_side + [.0, .12, -.10, .08][arrangement], 0, front + [.0, -.10, .12, -.16][arrangement])
	var compact: bool = _spec.compact
	# The principal work station always matches the resident's actual hand task.
	match program:
		"workshop", "toolroom": _workbench(right, "Workbench", compact)
		"kitchen", "shared_kitchen", "cafe", "staff": _kitchen(right, "Kitchen", compact)
		"packing", "stockroom", "dispatch": _packing(right, "Dispatch", compact)
		"tailor", "studio", "artist": _studio(right, "Studio", compact)
		"laundry": _laundry(right, "Laundry", compact)
		"aquarium": _aquarium(right, "CareTank", compact)
		"shop": _shop_counter(right, "Counter", compact)
		_: _desk(right, "WorkDesk", program, compact)
	if compact:
		if _spec.size.x * _spec.size.y >= 80.0:
			_populate_compact_activity_zones(arrangement)
		else:
			_small_wall_detail()
	else:
		_program_zones(program, left, near)
		_room_identity()
		_secret_recess()
		_partitioned_rooms(arrangement)
	if _spec.abandoned: _neglected_details()
	if _spec.illicit: _illicit_details(right)
	_populate_large_volume()
	_life_objects()
	_wall_finish()
	_lighting()
	_rugs()

## Os três núcleos fixos (estação, fundo esquerdo, frente) recebem móveis
## alternativos por planta. As alternativas respeitam a pegada do móvel
## original de cada zona, para preservar corredores e aproximações.
func _program_zones(program: String, left: Vector3, near: Vector3) -> void:
	var variant := _layout % 3
	var lounge: Array[String] = ["sofa", "tv", "armchairs", "dining"]
	match program:
		"aquarium":
			_aquarium(left, "ReefTank", false)
			_sofa(near, "AquariumBench")
		"gallery":
			_ship_exhibit(left, "ShipModel")
			_ship_exhibit(near, "HarborArchive")
		"family", "bedroom", "guest", "kids":
			var bed_at := left + Vector3(0, 0, .38 if _spec.size.y >= 9.5 else 0.0)
			if _spec.size.y < 9.5:
				_frame = Transform3D(Basis(Vector3.UP, PI * .5), bed_at) * Transform3D(Basis.IDENTITY, -bed_at)
			if program == "kids": _bunk_bed(bed_at, "Bed")
			else: _bed(bed_at, "Bed", program == "guest" or variant == 2)
			_frame = Transform3D.IDENTITY
			_lounge(lounge[_layout % lounge.size()], near, "LivingSofa")
		"living":
			_tv_wall(left + Vector3(0, 0, -.30), "MediaWall")
			_lounge(["sofa", "armchairs", "dining", "sofa"][_layout % 4], near, "LivingSofa")
		"artist", "studio", "music":
			if program == "music" and variant != 1: _piano(left + Vector3(0, 0, -.20), "Piano")
			elif variant == 2: _canvas_stack(left + Vector3(0, 0, -.25), "Canvases")
			else: _easel(left, "Easel")
			_lounge(["sofa", "armchairs", "sofa"][variant], near, "StudioSofa")
		"library", "records", "press":
			if variant == 1: _filing(left + Vector3(0, 0, -.25), "Archive")
			else: _bookcase(left + Vector3(0, 0, -.25), "Archive", program != "library")
			if variant == 2: _armchairs(near, "ReadingTable")
			else: _table(near, "ReadingTable", true)
		"workshop", "toolroom", "packing", "stockroom", "dispatch":
			match variant:
				0: _rack(left + Vector3(0, 0, -.28), "PartsRack")
				1: _tool_cabinet(left + Vector3(0, 0, -.28), "PartsRack")
				_: _barrels(left + Vector3(0, 0, -.28), "PartsRack")
			match (_layout + int(_spec.floor)) % 3:
				0: _pallet(near, "Shipment")
				1: _crate_stack(near, "Shipment")
				_: _engine_stand(near, "Shipment")
		"shop", "tailor":
			if program == "tailor" or variant == 1: _clothes_rack(left + Vector3(0, 0, -.30), "StockShelf")
			else: _bookcase(left + Vector3(0, 0, -.30), "StockShelf", true)
			_display(near, "Display")
		"laundry":
			_laundry(left + Vector3(0, 0, -.20), "Dryers", false)
			if variant == 1: _laundry_carts(near, "FoldingTable")
			else: _table(near, "FoldingTable", false)
		"meeting", "drafting":
			if variant == 1: _whiteboard_table(left, "MeetingTable")
			else: _table(left, "MeetingTable", true)
			if variant == 2: _armchairs(near, "Drawings")
			else: _bookcase(near, "Drawings", false)
		_:
			match variant:
				0: _bookcase(left + Vector3(0, 0, -.3), "Library", false)
				1: _filing(left + Vector3(0, 0, -.3), "Library")
				_: _coat_corner(left + Vector3(0, 0, -.3), "Library")
			_lounge(["sofa", "dining", "armchairs", "sofa", "tv"][_layout % 5], near, "WaitingSofa")

func _lounge(kind: String, at: Vector3, id: String) -> void:
	match kind:
		"tv": _tv_lounge(at, id)
		"armchairs": _armchairs(at, id)
		"dining": _dining(at, id)
		_: _sofa(at, id)

func _box(at: Vector3, size: Vector3, color: String, solid := "", kind := "wood") -> void:
	_record("box", Transform3D(Basis.from_scale(size), at), color, kind)
	if not solid.is_empty(): _reserve(solid, AABB(at - size * .5, size))

func _cylinder(at: Vector3, radius: float, height: float, color: String, solid := "", kind := "metal") -> void:
	_record("cylinder", Transform3D(Basis.from_scale(Vector3(radius * 2, height, radius * 2)), at), color, kind)
	if not solid.is_empty(): _reserve(solid, AABB(at - Vector3(radius, height * .5, radius), Vector3(radius * 2, height, radius * 2)))

func _record(shape: String, transform: Transform3D, color: String, kind: String) -> void:
	var key := shape + ":" + kind + ":" + color
	if not _batches.has(key): _batches[key] = {"shape":shape, "kind":kind, "color":color, "transforms":[]}
	_batches[key].transforms.append(_frame * transform)

func _reserve(id: String, bounds: AABB) -> void:
	bounds = _frame * bounds
	_solids[id] = _solids[id].merge(bounds) if _solids.has(id) else bounds

func _flush() -> void:
	var detail_count := 0
	for entry in _batches.values():
		var primitive: PrimitiveMesh
		if entry.shape == "cylinder":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .5
			cylinder.bottom_radius = .5
			cylinder.height = 1.0
			cylinder.radial_segments = 12
			primitive = cylinder
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			primitive = box
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = primitive
		instances.instance_count = entry.transforms.size()
		for index in entry.transforms.size(): instances.set_instance_transform(index, entry.transforms[index])
		var visual := MultiMeshInstance3D.new()
		visual.name = "Dressing_" + str(entry.kind) + "_" + str(entry.color)
		visual.multimesh = instances
		visual.material_override = MATERIALS.material(entry.kind, Color(entry.color))
		_model.add_child(visual)
		detail_count += instances.instance_count
	for id in _solids:
		var bounds: AABB = _solids[id]
		var envelope := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = bounds.size
		envelope.mesh = mesh
		envelope.position = bounds.get_center()
		envelope.visible = false
		envelope.name = "Envelope_" + str(id)
		envelope.set_meta("interior_solid_id", "Dressing_" + str(id))
		envelope.set_meta("dressing_envelope", true)
		_model.add_child(envelope)
	_model.set_meta("dressing_program", _spec.program)
	_model.set_meta("dressing_detail_count", detail_count)
	_model.set_meta("dressing_solid_count", _solids.size())
	_model.set_meta("dressing_batch_count", _batches.size())
	_model.set_meta("dressing_extra_stations", _extra_stations)
	_model.set_meta("dressing_layout", _layout)
	_model.set_meta("dressing_decor", _decor)
	# Camas reais do andar (frame local da sala): o morador que dorme deita
	# sobre o colchão a partir de um ponto livre ao lado, nunca atravessando-a.
	_model.set_meta("dressing_beds", _beds)

func _desk(at: Vector3, id: String, program: String, compact: bool) -> void:
	var width := 1.55 if compact else 2.0
	_table_base(at, id, Vector2(width, .82), .90 if compact else .82)
	var y := .96 if compact else .88
	var screen := program in ["reception", "press", "drafting", "meeting"] or _rng.randf() < .3
	if screen and _rng.randf() < .35:
		# Notebook aberto em vez do monitor de mesa.
		_box(at + Vector3(.3, y + .02, .08), Vector3(.40, .025, .28), "3a3f42", id, "metal")
		_box(at + Vector3(.3, y + .15, -.06), Vector3(.40, .26, .02), "2c3134", id, "metal")
		_box(at + Vector3(.3, y + .15, -.048), Vector3(.35, .21, .006), "5d7f8a", id, "glass")
	elif screen:
		_box(at + Vector3(.3, y + .31, -.1), Vector3(.58, .40, .06), "28383c", id, "metal")
		_box(at + Vector3(.3, y + .1, -.1), Vector3(.055, .25, .10), "737b79", id, "metal")
		_box(at + Vector3(.3, y + .015, .22), Vector3(.53, .025, .17), "3d4949", id, "metal")
		_box(at + Vector3(.3, y + .31, -.063), Vector3(.50, .32, .01), "618386", id, "glass")
	else:
		_surface_items(at + Vector3(.32, y + .05, -.05), id, 1)
	_papers(at + Vector3(-.33, y + .025, .18), id)
	_mug(at + Vector3(.62, y + .09, .14), id)
	if _rng.randf() < .5: _desk_lamp(at + Vector3(-.58 if compact else -.74, y + .05, -.18), id)
	else: _box(at + Vector3(-.49, y + .05, -.18), Vector3(.26, .1, .22), _palette.accent, id)

func _table_base(at: Vector3, id: String, size: Vector2, height := .78) -> void:
	_box(at + Vector3(0, height, 0), Vector3(size.x, .10, size.y), _palette.wood, id)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]: _box(at + Vector3(side * (size.x * .5 - .11), height * .5, end * (size.y * .5 - .10)), Vector3(.085, height, .085), _palette.metal, id, "metal")
	_box(at + Vector3(0, height - .20, 0), Vector3(size.x - .16, .12, .065), "6d5945", id)

func _table(at: Vector3, id: String, papers: bool) -> void:
	_table_base(at, id, Vector2(1.85, .90))
	if papers: _papers(at + Vector3(-.30, .85, .1), id)
	else:
		for level in 3: _box(at + Vector3(.24, .87 + level * .055, 0), Vector3(.60, .05, .43), _palette.cloth, id, "cloth")
	_mug(at + Vector3(.54, .91, -.20), id)
	_surface_items(at + Vector3(-.66 if papers else -.42, .88, -.20), id, 1)
	# A cadeira muda de lado e de ângulo, sempre dentro da pegada original.
	var chair_x: float = [-.53, .48, -.30][_layout % 3]
	_chair_turned(at + Vector3(chair_x, 0, .76), id + "Chair", [0.0, .12, -.10][(_layout + int(_spec.floor)) % 3])

func _chair(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, .47, 0), Vector3(.49, .11, .50), _palette.cloth, id, "cloth")
	_box(at + Vector3(0, .79, -.2), Vector3(.50, .56, .10), _palette.cloth, id, "cloth")
	for x in [-.18, .18]:
		for z in [-.18, .18]: _box(at + Vector3(x, .23, z), Vector3(.05, .46, .05), _palette.metal, id, "metal")

## Cadeira girada em torno do próprio centro (compõe com o frame atual).
func _chair_turned(at: Vector3, id: String, yaw: float) -> void:
	var saved := _frame
	_frame = saved * Transform3D(Basis(Vector3.UP, yaw), at) * Transform3D(Basis.IDENTITY, -at)
	_chair(at, id)
	_frame = saved

func _bookcase(at: Vector3, id: String, folders: bool) -> void:
	_box(at + Vector3(0, 1.04, -.24), Vector3(1.80, 2.08, .06), _palette.wood, id)
	for side in [-1.0, 1.0]: _box(at + Vector3(side * .88, 1.04, 0), Vector3(.08, 2.08, .55), _palette.wood, id)
	for level in 4:
		var y := .13 + level * .50
		_box(at + Vector3(0, y, 0), Vector3(1.80, .065, .55), _palette.wood, id)
		for column in 6:
			var col: String = ["6b7769", "8e6c52", "465e6b", "b5a37c", "76686a", "a28b6c"][(column + level + _spec.floor) % 6]
			var bx := -.72 + column * .28
			_box(at + Vector3(bx, y + .21, 0), Vector3(.20 if folders else .15, .34 + (column % 2) * .04, .34), col, id, "paper")
			_box(at + Vector3(bx, y + .25, .176), Vector3(.10, .06, .01), "d4c9ac", id, "paper")

func _sofa(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, .25, 0), Vector3(2.1, .38, .88), _palette.wood, id)
	_box(at + Vector3(0, .80, .35), Vector3(2.05, .75, .18), _palette.cloth, id, "cloth")
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * .51, .50, 0), Vector3(.93, .23, .70), _palette.cloth, id, "cloth")
		_box(at + Vector3(side * 1.02, .59, 0), Vector3(.20, .52, .94), _palette.cloth, id, "cloth")
	_box(at + Vector3(.70, .72, .18), Vector3(.34, .36, .18), _palette.accent, id, "cloth")
	_box(at + Vector3(-.70, .64, 0), Vector3(.32, .06, .50), "c1b39a", id, "cloth")
	# A folded blanket has a hem and two short hanging folds, within the sofa.
	for z in [-.16, .04, .23]: _box(at + Vector3(-.7, .681, z), Vector3(.33, .015, .025), "84775e", id, "cloth")

func _bed(at: Vector3, id: String, single := false) -> void:
	# Âncora da cama (centro, cabeceira em -Z) para quem dorme nela.
	# A origem fica na altura do lençol (0,62 m).
	_beds.append(_frame * Transform3D(Basis.IDENTITY, at + Vector3(-.26 if single else 0.0, .62, 0)))
	if single:
		# Cama de solteiro com criado-mudo, dentro da pegada da cama de casal.
		var bed := at + Vector3(-.26, 0, 0)
		_box(bed + Vector3(0, .24, 0), Vector3(1.02, .40, 2.10), _palette.wood, id)
		_box(bed + Vector3(0, .51, 0), Vector3(.97, .19, 2.03), _palette.linen, id, "cloth")
		_box(bed + Vector3(0, .64, .30), Vector3(.98, .08, 1.38), _palette.cloth, id, "cloth")
		_box(bed + Vector3(0, .56, -1.02), Vector3(1.06, 1.0, .10), _palette.wood, id)
		_box(bed + Vector3(0, .68, -.70), Vector3(.62, .14, .36), "e0d6bf", id, "cloth")
		var stand := at + Vector3(.56, 0, -.78)
		_box(stand + Vector3(0, .29, 0), Vector3(.42, .58, .40), _palette.wood, id)
		_box(stand + Vector3(0, .36, .205), Vector3(.30, .12, .012), _palette.metal, id, "metal")
		_desk_lamp(stand + Vector3(-.05, .58, -.05), id)
		return
	_box(at + Vector3(0, .24, 0), Vector3(1.55, .40, 2.13), _palette.wood, id)
	_box(at + Vector3(0, .51, 0), Vector3(1.50, .19, 2.06), _palette.linen, id, "cloth")
	_box(at + Vector3(0, .64, .28), Vector3(1.51, .08, 1.44), _palette.cloth, id, "cloth")
	_box(at + Vector3(0, .56, -1.03), Vector3(1.61, 1.05, .12), _palette.wood, id)
	for side in [-1.0, 1.0]: _box(at + Vector3(side * .35, .68, -.70), Vector3(.59, .14, .39), "e0d6bf", id, "cloth")
	for z in [.12, .23]: _box(at + Vector3(0, .687, z), Vector3(1.52, .014, .045), "b9aa8d", id, "cloth")

func _kitchen(at: Vector3, id: String, compact: bool) -> void:
	var width := 1.65 if compact else 2.45
	_box(at + Vector3(0, .45, 0), Vector3(width, .90, .70), _palette.cabinet, id)
	_box(at + Vector3(0, .945, 0), Vector3(width + .06, .09, .76), "c8c0ab", id, "stone")
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * width * .25, .50, .362), Vector3(width * .44, .65, .035), _palette.cabinet if side < 0 else _palette.wood, id)
		_box(at + Vector3(side * width * .25, .72, .394), Vector3(.18, .025, .045), "a9aca0", id, "metal")
	_box(at + Vector3(-width * .22, 1.0, -.03), Vector3(.53, .035, .45), "516b6d", id, "metal")
	_box(at + Vector3(-width * .22, 1.16, -.26), Vector3(.035, .34, .035), "b3b8b1", id, "metal")
	_box(at + Vector3(-width * .22, 1.32, -.19), Vector3(.035, .035, .19), "b3b8b1", id, "metal")
	_box(at + Vector3(width * .23, 1.0, .02), Vector3(.57, .03, .51), "303c3a", id, "metal")
	_cylinder(at + Vector3(.16, 1.115, .27), .16, .22, "6a7068", id)
	_cylinder(at + Vector3(.16, 1.233, .27), .135, .015, "9d8654", id, "ceramic")
	_mug(at + Vector3(-width * .42, 1.08, .15), id)
	if not compact: _surface_items(at + Vector3(width * .40, 1.0, -.18), id, 1)
	_box(at + Vector3(0, 1.36, -.36), Vector3(width, .64, .03), "c2c1aa" if _layout % 2 == 0 else _palette.linen, id, "ceramic")
	for row in 2:
		for column in 6: _box(at + Vector3(-width * .42 + column * width * .168, 1.2 + row * .24, -.335), Vector3(.006, .23, .006), "999d8d", id, "ceramic")

func _workbench(at: Vector3, id: String, compact: bool) -> void:
	_table_base(at, id, Vector2(1.65 if compact else 2.30, .82), .94)
	_box(at + Vector3(-.45, 1.10, .18), Vector3(.30, .24, .28), "526764", id, "metal")
	_box(at + Vector3(-.45, 1.245, .18), Vector3(.43, .06, .14), "8e9690", id, "metal")
	_box(at + Vector3(.29, 1.027, .15), Vector3(.64, .035, .43), "5b665b", id, "cloth")
	for part in 4: _cylinder(at + Vector3(.05 + part * .15, 1.07, .14), .035, .07, "a6a392", id)
	_box(at + Vector3(0, 1.60, -.36), Vector3(1.48, .88, .075), "867255", id)
	for tool in 5:
		var x := -.55 + tool * .27
		_box(at + Vector3(x, 1.57, -.305), Vector3(.055, .35, .045), "90978f", id, "metal")
		_box(at + Vector3(x, 1.39, -.29), Vector3(.075, .14, .07), "665345", id)

func _packing(at: Vector3, id: String, compact: bool) -> void:
	_table_base(at, id, Vector2(1.65 if compact else 2.3, .82), .93)
	for column in 3:
		_box(at + Vector3(-.48 + column * .46, 1.12, -.12), Vector3(.38, .28 + column * .06, .40), "a88c61", id, "paper")
		_box(at + Vector3(-.48 + column * .46, 1.27 + column * .03, -.12), Vector3(.10, .01, .42), "c5b283", id, "paper")
	_papers(at + Vector3(0, .999, .24), id)

func _studio(at: Vector3, id: String, compact: bool) -> void:
	_table_base(at, id, Vector2(1.65 if compact else 2.25, .85), .91)
	_box(at + Vector3(.18, .979, .04), Vector3(.90, .02, .54), "d9c8a5", id, "paper")
	for stroke in 4: _box(at + Vector3(-.14 + stroke * .14, .992, .05), Vector3(.045, .008, .32 - stroke * .035), ["798372", "9e7352", "576f79", "ac9c78"][stroke], id, "paper")
	_cylinder(at + Vector3(-.54, 1.095, -.13), .085, .24, "938466", id, "ceramic")
	for brush in 4: _box(at + Vector3(-.59 + brush * .035, 1.26, -.13), Vector3(.017, .28, .017), "7d6441", id)
	_box(at + Vector3(.64, 1.02, -.2), Vector3(.20, .12, .22), _palette.cloth, id, "cloth")

func _shop_counter(at: Vector3, id: String, compact: bool) -> void:
	_box(at + Vector3(0, .50, 0), Vector3(1.65 if compact else 2.4, 1.0, .78), _palette.wood, id)
	_box(at + Vector3(0, 1.055, 0), Vector3(1.7 if compact else 2.46, .10, .84), "c0b8a4", id, "stone")
	_box(at + Vector3(.4, 1.24, -.15), Vector3(.45, .30, .31), "445654", id, "metal")
	_box(at + Vector3(.4, 1.26, .017), Vector3(.28, .17, .015), "688b85", id, "glass")
	_papers(at + Vector3(-.35, 1.12, .20), id)

func _laundry(at: Vector3, id: String, compact: bool) -> void:
	for column in (1 if compact else 2):
		var point := at + Vector3(column * .9 - (0.0 if compact else .45), 0, 0)
		var machine_id := id + str(column)
		_box(point + Vector3(0, .48, 0), Vector3(.80, .96, .72), "b5beb3", machine_id, "metal")
		_box(point + Vector3(0, .49, .368), Vector3(.56, .57, .04), "657e7c", machine_id, "metal")
		_box(point + Vector3(0, .49, .396), Vector3(.40, .40, .025), "364f54", machine_id, "glass")
		for knob in [-.2, .2]: _box(point + Vector3(knob, .84, .388), Vector3(.08, .08, .04), "566664", machine_id, "metal")
		for fold in 3: _box(point + Vector3(0, 1.015 + fold * .055, 0), Vector3(.52, .05, .36), _palette.cloth, machine_id, "cloth")

func _rack(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]: _box(at + Vector3(side * .84, 1.12, 0), Vector3(.06, 2.24, .60), "59695f", id, "metal")
	for level in 3:
		var y := .18 + level * .66
		_box(at + Vector3(0, y, 0), Vector3(1.78, .06, .62), "778271", id, "metal")
		for side in [-1.0, 1.0]:
			_box(at + Vector3(side * .43, y + .24, 0), Vector3(.68, .39, .48), "9e8962", id, "paper")
			_box(at + Vector3(side * .43, y + .29, .247), Vector3(.24, .10, .012), "d0c6a5", id, "paper")

func _pallet(at: Vector3, id: String) -> void:
	for strip in 5: _box(at + Vector3(-.64 + strip * .32, .12, 0), Vector3(.26, .10, 1.00), "91774f", id)
	for side in [-1.0, 1.0]: _box(at + Vector3(0, .06, side * .36), Vector3(1.55, .10, .12), "6e5a41", id)
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * .36, .44, 0), Vector3(.64, .56, .82), "ac946c", id, "paper")
		_box(at + Vector3(side * .36, .731, 0), Vector3(.12, .014, .83), "c9b587", id, "paper")
	_box(at + Vector3(.2, .92, 0), Vector3(.57, .38, .58), "8c9c8e", id, "metal")

func _easel(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]: _box(at + Vector3(side * .40, .9, 0), Vector3(.065, 1.80, .065), "8d7049", id)
	_box(at + Vector3(0, .47, -.3), Vector3(.10, .94, .1), "80603e", id)
	_box(at + Vector3(0, .95, .10), Vector3(1.0, .055, .17), "927345", id)
	_box(at + Vector3(0, 1.44, .03), Vector3(.91, .93, .07), "c7bfa0", id, "paper")
	for stripe in 6: _box(at + Vector3(-.35 + stripe * .14, 1.42 + sin(stripe * 2.0) * .10, .074), Vector3(.12, .50 + stripe * .035, .012), ["526c76", "8a987f", "b6a47e"][stripe % 3], id, "paper")

func _display(at: Vector3, id: String) -> void:
	_table_base(at, id, Vector2(1.8, .74), .80)
	for column in 4:
		for level in 2: _box(at + Vector3(-.64 + column * .42, .92 + level * .13, 0), Vector3(.34, .12, .45), ["91775f", "687a70", "687c89", "a19378"][column], id, "cloth")

func _aquarium(at: Vector3, id: String, compact: bool) -> void:
	var width := 1.60 if compact else 2.16
	_box(at + Vector3(0, .41, 0), Vector3(width, .82, .68), "536a64", id, "wood")
	_box(at + Vector3(0, .86, 0), Vector3(width + .04, .08, .73), "394e4b", id, "metal")
	_box(at + Vector3(0, .94, 0), Vector3(width - .12, .12, .59), "b3ad85", id, "stone")
	_box(at + Vector3(0, 1.42, -.315), Vector3(width - .06, .95, .035), "557d87", id, "glass")
	_box(at + Vector3(0, 1.93, 0), Vector3(width + .03, .10, .73), "445c58", id, "metal")
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * (width * .5 - .03), 1.43, 0), Vector3(.065, 1.04, .70), "78999b", id, "tank_glass")
		_box(at + Vector3(side * (width * .5 - .04), 1.43, .33), Vector3(.05, 1.04, .04), "546d67", id, "metal")
	_box(at + Vector3(0, 1.43, .33), Vector3(width - .10, .96, .022), "82b1b0", id, "tank_glass")
	for plant in 6:
		var px := -width * .39 + plant * width * .15
		_box(at + Vector3(px, 1.12 + (plant % 3) * .05, -.11), Vector3(.085, .36 + (plant % 3) * .10, .12), ["5a816a", "728b66", "436d61"][plant % 3], id, "cloth")
	for fish in 6:
		var fx := -width * .34 + fish * width * .125
		var fy := 1.38 + sin(fish * 1.2) * .20
		var color: String = ["c1a16b", "8cb0ab", "b08c6a"][fish % 3]
		_box(at + Vector3(fx, fy, .13), Vector3(.15, .075, .06), color, id, "ceramic")
		_box(at + Vector3(fx - .09, fy, .13), Vector3(.04, .11, .035), color, id, "ceramic")

func _ship_exhibit(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, .40, 0), Vector3(1.80, .80, .77), "86755b", id, "wood")
	_box(at + Vector3(0, .85, 0), Vector3(1.84, .10, .82), "c0b69b", id, "stone")
	_box(at + Vector3(0, 1.01, 0), Vector3(1.38, .18, .37), "655b47", id, "wood")
	_box(at + Vector3(.68, 1.055, 0), Vector3(.20, .12, .24), "655b47", id, "wood")
	_box(at + Vector3(-.67, 1.10, 0), Vector3(.20, .18, .33), "816a4a", id, "wood")
	_box(at + Vector3(0, 1.12, 0), Vector3(1.36, .06, .36), "ac956a", id, "wood")
	for mast in [-.30, .30]:
		_box(at + Vector3(mast, 1.49, 0), Vector3(.028, .82, .028), "6d634c", id, "wood")
		_box(at + Vector3(mast + .12, 1.58, .028), Vector3(.28, .46, .018), "d0c6a6", id, "cloth")
		_box(at + Vector3(mast, 1.83, 0), Vector3(.42, .023, .025), "6d634c", id, "wood")
	for rail in [-.17, .17]: _box(at + Vector3(0, 1.22, rail), Vector3(1.3, .03, .024), "968563", id, "wood")

func _papers(at: Vector3, id: String) -> void:
	_box(at, Vector3(.36, .035, .28), "d9d1b8", id, "paper")
	for line in 4: _box(at + Vector3(0, .020, -.09 + line * .046), Vector3(.25, .003, .007), "858577", id, "paper")
	_box(at + Vector3(.21, .009, .06), Vector3(.016, .016, .23), "354f55", id, "metal")

func _mug(at: Vector3, id: String) -> void:
	_cylinder(at, .072, .15, "b8bca7", id, "ceramic")
	_cylinder(at + Vector3(0, .077, 0), .056, .007, "504939", id, "ceramic")
	_box(at + Vector3(.086, .015, 0), Vector3(.041, .067, .045), "b8bca7", id, "ceramic")

func _small_wall_detail() -> void:
	var size: Vector2 = _spec.size
	var x := -size.x * .5 + .78
	var z := -size.y * .5 + .35
	if _layout % 2 == 0:
		_box(Vector3(x, 1.27, z), Vector3(1.15, .72, .34), _palette.wood, "WallCabinet")
		_box(Vector3(x, 1.26, z + .18), Vector3(1.04, .61, .035), _palette.cloth, "WallCabinet")
		_box(Vector3(x, 1.14, z + .21), Vector3(.18, .03, .025), "999e91", "WallCabinet", "metal")
	else:
		# Prateleiras abertas com potes e uma caixa de ferramentas na mesma pegada.
		for level in 2: _box(Vector3(x, 1.05 + level * .42, z), Vector3(1.15, .04, .34), _palette.wood, "WallCabinet")
		_box(Vector3(x, 1.26, z - .10), Vector3(1.15, .66, .04), _palette.cabinet, "WallCabinet")
		for jar in 4: _cylinder(Vector3(x - .40 + jar * .26, 1.15 + (jar % 2) * .42, z), .06, .16, [_palette.accent, "b8bca7", "8a7655"][jar % 3], "WallCabinet", "ceramic")
	# A narrow wall recess with its cover set aside visually hints at the cache.
	var rx: float = _spec.x
	_box(Vector3(rx, .22, size.y * .5 - .20), Vector3(.62, .42, .04), "343f39", "", "metal")
	_box(Vector3(rx + .42, .18, size.y * .5 - .18), Vector3(.20, .32, .035), "897b5d", "", "metal")

func _secret_recess() -> void:
	var x: float = -_spec.x
	if _spec.front_side < 0 or (_spec.floor == 0 and absf(_spec.entrance.x - x) < 1.30): return
	var z: float = _spec.size.y * .5 - .42
	_box(Vector3(x, .49, z), Vector3(1.35, .98, .45), _palette.wood, "CacheCabinet")
	_box(Vector3(x, .51, z - .24), Vector3(1.14, .76, .025), "303b36", "CacheCabinet")
	for side in [-1.0, 1.0]: _box(Vector3(x + side * .56, .50, z - .28), Vector3(.09, .72, .07), _palette.wood, "CacheCabinet")
	_box(Vector3(x + .43, .20, z - .30), Vector3(.23, .34, .055), "a3916a", "CacheCabinet")
	for book in 3: _box(Vector3(x - .24 + book * .15, 1.015 + book * .03, z), Vector3(.29, .035, .24), "89927d", "CacheCabinet", "paper")

func _room_identity() -> void:
	var size: Vector2 = _spec.size
	var variant: int = _rng.randi() % 6
	var wall := size.x * .5
	# Distinct wall installations, not just a palette swap of the same furniture.
	# Todas cabem na pegada do radiador/floreira originais junto à parede leste.
	if _spec.program == "music":
		_box(Vector3(wall - .4, .68, .4), Vector3(.42, 1.36, .72), "303e3e", "Speaker", "cloth")
		for y in [.40, .94]: _box(Vector3(wall - .63, y, .4), Vector3(.035, .29, .30), "617573", "Speaker", "metal")
	elif variant == 0:
		_box(Vector3(wall - .25, .53, .8), Vector3(.24, 1.06, 1.22), "a3a595", "Radiator", "metal")
		for rib in 8: _box(Vector3(wall - .385, .54, .30 + rib * .14), Vector3(.035, .94, .045), "b6b6a4", "Radiator", "metal")
	elif variant == 1:
		_box(Vector3(wall - .37, .26, .8), Vector3(.55, .52, .55), "8a7655", "Planter", "ceramic")
		for leaf in 5: _box(Vector3(wall - .37 + sin(leaf * 2.0) * .13, .67 + leaf * .07, .80 + cos(leaf * 2.0) * .16), Vector3(.18, .28, .16), "5a7655", "Planter", "cloth")
	elif variant == 2:
		# Estante baixa com livros e um rádio.
		_box(Vector3(wall - .30, .45, .8), Vector3(.34, .90, 1.15), _palette.wood, "LowShelf")
		for level in 2:
			for book in 5:
				_box(Vector3(wall - .30, .17 + level * .40, .36 + book * .19), Vector3(.24, .26 + (book % 2) * .05, .12),
					[_palette.accent, _palette.cloth, "b5a37c", "6b7769"][(book + level) % 4], "LowShelf", "paper")
		_box(Vector3(wall - .30, .99, .62), Vector3(.22, .16, .34), "4c4a45", "LowShelf", "metal")
	elif variant == 3:
		# Aquecedor de água / boiler de parede, só volume técnico.
		_cylinder(Vector3(wall - .32, .75, .8), .25, 1.30, "c9c7bc", "Boiler", "metal")
		_box(Vector3(wall - .32, .07, .8), Vector3(.48, .14, .48), _palette.metal, "Boiler", "metal")
		_box(Vector3(wall - .14, 1.55, .8), Vector3(.05, .45, .05), "8e9181", "Boiler", "metal")
	elif variant == 4:
		_box(Vector3(wall - .27, .40, .8), Vector3(.30, .80, .90), _palette.cabinet, "Sideboard")
		_box(Vector3(wall - .27, .82, .8), Vector3(.34, .04, .96), _palette.wood, "Sideboard")
		_cylinder(Vector3(wall - .27, .95, .55), .07, .22, _palette.accent, "Sideboard", "ceramic")
		_box(Vector3(wall - .27, .92, 1.0), Vector3(.18, .16, .26), "d4c9ac", "Sideboard", "paper")

func _neglected_details() -> void:
	var size: Vector2 = _spec.size
	for board in 3:
		_box(Vector3(-_spec.x, 1.70 + board * .20, -size.y * .5 + .40), Vector3(1.0, .11, .065), "726a56", "", "wood")
	for paper in 7:
		_box(Vector3(.42 + sin(paper * 2.4) * .33, .027, -.50 + paper * .29), Vector3(.18, .012, .24), "a69d82", "", "paper")
	_box(Vector3(size.x * .5 - .15, 1.05, -size.y * .22), Vector3(.012, .70, 1.1), "788071", "", "stone")

func _partitioned_rooms(arrangement: int) -> void:
	var size: Vector2 = _spec.size
	var z := -.82 + arrangement * .11
	var start := 2.24
	var end := size.x * .5 - .25
	if end > start:
		var center := (start + end) * .5
		var id := "OfficeRoomDivider"
		var length := end - start
		# Divisórias diferentes com o mesmo volume físico (1,08 m de altura).
		match _rng.randi() % 4:
			0:
				_box(Vector3(center, .54, z), Vector3(length, 1.08, .14), _palette.wall, id, "stone")
				_box(Vector3(center, 1.115, z), Vector3(length + .025, .07, .20), _palette.wood, id)
			1:
				# Estante vazada de livros virada para a sala da frente.
				_box(Vector3(center, .54, z), Vector3(length, 1.08, .14), _palette.wood, id)
				for column in maxi(1, floori(length / .30)):
					_box(Vector3(start + .17 + column * .30, .80, z + .074), Vector3(.20, .30, .012),
						["6b7769", "8e6c52", "465e6b", "b5a37c", "76686a"][(column + _layout) % 5], id, "paper")
					_box(Vector3(start + .17 + column * .30, .30, z + .074), Vector3(.22, .28, .012),
						["a28b6c", "6b7769", "8e6c52", "465e6b"][(column + _layout) % 4], id, "paper")
			2:
				# Meia parede com vidro canelado opaco sobre base de madeira.
				_box(Vector3(center, .30, z), Vector3(length, .60, .14), _palette.wood, id)
				_box(Vector3(center, .84, z), Vector3(length, .48, .08), "8fa3a6", id, "glass")
				for post in maxi(2, floori(length / .9) + 1):
					_box(Vector3(start + post * length / maxf(1.0, float(maxi(2, floori(length / .9) + 1) - 1)), .84, z), Vector3(.05, .50, .10), _palette.metal, id, "metal")
				_box(Vector3(center, 1.10, z), Vector3(length + .02, .05, .16), _palette.metal, id, "metal")
			_:
				# Armários baixos em fila, portas para a sala da frente.
				_box(Vector3(center, .54, z), Vector3(length, 1.08, .14), _palette.cabinet, id)
				for door in maxi(1, floori(length / .55)):
					_box(Vector3(start + .30 + door * .55, .54, z + .074), Vector3(.48, .96, .012), _palette.wood, id)
					_box(Vector3(start + .48 + door * .55, .60, z + .086), Vector3(.03, .12, .02), "aaa994", id, "metal")
		# The low cutaway opens the real sightline; collision still matches its
		# volume. The generous opening next to the central hall is walkable.
		_box(Vector3(start + .18, .66, z + .087), Vector3(.23, .36, .025), "6c7d70", id, "paper")
	var wall_x := size.x * .5 - .48
	var cabinet_z := .83 if arrangement % 2 == 0 else 1.08
	_side_storage(wall_x, cabinet_z)
	if size.x >= 12.0 and size.y >= 11.0 and _spec.front_side > 0 and not (_spec.floor == 0 and absf(_spec.entrance.x + _spec.x) < 1.80):
		var secondary := Vector3(-_spec.x, 0, size.y * .5 - 2.75)
		match (_layout + int(_spec.floor)) % 4:
			1: _dining(secondary, "SecondaryWork")
			2: _armchairs(secondary, "SecondaryWork")
			_: _table(secondary, "SecondaryWork", _spec.family in ["office", "civic"])

## Móvel junto à parede leste: mesma pegada (0,52 x 0,95 m), usos diferentes.
func _side_storage(wall_x: float, cabinet_z: float) -> void:
	var cabinet := "SideStorage"
	match _rng.randi() % 4:
		0:
			_box(Vector3(wall_x, .57, cabinet_z), Vector3(.52, 1.14, .95), _palette.wood, cabinet)
			for shelf in 3:
				_box(Vector3(wall_x - .272, .25 + shelf * .34, cabinet_z), Vector3(.015, .26, .80), _palette.cloth, cabinet, "cloth")
				_box(Vector3(wall_x - .29, .25 + shelf * .34, cabinet_z + .18), Vector3(.03, .04, .16), "aaa994", cabinet, "metal")
			for fold in 3: _box(Vector3(wall_x, 1.19 + fold * .045, cabinet_z), Vector3(.39, .04, .50), "b8af98", cabinet, "cloth")
		1:
			# Guarda-roupa alto de duas portas.
			_box(Vector3(wall_x, .95, cabinet_z), Vector3(.52, 1.90, .95), _palette.wood, cabinet)
			for side in [-1.0, 1.0]:
				_box(Vector3(wall_x - .265, .98, cabinet_z + side * .235), Vector3(.012, 1.70, .44), _palette.cabinet, cabinet)
				_box(Vector3(wall_x - .285, 1.0, cabinet_z + side * .05), Vector3(.025, .16, .025), "aaa994", cabinet, "metal")
		2:
			if _spec.program in ["kitchen", "shared_kitchen", "cafe", "staff", "family", "living"]:
				# Geladeira.
				_box(Vector3(wall_x, .85, cabinet_z), Vector3(.52, 1.70, .70), "d6d6cc", cabinet, "ceramic")
				_box(Vector3(wall_x - .265, 1.18, cabinet_z), Vector3(.012, .02, .66), "aeb0a6", cabinet, "metal")
				_box(Vector3(wall_x - .28, 1.42, cabinet_z + .26), Vector3(.03, .36, .03), "8e9690", cabinet, "metal")
			else:
				# Arquivo de aço de quatro gavetas.
				_box(Vector3(wall_x, .66, cabinet_z), Vector3(.52, 1.32, .70), _palette.metal, cabinet, "metal")
				for drawer in 4:
					_box(Vector3(wall_x - .265, .20 + drawer * .31, cabinet_z), Vector3(.012, .27, .62), "8e9181", cabinet, "metal")
					_box(Vector3(wall_x - .285, .28 + drawer * .31, cabinet_z), Vector3(.025, .03, .18), "c9c7bc", cabinet, "metal")
		_:
			# Cômoda baixa com objetos em cima.
			_box(Vector3(wall_x, .42, cabinet_z), Vector3(.50, .84, .95), _palette.cabinet, cabinet)
			for drawer in 3: _box(Vector3(wall_x - .255, .16 + drawer * .26, cabinet_z), Vector3(.012, .22, .86), _palette.wood, cabinet)
			_surface_items(Vector3(wall_x, .86, cabinet_z - .22), cabinet, 2, .40)

func _populate_large_volume() -> void:
	var size: Vector2 = _spec.size
	if _spec.compact or size.x * size.y < 220.0: return
	var family: String = _spec.family
	var depth := 1.08 if family in ["office", "hospitality"] else .59
	var maximum := mini(32, maxi(4, floori(size.x * size.y / 17.0) - 5))
	var columns := floori((size.x - 3.4) / 3.25) + 1
	var rows := floori((size.y - 4.3) / 2.75) + 1
	# The second staggered pass fills broad compartments whose entry aisle
	# intersects a first-pass row, without packing objects into narrow gaps.
	for row in rows * 2:
		for column in columns:
			if _extra_stations >= maximum: return
			var x := -size.x * .5 + 1.7 + column * 3.25
			var z := -size.y * .5 + 2.2 + (row % rows) * 2.75 + (1.35 if row >= rows else 0.0)
			var point := Vector3(x, 0, z)
			if not _station_fits(point, Vector2(1.19, depth)): continue
			var id := "ExtraStation%02d" % _extra_stations
			# Grandes volumes alternam peças por estação, não um único móvel repetido.
			var pick := _rng.randi() % 3
			match family:
				"industrial":
					if _spec.source_id == "ColdStorage": _cold_unit(point, id)
					elif _extra_stations % 3 == 1: [_pallet, _crate_stack, _barrels][pick].call(point, id)
					else: [_rack, _rack, _tool_cabinet][pick].call(point, id)
				"office":
					if pick == 2: _filing(point, id)
					else: _desk(point, id, "drafting", false)
				"hospitality":
					match pick:
						0: _table(point, id, false)
						1: _dining(point, id)
						_: _armchairs(point, id)
				"retail":
					if _spec.program == "laundry": _laundry(point, id, false)
					elif _extra_stations % 2 == 0 and pick == 2: _clothes_rack(point, id)
					elif _extra_stations % 2 == 0: _bookcase(point, id, true)
					else: _display(point, id)
				"civic":
					if _spec.program == "aquarium": _aquarium(point, id, false)
					elif _spec.program == "gallery": _ship_exhibit(point, id)
					else: _bookcase(point, id, true)
				_: _bookcase(point, id, false)
			_extra_stations += 1

func _populate_compact_activity_zones(arrangement: int) -> void:
	# A shallow house or a narrow tower can still have a substantial floor area.
	# Keep the compact worker/cache positions, but furnish the usable side bays
	# at human scale. Small port cabins retain their original clear floor plan.
	var size: Vector2 = _spec.size
	var rear := -size.y * .5
	var front := size.y * .5
	var offset: float = [-.10, .08, .0, .14][arrangement]
	var corner: String = ["sofa", "tv", "armchairs", "dining", "sofa", "tv"][_layout]
	match str(_spec.family):
		"residential":
			if size.x < 10.5:
				_compact_station("bed", Vector3(-2.68, 0, rear + 1.55))
				_compact_station("kitchen", Vector3(2.73, 0, -1.90 - offset))
				_compact_station(corner, Vector3(-2.68, 0, front - 1.05))
			else:
				_compact_station("bed", Vector3(-size.x * .21, 0, rear + 1.18), PI * (.5 if arrangement % 2 == 0 else -.5))
				_compact_station("kitchen", Vector3(2.85 + offset, 0, rear + .72))
				_compact_station(corner, Vector3(-size.x * (.25 if arrangement % 2 == 0 else .29), 0, front - .78))
		"office":
			var rear_use := "table" if _spec.program in ["meeting", "drafting"] else "archive"
			_compact_station(rear_use, Vector3(-2.68, 0, rear + (1.08 if rear_use == "table" else .68)))
			var middle_use := "kitchen" if _spec.program == "staff" else ("archive" if _spec.program == "records" else "desk")
			# Right-side work and left-side waiting rooms leave the entire stair
			# landing and the wall-side collectible approach unobstructed.
			_compact_station(middle_use, Vector3(2.72, 0, -1.90 - offset))
			_compact_station("armchairs" if corner == "armchairs" else "sofa", Vector3(-2.68, 0, front - 1.05))
		"retail":
			var automotive: bool = _spec.source_id == "TorqueStore"
			_compact_station("rack" if automotive else "groceries", Vector3(-size.x * .29, 0, rear + .72))
			_compact_station("workbench" if automotive else "groceries", Vector3(3.05 + offset, 0, rear + .78))
			_compact_station("parts" if automotive else "produce", Vector3(-size.x * .27, 0, front - .78))
			_compact_station("rack" if automotive else "produce", Vector3(3.05, 0, front - .78))

func _compact_station(kind: String, at: Vector3, yaw := 0.0) -> void:
	var footprint: Rect2
	match kind:
		"bed": footprint = Rect2(-.805, -1.09, 1.61, 2.18)
		"kitchen": footprint = Rect2(-1.26, -.38, 2.52, .80)
		"sofa": footprint = Rect2(-1.12, -.47, 2.24, .94)
		"tv": footprint = Rect2(-.82, -.48, 1.64, .98)
		"armchairs": footprint = Rect2(-1.13, -.42, 2.26, .84)
		"dining": footprint = Rect2(-.72, -.47, 1.44, 1.34)
		"table": footprint = Rect2(-.925, -.45, 1.85, 1.48)
		"desk": footprint = Rect2(-1.0, -.41, 2.0, 1.58)
		"archive": footprint = Rect2(-.92, -.275, 1.84, .55)
		"rack", "groceries": footprint = Rect2(-.90, -.32, 1.80, .64)
		"workbench": footprint = Rect2(-1.15, -.41, 2.30, .82)
		_: footprint = Rect2(-.92, -.44, 1.84, .88)
	var pose := Transform3D(Basis(Vector3.UP, yaw), at)
	var bounds := pose * AABB(Vector3(footprint.position.x, 0, footprint.position.y), Vector3(footprint.size.x, 2.3, footprint.size.y))
	if not _compact_zone_fits(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)): return
	var id := "CompactUse%02d_%s" % [_extra_stations, kind]
	_frame = pose * Transform3D(Basis.IDENTITY, -at)
	match kind:
		"bed": _bed(at, id)
		"kitchen": _kitchen(at, id, false)
		"sofa": _sofa(at, id)
		"tv": _tv_lounge(at, id)
		"armchairs": _armchairs(at, id)
		"dining": _dining(at, id)
		"table": _table(at, id, true)
		"desk":
			_desk(at, id, "drafting", false)
			_chair(at + Vector3(0, 0, .92), id + "Chair")
		"archive": _bookcase(at, id, true)
		"rack": _rack(at, id)
		"workbench": _workbench(at, id, false)
		"groceries": _grocery_shelf(at, id)
		"produce": _produce_table(at, id)
		"parts": _parts_table(at, id)
	_frame = Transform3D.IDENTITY
	_extra_stations += 1

func _compact_zone_fits(rect: Rect2) -> bool:
	var size: Vector2 = _spec.size
	if rect.position.x < -size.x * .5 + .25 or rect.end.x > size.x * .5 - .25: return false
	if rect.position.y < -size.y * .5 + .25 or rect.end.y > size.y * .5 - .25: return false
	# These are the actual compact hall and stair extents, not a scaled-down
	# human or furniture model. A 60 cm body retains room along both aisles.
	if rect.grow(.30).intersects(Rect2(-1.15, -size.y * .5, 2.30, size.y)): return false
	if rect.grow(.30).intersects(Rect2(-size.x * .5, .80, size.x, 1.20)): return false
	if rect.grow(.35).intersects(Rect2(-size.x * .5 + .43, -1.70, 2.06, 2.08)): return false
	if _spec.floor == 0 and rect.grow(.40).intersects(Rect2(_spec.entrance.x - .65, 1.40, 1.30, size.y * .5 - 1.20)): return false
	for solid: AABB in _solids.values():
		if rect.grow(.52).intersects(Rect2(solid.position.x, solid.position.z, solid.size.x, solid.size.z)): return false
	for station in _spec.occupants:
		var point: Vector3 = station.position
		if rect.grow(.72).has_point(Vector2(point.x, point.z)): return false
	for reward in _spec.rewards:
		var point: Vector3 = reward.local_position
		if rect.grow(.72).has_point(Vector2(point.x, point.z)): return false
	return true

func _grocery_shelf(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]: _box(at + Vector3(side * .86, 1.02, 0), Vector3(.06, 2.04, .58), "647464", id, "metal")
	for level in 3:
		var y := .16 + level * .62
		_box(at + Vector3(0, y, 0), Vector3(1.80, .06, .62), _palette.wood, id)
		for column in 7:
			var point := at + Vector3(-.72 + column * .24, y + .20, .06)
			if level == 0:
				_box(point, Vector3(.17, .34, .28), ["c1ac79", "8c9b73", "b08a63"][column % 3], id, "paper")
			else:
				_cylinder(point, .074, .29, ["869968", "b8aa7f", "8a7666"][(column + level) % 3], id, "ceramic")
				_cylinder(point + Vector3(0, .15, 0), .064, .025, "b7b7a4", id, "metal")

func _produce_table(at: Vector3, id: String) -> void:
	_table_base(at, id, Vector2(1.80, .82), .78)
	for side in [-1.0, 1.0]:
		var crate := at + Vector3(side * .44, .90, 0)
		_box(crate, Vector3(.79, .14, .66), "8b7653", id)
		for edge in [-1.0, 1.0]: _box(crate + Vector3(0, .11, edge * .30), Vector3(.79, .17, .035), "a68a5f", id)
		for column in 3:
			for row in 2: _cylinder(crate + Vector3(-.25 + column * .25, .16, -.13 + row * .26), .085, .13, "99804a" if side < 0 else "7d9160", id, "ceramic")

func _parts_table(at: Vector3, id: String) -> void:
	_table_base(at, id, Vector2(1.80, .82), .82)
	for column in 3:
		var point := at + Vector3(-.55 + column * .55, .99, -.03)
		_cylinder(point, .21, .21, "394441", id, "rubber")
		_cylinder(point + Vector3(0, .12, 0), .12, .035, "8e9990", id, "metal")
		_cylinder(point + Vector3(0, .142, 0), .035, .014, "475955", id, "metal")
	_box(at + Vector3(.08, .91, .30), Vector3(.55, .06, .06), "9ea495", id, "metal")

func _station_fits(at: Vector3, half_size: Vector2) -> bool:
	var size: Vector2 = _spec.size
	var rect := Rect2(Vector2(at.x, at.z) - half_size, half_size * 2.0)
	if rect.position.x < -size.x * .5 + .62 or rect.end.x > size.x * .5 - .62: return false
	if rect.position.y < -size.y * .5 + .62 or rect.end.y > size.y * .5 - .62: return false
	# Continuous spine and stair landing remain generous even in a full store.
	if rect.grow(.45).intersects(Rect2(-1.23, -size.y * .5, 2.46, size.y)): return false
	if rect.grow(.40).intersects(Rect2(-size.x * .5, .83, size.x, 1.30)): return false
	if _spec.floor == 0 and rect.grow(.40).intersects(Rect2(_spec.entrance.x - .65, 1.4, 1.30, size.y * .5 - 1.2)): return false
	var stair := Rect2(-size.x * .5 + .43, -1.82, 2.24, 4.06)
	if rect.grow(.45).intersects(stair): return false
	for bounds: AABB in _solids.values():
		var footprint := Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
		if rect.grow(.65).intersects(footprint): return false
	for station in _spec.occupants:
		var point: Vector3 = station.position
		if rect.grow(.72).has_point(Vector2(point.x, point.z)): return false
	for reward in _spec.rewards:
		var point: Vector3 = reward.local_position
		if rect.grow(.72).has_point(Vector2(point.x, point.z)): return false
	# A locked room is furnished too, but its front/east boundaries, the clear
	# aisle through the door and the cache's wall-side approach stay unoccupied.
	var secret := {}
	for reward in _spec.rewards:
		if reward.get("locked", false): secret = reward; break
	if not secret.is_empty():
		var door_z := -size.y * .5 + 2.30
		if rect.grow(.45).intersects(Rect2(-1.12, -size.y * .5 + .24, .14, size.y * .5 - 2.09)): return false
		if rect.grow(.45).intersects(Rect2(-size.x * .5 + .24, -1.93, size.x * .5 - 1.29, .16)): return false
		if at.x < -1.0 and rect.intersects(Rect2(-size.x * .5, door_z - .57, size.x * .5, 1.14)): return false
		if at.x < -1.0 and rect.intersects(Rect2(-size.x * .5, -3.02, size.x * .5, 1.05)): return false
	return true

func _cold_unit(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, 1.02, 0), Vector3(2.24, 2.04, .94), "9caeaa", id, "metal")
	_box(at + Vector3(0, 2.08, 0), Vector3(2.30, .10, 1.00), "ced1be", id, "metal")
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * .55, 1.09, .485), Vector3(1.02, 1.80, .035), "6f8b88", id, "metal")
		_box(at + Vector3(side * .55, 1.19, .51), Vector3(.81, 1.40, .025), "536f75", id, "glass")
		_box(at + Vector3(side * .12, 1.04, .55), Vector3(.05, .46, .05), "bfc5b9", id, "metal")
	for grille in 9: _box(at + Vector3(-.96 + grille * .24, .15, .49), Vector3(.17, .018, .02), "5b706b", id, "metal")

func _illicit_details(at: Vector3) -> void:
	# Fictional contraband is communicated through sealed packets and an unused
	# counting scale, without signage or any real-world production instructions.
	for packet in 3:
		_box(at + Vector3(-.46 + packet * .30, 1.04, -.26), Vector3(.23, .10, .17), "c0bdaa", "Workbench", "paper")
		_box(at + Vector3(-.46 + packet * .30, 1.10, -.26), Vector3(.06, .014, .18), "637569", "Workbench", "cloth")

func _wall_finish() -> void:
	var size: Vector2 = _spec.size
	var x: float = _spec.x
	var rear := -size.y * .5 + .25
	# Cornices, skirting and framed imagery add scale without floor obstructions.
	_box(Vector3(0, .10, rear), Vector3(size.x - .30, .20, .08), _palette.wood)
	_box(Vector3(0, 2.65, rear), Vector3(size.x - .30, .09, .11), ["c7bda4", _palette.wood, _palette.wall, "d8d2c0"][_layout % 4])
	if _rng.randf() < .4:
		# Lambri na metade de baixo da parede do fundo.
		_box(Vector3(0, .55, rear + .012), Vector3(size.x - .30, .90, .025), _palette.cabinet)
		_box(Vector3(0, 1.01, rear + .03), Vector3(size.x - .30, .04, .05), _palette.wood)
	_wall_decor(rear, x)
	# Visible conduit belongs to the built room; no duplicate lights or effects.
	if _spec.family == "industrial":
		_box(Vector3(size.x * .5 - .22, 2.48, 0), Vector3(.10, .10, size.y - .35), "656d61", "", "metal")
		for z in [-size.y * .3, size.y * .3]: _box(Vector3(size.x * .5 - .23, 2.48, z), Vector3(.14, .17, .10), "8e9181", "", "metal")

func _lighting() -> void:
	var size: Vector2 = _spec.size
	var positions: Array[Vector3] = [Vector3(.45, 2.34, 0)]
	if not _spec.compact:
		positions = [Vector3(.30, 2.38, -size.y * .26), Vector3(.30, 2.38, size.y * .27)]
	if size.x * size.y >= 220.0:
		positions.clear()
		for side in [-1.0, 1.0]:
			for end in [-1.0, 1.0]: positions.append(Vector3(side * size.x * .26, 2.38, end * size.y * .27))
	var warm: bool = _spec.family in ["residential", "hospitality"]
	# Mesmas luzes (quantidade, posição, energia); só a luminária e o tom mudam.
	var tone: String = (["ffe2b5", "ffd9a8", "fff0d0"] if warm else ["e8e9d6", "dfe6ea", "f0ead8"])[_layout % 3]
	var fixture := _rng.randi() % 4
	for index in positions.size():
		var at: Vector3 = positions[index]
		_box(at + Vector3(0, .16, 0), Vector3(.045, .32, .045), "5d685f", "", "metal")
		match fixture:
			0: _cylinder(at, .25, .14, _palette.accent, "", "metal")
			1: _cylinder(at + Vector3.UP * .02, .33, .06, _palette.accent, "", "metal")
			2: _box(at, Vector3(.46, .16, .46), _palette.accent, "", "cloth")
			_: _cylinder(at + Vector3.UP * .05, .18, .26, _palette.metal, "", "metal")
		_cylinder(at - Vector3.UP * .08, .20 if fixture != 3 else .15, .026, tone, "", "light")
		var light := OmniLight3D.new()
		light.name = "RoomPendant%d" % index
		light.position = at - Vector3.UP * .19
		light.light_color = Color(tone)
		light.light_energy = .90 if _spec.compact else 1.05
		light.omni_range = minf(10.0, maxf(size.x * .62, size.y * .42)) if positions.size() < 4 else minf(11.0, maxf(size.x, size.y) * .39)
		light.omni_attenuation = .85
		light.shadow_enabled = false
		# Test-only A/B retains the identical scene, material and fixture count.
		light.visible = not Engine.get_meta("harbor_building_lights_baseline", false)
		_model.add_child(light)

# --- Rework de variedade (15/10/2026) -------------------------------------
# Alternativas de móveis por zona, objetos de vida junto às paredes e
# decoração de parede. Tudo entra nos mesmos lotes MultiMesh por cor/material
# (sem nós por objeto, sem luzes novas) e cada objeto sólido ganha envelope
# próprio para o adaptador de colisão.
const LIFE_POOLS := {
	"residential":["plant", "tall_plant", "floor_lamp", "boxes", "basket", "guitar", "radio_table", "bin", "coat_rack", "bicycle", "fan", "shelf", "suitcase", "shoe_rack", "dresser"],
	"hospitality":["plant", "tall_plant", "floor_lamp", "coat_rack", "bin", "shelf", "fan", "basket", "radio_table", "suitcase"],
	"office":["plant", "tall_plant", "cooler", "bin", "coat_rack", "boxes", "shelf", "fan", "extinguisher", "floor_lamp"],
	"civic":["plant", "tall_plant", "cooler", "bin", "bench", "extinguisher", "shelf", "floor_lamp"],
	"retail":["boxes", "plant", "bin", "shelf", "extinguisher", "crates", "basket"],
	"industrial":["crates", "barrel", "boxes", "extinguisher", "bin", "bicycle", "fan", "tire"],
}
# Largura ao longo da parede, profundidade e altura (m).
const LIFE_SIZES := {"plant":Vector3(.50, .50, .95), "tall_plant":Vector3(.56, .56, 1.65), "floor_lamp":Vector3(.42, .42, 1.62),
	"boxes":Vector3(.78, .60, .70), "basket":Vector3(.55, .42, .42), "guitar":Vector3(.46, .30, 1.05), "radio_table":Vector3(.56, .45, .74),
	"bin":Vector3(.36, .36, .52), "coat_rack":Vector3(.50, .50, 1.75), "bicycle":Vector3(1.68, .46, .98), "fan":Vector3(.46, .46, 1.22),
	"shelf":Vector3(1.0, .38, 1.55), "suitcase":Vector3(.56, .30, .66), "shoe_rack":Vector3(.82, .32, .48), "dresser":Vector3(1.06, .50, .92),
	"cooler":Vector3(.42, .42, 1.30), "extinguisher":Vector3(.30, .26, .62), "crates":Vector3(.86, .86, .72), "barrel":Vector3(.64, .64, .92),
	"tire":Vector3(.72, .72, .62), "bench":Vector3(1.30, .46, .50), "toys":Vector3(.72, .46, .42)}

func _surface_items(at: Vector3, id: String, count: int, spread := .30) -> void:
	# Objetos de tampo (só visuais, já dentro do envelope do móvel que os apoia).
	for index in count:
		var point := at + Vector3((float(index) - (count - 1) * .5) * spread, 0, 0)
		match _rng.randi() % 7:
			0: _desk_lamp(point, id)
			1:
				for book in 2 + _rng.randi() % 3:
					_box(point + Vector3(0, .025 + book * .045, 0), Vector3(.24 - book * .02, .04, .17), [_palette.accent, _palette.cloth, "b5a37c", "6b7769"][book % 4], id, "paper")
			2:
				_cylinder(point + Vector3(0, .07, 0), .08, .14, "8a7655", id, "ceramic")
				for leaf in 4: _box(point + Vector3(sin(leaf * 1.7) * .06, .20 + leaf * .03, cos(leaf * 1.7) * .06), Vector3(.10, .12, .08), "5a7655", id, "cloth")
			3:
				_cylinder(point + Vector3(0, .12, 0), .045, .24, ["5f7a5c", "7a5240", "6b7f8c"][_layout % 3], id, "glass")
				_cylinder(point + Vector3(0, .27, 0), .018, .06, "3d3a33", id, "metal")
			4:
				_cylinder(point + Vector3(0, .04, 0), .15, .07, _palette.linen, id, "ceramic")
				for fruit in 3: _cylinder(point + Vector3(-.06 + fruit * .06, .10, .02 * fruit), .045, .07, ["c0904a", "a5502f", "8fa04a"][fruit], id, "ceramic")
			5:
				_box(point + Vector3(0, .09, 0), Vector3(.30, .18, .14), "4c4a45", id, "metal")
				_cylinder(point + Vector3(-.07, .09, .072), .045, .01, "8e9690", id, "metal")
			_:
				_box(point + Vector3(0, .09, 0), Vector3(.17, .17, .025), _palette.wood, id)
				_box(point + Vector3(0, .09, .014), Vector3(.13, .13, .006), _palette.cloth, id, "paper")

func _desk_lamp(at: Vector3, id: String) -> void:
	_cylinder(at + Vector3(0, .015, 0), .08, .03, _palette.metal, id, "metal")
	_box(at + Vector3(0, .20, -.02), Vector3(.025, .36, .025), _palette.metal, id, "metal")
	_cylinder(at + Vector3(0, .40, .03), .09, .12, _palette.accent, id, "cloth")

func _bunk_bed(at: Vector3, id: String) -> void:
	# Beliche: dorme-se na cama de baixo (âncora com a altura do colchão).
	_beds.append(_frame * Transform3D(Basis.IDENTITY, at + Vector3(-.18, .55, 0)))
	var bed := at + Vector3(-.18, 0, 0)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]: _box(bed + Vector3(side * .52, .92, end * 1.0), Vector3(.07, 1.84, .07), _palette.wood, id)
	for level in [.36, 1.36]:
		_box(bed + Vector3(0, level, 0), Vector3(1.0, .12, 2.0), _palette.wood, id)
		_box(bed + Vector3(0, level + .12, 0), Vector3(.94, .14, 1.94), _palette.linen, id, "cloth")
		_box(bed + Vector3(0, level + .21, .25), Vector3(.95, .05, 1.30), [_palette.cloth, _palette.accent][int(level > 1.0)], id, "cloth")
		_box(bed + Vector3(0, level + .25, -.72), Vector3(.55, .12, .32), "e0d6bf", id, "cloth")
	_box(bed + Vector3(.30, 1.58, 0), Vector3(.05, .22, 2.0), _palette.wood, id)
	for rung in 4: _box(bed + Vector3(.60, .30 + rung * .36, .62), Vector3(.05, .04, .36), _palette.wood, id)
	_box(at + Vector3(.62, .9, .44), Vector3(.05, 1.8, .05), _palette.wood, id)
	_box(at + Vector3(.62, .9, .80), Vector3(.05, 1.8, .05), _palette.wood, id)
	# Caixa de brinquedos ao pé do beliche.
	_box(at + Vector3(.45, .20, -.70), Vector3(.40, .40, .50), _palette.accent, id)
	for toy in 3: _box(at + Vector3(.36 + toy * .09, .45, -.70 + toy * .1), Vector3(.08, .10, .08), ["c0904a", "5b7fa0", "a5502f"][toy], id, "ceramic")

func _tv_wall(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, .25, -.02), Vector3(1.80, .50, .45), _palette.cabinet, id)
	for door in 3: _box(at + Vector3(-.58 + door * .58, .25, .21), Vector3(.52, .40, .012), _palette.wood, id)
	_box(at + Vector3(0, .53, -.08), Vector3(.30, .06, .20), "2d3133", id, "metal")
	_box(at + Vector3(0, .93, -.10), Vector3(1.20, .70, .06), "202426", id, "metal")
	_box(at + Vector3(0, .93, -.068), Vector3(1.12, .63, .006), "3b4d55", id, "glass")
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * .78, .95, -.08), Vector3(.24, 1.40, .30), _palette.wood, id)
		for item in 3: _box(at + Vector3(side * .78, .70 + item * .32, -.06), Vector3(.16, .18, .18), [_palette.accent, "b8bca7", _palette.cloth][item], id, "ceramic")

func _tv_lounge(at: Vector3, id: String) -> void:
	# Rack baixo com TV voltada para a sala e um pufe à frente.
	_box(at + Vector3(0, .25, .28), Vector3(1.60, .50, .42), _palette.cabinet, id)
	_box(at + Vector3(0, .54, .30), Vector3(.30, .06, .18), "2d3133", id, "metal")
	_box(at + Vector3(0, .92, .32), Vector3(1.15, .68, .06), "202426", id, "metal")
	_box(at + Vector3(0, .92, .288), Vector3(1.07, .61, .006), "3b4d55", id, "glass")
	_cylinder(at + Vector3(-.40, .20, -.25), .22, .40, _palette.cloth, id, "cloth")
	_box(at + Vector3(.55, .56, .30), Vector3(.22, .08, .14), _palette.accent, id, "ceramic")

func _armchairs(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]:
		var seat := at + Vector3(side * .73, 0, 0)
		_box(seat + Vector3(0, .22, 0), Vector3(.78, .36, .76), _palette.wood, id)
		_box(seat + Vector3(0, .44, -.03), Vector3(.62, .14, .62), _palette.cloth, id, "cloth")
		# Encosto alto (poltrona de orelhas) voltado para a parede da frente.
		_box(seat + Vector3(0, .78, .30), Vector3(.76, .82, .16), _palette.cloth, id, "cloth")
		for arm in [-1.0, 1.0]: _box(seat + Vector3(arm * .35, .56, 0), Vector3(.10, .32, .72), _palette.cloth, id, "cloth")
	_cylinder(at + Vector3(0, .28, -.05), .21, .56, _palette.wood, id, "wood")
	_surface_items(at + Vector3(0, .56, -.05), id, 1)

func _dining(at: Vector3, id: String) -> void:
	_table_base(at + Vector3(0, 0, -.05), id, Vector2(1.40, .82), .76)
	_box(at + Vector3(0, .82, -.05), Vector3(.90, .01, .30), _palette.linen, id, "cloth")
	for plate in [-.35, .35]: _cylinder(at + Vector3(plate, .825, .12), .11, .012, "e3ddcc", id, "ceramic")
	_surface_items(at + Vector3(0, .82, -.20), id, 1)
	for side in [-1.0, 1.0]: _chair_turned(at + Vector3(side * .36, 0, .58), id + "Chair", PI)

func _piano(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, .63, -.12), Vector3(1.50, 1.26, .55), "2b2523", id)
	_box(at + Vector3(0, .74, .22), Vector3(1.42, .08, .26), "2b2523", id)
	_box(at + Vector3(0, .79, .22), Vector3(1.30, .02, .22), "e4ddcc", id, "ceramic")
	for key in 12: _box(at + Vector3(-.60 + key * .11, .81, .18), Vector3(.035, .02, .12), "1c1a19", id, "ceramic")
	for leg in [-.65, .65]: _box(at + Vector3(leg, .35, .26), Vector3(.06, .70, .06), "2b2523", id)
	_box(at + Vector3(0, .46, .66), Vector3(.82, .08, .34), "2b2523", id)
	for leg in [-.35, .35]: _box(at + Vector3(leg, .22, .66), Vector3(.06, .44, .28), "2b2523", id)
	_box(at + Vector3(.35, 1.30, -.18), Vector3(.30, .06, .22), "d4c9ac", id, "paper")

func _canvas_stack(at: Vector3, id: String) -> void:
	for canvas in 4:
		var x := -.62 + canvas * .40
		_box(at + Vector3(x, .55 + (canvas % 2) * .08, -.12 + canvas * .03), Vector3(.36 + (canvas % 2) * .1, 1.0 + (canvas % 2) * .16, .04), "c7bfa0", id, "paper")
		_box(at + Vector3(x, .60, -.095 + canvas * .03), Vector3(.30, .55, .006), [_palette.accent, "526c76", _palette.cloth, "8a987f"][canvas], id, "paper")
	_box(at + Vector3(.55, .34, .15), Vector3(.50, .68, .40), _palette.wood, id)
	for jar in 3: _cylinder(at + Vector3(.40 + jar * .14, .74, .15), .045, .12, ["798372", "9e7352", "576f79"][jar], id, "ceramic")

func _filing(at: Vector3, id: String) -> void:
	for cabinet in 3:
		var point := at + Vector3(-.61 + cabinet * .61, 0, -.05)
		_box(point + Vector3(0, .66, 0), Vector3(.58, 1.32, .60), _palette.metal if cabinet != 1 else _palette.cabinet, id, "metal")
		for drawer in 4:
			_box(point + Vector3(0, .20 + drawer * .31, .305), Vector3(.50, .27, .012), "8e9181", id, "metal")
			_box(point + Vector3(0, .28 + drawer * .31, .318), Vector3(.16, .03, .02), "c9c7bc", id, "metal")
	_papers(at + Vector3(-.40, 1.34, -.05), id)
	_surface_items(at + Vector3(.45, 1.32, -.05), id, 1)

func _tool_cabinet(at: Vector3, id: String) -> void:
	_box(at + Vector3(-.30, .50, 0), Vector3(1.10, 1.0, .55), "8c3b32", id, "metal")
	for drawer in 5: _box(at + Vector3(-.30, .12 + drawer * .18, .28), Vector3(1.02, .14, .012), "a9483d", id, "metal")
	_box(at + Vector3(-.30, 1.08, 0), Vector3(.40, .16, .22), "4c4a45", id, "metal")
	_box(at + Vector3(.58, .95, 0), Vector3(.58, 1.90, .52), _palette.metal, id, "metal")
	_box(at + Vector3(.58, .95, .265), Vector3(.012, 1.70, .02), "2d3133", id, "metal")

func _barrels(at: Vector3, id: String) -> void:
	for barrel in 3:
		var color: String = ["3f5d7a", "8c4a32", _palette.metal][(barrel + _layout) % 3]
		_cylinder(at + Vector3(-.60 + barrel * .60, .46, 0), .28, .92, color, id, "metal")
		for ring in [.18, .74]: _cylinder(at + Vector3(-.60 + barrel * .60, ring, 0), .285, .03, "2d3133", id, "metal")

func _crate_stack(at: Vector3, id: String) -> void:
	for crate in 2:
		var point := at + Vector3(-.42 + crate * .84, 0, 0)
		_box(point + Vector3(0, .30, 0), Vector3(.76, .60, .74), "8b7653", id)
		for slat in 3: _box(point + Vector3(0, .12 + slat * .19, .375), Vector3(.76, .07, .012), "a68a5f", id)
	_box(at + Vector3(-.20, .85, 0), Vector3(.70, .50, .64), "a68a5f", id)
	_box(at + Vector3(-.20, 1.105, 0), Vector3(.10, .012, .66), "c5b283", id, "paper")

func _engine_stand(at: Vector3, id: String) -> void:
	for leg in [-.35, .35]: _box(at + Vector3(leg - .20, .25, 0), Vector3(.06, .50, .55), _palette.metal, id, "metal")
	_box(at + Vector3(-.20, .74, 0), Vector3(.72, .46, .52), "4f5755", id, "metal")
	for cylinder in 4: _cylinder(at + Vector3(-.47 + cylinder * .18, 1.0, 0), .06, .08, "8e9690", id, "metal")
	for tire in 3: _cylinder(at + Vector3(.72, .11 + tire * .21, 0), .32, .20, "2a2c2b", id, "rubber")

func _clothes_rack(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * .84, .80, 0), Vector3(.05, 1.60, .05), _palette.metal, id, "metal")
		_box(at + Vector3(side * .84, .03, 0), Vector3(.10, .05, .50), _palette.metal, id, "metal")
	_box(at + Vector3(0, 1.58, 0), Vector3(1.72, .03, .03), _palette.metal, id, "metal")
	for garment in 9:
		var color: String = [_palette.cloth, _palette.accent, "3f4a5a", "a3734e", "d8d2c0", "6b5878"][(garment + _layout) % 6]
		_box(at + Vector3(-.72 + garment * .18, 1.17, 0), Vector3(.06, .74 + (garment % 3) * .10, .44), color, id, "cloth")

func _laundry_carts(at: Vector3, id: String) -> void:
	for side in [-1.0, 1.0]:
		var cart := at + Vector3(side * .50, 0, 0)
		_box(cart + Vector3(0, .45, 0), Vector3(.72, .56, .50), _palette.metal, id, "metal")
		for wheel in [-.28, .28]: _cylinder(cart + Vector3(wheel, .06, .18), .05, .06, "2a2c2b", id, "rubber")
		for fold in 3: _box(cart + Vector3(0, .76 + fold * .06, 0), Vector3(.56, .05, .38), [_palette.linen, _palette.cloth, "d8d2c0"][fold], id, "cloth")

func _whiteboard_table(at: Vector3, id: String) -> void:
	_table(at, id, true)
	_box(at + Vector3(0, 1.28, -.62), Vector3(1.60, .90, .04), "e8e9e2", id + "Board", "ceramic")
	_box(at + Vector3(0, 1.28, -.645), Vector3(1.68, .98, .03), _palette.metal, id + "Board", "metal")
	for leg in [-.80, .80]: _box(at + Vector3(leg, .62, -.64), Vector3(.05, 1.24, .30), _palette.metal, id + "Board", "metal")
	for mark in 3: _box(at + Vector3(-.45 + mark * .35, 1.40 - mark * .1, -.598), Vector3(.30, .015, .004), ["3f5d7a", "8c3b32", "2d3133"][mark], id + "Board", "paper")

func _coat_corner(at: Vector3, id: String) -> void:
	_life_object("coat_rack", at + Vector3(-.62, 0, 0), id)
	_life_object("tall_plant", at + Vector3(.62, 0, 0), id)
	_box(at + Vector3(0, .24, .05), Vector3(.62, .48, .38), _palette.wood, id)
	_box(at + Vector3(0, .50, .05), Vector3(.56, .05, .34), _palette.cloth, id, "cloth")

## Peça canônica: costas em -Z (parede), frente em +Z, base no chão em `at`.
func _life_object(kind: String, at: Vector3, id: String) -> void:
	match kind:
		"plant":
			_cylinder(at + Vector3(0, .20, 0), .21, .40, ["8a7655", "b06a4a", "6e7f8a"][_layout % 3], id, "ceramic")
			for leaf in 7: _box(at + Vector3(sin(leaf * 2.3) * .14, .52 + leaf * .05, cos(leaf * 2.3) * .14), Vector3(.18, .26, .14), ["5a7655", "6f8a55", "4a6a50"][leaf % 3], id, "cloth")
		"tall_plant":
			_cylinder(at + Vector3(0, .22, 0), .24, .44, ["d8d2c0", "3f4346", "8a7655"][_layout % 3], id, "ceramic")
			_box(at + Vector3(0, .80, 0), Vector3(.05, .80, .05), "6b5a40", id)
			for leaf in 9: _box(at + Vector3(sin(leaf * 1.9) * .18, .95 + leaf * .07, cos(leaf * 1.9) * .16), Vector3(.24, .16, .20), ["4f7a4f", "6f8a55", "3e6a48"][leaf % 3], id, "cloth")
		"floor_lamp":
			_cylinder(at + Vector3(0, .02, 0), .17, .04, _palette.metal, id, "metal")
			_box(at + Vector3(0, .75, 0), Vector3(.03, 1.46, .03), _palette.metal, id, "metal")
			_cylinder(at + Vector3(0, 1.48, 0), .19, .26, _palette.linen, id, "cloth")
		"boxes":
			_box(at + Vector3(-.10, .21, 0), Vector3(.56, .42, .56), "a88c61", id, "paper")
			_box(at + Vector3(-.10, .421, 0), Vector3(.08, .006, .57), "c5b283", id, "paper")
			_box(at + Vector3(.12, .56, .02), Vector3(.40, .28, .40), "b39a6e", id, "paper")
			if _rng.randf() < .5: _box(at + Vector3(.27, .13, .08), Vector3(.22, .26, .36), "9c7e55", id, "paper")
		"basket":
			_box(at + Vector3(0, .17, 0), Vector3(.52, .34, .40), "b39468", id, "cloth")
			for fold in 2: _box(at + Vector3(.04 * fold, .36 + fold * .04, 0), Vector3(.40, .05, .30), [_palette.cloth, _palette.linen][fold], id, "cloth")
		"guitar":
			_box(at + Vector3(0, .26, .05), Vector3(.40, .48, .10), _palette.accent, id)
			_box(at + Vector3(0, .58, .05), Vector3(.32, .28, .09), _palette.accent, id)
			_box(at + Vector3(0, .88, .02), Vector3(.06, .40, .04), "3d3a33", id)
			_cylinder(at + Vector3(0, .40, .105), .06, .01, "2d2a26", id, "metal")
			_box(at + Vector3(0, .15, -.05), Vector3(.30, .30, .10), "2d3133", id, "metal")
		"radio_table":
			_table_base(at, id, Vector2(.54, .42), .66)
			_box(at + Vector3(0, .80, 0), Vector3(.34, .18, .18), "6b5a40", id)
			_cylinder(at + Vector3(-.08, .80, .092), .05, .01, "c9c7bc", id, "metal")
		"bin":
			_cylinder(at + Vector3(0, .25, 0), .16, .50, ["3f4346", "5e7774", "8c3b32"][_layout % 3], id, "metal")
			_box(at + Vector3(.02, .51, 0), Vector3(.16, .04, .12), "d9d1b8", id, "paper")
		"coat_rack":
			_cylinder(at + Vector3(0, .03, 0), .22, .06, _palette.wood, id, "wood")
			_box(at + Vector3(0, .88, 0), Vector3(.05, 1.72, .05), _palette.wood, id)
			_box(at + Vector3(.12, 1.25, .05), Vector3(.22, .70, .18), _palette.cloth, id, "cloth")
			_box(at + Vector3(-.10, 1.40, -.04), Vector3(.18, .40, .14), "3f4a5a", id, "cloth")
		"bicycle":
			for wheel in [-.52, .52]:
				_record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.62, .04, .62)), at + Vector3(wheel, .32, 0)), "2a2c2b", "rubber")
				_record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.50, .045, .50)), at + Vector3(wheel, .32, 0)), "8e9690", "metal")
			_box(at + Vector3(0, .52, 0), Vector3(1.0, .04, .04), _palette.accent, id, "metal")
			_box(at + Vector3(-.18, .48, 0), Vector3(.04, .36, .04), _palette.accent, id, "metal")
			_box(at + Vector3(-.18, .70, 0), Vector3(.22, .05, .10), "2a2c2b", id, "rubber")
			_box(at + Vector3(.46, .80, 0), Vector3(.05, .04, .44), "2a2c2b", id, "metal")
			_reserve(id, AABB(at + Vector3(-.84, 0, -.23), Vector3(1.68, .98, .46)))
		"fan":
			_cylinder(at + Vector3(0, .03, 0), .2, .05, _palette.metal, id, "metal")
			_box(at + Vector3(0, .58, 0), Vector3(.04, 1.10, .04), _palette.metal, id, "metal")
			_record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.40, .10, .40)), at + Vector3(0, 1.08, .04)), "c9c7bc", "metal")
			_reserve(id, AABB(at + Vector3(-.23, 0, -.23), Vector3(.46, 1.22, .46)))
		"shelf":
			_box(at + Vector3(0, .78, -.17), Vector3(1.0, 1.55, .04), _palette.wood, id)
			for side in [-1.0, 1.0]: _box(at + Vector3(side * .48, .78, 0), Vector3(.04, 1.55, .38), _palette.wood, id)
			for level in 4:
				_box(at + Vector3(0, .05 + level * .48, 0), Vector3(.96, .03, .38), _palette.wood, id)
				if level == 3: continue
				for item in 3:
					var x := -.30 + item * .30
					if (item + level + _layout) % 3 == 0: _cylinder(at + Vector3(x, .16 + level * .48, 0), .07, .20, [_palette.accent, "b8bca7", "8a7655"][item], id, "ceramic")
					else: _box(at + Vector3(x, .17 + level * .48, 0), Vector3(.22, .22 + (item % 2) * .06, .26), [_palette.cloth, "b5a37c", "6b7769", "a28b6c"][(item + level) % 4], id, "paper")
		"suitcase":
			_box(at + Vector3(0, .32, 0), Vector3(.52, .62, .24), ["3f4a5a", "8c4a32", "5e7774"][_layout % 3], id, "cloth")
			_box(at + Vector3(0, .66, 0), Vector3(.18, .05, .04), "2a2c2b", id, "metal")
		"shoe_rack":
			_box(at + Vector3(0, .24, 0), Vector3(.80, .48, .30), _palette.wood, id)
			for pair in 3:
				for shoe in 2: _box(at + Vector3(-.26 + pair * .26 + shoe * .08, .52, .02), Vector3(.07, .07, .24), ["2a2c2b", "8c4a32", "d8d2c0"][pair], id, "rubber")
		"dresser":
			_box(at + Vector3(0, .45, 0), Vector3(1.04, .90, .48), _palette.cabinet, id)
			for drawer in 3: _box(at + Vector3(0, .17 + drawer * .27, .245), Vector3(.96, .22, .012), _palette.wood, id)
			_surface_items(at + Vector3(0, .90, -.04), id, 2, .40)
		"cooler":
			_box(at + Vector3(0, .50, 0), Vector3(.38, 1.0, .38), "d6d6cc", id, "ceramic")
			_cylinder(at + Vector3(0, 1.16, 0), .15, .30, "8fb3c2", id, "glass")
			_box(at + Vector3(0, .80, .20), Vector3(.10, .06, .04), "3f5d7a", id, "metal")
		"extinguisher":
			_cylinder(at + Vector3(0, .27, 0), .09, .54, "a3352c", id, "metal")
			_box(at + Vector3(0, .57, 0), Vector3(.10, .06, .14), "2a2c2b", id, "metal")
		"crates":
			_box(at + Vector3(0, .36, 0), Vector3(.84, .72, .84), "8b7653", id)
			for slat in 3: _box(at + Vector3(0, .12 + slat * .24, .425), Vector3(.84, .08, .012), "a68a5f", id)
		"barrel":
			_cylinder(at + Vector3(0, .46, 0), .30, .92, ["3f5d7a", "8c4a32", "4f6a50"][_layout % 3], id, "metal")
			for ring in [.18, .74]: _cylinder(at + Vector3(0, ring, 0), .305, .03, "2d3133", id, "metal")
		"tire":
			for tire in 3: _cylinder(at + Vector3(0, .10 + tire * .20, 0), .34, .19, "2a2c2b", id, "rubber")
		"bench":
			_box(at + Vector3(0, .42, 0), Vector3(1.28, .06, .42), _palette.wood, id)
			for leg in [-.55, .55]: _box(at + Vector3(leg, .20, 0), Vector3(.06, .40, .38), _palette.metal, id, "metal")
		"toys":
			_box(at + Vector3(0, .20, 0), Vector3(.70, .40, .44), _palette.accent, id)
			for toy in 4: _box(at + Vector3(-.24 + toy * .16, .45, (toy % 2) * .08), Vector3(.12, .12, .12), ["c0904a", "5b7fa0", "a5502f", "8fa04a"][toy], id, "ceramic")

## Objetos de vida encostados nas paredes, sorteados por prédio/andar. A
## pegada é testada contra corredores, escada, entrada, sólidos, estações e
## recompensas; a parede da frente (lado da câmera) fica livre.
func _life_objects() -> void:
	var size: Vector2 = _spec.size
	var pool: Array = LIFE_POOLS.get(str(_spec.family), LIFE_POOLS.residential).duplicate()
	if _spec.program == "kids": pool.append_array(["toys", "toys"])
	if _spec.abandoned: pool = ["boxes", "crates", "bin", "tire", "barrel"]
	var target := clampi(int(size.x * size.y / 18.0), 3, 7) + (2 if _spec.abandoned else 0)
	var used := {}
	var spots: Array[Dictionary] = []
	var half := size * .5
	# Parede do fundo (yaw 0), frente (PI), leste (-PI/2) e oeste (PI/2).
	var t := -half.x + .7
	while t < half.x - .6:
		# A parede da frente fica livre: atrás dela fica o controle de oclusão
		# do contrato e é por ela que a câmera olha para dentro.
		spots.append({"wall":"back", "t":t})
		t += .55
	t = -half.y + .8
	while t < half.y - .7:
		spots.append({"wall":"east", "t":t})
		spots.append({"wall":"west", "t":t})
		t += .55
	var tries := 0
	for spot in CONTENT._shuffled(_rng, spots):
		if _decor_count >= target or tries > 90: break
		tries += 1
		if pool.is_empty(): break
		var kind: String = pool[_rng.randi() % pool.size()]
		var dims: Vector3 = LIFE_SIZES[kind]
		if spot.wall == "front" and dims.z > .74: continue
		var face := .26
		var yaw := 0.0
		var at := Vector3.ZERO
		match str(spot.wall):
			"back": at = Vector3(spot.t, 0, -half.y + face + dims.y * .5 + .02)
			"front":
				at = Vector3(spot.t, 0, half.y - face - dims.y * .5 - .02)
				yaw = PI
			"east":
				at = Vector3(half.x - face - dims.y * .5 - .02, 0, spot.t)
				yaw = -PI * .5
			_:
				at = Vector3(-half.x + face + dims.y * .5 + .02, 0, spot.t)
				yaw = PI * .5
		var rotated := absf(sin(yaw)) > .5
		var extent := Vector2(dims.y, dims.x) if rotated else Vector2(dims.x, dims.y)
		var rect := Rect2(Vector2(at.x, at.z) - extent * .5, extent)
		if not _decor_fits(rect): continue
		var id := "Decor%02d_%s" % [_decor_count, kind]
		_frame = Transform3D(Basis(Vector3.UP, yaw), at) * Transform3D(Basis.IDENTITY, -at)
		_life_object(kind, at, id)
		_frame = Transform3D.IDENTITY
		# Todo objeto de vida é sólido por inteiro (vaso, folhas e base).
		_reserve(id, Transform3D(Basis(Vector3.UP, yaw), at) * AABB(Vector3(-dims.x * .5, 0, -dims.y * .5), Vector3(dims.x, dims.z, dims.y)))
		_decor.append(kind)
		_decor_count += 1
		# Um de cada (dois para vasos e caixas): a sala não vira depósito de fãs.
		used[kind] = int(used.get(kind, 0)) + 1
		if used[kind] >= (2 if kind in ["plant", "boxes", "crates", "toys"] else 1): pool.erase(kind)

func _decor_fits(rect: Rect2) -> bool:
	var size: Vector2 = _spec.size
	if rect.position.x < -size.x * .5 + .25 or rect.end.x > size.x * .5 - .25: return false
	if rect.position.y < -size.y * .5 + .25 or rect.end.y > size.y * .5 - .25: return false
	# Corredor central, faixa transversal da escada, a própria escada e a porta.
	if rect.grow(.22).intersects(Rect2(-1.23, -size.y * .5, 2.46, size.y)): return false
	if rect.grow(.22).intersects(Rect2(-size.x * .5, .78, size.x, 1.37)): return false
	if rect.grow(.35).intersects(Rect2(-size.x * .5 + .43, -1.82, 2.24, 4.06)): return false
	if _spec.floor == 0 and rect.grow(.45).intersects(Rect2(_spec.entrance.x - .65, 1.2, 1.30, size.y * .5)): return false
	for id in _solids:
		var bounds: AABB = _solids[id]
		# Ao redor da cama fica um vão livre: é por ali que se deita e levanta.
		var gap := .85 if str(id) == "Bed" or str(id).ends_with("_bed") else .24
		if rect.grow(gap).intersects(Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)): return false
	for station in _spec.occupants:
		var point: Vector3 = station.position
		if rect.grow(.80).has_point(Vector2(point.x, point.z)): return false
	for reward in _spec.rewards:
		var point: Vector3 = reward.local_position
		if rect.grow(.65).has_point(Vector2(point.x, point.z)): return false
	# Sala trancada: paredes, porta e a aproximação do esconderijo ficam livres.
	for reward in _spec.rewards:
		if not reward.get("locked", false): continue
		var door_z := -size.y * .5 + 2.30
		if rect.grow(.45).intersects(Rect2(-1.12, -size.y * .5 + .24, .14, size.y * .5 - 2.09)): return false
		if rect.grow(.45).intersects(Rect2(-size.x * .5 + .24, -1.93, size.x * .5 - 1.29, .16)): return false
		if rect.get_center().x < -1.0 and rect.intersects(Rect2(-size.x * .5, door_z - .57, size.x * .5, 1.14)): return false
		if rect.get_center().x < -1.0 and rect.intersects(Rect2(-size.x * .5, -3.02, size.x * .5, 1.05)): return false
	return true

## Quadros, relógio, prateleiras e espelho na parede do fundo (não sólidos),
## fora das janelas e acima de móveis altos encostados nela.
func _wall_decor(rear: float, _x: float) -> void:
	var size: Vector2 = _spec.size
	var window_half := minf(1.8, size.x * .24) * .5 + .18
	var count := 2 + _rng.randi() % 4
	var placed: Array[Rect2] = []
	var clock_used := false
	for attempt in 24:
		if placed.size() >= count: break
		var width := _rng.randf_range(.35, .95)
		var height := _rng.randf_range(.30, .70)
		var kind := _rng.randi() % 6
		# Um relógio só por parede.
		if kind == 1 and clock_used: kind = 0
		if kind == 1:
			clock_used = true
			width = .34
			height = .34
		var x := _rng.randf_range(-size.x * .5 + .5 + width * .5, size.x * .5 - .5 - width * .5)
		var y := _rng.randf_range(1.45, 2.15)
		var rect := Rect2(x - width * .5, y - height * .5, width, height)
		var blocked := false
		for side in [-1.0, 1.0]:
			if absf(x - side * size.x * .27) < window_half + width * .5: blocked = true
		for other in placed:
			if other.grow(.12).intersects(rect): blocked = true
		for bounds: AABB in _solids.values():
			if bounds.position.z > -size.y * .5 + 1.0: continue
			if bounds.end.y > rect.position.y - .05 and bounds.position.x < rect.end.x and bounds.end.x > rect.position.x: blocked = true
		if blocked: continue
		placed.append(rect)
		var at := Vector3(x, y, rear + .03)
		match kind:
			0, 4:
				# Quadro abstrato emoldurado: duas a três manchas de cor.
				_box(at, Vector3(width, height, .04), _palette.wood if kind == 0 else _palette.metal, "", "wood" if kind == 0 else "metal")
				_box(at + Vector3(0, 0, .022), Vector3(width - .08, height - .08, .006), ["d8d2c0", "c9b8a0", "aeb9b4"][_layout % 3], "", "paper")
				for blot in 2 + _rng.randi() % 2:
					_box(at + Vector3(_rng.randf_range(-.25, .25) * width, _rng.randf_range(-.2, .2) * height, .027),
						Vector3(width * _rng.randf_range(.18, .4), height * _rng.randf_range(.2, .45), .004),
						[_palette.accent, _palette.cloth, "526c76", "a5502f", "8a987f"][_rng.randi() % 5], "", "paper")
			1:
				# Relógio redondo.
				_record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.34, .05, .34)), at), _palette.metal, "metal")
				_record("cylinder", Transform3D(Basis(Vector3.RIGHT, PI * .5) * Basis.from_scale(Vector3(.29, .01, .29)), at + Vector3(0, 0, .03)), "e4ddcc", "ceramic")
				_box(at + Vector3(0, .05, .04), Vector3(.015, .10, .004), "2a2c2b", "", "metal")
				_box(at + Vector3(.04, 0, .04), Vector3(.08, .012, .004), "2a2c2b", "", "metal")
			2:
				# Prateleira de parede com objetos.
				_box(at + Vector3(0, -height * .5, .08), Vector3(width, .03, .18), _palette.wood)
				for item in maxi(1, int(width / .2)):
					var ix := -width * .5 + .12 + item * .2
					if item % 2 == 0: _cylinder(at + Vector3(ix, -height * .5 + .10, .08), .05, .16, [_palette.accent, "b8bca7", "8a7655"][item % 3], "", "ceramic")
					else: _box(at + Vector3(ix, -height * .5 + .11, .08), Vector3(.12, .18, .12), [_palette.cloth, "b5a37c"][item % 2], "", "paper")
			3:
				# Espelho.
				_box(at, Vector3(width * .7, height + .2, .03), _palette.wood)
				_box(at + Vector3(0, 0, .018), Vector3(width * .7 - .06, height + .14, .006), "9fb3b8", "", "glass")
			_:
				# Painel de fotos pequenas.
				for photo in 3:
					_box(at + Vector3((photo - 1) * width * .34, (photo % 2) * .08, 0), Vector3(width * .26, height * .55, .03), _palette.wood)
					_box(at + Vector3((photo - 1) * width * .34, (photo % 2) * .08, .017), Vector3(width * .22, height * .45, .005), [_palette.cloth, "8a987f", "b39468"][photo], "", "paper")

## Tapetes rasos (transitáveis, sem envelope): forma, tamanho, cor e posição
## variam por andar; um sob a estação de trabalho quando há espaço.
func _rugs() -> void:
	var size: Vector2 = _spec.size
	var rug: String = _palette.rug
	var border: String = _palette.accent
	match _rng.randi() % 4:
		0:
			_box(Vector3(0, .015, size.y * .21), Vector3(1.75, .018, 1.25), rug, "", "cloth")
		1:
			_record("cylinder", Transform3D(Basis.from_scale(Vector3(2.0, .016, 2.0)), Vector3(0, .012, size.y * .22)), border, "cloth")
			_record("cylinder", Transform3D(Basis.from_scale(Vector3(1.8, .018, 1.8)), Vector3(0, .014, size.y * .22)), rug, "cloth")
		2:
			# Passadeira ao longo do corredor central.
			_box(Vector3(0, .012, size.y * .05), Vector3(1.05, .014, size.y * .62), border, "", "cloth")
			_box(Vector3(0, .015, size.y * .05), Vector3(.88, .016, size.y * .62 - .16), rug, "", "cloth")
		_:
			_box(Vector3(0, .012, size.y * .22), Vector3(2.05, .014, 1.45), border, "", "cloth")
			_box(Vector3(0, .015, size.y * .22), Vector3(1.85, .016, 1.25), rug, "", "cloth")
			for stripe in 3: _box(Vector3(0, .0175, size.y * .22 - .4 + stripe * .4), Vector3(1.85, .004, .08), _palette.cloth, "", "cloth")
	if not _spec.compact:
		var station := Vector3(_spec.x + float(_spec.get("work_dx", 0.0)), .018, _spec.back + .72)
		_box(station, Vector3(_rng.randf_range(1.8, 2.3), .012, _rng.randf_range(1.6, 2.1)), [_palette.cloth, _palette.rug, "6f6a5e"][_layout % 3], "", "cloth")
