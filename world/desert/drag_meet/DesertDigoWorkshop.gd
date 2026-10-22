extends Node3D
## An open service yard: no doorway transfer, ceiling over the actors, private
## viewport, traffic spawn or active light. Static pieces stream with the meet.
const G := preload("res://world/desert/DesertGeometry.gd")
const GOL := preload("res://gameplay/digo/DigoGolModel.gd")
const URBAN := preload("res://assets/urban_detail/UrbanMaterials.gd")
const FINISH := preload("res://world/places/ShopInteriorMaterials.gd")
const MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")
const YARD := preload("res://world/desert/drag_meet/DesertDigoYardDetails.gd")
const PARKING := Vector3(6,.08,-5.8)
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
## Capô sem a tampa fechada, uma vez por malha do Gol (21/10): a oficina monta no streaming do deserto
## e cada montagem lia as malhas de volta da GPU (surface_get_arrays) e refazia a malha. No estresse
## de release o registro inteiro custou 265 ms num quadro (stream.desert.record.drag_workshop).
## Agora a leitura vem da cópia na CPU (MeshArrayCache) e a malha limpa fica guardada por malha-fonte.
## GETECO_DIGO_HOOD_CACHE=0 volta ao caminho antigo (A/B).
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
static var _hood_cache_enabled := OS.get_environment("GETECO_DIGO_HOOD_CACHE") != "0"
static var _cleaned_hoods: Dictionary = {}
static var _finishes: Dictionary = {}
var solid_inventory: Array[Dictionary] = []

func _ready() -> void:
	name="DigoWorkshop"
	set_meta("desert_drag_workshop",true)
	var slab := G.box(self,"ServiceConcrete",Vector3(0,.019,0),Vector3(30,.012,24),Color("8c8678"),true)
	slab.material_override=URBAN.textured_wall(Color("767d78"),.97)
	# The north-facing bay has a low weathered back panel. Its former tall
	# wall and full awning completely hid the worker from the default camera.
	_solid("RearPanel",Vector3(-2,.525,4.5),Vector3(11,1.05,.16),Color("52646a"))
	for x in [.45,3.3]:
		_solid("AwningPost",Vector3(x,1.75,2.8),Vector3(.16,3.5,.16),Color("b4a582"))
		G.box(self,"RoofBrace",Vector3(x,3.32,3.5),Vector3(.16,.15,2.4),Color("797969"))
	var roof := G.box(self,"PartsStoreAwning",Vector3(1.9,3.58,3.72),Vector3(3.1,.09,2.05),Color("929789"))
	roof.rotation.x=-.045
	for i in 13:
		G.box(self,"CorrugatedRoofRib",Vector3(.42+float(i)*.246,3.65,3.72),Vector3(.035,.035,2.05),Color("8b8f82"))
	for x in [-3.6,-.4]:
		_solid("NameFrame",Vector3(x,1.5,4.5),Vector3(.08,3,.08),Color("686e5f"))
	G.box(self,"NamePlate",Vector3(-2,2.67,4.38),Vector3(3.3,.7,.06),Color("253e47"))
	var sign := Label3D.new()
	sign.text="Digo"
	sign.position=Vector3(-2,2.69,4.33)
	sign.rotation.y=PI
	sign.font_size=64
	sign.pixel_size=.012
	sign.outline_size=0
	sign.shaded=true
	sign.modulate=Color("e2d4b8")
	add_child(sign)
	var back_sign := sign.duplicate() as Label3D
	back_sign.position.z=4.43
	back_sign.rotation.y=0
	add_child(back_sign)
	_bench()
	var stage := STALL_WORK.begin()
	_car()
	STALL_WORK.finish_slow("desert.digo_workshop.car", stage, 2000)
	stage = STALL_WORK.begin()
	_tools()
	var yard := YARD.new()
	add_child(yard)
	STALL_WORK.finish_slow("desert.digo_workshop.yard", stage, 2000)
	stage = STALL_WORK.begin()
	_surface_wear()
	STALL_WORK.finish_slow("desert.digo_workshop.wear", stage, 2000)
	# Both service and customer bays are readable through paint alone.
	for x in [-1.6,1.6]: G.box(self,"ServiceBayPaint",Vector3(x,.033,-.2),Vector3(.055,.008,5.4),Color("c6b783"))
	for x in [3.8,8.2]: G.box(self,"CustomerBayPaint",Vector3(x,.033,-5.8),Vector3(.065,.008,5.5),Color("c6b783"))
	G.box(self,"CustomerBayEnd",Vector3(6,.033,-3.05),Vector3(4.4,.008,.065),Color("c6b783"))
	stage = STALL_WORK.begin()
	_apply_finishes(self)
	MATERIALS.batch_visuals(self)
	STALL_WORK.finish_slow("desert.digo_workshop.batch", stage, 2000)

func _bench() -> void:
	# One complete solid reserves the tabletop footprint, including its legs.
	var bench := _solid("Workbench",Vector3(-4.5,.48,2.4),Vector3(3,.96,.85),Color("4c5b5f"))
	var bench_shape: CollisionShape3D=bench.get_child(0).get_child(0)
	bench_shape.shape.size=Vector3(3.05,1.035,.90)
	bench_shape.position.y=.0375
	solid_inventory[-1].bounds=AABB(Vector3(-6.025,0,1.95),Vector3(3.05,1.035,.90))
	G.box(self,"WoodWorkbenchTop",Vector3(-4.5,.99,2.4),Vector3(3.05,.075,.90),Color("9b7950"))
	G.box(self,"ToolBoard",Vector3(-4.5,1.65,2.8),Vector3(3,.95,.045),Color("343d40"))
	for i in 7:
		var x := -5.65+float(i)*.34
		G.box(self,"HungTool",Vector3(x,1.62,2.76),Vector3(.025,.24+float(i%3)*.055,.018),Color("a1a5a3"))
		G.box(self,"ToolHead",Vector3(x,1.77,2.75),Vector3(.075,.04,.023),Color("a1a5a3"))
	G.box(self,"BenchVise",Vector3(-5.55,1.15,2.24),Vector3(.32,.25,.28),Color("4c6878"))
	G.box(self,"BenchViseJaw",Vector3(-5.55,1.26,2.06),Vector3(.35,.055,.06),Color("a8aca8"))
	G.cylinder(self,"TurboHousing",Vector3(-4.4,1.16,2.34),.16,.20,Color("95998f"))
	G.box(self,"BlueWorkRag",Vector3(-3.73,1.035,2.14),Vector3(.4,.015,.25),Color("445c6e"))
	bench.set_meta("work_surface",true)

func _car() -> void:
	var car := Node3D.new()
	car.name="GolUnderRepair"
	add_child(car)
	var model := GOL.new()
	car.add_child(model)
	# The original shared Gol resources are untouched. This presentation hides
	# only the closed bonnet triangles in its own copy before opening the hood.
	for panel: MeshInstance3D in model.get_children():
		if not panel.mesh is ArrayMesh: continue
		var cleaned := _without_closed_hood(panel.mesh)
		if cleaned!=null: panel.mesh=cleaned
		# The parked repair car is oxidised/satin. Never change the shared Gol
		# resources used by Digo's real racer or the motocross car.
		if panel.material_override is StandardMaterial3D:
			var worn: StandardMaterial3D=panel.material_override.duplicate()
			worn.roughness=maxf(worn.roughness,.78)
			worn.metallic=minf(worn.metallic,.25)
			worn.metallic_specular=.22
			panel.material_override=worn
	var body := StaticBody3D.new()
	body.name="RepairCarSolid"
	body.collision_layer=1
	body.collision_mask=0
	car.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(1.95,1.5,3.92)
	collider.shape=shape
	collider.position=Vector3(0,.75,0)
	body.add_child(collider)
	solid_inventory.append({"id":"RepairCarSolid","bounds":AABB(Vector3(-.975,0,-1.96),shape.size)})
	G.box(car,"DarkEngineBay",Vector3(0,.925,-1.24),Vector3(1.45,.035,1.0),Color("252b2c"))
	G.box(car,"EngineHead",Vector3(-.13,1.015,-1.23),Vector3(.68,.16,.60),Color("8a9290"))
	G.box(car,"EngineCover",Vector3(-.13,1.112,-1.23),Vector3(.52,.032,.46),Color("404b4d"))
	for i in 4: G.box(car,"PlugLead",Vector3(-.32+float(i)*.125,1.138,-1.23),Vector3(.023,.014,.36),Color("303235"))
	G.box(car,"Battery",Vector3(.48,1.005,-1.22),Vector3(.28,.20,.38),Color("22292d"))
	var bonnet := Node3D.new()
	bonnet.name="OpenBonnet"
	bonnet.position=Vector3(0,.94,-.64)
	bonnet.rotation.x=.72
	car.add_child(bonnet)
	G.box(bonnet,"BonnetSkin",Vector3(0,-.01,-.60),Vector3(1.60,.045,1.2),Color("bcc2c4"),true)
	G.box(bonnet,"BonnetInner",Vector3(0,.023,-.60),Vector3(1.43,.018,1.08),Color("677176"))
	var rod_base := Vector3(.62,.93,-1.62)
	var rod_top := bonnet.transform*Vector3(.62,.012,-1.0)
	var stay := G.cylinder(car,"BonnetStay",(rod_base+rod_top)*.5,.012,rod_base.distance_to(rod_top),Color("59635d"),true)
	stay.basis=Basis(Quaternion(Vector3.UP,(rod_top-rod_base).normalized()))
	# High hood geometry stays inside the car's reserved footprint.

func _without_closed_hood(source: ArrayMesh) -> ArrayMesh:
	if not _hood_cache_enabled: return _build_without_closed_hood(source, source.surface_get_arrays(0).duplicate())
	if _cleaned_hoods.has(source):
		var cached: Variant = _cleaned_hoods[source]
		return cached as ArrayMesh
	# A cópia compartilhada do MeshArrayCache não pode ser alterada: o índice novo vai numa cópia rasa.
	var cleaned := _build_without_closed_hood(source, MESH_ARRAYS.arrays_of(source, 0).duplicate())
	_cleaned_hoods[source] = cleaned
	return cleaned

## Sob a cortina (ProductionWorld._prewarm_regions): as malhas limpas do Gol ficam prontas antes de a
## oficina entrar no streaming, e as leituras da GPU acontecem no carregamento.
static func prewarm_hoods() -> void:
	if not _hood_cache_enabled: return
	var model := GOL.new()
	for panel in model.get_children():
		if not panel is MeshInstance3D or not (panel as MeshInstance3D).mesh is ArrayMesh: continue
		var source: ArrayMesh = (panel as MeshInstance3D).mesh
		if _cleaned_hoods.has(source): continue
		_cleaned_hoods[source] = _build_without_closed_hood(source, MESH_ARRAYS.arrays_of(source, 0).duplicate())
	model.free()

static func _build_without_closed_hood(_source: ArrayMesh, arrays: Array) -> ArrayMesh:
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	var removed := false
	for i in range(0,indices.size(),3):
		var closed_hood := true
		for k in 3:
			var v := vertices[indices[i+k]]
			closed_hood=closed_hood and absf(v.x)>.78 and absf(v.x)<.82 and ((absf(v.z+1.82)<.001 and absf(v.y-.86)<.001) or (absf(v.z+.64)<.001 and absf(v.y-.94)<.001))
		if closed_hood: removed=true
		else:
			for k in 3: kept.append(indices[i+k])
	if not removed: return null
	arrays[Mesh.ARRAY_INDEX]=kept
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _tools() -> void:
	_solid("ToolChest",Vector3(-6.65,.55,.35),Vector3(1,1.1,.70),Color("a44737"))
	for i in 5: G.box(self,"DrawerHandle",Vector3(-6.65,.20+float(i)*.17,-.009),Vector3(.72,.025,.03),Color("c3c3b7"))
	_solid("PartsCabinet",Vector3(1.95,1.03,3.82),Vector3(1.7,2.06,.65),Color("536268"),false)
	G.box(self,"CabinetBack",Vector3(1.95,1.03,4.13),Vector3(1.7,2.06,.04),Color("536268"))
	for x in [1.125,2.775]: G.box(self,"CabinetSide",Vector3(x,1.03,3.82),Vector3(.05,2.06,.65),Color("65756b"))
	for y in [.04,.59,1.14,1.69,2.06]: G.box(self,"CabinetShelf",Vector3(1.95,y,3.82),Vector3(1.7,.055,.65),Color("a2a18e"))
	for x in [1.38,1.95,2.52]:
		G.box(self,"PartsBox",Vector3(x,1.89,3.78),Vector3(.48,.34,.4),Color("a9936f"))
	for x in [-6.55,-5.5]:
		_solid("SpareTyreStack",Vector3(x,.44,-3.45),Vector3(.72,.88,.72),Color("292b2b"),false)
		for tier in 3:
			G.cylinder(self,"SpareTyre",Vector3(x,.15+float(tier)*.28,-3.45),.36,.27,Color("202425"))
		G.cylinder(self,"WheelRim",Vector3(x,.89,-3.45),.23,.03,Color("9caaa8"))
	_solid("Compressor",Vector3(2.55,.49,1.25),Vector3(.95,.98,.65),Color("ab5140"))
	G.cylinder(self,"CompressorMotor",Vector3(2.55,1.02,1.25),.20,.24,Color("444c4b"))
	# Real motor fins, wheels and gauge make the compressor readable at play
	# distance, while its complete footprint remains reserved by one body.
	for i in 5: G.box(self,"CompressorFin",Vector3(2.55,.98+float(i)*.045,1.25),Vector3(.47,.018,.40),Color("6e7770"))
	G.cylinder(self,"CompressorGauge",Vector3(2.55,1.25,1.05),.075,.035,Color("c0c1b0")).rotation.x=PI*.5

func _surface_wear() -> void:
	for i in 24:
		var x := -7.25+float(i)*.455
		G.box(self,"PanelRib",Vector3(x,.53,4.405),Vector3(.032,1.04,.034),Color("5c6c6a"))
		if i%3==0: G.box(self,"PanelRust",Vector3(x,.19+float(i%5)*.14,4.38),Vector3(.11,.20,.008),Color("845e46"))
	for x in [-10,-5,0,5,10]:
		G.box(self,"ConcreteJoint",Vector3(x,.027,0),Vector3(.018,.002,24),Color("565950"))
	for z in [-8,-4,0,4,8]:
		G.box(self,"ConcreteJoint",Vector3(0,.027,z),Vector3(30,.002,.018),Color("565950"))
	for i in 12:
		var mark := G.box(self,"ConcreteCrack",Vector3(-13+float(i)*2.2,.029,-9+float(i%4)*5.5),Vector3(.025,.002,1.6),Color("4f544c"))
		mark.rotation.y=float(i)*.81

func _apply_finishes(node: Node) -> void:
	if node.name in ["GolUnderRepair","DigoYardDetails","ServiceConcrete"]: return
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		var color: Color=node.material_override.albedo_color
		var kind := "metal"
		var label := str(node.name)
		if "Wood" in label or "PartsBox" in label: kind="wood"
		elif "Rag" in label: kind="cloth"
		elif "Tyre" in label: kind="rubber"
		var key := kind+color.to_html()
		if not _finishes.has(key):
			var material: StandardMaterial3D=FINISH.material(kind,color).duplicate()
			material.uv1_world_triplanar=true
			material.roughness=.91
			material.metallic=.12 if kind=="metal" else 0.0
			_finishes[key]=material
		node.material_override=_finishes[key]
	for child in node.get_children(): _apply_finishes(child)

func _solid(id: String, at: Vector3, size: Vector3, color: Color, visible_mesh := true) -> Node3D:
	var holder: Node3D
	if visible_mesh: holder=G.box(self,id,at,size,color,true)
	else:
		holder=Node3D.new()
		holder.name=id
		holder.position=at
		add_child(holder)
		G.collision(holder,size)
	holder.set_meta("interior_solid_id",id)
	solid_inventory.append({"id":id,"bounds":AABB(at-size*.5,size)})
	return holder
