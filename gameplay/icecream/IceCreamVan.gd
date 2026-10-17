extends Node3D
## Courier variant identified by persisted vehicle_id, including garage/save restore.
const PREFIX := "street_icecream_"
const GROUP := &"icecream_vans"
const KIT := preload("res://world/city_look/CityPropKit.gd")
const SURFACES := preload("res://runtime/VehicleSurfaceRoles.gd")
static var _livery: ArrayMesh
static var _roof_liveries: Dictionary = {}
static var _roof_heights: Dictionary = {}
static var _glass: Dictionary = {}
static var _visual_roof: Dictionary = {}
static var _clown: ArrayMesh
static var _song: AudioStreamWAV
static var enabled := true # Process-local A/B measurement only; never saved.
var car: CharacterBody3D
var song: AudioStreamPlayer3D
var crew: Node3D
var clock := 0.0

static func matches(vehicle: Node) -> bool:
	return vehicle.archetype == "courier_van" and str(vehicle.vehicle_id).begins_with(PREFIX)

static func attach(vehicle: CharacterBody3D) -> void:
	if not enabled or not matches(vehicle) or not is_instance_valid(vehicle.visual) or vehicle.has_node("IceCreamVan"): return
	var rig = load("res://gameplay/icecream/IceCreamVan.gd").new()
	rig.name = "IceCreamVan"
	rig.car = vehicle
	vehicle.add_child(rig)

static func choose(vehicles: Array) -> bool:
	var count := 0
	for vehicle in vehicles:
		if is_instance_valid(vehicle) and matches(vehicle) and vehicle.traffic and vehicle.health > 0: count += 1
	return count < 2 and (count == 0 or randf() < .25)

static func prewarm() -> void:
	if not enabled: return
	livery_mesh()
	clown_mesh()
	song_stream()
	# Altura do teto da courier sob a cortina: surface_get_arrays lê os vértices de volta do
	# servidor de render, e mesmo com o cache a primeira van que nascia no trânsito custava
	# 38,7 ms num quadro (serra, EXE de 17/10).
	if not _visual_roof.has("courier_van"):
		var visual: Node3D = preload("res://runtime/FleetCatalog.gd").create("courier_van")
		if visual != null:
			_visual_roof["courier_van"] = _paint_top(visual)
			# O vidro transparente também: o primeiro gerava shader novo na primeira van (19 ms,
			# serra perfinv7 de 17/10). Os materiais originais vêm da cena da frota, compartilhados.
			for part: MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
				if part.mesh == null or part.has_meta("wheel_center"): continue
				for surface in part.mesh.get_surface_count():
					if SURFACES.key(part,surface) != "glass": continue
					var original := part.get_active_material(surface) as StandardMaterial3D
					if original != null: _glass_for(original).get_rid()
			visual.free()
	# A pintura do teto também lê os vértices da pintura base (surface_get_arrays): monta a da
	# altura medida já aqui, que é a mesma chave quando o visual fica na origem do carro.
	if _visual_roof.has("courier_van") and is_finite(float(_visual_roof["courier_van"])):
		var top := float(_visual_roof["courier_van"])
		_livery_for_roof(top if top > 1.2 else 2.10)

## Ponto mais alto da pintura no espaço do nó raiz do visual, sem precisar estar na árvore.
static func _paint_top(root: Node3D) -> float:
	var height := -INF
	for part: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		var to_root := Transform3D.IDENTITY
		var node: Node = part
		while node != root and node is Node3D:
			to_root = (node as Node3D).transform * to_root
			node = node.get_parent()
		for surface in part.mesh.get_surface_count():
			if SURFACES.key(part,surface) != "paint": continue
			var vertices: PackedVector3Array = to_root * (part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			for vertex in vertices:
				if vertex.y > height: height = vertex.y
	return height

func _ready() -> void:
	add_to_group(GROUP)
	# Etapas medidas só com diagnóstico de sessão (a montagem custou 35 ms em 17/10).
	var traced := Time.get_ticks_usec() if preload("res://runtime/StallWorkTrace.gd").session_enabled else 0
	var roof_height := _roof_height()
	traced = _span("icecream_roof", traced)
	var art := MeshInstance3D.new()
	art.name = "SorveteLivery"
	art.mesh = _livery_for_roof(roof_height)
	add_child(art)
	traced = _span("icecream_livery", traced)
	crew = Node3D.new()
	crew.name = "Clowns"
	add_child(crew)
	for side in [-1,1]:
		var clown := MeshInstance3D.new()
		clown.mesh = clown_mesh()
		clown.position = Vector3(side*.43,.68,-.83)
		crew.add_child(clown)
	# The authored courier batches glass and paint in Body. Override only glass
	# surfaces; a node-wide override would also make its bodywork transparent.
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		for surface in part.mesh.get_surface_count():
			if SURFACES.key(part,surface) != "glass": continue
			var original := part.get_active_material(surface) as StandardMaterial3D
			if original != null:
				part.set_surface_override_material(surface,_glass_for(original))
	traced = _span("icecream_crew_glass", traced)
	song = AudioStreamPlayer3D.new()
	song.name = "IceCreamJingle"
	song.stream = song_stream()
	song.bus = &"Ambient"
	song.unit_size = 8.0
	song.max_distance = 48.0
	song.volume_db = -13.0
	song.max_db = -10.0
	song.position.y = 2.1
	add_child(song)
	traced = _span("icecream_song", traced)
	# Solid rooftop ornament; the existing road sensor keeps the van's dimensions.
	var roof := CollisionShape3D.new()
	roof.name = "IceCreamRoofCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(.7,.92,.7)
	roof.shape = shape
	roof.position = Vector3(0,roof_height+.50,.5)
	car.add_child(roof)
	_update_ambience()
	_span("icecream_roof_collision_ambience", traced)

## Um vidro por material original, compartilhado entre as vans.
static func _glass_for(original: StandardMaterial3D) -> StandardMaterial3D:
	if not _glass.has(original):
		var glass := original.duplicate() as StandardMaterial3D
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.albedo_color = Color(.68,.84,.9,.23)
		_glass[original] = glass
	return _glass[original]

func _span(label: String, began: int) -> int:
	if began == 0: return 0
	preload("res://runtime/SessionOperations.gd").completed(car, "vehicle", label, began)
	return Time.get_ticks_usec()

func _roof_height() -> float:
	# A courier's highest painted vertices are its roof. Read once on attachment,
	# before adding the ornament; wheels, windows and trim cannot move the mount.
	# Todas as vans usam as mesmas malhas do FleetCatalog: a varredura (vértice a vértice em
	# GDScript) custou 43 ms num quadro da serra no EXE de 17/10 e agora roda uma vez por
	# conjunto de malhas e posições, não a cada van que nasce no trânsito.
	# Caminho rápido: altura medida no pré-aquecimento, levada do visual para o carro.
	if _visual_roof.has(car.archetype) and is_finite(float(_visual_roof[car.archetype])):
		var top := car.to_local(car.visual.to_global(Vector3(0, float(_visual_roof[car.archetype]), 0))).y
		return top if top > 1.2 else 2.10
	var parts: Array[MeshInstance3D] = []
	var key := ""
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center"): continue
		parts.append(part)
		key += "%d:%s;" % [part.mesh.get_instance_id(), car.global_transform.affine_inverse() * part.global_transform]
	if _roof_heights.has(key): return _roof_heights[key]
	var height := 0.0
	for part in parts:
		var to_car: Transform3D = car.global_transform.affine_inverse() * part.global_transform
		for surface in part.mesh.get_surface_count():
			if SURFACES.key(part,surface) != "paint": continue
			# Transformação do array inteiro em código nativo; o laço só compara alturas.
			var vertices: PackedVector3Array = to_car * (part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
			for vertex in vertices:
				if vertex.y > height: height = vertex.y
	height = height if height > 1.2 else 2.10
	_roof_heights[key] = height
	return height

static func _livery_for_roof(height: float) -> ArrayMesh:
	var key := roundi(height*1000.0)
	if _roof_liveries.has(key): return _roof_liveries[key]
	var original := livery_mesh()
	var arrays := original.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX].duplicate()
	var offset := height-2.10
	for i in vertices.size():
		# Only the central roof ornament occupies this region. Side serving
		# windows, canopy, stripes and the separate clown meshes stay in place.
		if absf(vertices[i].x)<.5 and vertices[i].y>1.97:
			vertices[i].y += offset
	arrays[Mesh.ARRAY_VERTEX]=vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,original.surface_get_material(0))
	_roof_liveries[key]=mesh
	return mesh

func _process(delta: float) -> void:
	clock -= delta
	if clock > 0: return
	clock = .25
	_update_ambience()

func _update_ambience() -> void:
	crew.visible = car.traffic and not car.controlled and car.health > 0
	var active: bool = car.health > 0 and not car.engine_disabled and car.is_visible_in_tree() and car.is_physics_processing() and not car.get_meta("awaiting_ground",false)
	var world := car.get_parent()
	var listener := world.get("player") as Node3D
	if listener == null: listener = get_viewport().get_camera_3d()
	if listener == null: active = false
	elif active:
		var distance := global_position.distance_squared_to(listener.global_position)
		active = distance < 48.0*48.0
		var nearer := 0
		for other in get_tree().get_nodes_in_group(GROUP):
			if other == self or not other.car.is_visible_in_tree() or other.car.health <= 0 or other.car.engine_disabled or not other.car.is_physics_processing() or other.car.get_meta("awaiting_ground",false): continue
			var other_distance: float = other.global_position.distance_squared_to(listener.global_position)
			if other_distance < distance or (is_equal_approx(other_distance,distance) and other.get_instance_id() < get_instance_id()): nearer += 1
		active = active and nearer < 2
	if active and not song.playing:
		# Common musical clock keeps nearby trucks in phase.
		song.play(fmod(Time.get_ticks_msec()/1000.0,song.stream.get_length()))
	elif not active and song.playing: song.stop()

static func song_stream() -> AudioStreamWAV:
	if _song == null:
		_song = load("res://audio/icecream/jingle.wav") as AudioStreamWAV
		_song.loop_mode = AudioStreamWAV.LOOP_FORWARD
		_song.loop_begin = 0
		# Imported WAV may be QOA/ADPCM: loop points count frames, not PCM bytes.
		_song.loop_end = roundi(_song.get_length()*_song.mix_rate)
	return _song

static func _sphere(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var arrays := mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	tool.set_color(color)
	for index in indices: tool.add_vertex(center+vertices[index]*size)

static func _commit(tool: SurfaceTool) -> ArrayMesh:
	tool.generate_normals()
	tool.set_material(KIT.material())
	return tool.commit()

static func livery_mesh() -> ArrayMesh:
	if _livery != null: return _livery
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pink := Color("f56d98")
	var mint := Color("66d8c2")
	var cream := Color("fff1cc")
	for side in [-1,1]:
		KIT.box(t,Vector3(side*.978,.84,.8),Vector3(.024,.28,2.7),mint)
		KIT.box(t,Vector3(side*.994,1.04,.8),Vector3(.022,.065,2.7),pink)
		# Closed serving hatch and striped canopy, no decorative text.
		KIT.box(t,Vector3(side*.993,1.55,.75),Vector3(.035,.66,1.52),cream)
		KIT.box(t,Vector3(side*1.016,1.55,.75),Vector3(.018,.51,1.38),Color("405265"))
		KIT.box(t,Vector3(side*1.025,1.93,.75),Vector3(.19,.10,1.65),pink)
		for stripe in 7:
			KIT.box(t,Vector3(side*1.03,1.93,.04+stripe*.235),Vector3(.20,.105,.115),cream)
		for z in [.27,1.23]:
			KIT.cylinder(t,Vector3(side*1.04,1.31,z),.025,.20,Color("dfab64"),12,.10)
			_sphere(t,Vector3(side*1.04,1.58,z),Vector3(.025,.25,.25),pink if z<1 else mint)
		for dot in 8:
			_sphere(t,Vector3(side*.997,.73+(dot%2)*.18,-.1+dot*.27),Vector3(.025,.065,.065),cream)
	KIT.box(t,Vector3(0,2.15,.5),Vector3(.72,.10,.72),pink)
	KIT.cylinder(t,Vector3(0,2.19,.5),.09,.40,Color("dfab64"),12,.24)
	_sphere(t,Vector3(0,2.67,.5),Vector3(.60,.49,.60),pink)
	_sphere(t,Vector3(-.10,2.82,.49),Vector3(.35,.30,.35),cream)
	_sphere(t,Vector3(-.10,3.0,.49),Vector3(.11,.11,.11),Color("d5314e"))
	_livery = _commit(t)
	return _livery

static func clown_mesh() -> ArrayMesh:
	if _clown != null: return _clown
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	var white := Color("fff6e4")
	var red := Color("ee3854")
	_sphere(t,Vector3(0,.43,0),Vector3(.36,.46,.25),Color("53bcca"))
	for side in [-1,1]:
		_sphere(t,Vector3(side*.19,.36,-.14),Vector3(.13,.27,.28),Color("f2c650"))
		_sphere(t,Vector3(side*.17,.31,-.28),Vector3(.12,.12,.13),white)
		_sphere(t,Vector3(side*.10,.12,-.09),Vector3(.15,.22,.32),Color("53bcca"))
	_sphere(t,Vector3(0,.66,0),Vector3(.34,.095,.30),white)
	_sphere(t,Vector3(0,.84,0),Vector3(.29,.34,.28),white)
	for side in [-1,1]:
		_sphere(t,Vector3(side*.15,.86,.035),Vector3(.16,.23,.20),Color("f18b35"))
		_sphere(t,Vector3(side*.06,.88,-.128),Vector3(.036,.055,.024),Color("202638"))
		_sphere(t,Vector3(side*.087,.79,-.125),Vector3(.060,.055,.027),Color("ef8598"))
	_sphere(t,Vector3(0,.825,-.16),Vector3(.09,.09,.095),red)
	_sphere(t,Vector3(0,.746,-.13),Vector3(.115,.039,.024),red)
	_sphere(t,Vector3(0,.757,-.145),Vector3(.076,.015,.01),white)
	KIT.cylinder(t,Vector3(0,1.0,0),.11,.21,Color("9a70cf"),12,0)
	_sphere(t,Vector3(0,1.215,0),Vector3(.075,.075,.075),Color("f6d667"))
	for y in [.34,.46,.56]: _sphere(t,Vector3(0,y,-.132),Vector3(.065,.065,.04),red)
	_clown = _commit(t)
	return _clown
