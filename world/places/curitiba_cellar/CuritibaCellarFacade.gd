extends "res://world/places/curitiba_cellar/CellarGeometry.gd"
## Uma única fachada de loja autorada no Harbor. A entrada no estilo de transferência divide o
## marcador de porta compacto; a frente leva só o nome do estabelecimento.
const PAINTED := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const PAINTED_STYLE := "curitiba-cellar"

var leaves: Array[Node3D] = []
var open_amount := 0.0

func _ready() -> void:
	name = "CuritibaCellarFacade"
	set_meta("place_id","harbor_curitiba_cellar")
	add_to_group("curitiba_cellar_facade")
	# Entrada de empurrar (WeaponShopEntrance): as folhas deslizam ao empurrar.
	# Antes ninguém as abria e só a ação silenciosa "Entrar" levava para dentro.
	add_to_group("v2_walkin_facade")
	if OS.get_environment("GETECO_PAINTED_CELLAR") != "0" and PAINTED.enabled() and FileAccess.file_exists(PAINTED.ROOT+PAINTED_STYLE+"/style.json"):
		_build_painted()
		return
	box("RearShell",Vector3(0,1.8,-5.35),Vector3(14,3.6,.3),"afa38c","RearShell","stone")
	for side in [-1,1]:
		box("SideShell%d"%side,Vector3(side*6.85,1.8,0),Vector3(.3,3.6,11),"b9ad95","SideShell%d"%side,"stone")
		box("FrontShell%d"%side,Vector3(side*4.08,1.8,5.34),Vector3(5.83,3.6,.28),"6b4935","FrontShell%d"%side)
		box("ShopWindow%d"%side,Vector3(side*4.15,1.67,5.497),Vector3(4.92,2.20,.026),"283c3c","","bottle")
		for edge in [-1,1]:
			box("WindowUpright",Vector3(side*4.15+edge*2.48,1.67,5.535),Vector3(.075,2.35,.07),"ac8b57","","metal")
			box("WindowRail",Vector3(side*4.15,1.67+edge*1.135,5.535),Vector3(5.02,.07,.07),"ac8b57","","metal")
		box("WindowMiddle",Vector3(side*4.15,1.67,5.535),Vector3(.055,2.26,.07),"ac8b57","","metal")
		# Vitrines simuladas sólidas não precisam de passo de transparência nem de segundo
		# viewport. As garrafas ficam em escala humana atrás de um trilho raso de latão.
		for tier in 2:
			var y := .86+tier*.73
			box("WindowShelf",Vector3(side*4.15,y,5.58),Vector3(4.6,.07,.23),"aa8354")
			for index in 20:
				bottle(Vector3(side*4.15-2.1+index*.22,y+.039,5.65),"e3d8b9","284231","652c3d" if side<0 else "b49755")
		box("WindowApron",Vector3(side*4.15,.32,5.53),Vector3(5.1,.51,.12),"55322f")
		for index in 22: piece("box",Vector3(side*4.15-2.40+index*.229,.32,5.608),Vector3(.028,.40,.035),"8b6947")
		box("StonePilaster",Vector3(side*6.69,1.86,5.48),Vector3(.40,3.7,.23),"c1b397","StonePilaster%d"%side,"stone")
		box("SidePlinth",Vector3(side*6.96,.20,0),Vector3(.07,.4,10.65),"82765e")
		for z in [-3.9,-1.3,1.3,3.9]: box("SidePier",Vector3(side*6.985,1.70,z),Vector3(.026,3.0,.18),"91816a")
	box("Cornice",Vector3(0,3.57,5.34),Vector3(13.97,.22,.5),"b39260")
	box("BurgundyFascia",Vector3(0,3.17,5.50),Vector3(13.02,.70,.20),"4e2837")
	for y in [2.85,3.49]: piece("box",Vector3(0,y,5.617),Vector3(12.84,.025,.025),"bd9b5a","metal")
	var name_label := Label3D.new()
	name_label.name = "CuritibaCellarName"
	name_label.text = "CURITIBA CELLAR"
	name_label.font_size = 90
	name_label.pixel_size = .0086
	name_label.outline_size = 0
	name_label.position = Vector3(0,3.18,5.624)
	name_label.modulate = Color("dfc99c")
	add_child(name_label)
	# Toldo de tecido bordô com uma borda fina de latão, projetando menos de 1 m.
	box("Canopy",Vector3(0,2.74,5.9),Vector3(13.05,.085,1.08),"552b3c","","cloth").rotation.x = .08
	box("CanopyLip",Vector3(0,2.688,6.44),Vector3(13.05,.075,.055),"ad8c50","","metal")
	for side in [-1,1]:
		var leaf := Node3D.new()
		leaf.name = "DoorLeaf%d"%side
		leaf.position = Vector3(side*.565,0,5.39)
		add_child(leaf)
		var glass_panel := box("DoorPanel",Vector3(0,1.34,0),Vector3(1.11,2.68,.09),"42534c","","bottle")
		remove_child(glass_panel)
		leaf.add_child(glass_panel)
		for edge in [-1,1]:
			var rail := box("DoorRail",Vector3(edge*.54,1.34,.061),Vector3(.045,2.68,.035),"bb9f66","","metal")
			remove_child(rail)
			leaf.add_child(rail)
		var handle := box("DoorHandle",Vector3(-side*.37,1.23,.095),Vector3(.035,.49,.055),"ceb179","","metal")
		remove_child(handle)
		leaf.add_child(handle)
		leaves.append(leaf)
		_collision(leaf,Vector3(0,1.34,0),Vector3(1.11,2.68,.13),"CellarDoor")
	box("StoneThreshold",Vector3(0,.04,5.61),Vector3(2.27,.08,.63),"b9ab90")
	box("Roof",Vector3(0,3.69,0),Vector3(13.98,.22,10.95),"53574b")
	for side in [-1,1]:
		box("RoofParapet",Vector3(side*6.77,3.92,0),Vector3(.23,.3,10.7),"a59c83")
		box("RoofParapet",Vector3(0,3.92,side*5.24),Vector3(13.7,.3,.23),"a59c83")
	box("RooftopCooling",Vector3(-3.7,4.05,-2.45),Vector3(1.45,.49,1.03),"7c867b","","metal")
	for i in 9: piece("box",Vector3(-4.26+i*.14,4.302,-2.45),Vector3(.054,.014,.86),"37433d","metal")
	# Estas carcaças autoradas justificam os acentos quentes da fachada. Não precisa
	# criar luz por quadro nem garrafas emissivas individuais.
	for side in [-1,1]:
		box("WallSconce",Vector3(side*1.43,2.00,5.60),Vector3(.16,.48,.15),"514c3c","","metal")
		box("SconceDiffuser",Vector3(side*1.43,2.00,5.686),Vector3(.09,.32,.024),"e8bf7c","","glow")
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("interior_solid_id"):
			_collision(self,child.position,child.mesh.get_aabb().size,str(child.get_meta("interior_solid_id")))
	anchor("Entrance",Vector3(0,0,6.7))
	anchor("Return",Vector3(0,0,7.8))
	flush_batches()
	set_process(false)
	set_physics_process(false)

func _collision(parent: Node3D, at: Vector3, size: Vector3, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label+"Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id",label)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at
	body.add_child(collision)
	parent.add_child(body)

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount,0,1)
	for index in leaves.size():
		leaves[index].position.x = (-1 if index == 0 else 1)*(.565+open_amount*1.16)


## A pintura troca somente a apresentação; caixas, folhas deslizantes e acesso são os originais.
## O catálogo de estilos é descoberto e retido automaticamente pelo PaintedFacadePrewarm.
func _build_painted() -> void:
	var visual := PAINTED.build(self,PAINTED_STYLE,Vector3(14,3.6,11),null,NAN,{"ground_door":false})
	# O kit também atende portas giratórias; este acesso conserva suas folhas de correr.
	for child in visual.get_children():
		if str(child.name).begins_with("Doorway_") or child.name in ["Roof","Cornice"]: child.free()
	_collision(self,Vector3(0,1.8,-5.35),Vector3(14,3.6,.3),"RearShell")
	for side in [-1,1]:
		_collision(self,Vector3(side*6.85,1.8,0),Vector3(.3,3.6,11),"SideShell%d"%side)
		_collision(self,Vector3(side*4.08,1.8,5.34),Vector3(5.83,3.6,.28),"FrontShell%d"%side)
		_collision(self,Vector3(side*6.69,1.86,5.48),Vector3(.40,3.7,.23),"StonePilaster%d"%side)
		_painted_box("StonePilaster%d"%side,Vector3(side*6.69,1.86,5.48),Vector3(.40,3.7,.23),"side")
	_painted_box("Roof",Vector3(0,3.69,0),Vector3(13.98,.22,10.95),"roof")
	for side in [-1,1]:
		_painted_box("RoofParapet",Vector3(side*6.77,3.92,0),Vector3(.23,.3,10.7),"side")
		_painted_box("RoofParapet",Vector3(0,3.92,side*5.24),Vector3(13.7,.3,.23),"side")
	_painted_box("RooftopCooling",Vector3(-3.7,4.05,-2.45),Vector3(1.45,.49,1.03),"roof")
	_painted_box("StoneThreshold",Vector3(0,.04,5.61),Vector3(2.27,.08,.63),"side")
	for side in [-1,1]:
		var leaf := Node3D.new()
		leaf.name = "DoorLeaf%d"%side
		leaf.position = Vector3(side*.565,0,5.39)
		add_child(leaf)
		# QuadMesh usa a imagem inteira: BoxMesh divide o UV entre seis faces.
		for facing in [-1,1]:
			var panel := MeshInstance3D.new()
			panel.name = "DoorPanel" if facing>0 else "DoorPanelInside"
			var quad := QuadMesh.new()
			quad.size = Vector2(1.11,2.68)
			panel.mesh = quad
			panel.position = Vector3(0,1.34,facing*.045)
			panel.rotation.y = PI if facing<0 else 0.0
			panel.material_override = PAINTED.material(PAINTED_STYLE,"door_front" if side<0 else "door_back")
			leaf.add_child(panel)
		_collision(leaf,Vector3(0,1.34,0),Vector3(1.11,2.68,0.13),"CellarDoor")
		leaves.append(leaf)
	anchor("Entrance",Vector3(0,0,6.7))
	anchor("Return",Vector3(0,0,7.8))
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
