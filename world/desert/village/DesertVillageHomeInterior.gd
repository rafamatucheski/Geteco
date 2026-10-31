extends Node3D
## Static human-scale adobe homes; the native adapter derives full furniture collision envelopes.
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const SHOP := preload("res://world/places/ShopInteriorMaterials.gd")
const CRAFT := preload("res://world/desert/village/DesertHomeCraft.gd")
var variant := 0
var _materials: Dictionary = {}

func _ready() -> void:
	var layout := HOMES.specification(variant)
	_shell(layout)
	_bed(layout.bed,Color(layout.cloth))
	_kitchen(layout.kitchen,variant in [1,3])
	_table(layout.table,variant)
	_sofa(layout.sofa,float(layout.sofa_yaw),Color(layout.cloth))
	_identity(layout)
	_finish(layout)
	set_process(false)
	set_physics_process(false)

func _material(color: Color,kind := "") -> Material:
	var key := color.to_html()+kind
	if _materials.has(key): return _materials[key]
	var mat: StandardMaterial3D
	if kind=="plaster":
		mat=StandardMaterial3D.new()
		mat.albedo_color=color
		mat.albedo_texture=CRAFT.plaster_texture()
		mat.uv1_triplanar=true
		mat.roughness=.97
	elif not kind.is_empty(): mat=SHOP.material(kind,color)
	else:
		mat=StandardMaterial3D.new()
		mat.albedo_color=color
		mat.roughness=.83
	_materials[key]=mat
	return mat

func _box(parent: Node3D,id: String,at: Vector3,size: Vector3,color: Color,solid := "",kind := "") -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name=id
	var shape := BoxMesh.new()
	shape.size=size
	mesh.mesh=shape
	if id in ["Mattress","Pillow","SeatCushion","SofaArm","SofaBack","SofaBase","Headboard","DiningTop","ChairSeat","ChairBack","KitchenTop","BedsideChest","Toolbox","LumbarCushion","FoldedQuilt"]:
		mesh.mesh=CRAFT.rounded_box(size,.10 if kind=="cloth" else .055)
	mesh.position=at
	mesh.material_override=_material(color,kind)
	if not solid.is_empty(): mesh.set_meta("interior_solid_id",solid)
	parent.add_child(mesh)
	return mesh

func _cylinder(parent: Node3D,id: String,at: Vector3,radius: float,height: float,color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name=id
	var shape := CylinderMesh.new()
	shape.top_radius=radius
	shape.bottom_radius=radius
	shape.height=height
	shape.radial_segments=24
	mesh.mesh=shape
	mesh.position=at
	mesh.material_override=_material(color)
	parent.add_child(mesh)
	return mesh

func _shell(layout: Dictionary) -> void:
	var size: Vector2=layout.size
	var wall:=Color(layout.wall)
	_box(self,"TerracottaFloor",Vector3(0,-.05,0),Vector3(size.x,.06,size.y),Color("947455"),"","wood" if variant==1 else "plaster")
	_box(self,"BackWall",Vector3(0,1.42,-size.y*.5+.12),Vector3(size.x,2.84,.24),wall,"BackWall","plaster")
	for side in [-1.0,1.0]:
		# Um corte em degraus abre a área de estar para a câmera alinhada. As duas partes
		# dividem um grupo de parede física, mantendo o limite de altura total.
		_box(self,"SideWall",Vector3(side*(size.x*.5-.12),1.42,-size.y*.225),Vector3(.24,2.84,size.y*.55),wall,"SideWall%s"%side,"plaster")
		_box(self,"LowSideWall",Vector3(side*(size.x*.5-.12),.45,size.y*.275),Vector3(.24,.90,size.y*.45),wall,"SideWall%s"%side,"plaster")
		var width: float=size.x*.5-1.05
		_box(self,"FrontWall",Vector3(side*(1.05+width*.5),1.42,size.y*.5-.12),Vector3(width,2.84,.24),wall,"FrontWall%s"%side,"plaster")
		_box(self,"DoorJamb",Vector3(side*1.03,1.13,size.y*.5-.12),Vector3(.13,2.26,.28),Color("70503b"),"DoorJamb%s"%side,"wood")
	# A marcenaria exposta segue a parede do fundo, deixando atores e móveis legíveis.
	_box(self,"RearLintel",Vector3(0,2.72,-size.y*.5+.27),Vector3(size.x-.48,.18,.16),Color("68543e"),"","wood")
	for index in layout.partitions.size():
		var rect: Rect2=layout.partitions[index]
		var height := 1.08 if rect.size.x>rect.size.y else 2.45
		var pos:=Vector3(rect.get_center().x,height*.5,rect.get_center().y)
		_box(self,"RoomDivider",pos,Vector3(rect.size.x,height,rect.size.y),wall,"Partition%d"%index,"plaster")
		_box(self,"DividerCap",pos+Vector3(0,height*.5+.025,0),Vector3(rect.size.x+.04,.05,rect.size.y+.04),Color("795f44"),"Partition%d"%index,"wood")
	# Deep wooden sill, divided glazing and gathered curtains read as a real rear window.
	var wx := 0.0 if variant != 3 else 1.0
	_box(self,"RearWindow",Vector3(wx,1.78,-size.y*.5+.255),Vector3(1.6,1.2,.035),Color("617b82"))
	for side in [-1.0,1.0]:
		_box(self,"WindowTrim",Vector3(wx+side*.84,1.78,-size.y*.5+.30),Vector3(.085,1.38,.12),Color("6a503a"))
		for fold in 4:
			var curtain := _cylinder(self,"CurtainFold",Vector3(wx+side*(.57+fold*.065),1.79,-size.y*.5+.40),.048,1.28,Color("cbbd9b"))
			curtain.material_override=_material(Color("cbbd9b"),"cloth")
	_box(self,"WindowCross",Vector3(wx,1.78,-size.y*.5+.31),Vector3(.055,1.24,.065),Color("998060"))
	_box(self,"WindowSill",Vector3(wx,1.13,-size.y*.5+.36),Vector3(1.95,.09,.3),Color("795b40"),"WindowSill","wood")
	_box(self,"EntryMat",Vector3(0,.001,size.y*.5-1),Vector3(1.65,.016,.72),Color("4d5143"),"","cloth")
	var rug := _cylinder(self,"WovenRug",Vector3(0,.003,.8),1.0,.018,Color(layout.cloth).darkened(.16))
	rug.scale=Vector3(1.25,1,.88)
	rug.material_override=_material(Color(layout.cloth).darkened(.16),"cloth")
	# Two motivated light pools, no room-specific environment/sun or frame loop.
	_lamp(Vector3(.3,2.48,.6),Color("ffdfb5"),.78,8.2)
	_lamp(layout.kitchen+Vector3(0,2.35,.55),Color("ffdfbd"),.46,5.1)

func _lamp(at: Vector3,color: Color,energy: float,reach: float) -> void:
	_cylinder(self,"PendantShade",at,.24,.15,Color("6d7565"))
	_cylinder(self,"PendantBulb",at-Vector3(0,.095,0),.10,.07,Color("fff0d4"))
	var light:=OmniLight3D.new()
	light.name="WarmPendant"
	light.position=at-Vector3(0,.18,0)
	light.light_color=color
	light.light_energy=energy
	light.omni_range=reach
	light.shadow_enabled=false
	add_child(light)

func _bed(at: Vector3,cloth: Color) -> void:
	var frame:=Color("795b43")
	_box(self,"BedFrame",at+Vector3(0,.255,0),Vector3(1.68,.43,2.25),frame,"Bed","wood")
	_box(self,"Mattress",at+Vector3(0,.55,0),Vector3(1.61,.16,2.17),Color("d6c9b0"),"Bed","cloth")
	_box(self,"Blanket",at+Vector3(0,.633,.32),Vector3(1.62,.016,1.46),cloth,"","cloth")
	for z in [.05,.20]: _box(self,"BlanketStripe",at+Vector3(0,.644,z),Vector3(1.63,.005,.065),cloth.lightened(.3),"","cloth")
	_box(self,"Pillow",at+Vector3(0,.69,-.77),Vector3(.92,.12,.42),Color("e2d6bd"),"BedPillow","cloth")
	_box(self,"Headboard",at+Vector3(0,.55,-1.10),Vector3(1.73,1.10,.12),frame,"BedHeadboard","wood")
	for x in [-.69,.69]: _box(self,"BedPost",at+Vector3(x,.61,-1.10),Vector3(.10,1.22,.14),frame,"BedHeadboard","wood")

func _kitchen(at: Vector3,corner: bool) -> void:
	_box(self,"KitchenCabinet",at+Vector3(0,.44,0),Vector3(3.25,.88,.83),Color("758075"),"KitchenMain","wood")
	_box(self,"KitchenTop",at+Vector3(0,.93,0),Vector3(3.35,.10,.94),Color("b8b0a0"),"KitchenMain","stone")
	for x in [-1.12,0.0,1.12]:
		_box(self,"CabinetDoor",at+Vector3(x,.48,.425),Vector3(1.00,.68,.04),Color("819084"),"KitchenMain","wood")
		_box(self,"CabinetPull",at+Vector3(x+.3,.60,.456),Vector3(.16,.035,.04),Color("4d5650"),"KitchenMain")
	_box(self,"Hob",at+Vector3(.83,1.00,0),Vector3(.97,.035,.72),Color("3c4440"),"KitchenMain")
	for x in [.58,1.08]:
		for z in [-.18,.30]: _cylinder(self,"Burner",at+Vector3(x,1.027,z),.105,.018,Color("858478"))
	_cylinder(self,"CookingPot",at+Vector3(.58,1.14,.30),.17,.21,Color("575f56"))
	_cylinder(self,"PotBroth",at+Vector3(.58,1.252,.30),.14,.012,Color("a7864d"))
	for side in [-1.0,1.0]: _box(self,"PotHandle",at+Vector3(.58+side*.205,1.17,.30),Vector3(.10,.055,.07),Color("3b403b"))
	_box(self,"Sink",at+Vector3(-.83,.99,0),Vector3(.87,.026,.63),Color("515f60"),"KitchenMain")
	_box(self,"SinkBasin",at+Vector3(-.83,1.006,0),Vector3(.66,.012,.44),Color("849798"))
	_box(self,"TapUpright",at+Vector3(-.83,1.16,-.29),Vector3(.045,.33,.045),Color("a5aaa0"))
	_box(self,"TapSpout",at+Vector3(-.83,1.30,-.20),Vector3(.045,.045,.23),Color("a5aaa0"))
	_box(self,"Backsplash",at+Vector3(0,1.22,-.43),Vector3(3.3,.45,.045),Color("b4b59e"))
	# L-shaped kitchens reserve each leg separately; their concave space stays usable.
	if corner:
		var side: float=-1.0 if variant==1 else 1.0
		_box(self,"PantryCabinet",at+Vector3(side*1.86,.85,.42),Vector3(.62,1.70,.91),Color("9c9279"),"PantryCabinet","wood")
		_box(self,"PantryHandle",at+Vector3(side*1.86,1.03,.90),Vector3(.18,.035,.04),Color("5b6056"),"PantryCabinet")

func _table(at: Vector3,index: int) -> void:
	var width:=1.85 if index!=3 else 2.2
	if index in [0,2]:
		var top := _cylinder(self,"OvalDiningTop",at+Vector3(0,.78,0),.5,.12,Color("956f45"))
		top.scale=Vector3(width,1,1.02)
		top.set_meta("interior_solid_id","DiningTable")
		top.material_override=_material(Color("956f45"),"wood")
	else:
		_box(self,"DiningTop",at+Vector3(0,.78,0),Vector3(width,.12,1.02),Color("956f45"),"DiningTable","wood")
	for x in [-width*.4,width*.4]:
		for z in [-.39,.39]: _box(self,"TableLeg",at+Vector3(x,.36,z),Vector3(.10,.72,.10),Color("6d5137"),"DiningTable","wood")
	for side in [-1.0,1.0]:
		var center:=at+Vector3(0,0,side*.98)
		var id: String="DiningChair%s"%side
		_box(self,"ChairSeat",center+Vector3(0,.44,0),Vector3(.52,.10,.48),Color("7d6042"),id,"wood")
		_box(self,"ChairBack",center+Vector3(0,.78,side*.20),Vector3(.52,.61,.075),Color("7d6042"),id,"wood")
		for x in [-.20,.20]:
			for z in [-.17,.17]: _box(self,"ChairLeg",center+Vector3(x,.2,z),Vector3(.065,.40,.065),Color("6a523b"),id,"wood")
	_cylinder(self,"DinnerPlate",at+Vector3(-.42,.854,.08),.20,.025,Color("dad8c5"))
	_cylinder(self,"Mug",at+Vector3(.44,.93,-.10),.075,.17,Color("899e9b"))
	_box(self,"FoldedCloth",at+Vector3(.50,.854,.22),Vector3(.27,.014,.23),Color("c6b99e"),"","cloth")

func _sofa(at: Vector3,yaw: float,cloth: Color) -> void:
	var couch:=Node3D.new()
	couch.name="SofaAssembly"
	couch.position=at
	couch.rotation.y=yaw
	add_child(couch)
	_box(couch,"SofaBase",Vector3(0,.28,0),Vector3(2.5,.40,.88),Color("6c5643"),"Sofa","wood")
	_box(couch,"SofaBack",Vector3(0,.71,-.37),Vector3(2.5,.85,.22),cloth,"Sofa","cloth")
	for x in [-.59,.59]: _box(couch,"SeatCushion",Vector3(x,.53,.05),Vector3(1.10,.20,.70),cloth.lightened(.1),"Sofa","cloth")
	for side in [-1.0,1.0]: _box(couch,"SofaArm",Vector3(side*1.23,.59,0),Vector3(.18,.60,.90),cloth,"Sofa","cloth")
	var cushion := _box(couch,"LumbarCushion",Vector3(-.64,.76,-.15),Vector3(.48,.42,.19),cloth.lightened(.28),"Sofa","cloth")
	cushion.rotation.z=.16
	_box(couch,"FoldedQuilt",Vector3(.70,.66,.12),Vector3(.58,.07,.58),Color("b8ab88"),"Sofa","cloth")

func _finish(layout: Dictionary) -> void:
	var size: Vector2=layout.size
	# Floor joints have no raised collision; deterministic colour variation reads as fired clay.
	if variant!=1:
		var nx := ceili(size.x/.75)
		var nz := ceili(size.y/.75)
		var joints := MultiMesh.new()
		joints.transform_format=MultiMesh.TRANSFORM_3D
		var unit := BoxMesh.new()
		unit.size=Vector3.ONE
		joints.mesh=unit
		joints.instance_count=nx+nz-2
		var slot := 0
		for x in range(1,nx):
			joints.set_instance_transform(slot,Transform3D(Basis.from_scale(Vector3(.012,.003,size.y-.48)),Vector3(-size.x*.5+x*size.x/nx,-.018,0)))
			slot+=1
		for z in range(1,nz):
			joints.set_instance_transform(slot,Transform3D(Basis.from_scale(Vector3(size.x-.48,.003,.012)),Vector3(0,-.018,-size.y*.5+z*size.y/nz)))
			slot+=1
		var tile_joints := MultiMeshInstance3D.new()
		tile_joints.name="TileJoints"
		tile_joints.multimesh=joints
		tile_joints.material_override=_material(Color("6e5d49"))
		add_child(tile_joints)
	# Timber skirtings remain within the already reserved wall footprint.
	for side in [-1.0,1.0]:
		_box(self,"Skirting",Vector3(side*(size.x*.5-.24),.10,0),Vector3(.035,.20,size.y-.48),Color("786249"),"SideWall%s"%side,"wood")
	_box(self,"Skirting",Vector3(0,.10,-size.y*.5+.24),Vector3(size.x-.48,.20,.035),Color("786249"),"BackWall","wood")
	# Artesanatos domésticos diferentes, presos na parede do fundo em vez de bloquear faixas do piso.
	var center := Vector3(layout.bed.x,1.98,-size.y*.5+.29)
	if variant in [0,2]:
		for i in 3:
			var plate := _cylinder(self,"WovenWallBasket",center+Vector3((i-1)*.46,sin(i*1.7)*.14,0),.19,.055,Color("b89663"))
			plate.rotation.x=PI*.5
	else:
		_box(self,"PictureFrame",center,Vector3(1.25,.79,.06),Color("735840"),"","wood")
		_box(self,"LandscapeCanvas",center+Vector3(0,0,.038),Vector3(1.10,.64,.015),Color("a7a189"),"","cloth")
		_box(self,"LandscapeHorizon",center+Vector3(0,-.16,.050),Vector3(1.10,.26,.008),Color(layout.cloth).darkened(.18))
	# Ripas de marcenaria quebram a cabeceira monolítica em madeira feita à mão reconhecível.
	for i in 7:
		_box(self,"HeadboardSlat",layout.bed+Vector3((i-3)*.22,.89,-1.025),Vector3(.13,.31,.025),Color("a4835b"),"BedHeadboard","wood")
	var bolster := _cylinder(self,"BedBolster",layout.bed+Vector3(.57,.70,-.74),.105,.37,Color(layout.cloth).lightened(.24))
	bolster.rotation.z=PI*.5
	bolster.material_override=_material(Color(layout.cloth).lightened(.24),"cloth")

func _identity(layout: Dictionary) -> void:
	# Cada planta tem uma área de estar útil diferente, além das próprias divisões de cômodo.
	match variant:
		0:
			_box(self,"KitchenWallShelf",Vector3(3.4,1.95,-4.14),Vector3(2.55,.13,.36),Color("8a6848"),"","wood")
			for i in 4: _cylinder(self,"PantryJar",Vector3(2.5+i*.55,2.15,-4.12),.12,.29,Color("af9a72"))
		1:
			_box(self,"WritingDesk",Vector3(4.95,.70,2.55),Vector3(2.0,.13,.88),Color("8b6c49"),"WritingDesk","wood")
			for x in [4.15,5.75]: _box(self,"DeskLeg",Vector3(x,.34,2.55),Vector3(.11,.68,.67),Color("705539"),"WritingDesk","wood")
			_box(self,"OpenNotebook",Vector3(4.95,.782,2.48),Vector3(.53,.018,.36),Color("d7cbb0"))
		2:
			_box(self,"Bookcase",Vector3(-4.65,1.03,2.55),Vector3(.60,2.06,1.9),Color("806146"),"Bookcase","wood")
			for row in 3:
				for i in 5: _box(self,"BookSpine",Vector3(-4.32,.38+row*.55,1.82+i*.33),Vector3(.04,.36,.23),[Color("866c4c"),Color("637b76"),Color("955f47")][i%3],"Bookcase")
		3:
			_box(self,"WorkBench",Vector3(5.85,.77,2.95),Vector3(.92,.15,2.1),Color("8c6b49"),"WorkBench","wood")
			for z in [2.12,3.78]: _box(self,"BenchLeg",Vector3(5.85,.37,z),Vector3(.72,.74,.10),Color("705437"),"WorkBench","wood")
			_box(self,"Toolbox",Vector3(5.85,.98,2.65),Vector3(.51,.28,.65),Color("7d5348"),"WorkBench")
	# Pequenos objetos de uso ficam em apoios sólidos, nunca nas rotas de entrada/circulação.
	var bed: Vector3=layout.bed
	_box(self,"BedsideChest",bed+Vector3(-1.22,.28,-.57),Vector3(.55,.56,.60),Color("806447"),"BedsideChest","wood")
	_box(self,"ChestDrawer",bed+Vector3(-1.22,.37,-.252),Vector3(.43,.19,.025),Color("9a7b54"),"BedsideChest","wood")

func create_reward_art(item: Dictionary) -> Node3D:
	var art:=Node3D.new()
	if str(item.get("kind",""))=="cash":
		for layer in 3:
			_box(art,"CashNotes",Vector3(0,.13+layer*.027,0),Vector3(.33,.026,.17),Color("839878"))
		_box(art,"CashBand",Vector3(0,.204,0),Vector3(.075,.018,.18),Color("d2cdb4"))
	elif str(item.get("item",""))=="water":
		_cylinder(art,"WaterBottle",Vector3(0,.22,0),.09,.35,Color("81adb5"))
		_cylinder(art,"BottleNeck",Vector3(0,.421,0),.044,.063,Color("8fbbc3"))
		_cylinder(art,"BottleCap",Vector3(0,.463,0),.049,.036,Color("425f75"))
		_cylinder(art,"BottleLabel",Vector3(0,.225,0),.092,.12,Color("d8ddd0"))
	else:
		_box(art,"SandwichPaper",Vector3(0,.13,0),Vector3(.38,.025,.30),Color("dfd2b5"))
		_box(art,"LowerBread",Vector3(0,.16,0),Vector3(.29,.055,.23),Color("d5ad72"))
		_box(art,"Lettuce",Vector3(0,.195,0),Vector3(.31,.018,.25),Color("809765"))
		_box(art,"SandwichFilling",Vector3(0,.218,0),Vector3(.27,.027,.21),Color("ab7759"))
		_box(art,"UpperBread",Vector3(0,.252,0),Vector3(.29,.050,.23),Color("ddbd86"))
	return art
