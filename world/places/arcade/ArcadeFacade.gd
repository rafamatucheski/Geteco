extends "res://world/places/arcade/ArcadeGeometry.gd"
## A compact Fagulha storefront, authored in the gap between existing shops.
const PAINTED := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const PAINTED_STYLE := "fagulha"

var leaves: Array[Node3D] = []
var open_amount := 0.0

func _ready() -> void:
	name = "FagulhaFacade"
	set_meta("place_id", "harbor_arcade")
	add_to_group("arcade_facade")
	# Entrada de empurrar (WeaponShopEntrance): as folhas deslizam ao empurrar.
	# Antes ninguém as abria e só a ação silenciosa "Entrar" levava para dentro.
	add_to_group("v2_walkin_facade")
	if OS.get_environment("GETECO_PAINTED_ARCADE") != "0" and PAINTED.enabled() and FileAccess.file_exists(PAINTED.ROOT+PAINTED_STYLE+"/style.json"):
		_build_painted()
		return
	box("BackShell",Vector3(0,1.75,-4.87),Vector3(12,3.5,.26),"585361","BackShell","stone")
	for side in [-1,1]:
		box("SideShell%d"%side,Vector3(side*5.87,1.75,0),Vector3(.26,3.5,10),"675b62","SideShell%d"%side,"stone")
		box("FrontShell%d"%side,Vector3(side*3.59,1.75,4.86),Vector3(4.80,3.5,.28),"413640","FrontShell%d"%side,"wood")
		box("Window%d"%side,Vector3(side*3.57,1.61,5.015),Vector3(4.12,2.06,.027),"162d3c","","screen")
		for edge in [-1,1]:
			box("WindowUpright",Vector3(side*3.57+edge*2.08,1.61,5.054),Vector3(.07,2.2,.06),"ad8c59","","metal")
			box("WindowRail",Vector3(side*3.57,1.61+edge*1.066,5.054),Vector3(4.19,.07,.06),"ad8c59","","metal")
		box("WindowMullion",Vector3(side*3.57,1.61,5.051),Vector3(.047,2.12,.057),"ac8253","","metal")
		box("BrickPlinth",Vector3(side*3.57,.29,5.034),Vector3(4.45,.48,.12),"635044","","stone")
		for brick in 10: detail(Vector3(side*3.57-2.0+brick*.444,.31,5.104),Vector3(.02,.40,.012),"463932")
		# Opaque shallow window art suggests real cabinets at their natural scale.
		for cabinet in 2:
			var x: float = side*3.57-.89+cabinet*1.77
			var accent := "63a89f" if side<0 else "c6869d"
			box("WindowCabinet",Vector3(x,1.04,5.075),Vector3(.95,1.46,.04),"222d3c")
			box("WindowCabinetHeader",Vector3(x,1.80,5.083),Vector3(1.0,.16,.034),accent,"","screen")
			box("WindowCabinetScreen",Vector3(x,1.38,5.102),Vector3(.61,.43,.02),"44676d","","screen")
			box("WindowCabinetControls",Vector3(x,1.08,5.105),Vector3(.98,.12,.027),accent)
			for dot in 4: detail(Vector3(x-.24+dot*.16,1.35+sin(dot)*.10,5.118),Vector3(.065,.065,.009),"daba78","screen")
		box("CornerPier",Vector3(side*5.77,1.82,4.98),Vector3(.27,3.63,.33),"a68b67","CornerPier%d"%side,"stone")
	box("Fascia",Vector3(0,3.02,5.065),Vector3(11.57,.78,.21),"353044")
	for y in [2.64,3.40]: detail(Vector3(0,y,5.180),Vector3(11.4,.038,.026),"69b6b1","screen")
	var name_label := Label3D.new()
	name_label.name = "FagulhaName"
	name_label.text = "FAGULHA"
	name_label.font_size = 96
	name_label.pixel_size = .0072
	name_label.outline_size = 0
	name_label.position = Vector3(0,3.015,5.18)
	name_label.modulate = Color("eed3a1")
	add_child(name_label)
	box("Canopy",Vector3(0,2.59,5.44),Vector3(11.58,.085,.92),"493848","","cloth")
	box("CanopyLip",Vector3(0,2.54,5.93),Vector3(11.58,.12,.05),"a07752","","metal")
	for side in [-1,1]:
		var leaf := Node3D.new()
		leaf.name = "DoorLeaf%d"%side
		leaf.position = Vector3(side*.565,0,4.91)
		add_child(leaf)
		for part in [
			["DoorPanel",Vector3(0,1.30,0),Vector3(1.11,2.60,.085),"29424b"],
			["DoorHandle",Vector3(-side*.36,1.18,.087),Vector3(.035,.48,.055),"d0b47b"],
			["DoorRailLeft",Vector3(-.537,1.30,.054),Vector3(.043,2.60,.037),"bc955d"],
			["DoorRailRight",Vector3(.537,1.30,.054),Vector3(.043,2.60,.037),"bc955d"],
		]:
			var mesh := box(part[0],part[1],part[2],part[3],"","metal")
			remove_child(mesh)
			leaf.add_child(mesh)
		_collision(leaf,Vector3(0,1.3,0),Vector3(1.11,2.60,.12),"FagulhaDoor")
		leaves.append(leaf)
	box("Threshold",Vector3(0,.035,5.13),Vector3(2.25,.07,.58),"ac9270","","stone")
	box("Roof",Vector3(0,3.57,0),Vector3(12,.18,10),"474952","Roof","metal")
	for side in [-1,1]:
		box("RoofParapetSide",Vector3(side*5.75,3.79,0),Vector3(.23,.3,9.83),"938271")
		box("RoofParapetEnd",Vector3(0,3.79,side*4.75),Vector3(11.75,.3,.23),"938271")
	box("Ventilator",Vector3(3.61,3.98,-2.53),Vector3(1.22,.64,1.1),"747c77","Ventilator","metal")
	for slat in 8: detail(Vector3(3.14+slat*.135,4.311,-2.53),Vector3(.049,.016,.90),"30393c","metal")
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("interior_solid_id"):
			_collision(self,child.position,child.mesh.get_aabb().size,str(child.get_meta("interior_solid_id")))
	flush()
	set_process(false)
	set_physics_process(false)

func _collision(parent: Node3D, at: Vector3, size: Vector3, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label + "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id",label)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	body.add_child(collision)
	parent.add_child(body)

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount,0,1)
	for index in leaves.size(): leaves[index].position.x = (-1 if index==0 else 1)*(.565+open_amount*1.15)


## A pintura troca somente a apresentação; caixas, folhas deslizantes e acesso são os originais.
## O catálogo de estilos é descoberto e retido automaticamente pelo PaintedFacadePrewarm.
func _build_painted() -> void:
	var visual := PAINTED.build(self,PAINTED_STYLE,Vector3(12,3.5,10),null,NAN,{"ground_door":false})
	# O kit também atende portas giratórias; este acesso conserva suas folhas de correr.
	for child in visual.get_children():
		if str(child.name).begins_with("Doorway_") or child.name in ["Roof","Cornice"]: child.free()
	_collision(self,Vector3(0,1.75,-4.87),Vector3(12,3.5,.26),"BackShell")
	for side in [-1,1]:
		_collision(self,Vector3(side*5.87,1.75,0),Vector3(.26,3.5,10),"SideShell%d"%side)
		_collision(self,Vector3(side*3.59,1.75,4.86),Vector3(4.80,3.5,.28),"FrontShell%d"%side)
		_collision(self,Vector3(side*5.77,1.82,4.98),Vector3(.27,3.63,.33),"CornerPier%d"%side)
		_painted_box("CornerPier%d"%side,Vector3(side*5.77,1.82,4.98),Vector3(.27,3.63,.33),"side")
	_collision(self,Vector3(0,3.57,0),Vector3(12,.18,10),"Roof")
	_collision(self,Vector3(3.61,3.98,-2.53),Vector3(1.22,.64,1.1),"Ventilator")
	_painted_box("Roof",Vector3(0,3.57,0),Vector3(12,.18,10),"roof")
	for side in [-1,1]:
		_painted_box("RoofParapetSide",Vector3(side*5.75,3.79,0),Vector3(.23,.3,9.83),"side")
		_painted_box("RoofParapetEnd",Vector3(0,3.79,side*4.75),Vector3(11.75,.3,.23),"side")
	_painted_box("Ventilator",Vector3(3.61,3.98,-2.53),Vector3(1.22,.64,1.1),"roof")
	_painted_box("Threshold",Vector3(0,.035,5.13),Vector3(2.25,.07,.58),"side")
	for side in [-1,1]:
		var leaf := Node3D.new()
		leaf.name = "DoorLeaf%d"%side
		leaf.position = Vector3(side*.565,0,4.91)
		add_child(leaf)
		# QuadMesh usa a imagem inteira: BoxMesh divide o UV entre seis faces.
		for facing in [-1,1]:
			var panel := MeshInstance3D.new()
			panel.name = "DoorPanel" if facing>0 else "DoorPanelInside"
			var quad := QuadMesh.new()
			quad.size = Vector2(1.11,2.6)
			panel.mesh = quad
			panel.position = Vector3(0,1.3,facing*.0425)
			panel.rotation.y = PI if facing<0 else 0.0
			panel.material_override = PAINTED.material(PAINTED_STYLE,"door_front" if side<0 else "door_back")
			leaf.add_child(panel)
		_collision(leaf,Vector3(0,1.3,0),Vector3(1.11,2.6,0.12),"FagulhaDoor")
		leaves.append(leaf)
	set_process(false)
	set_physics_process(false)

func _painted_box(label: String, at: Vector3, size: Vector3, part: String) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.material_override = PAINTED.material(PAINTED_STYLE,part)
	add_child(instance)
	return instance
