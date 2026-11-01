extends RefCounted
## Zonas de atividade autoradas com lotes estáticos compartilhados, móveis em escala humana e
## envelopes exatos para o adaptador de colisão nativo. Sem laço de decoração por quadro.
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
## Móveis e objetos de vida em auxiliares (01/11, Onda 1 do plano de divisão), soltos no fim de populate.
const FURNITURE_KIT := preload("res://world/places/harbor_buildings/HarborFurnitureKit.gd")
const LIFE_OBJECTS := preload("res://world/places/harbor_buildings/HarborLifeObjects.gd")
var _furniture_kit: FURNITURE_KIT = FURNITURE_KIT.new(self)
var _life_objects_part: LIFE_OBJECTS = LIFE_OBJECTS.new(self)

static func populate(model: Node3D, definition: Dictionary, floor_index: int) -> Dictionary:
	var builder := new()
	builder._model = model
	builder._spec = CONTENT.floor_spec(definition, floor_index)
	builder._palette = builder._spec.palette
	builder._build()
	builder._flush()
	# Dono e auxiliares se referenciam (RefCounted): sem soltar, o andar montado nunca seria liberado.
	builder._furniture_kit = null
	builder._life_objects_part = null
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
	# O posto de trabalho principal sempre bate com a tarefa de mãos real do morador.
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

## Móveis: corpo em HarborFurnitureKit.gd (delegação de uma linha; mesmos nomes e padrões).
func _desk(at: Vector3, id: String, program: String, compact: bool) -> void: _furniture_kit._desk(at, id, program, compact)
func _table_base(at: Vector3, id: String, size: Vector2, height := .78) -> void: _furniture_kit._table_base(at, id, size, height)
func _table(at: Vector3, id: String, papers: bool) -> void: _furniture_kit._table(at, id, papers)
func _chair(at: Vector3, id: String) -> void: _furniture_kit._chair(at, id)
func _bookcase(at: Vector3, id: String, folders: bool) -> void: _furniture_kit._bookcase(at, id, folders)
func _sofa(at: Vector3, id: String) -> void: _furniture_kit._sofa(at, id)
func _bed(at: Vector3, id: String, single := false) -> void: _furniture_kit._bed(at, id, single)
func _kitchen(at: Vector3, id: String, compact: bool) -> void: _furniture_kit._kitchen(at, id, compact)
func _workbench(at: Vector3, id: String, compact: bool) -> void: _furniture_kit._workbench(at, id, compact)
func _packing(at: Vector3, id: String, compact: bool) -> void: _furniture_kit._packing(at, id, compact)
func _studio(at: Vector3, id: String, compact: bool) -> void: _furniture_kit._studio(at, id, compact)
func _shop_counter(at: Vector3, id: String, compact: bool) -> void: _furniture_kit._shop_counter(at, id, compact)
func _laundry(at: Vector3, id: String, compact: bool) -> void: _furniture_kit._laundry(at, id, compact)
func _rack(at: Vector3, id: String) -> void: _furniture_kit._rack(at, id)
func _pallet(at: Vector3, id: String) -> void: _furniture_kit._pallet(at, id)
func _easel(at: Vector3, id: String) -> void: _furniture_kit._easel(at, id)
func _display(at: Vector3, id: String) -> void: _furniture_kit._display(at, id)
func _aquarium(at: Vector3, id: String, compact: bool) -> void: _furniture_kit._aquarium(at, id, compact)
func _ship_exhibit(at: Vector3, id: String) -> void: _furniture_kit._ship_exhibit(at, id)

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
	# Um nicho estreito na parede com a tampa posta de lado sugere visualmente o esconderijo.
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
	# Instalações de parede distintas, não só uma troca de paleta dos mesmos móveis.
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
		# O corte baixo abre a linha de visão real; a colisão ainda bate com o
		# volume. A abertura generosa ao lado do salão central é caminhável.
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
	# Uma casa rasa ou uma torre estreita ainda pode ter uma área de piso grande.
	# Mantém as posições compactas de trabalhador/esconderijo, mas mobília as baias laterais usáveis
	# em escala humana. Cabines pequenas do porto mantêm a planta livre original.
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
			# Trabalho do lado direito e salas de espera do lado esquerdo deixam o patamar
			# inteiro da escada e o acesso ao colecionável junto à parede desobstruídos.
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
	# Estas são as extensões reais do corredor compacto e da escada, não um modelo
	# reduzido de humano ou de móvel. Um corpo de 60 cm mantém espaço nos dois corredores.
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
	# A espinha contínua e o patamar da escada continuam generosos mesmo numa loja cheia.
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
	# Um cômodo trancado também é mobiliado, mas os limites da frente/leste, o corredor
	# livre pela porta e o acesso ao esconderijo junto à parede ficam desocupados.
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
	# Contrabando fictício é comunicado por pacotes lacrados e uma balança de contagem
	# sem uso, sem placas nem qualquer instrução de produção do mundo real.
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
	# O eletroduto visível pertence ao cômodo construído; sem luzes ou efeitos duplicados.
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
		# O A/B só de teste mantém a cena, o material e a contagem de luminárias idênticos.
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

func _surface_items(at: Vector3, id: String, count: int, spread := .30) -> void: _furniture_kit._surface_items(at, id, count, spread)
func _bunk_bed(at: Vector3, id: String) -> void: _furniture_kit._bunk_bed(at, id)
func _tv_wall(at: Vector3, id: String) -> void: _furniture_kit._tv_wall(at, id)
func _tv_lounge(at: Vector3, id: String) -> void: _furniture_kit._tv_lounge(at, id)
func _armchairs(at: Vector3, id: String) -> void: _furniture_kit._armchairs(at, id)
func _dining(at: Vector3, id: String) -> void: _furniture_kit._dining(at, id)
func _piano(at: Vector3, id: String) -> void: _furniture_kit._piano(at, id)
func _canvas_stack(at: Vector3, id: String) -> void: _furniture_kit._canvas_stack(at, id)
func _filing(at: Vector3, id: String) -> void: _furniture_kit._filing(at, id)
func _tool_cabinet(at: Vector3, id: String) -> void: _furniture_kit._tool_cabinet(at, id)
func _barrels(at: Vector3, id: String) -> void: _furniture_kit._barrels(at, id)
func _crate_stack(at: Vector3, id: String) -> void: _furniture_kit._crate_stack(at, id)
func _engine_stand(at: Vector3, id: String) -> void: _furniture_kit._engine_stand(at, id)
func _clothes_rack(at: Vector3, id: String) -> void: _furniture_kit._clothes_rack(at, id)
func _laundry_carts(at: Vector3, id: String) -> void: _furniture_kit._laundry_carts(at, id)
func _whiteboard_table(at: Vector3, id: String) -> void: _furniture_kit._whiteboard_table(at, id)
func _coat_corner(at: Vector3, id: String) -> void: _furniture_kit._coat_corner(at, id)

## Objetos de vida e decoração de parede: corpo em HarborLifeObjects.gd (delegação de uma linha).
func _life_object(kind: String, at: Vector3, id: String) -> void: _life_objects_part._life_object(kind, at, id)
func _life_objects() -> void: _life_objects_part._life_objects()
func _wall_decor(rear: float, _x: float) -> void: _life_objects_part._wall_decor(rear, _x)

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
