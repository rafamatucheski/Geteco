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
	var right := Vector3(x, 0, back)
	var arrangement: int = (_spec.seed + _spec.floor * 3) % 4
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
		match program:
			"aquarium":
				_aquarium(left, "ReefTank", false)
				_sofa(near, "AquariumBench")
			"gallery":
				_ship_exhibit(left, "ShipModel")
				_ship_exhibit(near, "HarborArchive")
			"family", "bedroom", "guest":
				var bed_at := left + Vector3(0, 0, .38 if _spec.size.y >= 9.5 else 0.0)
				if _spec.size.y < 9.5:
					_frame = Transform3D(Basis(Vector3.UP, PI * .5), bed_at) * Transform3D(Basis.IDENTITY, -bed_at)
				_bed(bed_at, "Bed")
				_frame = Transform3D.IDENTITY
				_sofa(near, "LivingSofa")
			"artist", "studio", "music":
				_easel(left, "Easel")
				_sofa(near, "StudioSofa")
			"library", "records", "press":
				_bookcase(left + Vector3(0, 0, -.25), "Archive", program != "library")
				_table(near, "ReadingTable", true)
			"workshop", "toolroom", "packing", "stockroom", "dispatch":
				_rack(left + Vector3(0, 0, -.28), "PartsRack")
				_pallet(near, "Shipment")
			"shop", "tailor":
				_bookcase(left + Vector3(0, 0, -.30), "StockShelf", true)
				_display(near, "Display")
			"laundry":
				_laundry(left + Vector3(0, 0, -.20), "Dryers", false)
				_table(near, "FoldingTable", false)
			"meeting", "drafting":
				_table(left, "MeetingTable", true)
				_bookcase(near, "Drawings", false)
			_:
				_bookcase(left + Vector3(0, 0, -.3), "Library", false)
				_sofa(near, "WaitingSofa")
		_room_identity()
		_secret_recess()
		_partitioned_rooms(arrangement)
	if _spec.abandoned: _neglected_details()
	if _spec.illicit: _illicit_details(right)
	_populate_large_volume()
	_wall_finish()
	_lighting()
	# Thin rugs are intentionally walkable; they do not acquire solid envelopes.
	_box(Vector3(0, .015, _spec.size.y * .21), Vector3(1.75, .018, 1.25), _palette.cloth, "", "cloth")

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

func _desk(at: Vector3, id: String, program: String, compact: bool) -> void:
	var width := 1.55 if compact else 2.0
	_table_base(at, id, Vector2(width, .82), .90 if compact else .82)
	var y := .96 if compact else .88
	if program in ["reception", "press", "drafting", "meeting"]:
		_box(at + Vector3(.3, y + .31, -.1), Vector3(.58, .40, .06), "28383c", id, "metal")
		_box(at + Vector3(.3, y + .1, -.1), Vector3(.055, .25, .10), "737b79", id, "metal")
		_box(at + Vector3(.3, y + .015, .22), Vector3(.53, .025, .17), "3d4949", id, "metal")
		_box(at + Vector3(.3, y + .31, -.063), Vector3(.50, .32, .01), "618386", id, "glass")
	_papers(at + Vector3(-.33, y + .025, .18), id)
	_mug(at + Vector3(.62, y + .09, .14), id)
	_box(at + Vector3(-.49, y + .05, -.18), Vector3(.26, .1, .22), _palette.accent, id)

func _table_base(at: Vector3, id: String, size: Vector2, height := .78) -> void:
	_box(at + Vector3(0, height, 0), Vector3(size.x, .10, size.y), _palette.wood, id)
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]: _box(at + Vector3(side * (size.x * .5 - .11), height * .5, end * (size.y * .5 - .10)), Vector3(.085, height, .085), "575a53", id, "metal")
	_box(at + Vector3(0, height - .20, 0), Vector3(size.x - .16, .12, .065), "6d5945", id)

func _table(at: Vector3, id: String, papers: bool) -> void:
	_table_base(at, id, Vector2(1.85, .90))
	if papers: _papers(at + Vector3(-.30, .85, .1), id)
	else:
		for level in 3: _box(at + Vector3(.24, .87 + level * .055, 0), Vector3(.60, .05, .43), _palette.cloth, id, "cloth")
	_mug(at + Vector3(.54, .91, -.20), id)
	_chair(at + Vector3(-.53, 0, .78), id + "Chair")

func _chair(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, .47, 0), Vector3(.49, .11, .50), _palette.cloth, id, "cloth")
	_box(at + Vector3(0, .79, -.2), Vector3(.50, .56, .10), _palette.cloth, id, "cloth")
	for x in [-.18, .18]:
		for z in [-.18, .18]: _box(at + Vector3(x, .23, z), Vector3(.05, .46, .05), "575a53", id, "metal")

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

func _bed(at: Vector3, id: String) -> void:
	_box(at + Vector3(0, .24, 0), Vector3(1.55, .40, 2.13), _palette.wood, id)
	_box(at + Vector3(0, .51, 0), Vector3(1.50, .19, 2.06), "d4cbb8", id, "cloth")
	_box(at + Vector3(0, .64, .28), Vector3(1.51, .08, 1.44), _palette.cloth, id, "cloth")
	_box(at + Vector3(0, .56, -1.03), Vector3(1.61, 1.05, .12), _palette.wood, id)
	for side in [-1.0, 1.0]: _box(at + Vector3(side * .35, .68, -.70), Vector3(.59, .14, .39), "e0d6bf", id, "cloth")
	for z in [.12, .23]: _box(at + Vector3(0, .687, z), Vector3(1.52, .014, .045), "b9aa8d", id, "cloth")

func _kitchen(at: Vector3, id: String, compact: bool) -> void:
	var width := 1.65 if compact else 2.45
	_box(at + Vector3(0, .45, 0), Vector3(width, .90, .70), "7a8879", id)
	_box(at + Vector3(0, .945, 0), Vector3(width + .06, .09, .76), "c8c0ab", id, "stone")
	for side in [-1.0, 1.0]:
		_box(at + Vector3(side * width * .25, .50, .362), Vector3(width * .44, .65, .035), "879582", id)
		_box(at + Vector3(side * width * .25, .72, .394), Vector3(.18, .025, .045), "a9aca0", id, "metal")
	_box(at + Vector3(-width * .22, 1.0, -.03), Vector3(.53, .035, .45), "516b6d", id, "metal")
	_box(at + Vector3(-width * .22, 1.16, -.26), Vector3(.035, .34, .035), "b3b8b1", id, "metal")
	_box(at + Vector3(-width * .22, 1.32, -.19), Vector3(.035, .035, .19), "b3b8b1", id, "metal")
	_box(at + Vector3(width * .23, 1.0, .02), Vector3(.57, .03, .51), "303c3a", id, "metal")
	_cylinder(at + Vector3(.16, 1.115, .27), .16, .22, "6a7068", id)
	_cylinder(at + Vector3(.16, 1.233, .27), .135, .015, "9d8654", id, "ceramic")
	_mug(at + Vector3(-width * .42, 1.08, .15), id)
	_box(at + Vector3(0, 1.36, -.36), Vector3(width, .64, .03), "c2c1aa", id, "ceramic")
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
	_box(Vector3(x, 1.27, z), Vector3(1.15, .72, .34), _palette.wood, "WallCabinet")
	_box(Vector3(x, 1.26, z + .18), Vector3(1.04, .61, .035), _palette.cloth, "WallCabinet")
	_box(Vector3(x, 1.14, z + .21), Vector3(.18, .03, .025), "999e91", "WallCabinet", "metal")
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
	var variant: int = (_spec.seed + _spec.floor) % 3
	# Distinct wall installations, not just a palette swap of the same furniture.
	if _spec.program == "music":
		_box(Vector3(size.x * .5 - .4, .68, .4), Vector3(.42, 1.36, .72), "303e3e", "Speaker", "cloth")
		for y in [.40, .94]: _box(Vector3(size.x * .5 - .63, y, .4), Vector3(.035, .29, .30), "617573", "Speaker", "metal")
	elif variant == 0:
		_box(Vector3(size.x * .5 - .25, .53, .8), Vector3(.24, 1.06, 1.22), "a3a595", "Radiator", "metal")
		for rib in 8: _box(Vector3(size.x * .5 - .385, .54, .30 + rib * .14), Vector3(.035, .94, .045), "b6b6a4", "Radiator", "metal")
	elif variant == 1:
		_box(Vector3(size.x * .5 - .37, .26, .8), Vector3(.55, .52, .55), "8a7655", "Planter", "ceramic")
		for leaf in 5: _box(Vector3(size.x * .5 - .37 + sin(leaf * 2.0) * .13, .67 + leaf * .07, .80 + cos(leaf * 2.0) * .16), Vector3(.18, .28, .16), "5a7655", "Planter", "cloth")

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
		_box(Vector3(center, .54, z), Vector3(end - start, 1.08, .14), _palette.wall, id, "stone")
		_box(Vector3(center, 1.115, z), Vector3(end - start + .025, .07, .20), _palette.wood, id)
		# The low cutaway opens the real sightline; collision still matches its
		# volume. The generous opening next to the central hall is walkable.
		_box(Vector3(start + .18, .66, z + .087), Vector3(.23, .36, .025), "6c7d70", id, "paper")
	var wall_x := size.x * .5 - .48
	var cabinet_z := .83 if arrangement % 2 == 0 else 1.08
	var cabinet := "SideStorage"
	_box(Vector3(wall_x, .57, cabinet_z), Vector3(.52, 1.14, .95), _palette.wood, cabinet)
	for shelf in 3:
		_box(Vector3(wall_x - .272, .25 + shelf * .34, cabinet_z), Vector3(.015, .26, .80), _palette.cloth, cabinet, "cloth")
		_box(Vector3(wall_x - .29, .25 + shelf * .34, cabinet_z + .18), Vector3(.03, .04, .16), "aaa994", cabinet, "metal")
	for fold in 3: _box(Vector3(wall_x, 1.19 + fold * .045, cabinet_z), Vector3(.39, .04, .50), "b8af98", cabinet, "cloth")
	if size.x >= 12.0 and size.y >= 11.0 and _spec.front_side > 0 and not (_spec.floor == 0 and absf(_spec.entrance.x + _spec.x) < 1.80):
		_table(Vector3(-_spec.x, 0, size.y * .5 - 2.75), "SecondaryWork", _spec.family in ["office", "civic"])
	# Differently shaped rugs show the separate rear/front uses of the room.
	_box(Vector3(_spec.x, .018, _spec.back + .72), Vector3(2.22, .012, 2.06), _palette.cloth, "", "cloth")

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
			match family:
				"industrial":
					if _spec.source_id == "ColdStorage": _cold_unit(point, id)
					elif _extra_stations % 3 == 1: _pallet(point, id)
					else: _rack(point, id)
				"office": _desk(point, id, "drafting", false)
				"hospitality": _table(point, id, false)
				"retail":
					if _spec.program == "laundry": _laundry(point, id, false)
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
	match str(_spec.family):
		"residential":
			if size.x < 10.5:
				_compact_station("bed", Vector3(-2.68, 0, rear + 1.55))
				_compact_station("kitchen", Vector3(2.73, 0, -1.90 - offset))
				_compact_station("sofa", Vector3(-2.68, 0, front - 1.05))
			else:
				_compact_station("bed", Vector3(-size.x * .21, 0, rear + 1.18), PI * (.5 if arrangement % 2 == 0 else -.5))
				_compact_station("kitchen", Vector3(2.85 + offset, 0, rear + .72))
				_compact_station("sofa", Vector3(-size.x * (.25 if arrangement % 2 == 0 else .29), 0, front - .78))
		"office":
			var rear_use := "table" if _spec.program in ["meeting", "drafting"] else "archive"
			_compact_station(rear_use, Vector3(-2.68, 0, rear + (1.08 if rear_use == "table" else .68)))
			var middle_use := "kitchen" if _spec.program == "staff" else ("archive" if _spec.program == "records" else "desk")
			# Right-side work and left-side waiting rooms leave the entire stair
			# landing and the wall-side collectible approach unobstructed.
			_compact_station(middle_use, Vector3(2.72, 0, -1.90 - offset))
			_compact_station("sofa", Vector3(-2.68, 0, front - 1.05))
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
	_box(Vector3(0, 2.65, rear), Vector3(size.x - .30, .09, .11), "c7bda4")
	_box(Vector3(-x, 1.88, rear + .02), Vector3(.88, .67, .06), _palette.wood)
	_box(Vector3(-x, 1.88, rear + .058), Vector3(.75, .55, .014), "87978b", "", "paper")
	_box(Vector3(-x, 1.73, rear + .07), Vector3(.72, .17, .015), _palette.accent, "", "paper")
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
	for index in positions.size():
		var at: Vector3 = positions[index]
		_box(at + Vector3(0, .16, 0), Vector3(.045, .32, .045), "5d685f", "", "metal")
		_cylinder(at, .25, .14, _palette.accent, "", "metal")
		_cylinder(at - Vector3.UP * .08, .20, .026, "ffe2b5" if warm else "e8e9d6", "", "light")
		var light := OmniLight3D.new()
		light.name = "RoomPendant%d" % index
		light.position = at - Vector3.UP * .19
		light.light_color = Color("ffe2b5" if warm else "e8e9d6")
		light.light_energy = .90 if _spec.compact else 1.05
		light.omni_range = minf(10.0, maxf(size.x * .62, size.y * .42)) if positions.size() < 4 else minf(11.0, maxf(size.x, size.y) * .39)
		light.omni_attenuation = .85
		light.shadow_enabled = false
		# Test-only A/B retains the identical scene, material and fixture count.
		light.visible = not Engine.get_meta("harbor_building_lights_baseline", false)
		_model.add_child(light)
