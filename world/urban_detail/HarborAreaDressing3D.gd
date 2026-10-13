extends Node3D
## V1-authored ground finish, vegetation and street furniture for the Harbor
## districts that were previously represented only by their principal model.

const SCALE := 1.0/16.0
const GROUND := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
const GRASS := preload("res://world/urban_detail/HarborGrassTufts.gd")
const COBRA_FINISH := preload("res://world/urban_detail/CobraMaterials.gd")
## Portão norte do cemitério (OriginalCemetery3D, -350 px da V1): caminho do carro funerário.
const CEMETERY_GATE := Vector2(0, -350) * (1.0/16.0)
var zone_id := ""
static var _materials: Dictionary = {}
static var _box_meshes: Dictionary = {}
static var _cylinder_meshes: Dictionary = {}
static var _sphere_meshes: Dictionary = {}
var _solid_root: StaticBody3D
var _cobra_paths: Array = []
var _cobra_joints: Dictionary = {}
var _cobra_joint_counts: Dictionary = {}

func configure(id: String) -> void:
	zone_id = id

func _ready() -> void:
	name = zone_id.to_pascal_case()+"Dressing"
	set_meta("source_id",_source_id())
	_solid_root = StaticBody3D.new()
	_solid_root.name = "AuthoredDressingSolids"
	_solid_root.collision_layer = 1
	_solid_root.collision_mask = 0
	add_child(_solid_root)
	match zone_id:
		"cobra": _build_cobra()
		"salvage": _build_salvage()
		"cemetery": _build_cemetery_edge()

func _source_id() -> String:
	match zone_id:
		"cobra": return "world/harbor/cobras/CobraNeighborhood.gd"
		"salvage": return "cars/ChopShopZone.gd"
		"cemetery": return "world/harbor/HarborCemetery.gd"
	return ""

func _build_salvage() -> void:
	# SalvageLocation.LAND and the exact V1 perimeter planting, local to (-750,550).
	# Gramado com textura e tufos 3D: antes era uma caixa de cor lisa (feedback de 25/09).
	var meadow := _box("SalvageMeadow",Vector3(15*SCALE,.006,10*SCALE),Vector3(1270*SCALE,.012,1120*SCALE),Color("46553e"))
	meadow.material_override = GRASS.ground_material()
	_box("SalvageNorthWall",Vector3(15*SCALE,.34,-534*SCALE),Vector3(1270*SCALE,.68,12*SCALE),Color("9b9c8c"),true)
	_box("SalvageWestWall",Vector3(-614*SCALE,.34,10*SCALE),Vector3(12*SCALE,.68,1120*SCALE),Color("9b9c8c"),true)
	for index in 12:
		var point: Vector2 = [Vector2(-500,-430),Vector2(-320,-465),Vector2(120,-460),Vector2(430,-465),Vector2(510,-410),Vector2(350,430),Vector2(440,430),Vector2(-565,-240),Vector2(-565,40),Vector2(575,-220),Vector2(575,80),Vector2(575,310)][index]
		_tree(point*SCALE,1.0+float(index%3)*.09,index%3==1)
	for point in [Vector2(-70,-445),Vector2(285,-430)]: _rock(point*SCALE,1.5)
	# Acesso de cascalho da V1: abaixo do asfalto (topo em 1 cm; a rua fica em 3 cm), só
	# aparece como acostamento. Antes ficava por cima e pintava a rua de bege liso.
	var route := [Vector2(-500,700),Vector2(-500,450),Vector2(0,450),Vector2(0,150)]
	var track_rects: Array = []
	for index in range(route.size()-1):
		var track := _beam("SalvageTrack",route[index]*SCALE,route[index+1]*SCALE,100*SCALE,.012,Color("8a8269"),false,.004)
		track.material_override = GRASS.ground_material("gravel")
		track_rects.append(Rect2(route[index]*SCALE,Vector2.ZERO).expand(route[index+1]*SCALE).grow(50*SCALE+.4))
	var meadow_area := Rect2(Vector2(15-635,10-560)*SCALE,Vector2(1270,1120)*SCALE)
	# Pátio de cascalho do SalvageYardNative (32 x 23 m, mesma origem) fica sem grama.
	GRASS.scatter(self,meadow_area,track_rects+[Rect2(-17.5,-13,35,26)],.8,7501)

func _build_cemetery_edge() -> void:
	# The cemetery owns its inner floor. These four strips restore only the V1
	# green/tree context around it, avoiding a coplanar duplicate under graves.
	var outer := Vector2(990,900)*SCALE
	var inner := Vector2(780,700)*SCALE
	var border_x := (outer.x-inner.x)*.5
	var border_z := (outer.y-inner.y)*.5
	for strip in [
		["CemeteryNorthGreen",Vector3(0,.006,-(inner.y+border_z)*.5),Vector3(outer.x,.012,border_z)],
		["CemeterySouthGreen",Vector3(0,.006,(inner.y+border_z)*.5),Vector3(outer.x,.012,border_z)],
		["CemeteryWestGreen",Vector3(-(inner.x+border_x)*.5,.006,0),Vector3(border_x,.012,inner.y)],
		["CemeteryEastGreen",Vector3((inner.x+border_x)*.5,.006,0),Vector3(border_x,.012,inner.y)]]:
		var green := _box(strip[0],strip[1],strip[2],Color("445441"))
		green.material_override = GRASS.ground_material()
	# Faixa livre do portão até a rua: o carro funerário para a 90 px do portão.
	var gate_lane := Rect2(CEMETERY_GATE.x-4.0,-outer.y*.5-1.0,8.0,outer.y*.5+CEMETERY_GATE.y+1.0)
	GRASS.scatter(self,Rect2(-outer*.5,outer),[Rect2(-inner*.5,inner),gate_lane],.8,7502)
	for index in 12:
		var angle := TAU*float(index)/12.0
		var point := Vector2(cos(angle)*outer.x*.44,sin(angle)*outer.y*.43)
		# A árvore do norte ficava em cima do caminho do carro funerário, na frente do portão.
		if gate_lane.grow(1.5).has_point(point): continue
		_tree(point,.88+float(index%3)*.08,index%4==0)

func _build_cobra() -> void:
	# CobraNeighborhood.VISUAL_LAND, local to the authored roundabout centre.
	var visual_center := (Vector2(7640,1685)-Vector2(7700,1700))*SCALE
	var meadow:=_box("CobraDryMeadow",Vector3(visual_center.x,.006,visual_center.y),Vector3(1760*SCALE,.012,1450*SCALE),Color("64724f"))
	meadow.material_override=COBRA_FINISH.ground()
	var approach_ground:=_box("CobraApproachGround",Vector3(-720*SCALE,.015,0),Vector3(940*SCALE,.012,240*SCALE),Color("777361"))
	approach_ground.material_override=COBRA_FINISH.ground("gravel")
	var island := MeshInstance3D.new()
	island.name = "CobraCommunalGarden"
	var island_mesh := CylinderMesh.new()
	island_mesh.top_radius = 200*SCALE
	island_mesh.bottom_radius = 200*SCALE
	island_mesh.height = .025
	island_mesh.radial_segments = 48
	island.mesh = island_mesh
	island.position.y = .025
	island.material_override = COBRA_FINISH.ground()
	add_child(island)
	var emblem := MeshInstance3D.new()
	emblem.name = "CobraEmblem"
	emblem.mesh = preload("res://world/urban_detail/CobraMaterials.gd").emblem()
	emblem.position = Vector3(0,.041,-1.875)
	var paint := StandardMaterial3D.new()
	paint.vertex_color_use_as_albedo = true
	paint.vertex_color_is_srgb = true
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.roughness = .96
	emblem.material_override = paint
	island.add_child(emblem)
	var pad := MeshInstance3D.new()
	pad.name = "EmblemPaving"
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 3.0
	pad_mesh.bottom_radius = 3.0
	pad_mesh.height = .012
	pad_mesh.radial_segments = 48
	pad.mesh = pad_mesh
	pad.position = Vector3(0,.024,-1.875)
	pad.material_override = _surface_material("concrete",Color("343c33"))
	island.add_child(pad)
	for route in [
		[Vector2(7580,1680),Vector2(7845,1770)],
		[Vector2(7695,1728),Vector2(7692,1635),_cobra_garden_gate()]]:
		for index in range(route.size()-1): _beam("CobraGardenPath",(route[index]-Vector2(7700,1700))*SCALE,(route[index+1]-Vector2(7700,1700))*SCALE,30*SCALE,.018,Color("9b9077"))
	var pedestrian_routes := [
		[Vector2(6730,1580),Vector2(7220,1580),Vector2(7250,1450),Vector2(7290,1290),Vector2(7730,1290),Vector2(8150,1290),Vector2(8150,1760)],
		[Vector2(6730,1820),Vector2(7200,1820),Vector2(7300,2080),Vector2(7750,2080),Vector2(8170,2080),Vector2(8170,1760)],
		[Vector2(7700,1290),Vector2(7740,1040)],
		[Vector2(7750,2080),Vector2(7750,2360)],
	]
	for route in pedestrian_routes:
		for index in range(route.size()-1):
			var a: Vector2=(route[index]-Vector2(7700,1700))*SCALE
			var b: Vector2=(route[index+1]-Vector2(7700,1700))*SCALE
			_beam("CobraFootpathEdge",a,b,36*SCALE,.013,Color("99917b"))
			_beam("CobraFootpath",a,b,29*SCALE,.015,Color("827e6c"))
	var entrance_paths := [
		[Vector2(7090,1420),Vector2(7090,1580)],[Vector2(7535,1225),Vector2(7535,1290)],
		[Vector2(7962.5,1265),Vector2(7962.5,1290)],
		[Vector2(8340,1645),Vector2(8340,1750),Vector2(8150,1750)],
		[Vector2(8368,2053),Vector2(8368,2110),Vector2(8170,2110),Vector2(8170,2080)],
		[Vector2(8000,2340),Vector2(8000,2360),Vector2(7750,2360)],
		[Vector2(7550,2315),Vector2(7550,2360),Vector2(7750,2360)],
		[Vector2(7047.5,2165),Vector2(7047.5,2200),Vector2(7220,2200),Vector2(7220,1820)],
	]
	for route in entrance_paths:
		for index in range(route.size()-1): _beam("CobraEntrancePath",(route[index]-Vector2(7700,1700))*SCALE,(route[index+1]-Vector2(7700,1700))*SCALE,20*SCALE,.017,Color("9e9580"))
	var secret_drive := [Vector2(7050,2290),Vector2(7220,2290),Vector2(7220,1700)]
	for index in range(secret_drive.size()-1): _beam("CobraSecretDrive",(secret_drive[index]-Vector2(7700,1700))*SCALE,(secret_drive[index+1]-Vector2(7700,1700))*SCALE,64*SCALE,.016,Color("837d67"))
	var sites := [
		Rect2(6980,1260,220,160),Rect2(7410,1060,250,165),Rect2(7850,1110,225,155),Rect2(8230,1390,220,255),
		Rect2(8250,1890,205,170),Rect2(7870,2170,260,170),Rect2(7440,2170,220,145),Rect2(6930,2010,235,155),
	]
	for site in sites:
		var lot: Rect2=(site as Rect2).grow(26)
		var lot_center: Vector2=(lot.get_center()-Vector2(7700,1700))*SCALE
		var gravel:=_box("CobraHomeGravel",Vector3(lot_center.x,.012,lot_center.y),Vector3(lot.size.x*SCALE,.012,lot.size.y*SCALE),Color("8c866c"))
		gravel.material_override=COBRA_FINISH.ground("gravel")
	var workshop:=_box("CobraWorkshopForecourt",Vector3((8355-7700)*SCALE,.018,(1745-1700)*SCALE),Vector3(270*SCALE,.012,150*SCALE),Color("8c8977"))
	workshop.material_override=COBRA_FINISH.ground("gravel")
	var secret_parking:=_box("CobraSecretParking",Vector3((7065-7700)*SCALE,.018,(2292.5-1700)*SCALE),Vector3(270*SCALE,.012,145*SCALE),Color("7b735e"))
	secret_parking.material_override=COBRA_FINISH.ground("gravel")
	for x in [6960.0,7050.0,7140.0]:
		var local_x: float = (float(x)-7700.0)*SCALE
		_box("CobraParkingStripe",Vector3(local_x,.037,(2290.0-1700.0)*SCALE),Vector3(.09,.012,6.9),Color("c2baa1"))
		_box("CobraParkingWheelStop",Vector3(local_x+2.75,.16,(2250.0-1700.0)*SCALE),Vector3(.75,.28,.18),Color("9b9787"),true)
	for z in [2240.0,2310.0]:
		_box("CobraParkingOilWear",Vector3((7050.0-7700.0)*SCALE,.035,(z-1700.0)*SCALE),Vector3(.85,.008,.48),Color("4c4b40"))
	_beam("CobraEasternCoast",Vector2(800,-740)*SCALE,Vector2(800,710)*SCALE,34*SCALE,.035,Color("9b9580"),true,.02)
	var features := [
		[Vector2(7580,1610),1.25,false],[Vector2(7730,1820),1.15,false],
		[Vector2(6800,1100),1.30,false],[Vector2(6910,1130),.78,true],
		[Vector2(7240,1090),.86,true],[Vector2(7340,2350),.82,true],
		[Vector2(8370,2230),.90,true],[Vector2(6830,1510),.92,false],
		[Vector2(6840,1910),1.0,false],[Vector2(7110,1050),.86,true],
		[Vector2(8110,1070),.96,false],[Vector2(8400,2140),.84,true],
		[Vector2(8240,2310),.90,false],[Vector2(7330,2250),.88,true],
		[Vector2(7860,1600),1.0,false],[Vector2(7830,1840),.92,false]]
	for feature in features:
		_tree((feature[0]-Vector2(7700,1700))*SCALE,float(feature[1]),bool(feature[2]))
	for point in [Vector2(8410,1040),Vector2(8445,2340)]: _rock((point-Vector2(7700,1700))*SCALE,1.45)
	for point in [Vector2(6890,1635),Vector2(7170,1765),Vector2(7450,1450),Vector2(7980,1450),Vector2(8010,1920),Vector2(7450,1960)]: _lamp((point-Vector2(7700,1700))*SCALE)
	for point in [Vector2(7185,1615),Vector2(7375,1400),Vector2(8185,1730)]: _barrel((point-Vector2(7700,1700))*SCALE)
	for point in [Vector2(7300,1625),Vector2(7300,1775)]: _tire_barricade((point-Vector2(7700,1700))*SCALE)
	for point in [Vector2(7630,1570),Vector2(7820,1740),Vector2(7600,1840)]: _bench((point-Vector2(7700,1700))*SCALE)
	for fence in [[Vector2(6870,1230),Vector2(6870,1440)],[Vector2(7380,1005),Vector2(7650,1005)],[Vector2(7860,2385),Vector2(8150,2385)]]:
		var a: Vector2 = (fence[0]-Vector2(7700,1700))*SCALE
		var b: Vector2 = (fence[1]-Vector2(7700,1700))*SCALE
		_beam("CobraYardFence",a,b,.28,1.05,Color("aaa082"),true,.55)
	# Supporting marks at the approach: no labels, only the Cobra insignia.
	for z in [-6.8,6.8]:
		var panel := _box("CobraTerritoryPanel",Vector3(-26,2.05,z),Vector3(.12,2.5,2.2),Color("222b25"),true)
		for offset in [-.85,.85]: _box("CobraPanelSupport",Vector3(-26,.75,z+offset),Vector3(.12,1.5,.12),Color("34352e"),true)
		for side in [-1.0,1.0]:
			var insignia := MeshInstance3D.new()
			insignia.name = "CobraInsignia"
			insignia.mesh = COBRA_FINISH.emblem()
			insignia.material_override = paint
			insignia.position = Vector3(side*.065,0,0)
			insignia.rotation = Vector3(PI*.5,side*PI*.5,0)
			insignia.scale = Vector3.ONE*.35
			panel.add_child(insignia)
	for point in [Vector2(7140,1620),Vector2(7200,1790),Vector2(7385,1405),Vector2(8410,1795)]: _barrel((point-Vector2(7700,1700))*SCALE)
	_connect_cobra_crossings()
	_build_cobra_joints()
	_scatter_grass()

func _connect_cobra_crossings() -> void:
	var region: Node=get_parent()
	while region!=null and not ("harbor_road_geometry" in region): region=region.get_parent()
	if region==null or region.harbor_road_geometry==null: return
	var geometry=region.harbor_road_geometry
	var authored := _cobra_paths.duplicate()
	for road in geometry._roads:
		var id := str(road.id).get_file()
		if id not in ["cobra_approach","cobra_court_northwest"] or not road.crossings: continue
		var sample: Dictionary=geometry._sample_polyline(road.points,.78 if id=="cobra_approach" else .90)
		if sample.is_empty(): continue
		var center: Vector2=sample.position-Vector2(global_position.x,global_position.z)
		var normal: Vector2=sample.tangent.orthogonal()
		for side in [-1.0,1.0]:
			var edge: Vector2=center+normal*side*_cobra_crossing_edge(road)
			var nearest:=Vector2.INF
			var distance:=6.0
			for segment in authored:
				var p:=Geometry2D.get_closest_point_to_segment(edge,segment[0],segment[1])
				if (p-center).dot(normal)*side<float(road.width)*.5: continue
				if p.distance_to(edge)<distance: nearest=p; distance=p.distance_to(edge)
			if nearest.is_finite() and distance>.8:
				_beam("CobraCrossingLink",edge,nearest,1.625,.018,Color("606653"),false,.025)

func _cobra_garden_gate() -> Vector2:
	var region: Node=get_parent()
	while region!=null and not ("harbor_road_geometry" in region): region=region.get_parent()
	if region==null or region.harbor_road_geometry==null: return Vector2(7700,1444)
	var geometry=region.harbor_road_geometry
	for road in geometry._roads:
		if str(road.id).get_file()!="cobra_court_northwest": continue
		var sample: Dictionary=geometry._sample_polyline(road.points,.90)
		if sample.is_empty(): continue
		var normal: Vector2=sample.tangent.orthogonal()
		var side:=signf((Vector2(global_position.x,global_position.z)-(sample.position as Vector2)).dot(normal))
		var gate: Vector2=sample.position+normal*side*_cobra_crossing_edge(road)
		return (gate-Vector2(global_position.x,global_position.z))/SCALE+Vector2(7700,1700)
	return Vector2(7700,1444)

func _cobra_crossing_edge(road: Dictionary) -> float:
	# Finish directly against the visible tactile paving, not an assumed verge.
	var sidewalk: float=road.sidewalk_width
	return float(road.width)*.5+minf(sidewalk*.5,.75)+minf(sidewalk,.75)*.5-.025

func _build_cobra_joints() -> void:
	# Rounded, flush caps close the inside/outside corners of every joined strip.
	# All caps share two meshes and world-space paving rather than separate props.
	for border in [true,false]:
		var tool:=SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for point in _cobra_joints:
			if int(_cobra_joint_counts.get(point,0))<2: continue
			var spec: Vector2=_cobra_joints[point]
			var radius: float=spec.x*.5+(.20 if border else 0.0)
			var y: float=spec.y+(.0005 if border else .003)
			for segment in 16:
				for a in [Vector2.ZERO,Vector2(cos((segment+1)*TAU/16),sin((segment+1)*TAU/16))*radius,Vector2(cos(segment*TAU/16),sin(segment*TAU/16))*radius]:
					tool.set_normal(Vector3.UP)
					tool.add_vertex(Vector3(point.x+a.x,y,point.y+a.y))
		var mesh:=MeshInstance3D.new()
		mesh.name="CobraPathCornersEdge" if border else "CobraPathCorners"
		mesh.mesh=tool.commit()
		mesh.material_override=_surface_material("concrete" if border else "stone",Color("606353") if border else Color("606653"))
		add_child(mesh)

func _scatter_grass() -> void:
	preload("res://world/urban_detail/CobraVegetation.gd").scatter(self)

func _tree(point: Vector2, scale_factor: float, dry: bool) -> void:
	if zone_id == "cobra":
		_cobra_tree(point,scale_factor,dry)
		return
	var trunk_height := 3.0*scale_factor
	var trunk := _cylinder("TreeTrunk",.24*scale_factor,trunk_height,Vector3(point.x,trunk_height*.5,point.y),Color("66513a"),true)
	trunk.material_override = preload("res://assets/urban_detail/FloraSurfaces.gd").material("bark",Color("66513a"),1.4,1.1)
	var foliage := Color("777b48") if dry else Color("465d3f")
	for offset in [Vector3(-.65,0,0),Vector3(.52,.18,.12),Vector3(0,.42,-.34),Vector3(.08,-.10,.58)]:
		var crown := MeshInstance3D.new()
		crown.name = "TreeCanopy"
		var sphere_key := snappedf(scale_factor,.01)
		if not _sphere_meshes.has(sphere_key):
			var sphere := SphereMesh.new()
			sphere.radius = 1.15*scale_factor
			sphere.height = 2.0*scale_factor
			sphere.radial_segments = 8
			sphere.rings = 4
			_sphere_meshes[sphere_key] = sphere
		crown.mesh = _sphere_meshes[sphere_key]
		crown.position = Vector3(point.x,trunk_height+.7*scale_factor,point.y)+offset*scale_factor
		crown.material_override = preload("res://assets/urban_detail/FloraSurfaces.gd").material("foliage",foliage.lightened(.07*float(get_child_count()%3)),1.2,.9)
		add_child(crown)

func _cobra_tree(point: Vector2, scale_factor: float, dry: bool) -> void:
	var variant := posmod(int(point.x*13+point.y*7),3)
	var h := (3.6 if variant==1 else 2.9)*scale_factor
	var trunk := _cylinder("TreeTrunk",.23*scale_factor,h,Vector3(point.x,h*.5,point.y),Color("403a2d"),true)
	trunk.material_override=COBRA_FINISH.surface("wood",Color("403a2d"))
	for branch in (0 if variant==1 and not dry else 3):
		var angle := float(branch)*2.3+point.x
		var start := Vector3(point.x,h*.64,point.y)
		var end := Vector3(point.x+cos(angle)*.85*scale_factor,h+.25*branch,point.y+sin(angle)*.85*scale_factor)
		var arm := _cylinder("TreeBranch",.10*scale_factor,start.distance_to(end),(start+end)*.5,Color("403a2d"))
		arm.quaternion=Quaternion(Vector3.UP,(end-start).normalized())
	if variant==1 and not dry:
		# Narrow, layered cypress silhouette breaks up the old identical globes.
		for tier in 3:
			var key := "cobra_cone_%d"%tier
			if not _cylinder_meshes.has(key):
				var cone := CylinderMesh.new()
				cone.top_radius=.18
				cone.bottom_radius=1.45-float(tier)*.24
				cone.height=2.5
				cone.radial_segments=7
				_cylinder_meshes[key]=cone
			var crown := MeshInstance3D.new()
			crown.name="CobraCypress"
			crown.mesh=_cylinder_meshes[key]
			crown.scale=Vector3.ONE*scale_factor
			crown.position=Vector3(point.x,(2.4+tier*.9)*scale_factor,point.y)
			crown.material_override=_material([Color("233b2a"),Color("2e4630"),Color("3b5033")][tier])
			add_child(crown)
		return
	if not _sphere_meshes.has("cobra_crown"):
		var sphere := SphereMesh.new()
		sphere.radius=1
		sphere.height=2
		sphere.radial_segments=7
		sphere.rings=3
		_sphere_meshes["cobra_crown"]=sphere
	for index in (3 if dry else 6):
		var angle := float(index)*2.4+point.y
		var crown := MeshInstance3D.new()
		crown.name="CobraWindTree" if dry else "CobraOak"
		crown.mesh=_sphere_meshes["cobra_crown"]
		var radius := (.7 if dry else 1.25)*scale_factor
		crown.scale=Vector3(radius*1.2,radius*.68,radius)
		crown.position=Vector3(point.x+cos(angle)*.9*scale_factor,h+.2+float(index%3)*.48,point.y+sin(angle)*.8*scale_factor)
		crown.rotation.y=angle
		crown.material_override=_material(([Color("514e32"),Color("605b39"),Color("42482e")] if dry else [Color("2b412c"),Color("394d30"),Color("455837")])[index%3])
		add_child(crown)

func _rock(point: Vector2, scale_factor: float) -> void:
	var rock := _box("CoastalRock",Vector3(point.x,.42*scale_factor,point.y),Vector3(1.4,0.85,1.1)*scale_factor,Color("726f63"),true)
	rock.rotation.y = point.angle()

func _lamp(point: Vector2) -> void:
	_cylinder("CobraLampPost",.08,2.8,Vector3(point.x,1.4,point.y),Color("3f4745"),true)
	_box("CobraLampHead",Vector3(point.x,2.87,point.y),Vector3(.42,.18,.42),Color("d3b487"))

func _barrel(point: Vector2) -> void:
	var first_mesh := get_child_count()
	var first_shape := _solid_root.get_child_count()
	var drum := _cylinder("CobraBarrel",.35,.78,Vector3(point.x,.39,point.y),Color("6d4a37"),true)
	if zone_id=="cobra": drum.material_override = COBRA_FINISH.surface("metal",Color("574337"))
	for y in [.12,.38,.65]: _cylinder("BarrelBand",.365,.045,Vector3(point.x,y,point.y),Color("333b39"))
	if zone_id=="cobra":
		_cylinder("BarrelLid",.33,.022,Vector3(point.x,.797,point.y),Color("30342c"))
		_cylinder("BarrelBung",.045,.025,Vector3(point.x+.16,.82,point.y),Color("171d19"))
	_register_breakable_parts("barrel",point,first_mesh,first_shape)

func _tire_barricade(point: Vector2) -> void:
	for index in 3:
		var tire := _cylinder("CobraTire",.43,.24,Vector3(point.x+.38*(index-1),.43,point.y),Color("222624"),true)
		tire.rotation_degrees.z = 90

func _bench(point: Vector2) -> void:
	var first_mesh := get_child_count()
	var first_shape := _solid_root.get_child_count()
	var seat := _box("CobraBenchSeat",Vector3(point.x,.48,point.y),Vector3(2.25,.16,.55),Color("67573c"),true)
	var back := _box("CobraBenchBack",Vector3(point.x,.82,point.y-.22),Vector3(2.25,.62,.12),Color("393c2c"),true)
	if zone_id=="cobra":
		seat.material_override = COBRA_FINISH.surface("wood",Color("67573c"))
		back.material_override = COBRA_FINISH.surface("wood",Color("494a33"))
		for x in [-.82,.82]:
			_box("BenchIronLeg",Vector3(point.x+x,.225,point.y),Vector3(.16,.4,.46),Color("282e29"),true)
			_box("BenchFoot",Vector3(point.x+x,.044,point.y),Vector3(.3,.028,.62),Color("34372d"))
			_box("BenchArm",Vector3(point.x+x,.68,point.y),Vector3(.09,.07,.55),Color("282e29"))
	_register_breakable_parts("bench_seat",point,first_mesh,first_shape)

func _register_breakable_parts(kind: String, point: Vector2, first_mesh: int, first_shape: int) -> void:
	var bench := Node3D.new()
	bench.name = "Breakable_"+kind
	bench.position = Vector3(point.x,0,point.y)
	var pieces: Array = get_children().slice(first_mesh)
	var colliders: Array = _solid_root.get_children().slice(first_shape)
	add_child(bench)
	for piece in pieces: piece.reparent(bench,true)
	preload("res://gameplay/street_physics/FragileProps3D.gd").register_node(kind,bench,self,{},colliders)

func _beam(label: String, a: Vector2, b: Vector2, width: float, height: float, color: Color, solid := false, center_y := .02) -> MeshInstance3D:
	var delta := b-a
	if zone_id == "cobra" and label == "CobraGardenPath": center_y = .05
	var mesh := _box(label,Vector3((a.x+b.x)*.5,center_y,(a.y+b.y)*.5),Vector3(width,height,delta.length()),color,solid)
	if zone_id == "cobra" and label in ["CobraGardenPath","CobraFootpath","CobraEntrancePath","CobraCrossingLink"]:
		mesh.material_override = _surface_material("stone",Color("606653"))
		_cobra_paths.append([a,b])
		for point in [a,b]:
			_cobra_joint_counts[point]=int(_cobra_joint_counts.get(point,0))+1
			var old: Vector2=_cobra_joints.get(point,Vector2.ZERO)
			_cobra_joints[point]=Vector2(maxf(width,old.x),maxf(center_y+height*.5,old.y))
	elif zone_id == "cobra" and label == "CobraSecretDrive":
		mesh.material_override = COBRA_FINISH.ground("gravel")
	elif zone_id == "cobra" and label == "CobraFootpathEdge":
		mesh.material_override = _surface_material("concrete",Color("606353"))
	mesh.rotation.y = atan2(delta.x,delta.y)
	if solid:
		var collider: CollisionShape3D = _solid_root.get_child(_solid_root.get_child_count()-1)
		collider.rotation.y = mesh.rotation.y
	return mesh

func _box(label: String, point: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	if zone_id=="cobra": result.set_meta("cobra_surface_label",label)
	var mesh_key := str(size)
	if not _box_meshes.has(mesh_key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_box_meshes[mesh_key] = mesh
	result.mesh = _box_meshes[mesh_key]
	result.position = point
	result.material_override = _material(color)
	add_child(result)
	if solid: _shape(point,size)
	return result

func _cylinder(label: String, radius: float, height: float, point: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = label
	var mesh_key := "%s:%s"%[radius,height]
	if not _cylinder_meshes.has(mesh_key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 10
		_cylinder_meshes[mesh_key] = mesh
	result.mesh = _cylinder_meshes[mesh_key]
	result.position = point
	result.material_override = _material(color)
	add_child(result)
	if solid: _shape(point,Vector3(radius*1.7,height,radius*1.7))
	return result

func _shape(point: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.position = point
	collider.shape = shape
	_solid_root.add_child(collider)

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .9
		_materials[key] = material
	return _materials[key]


func _surface_material(kind: String,color: Color)->StandardMaterial3D:
	var key:="surface:%s:%s"%[kind,color.to_html(true)]
	if not _materials.has(key):
		var material:=StandardMaterial3D.new()
		material.albedo_color=color
		GROUND.bind(material,kind)
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		# Projeção no mundo: a caixa tem dezenas de metros e o UV da BoxMesh esticava
		# um único ladrilho sobre ela inteira (lia como cor lisa).
		material.uv1_triplanar=true
		material.uv1_world_triplanar=true
		material.uv1_scale=Vector3.ONE*(.22 if kind=="grass" else .3)
		material.roughness=.92
		_materials[key]=material
	return _materials[key]
