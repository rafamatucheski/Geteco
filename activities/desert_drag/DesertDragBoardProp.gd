extends RefCounted
const G := preload("res://world/desert/DesertGeometry.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const SURFACES := preload("res://world/places/ShopInteriorMaterials.gd")
const BATCH := preload("res://world/desert/DesertTownMaterials.gd")
static var _materials: Dictionary = {}

static func position() -> Vector3:
	# Outside the driving/staging lane and parked-car bays; reached from the south.
	return LAYOUT.drag_staging_point()+Vector3(8,0,5)

static func build_chunk(parent: Node3D, rect: Rect2) -> void:
	var at := position()
	if not rect.has_point(Vector2(at.x,at.z)): return
	var board := Node3D.new()
	board.name="DragRivalsBoard"
	board.position=at
	parent.add_child(board)
	board.add_to_group("desert_drag_boards")
	_reception(board)
	G.box(board,"WoodenFrame",Vector3(0,1.65,0),Vector3(2.3,1.7,.16),Color("624936"),true)
	G.box(board,"ChalkFace",Vector3(0,1.65,.087),Vector3(2.14,1.54,.02),Color("243a33"))
	for x in [-.85,.85]: G.box(board,"Leg",Vector3(x,.45,0),Vector3(.10,.9,.14),Color("624936"),true)
	var font: Font
	if ResourceLoader.exists("res://assets/fonts/caveat/Caveat.ttf"): font=load("res://assets/fonts/caveat/Caveat.ttf")
	else:
		font=FontFile.new()
		font.load_dynamic_font("res://assets/fonts/caveat/Caveat.ttf")
	var text := Label3D.new()
	text.name="Names"
	text.text="Digo\nLívia\nRaul\nJessica\nNadir"
	text.font=font
	text.font_size=38
	text.pixel_size=.006
	text.outline_size=0
	text.modulate=Color("ede8d3")
	text.position=Vector3(0,1.65,.104)
	board.add_child(text)
	# Individually solid props keep their colliders; only decoration is merged.
	for child in board.get_children():
		if not child is MeshInstance3D: continue
		var source := child.material_override as StandardMaterial3D
		if source==null: continue
		var kind := "metal"
		var id := str(child.name)
		if "Canvas" in id or source.albedo_color in [Color("a85436"),Color("c57b52")]: kind="cloth"
		elif source.albedo_color in [Color("624936"),Color("9a7956"),Color("7f6246")]: kind="wood"
		var key := kind+source.albedo_color.to_html()
		if not _materials.has(key):
			var mat := SURFACES.material(kind,source.albedo_color).duplicate() as StandardMaterial3D
			mat.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			mat.metallic=.35 if kind=="metal" else 0.0
			mat.roughness=.72 if kind=="metal" else .95
			mat.cull_mode=BaseMaterial3D.CULL_DISABLED if kind=="cloth" else BaseMaterial3D.CULL_BACK
			_materials[key]=mat
		child.material_override=_materials[key]
	BATCH.batch_visuals(board)

static func _reception(board: Node3D) -> void:
	# A compact open registration canopy faces the southern pedestrian approach.
	# Its posts stay east of staging and outside the return/launch corridors.
	var steel := Color("9da8a5")
	var dark := Color("303e43")
	var canvas := Color("a85436")
	for x in [-3.1,3.1]:
		for z in [-1.3,3.5]:
			G.box(board,"CanopyFoot",Vector3(x,.055,z),Vector3(.44,.11,.44),dark,true)
			G.box(board,"CanopyPost",Vector3(x,1.65,z),Vector3(.09,3.3,.09),steel,true)
			G.box(board,"PostCollar",Vector3(x,1.15,z),Vector3(.13,.16,.13),dark)
			for dx in [-.14,.14]:
				G.cylinder(board,"AnchorBolt",Vector3(x+dx,.12,z),.025,.04,steel)
		G.box(board,"CanopySideRail",Vector3(x,3.22,1.1),Vector3(.09,.10,4.8),steel)
	for z in [-1.3,3.5]:
		G.box(board,"CanopyCrossRail",Vector3(0,3.22,z),Vector3(6.2,.10,.09),steel)
		G.box(board,"CanvasValance",Vector3(0,3.18,z),Vector3(6.5,.29,.025),canvas)
		# Checkered edging makes this read as the race reception without signage.
		for column in 26:
			for row in 2:
				G.box(board,"CheckeredHem",Vector3(-3.125+column*.25,3.10+row*.12,z+(.018 if z>0 else -.018)),Vector3(.248,.118,.012),Color("dfd5bc") if (column+row)%2==0 else dark)
	for side in [-1.0,1.0]:
		var roof := G.box(board,"CanvasRoof",Vector3(side*1.625,3.72,1.1),Vector3(3.41,.035,5.12),canvas)
		roof.rotation.z=-side*.30
		# Raised stitched seams follow the roof pitch; no extra effects or lights.
		for z in [-1.43,-.16,1.11,2.38,3.63]:
			var seam := G.box(board,"CanvasSeam",Vector3(side*1.625,3.745,z),Vector3(3.41,.018,.025),Color("c57b52"))
			seam.rotation.z=-side*.30
		G.box(board,"CanvasSideHem",Vector3(side*3.25,3.16,1.1),Vector3(.025,.28,5.12),canvas)
	G.box(board,"RidgeCap",Vector3(0,4.23,1.1),Vector3(.10,.06,5.15),Color("c57b52"))
	# Reception desk sits beside, never in front of, the interactive board.
	var counter := G.box(board,"ReceptionCounter",Vector3(2.05,.51,1.35),Vector3(1.3,1.02,1.10),dark)
	G.collision(counter,Vector3(1.42,1.10,1.2))
	G.box(board,"CounterTop",Vector3(2.05,1.06,1.35),Vector3(1.42,.08,1.2),Color("9a7956"))
	for x in [1.44,2.66]:
		G.box(board,"CaseEdge",Vector3(x,.51,1.91),Vector3(.055,.98,.035),steel)
	for y in [.08,.94]:
		G.box(board,"CaseEdge",Vector3(2.05,y,1.91),Vector3(1.25,.045,.035),steel)
	G.box(board,"CaseHandle",Vector3(2.05,.61,1.94),Vector3(.28,.06,.06),steel)
	G.box(board,"Clipboard",Vector3(1.81,1.112,1.40),Vector3(.29,.018,.4),Color("b08b5b"))
	G.box(board,"EntrySheet",Vector3(1.81,1.123,1.40),Vector3(.25,.005,.34),Color("ddd5bd"))
	G.box(board,"ClipboardClip",Vector3(1.81,1.13,1.25),Vector3(.10,.012,.045),steel)
	G.box(board,"Radio",Vector3(2.43,1.26,1.35),Vector3(.15,.30,.12),dark)
	G.cylinder(board,"RadioAntenna",Vector3(2.46,1.50,1.35),.008,.23,dark)
	# Frame hardware, feet and chalk ledge replace the floating slab appearance.
	for x in [-.85,.85]:
		G.box(board,"BoardFoot",Vector3(x,.07,0),Vector3(.27,.14,.75),dark,true)
		for y in [.93,2.37]:
			var bolt := G.cylinder(board,"FrameBolt",Vector3(x,y,.10),.025,.025,steel)
			bolt.rotation.x=PI*.5
	G.box(board,"ChalkTray",Vector3(0,.86,.15),Vector3(2.16,.055,.21),Color("7f6246"))
	G.box(board,"Chalk",Vector3(.52,.90,.18),Vector3(.12,.025,.025),Color("ede8d3"))
