extends RefCounted
## Prédios pintados (PaintedFacadeKit) da vila da serra: os quatro chalés e a loja
## "Casacos da Vila". O terminal fica em OriginalVillageArchitecture.
##
## Por que um arquivo à parte: a vila monta chalés e loja pelo PlaceCatalog (lugares
## com interior), com a cabana de lenhador e a ResortShop3D, que também servem a
## lugares fora da vila. Trocar só os da vila aqui não mexe nos outros.
##
## A entrada de verdade é a do WalkupFacadeDoor: porta em x=0 e z=walkup_door_z, para
## dentro em -Z. O prédio pintado é deslocado para que o vão da porta caia ali.
const KIT := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const CHALET_STYLES := ["chale-cedro", "chale-pedra", "chale-enxaimel"]
## Os chalés da vila ficam a 8,75 m um do outro (V1): 7,2 m de largura deixa passagem.
const CHALET_WIDTH := 7.2
## Fundo curto: o chalé 03 tem um banco da praça logo atrás.
const CHALET_DEPTH := 5.5
const SHOP_SIZE := Vector3(10.0, 5.0, 6.0)


static func handles(id: String) -> bool:
	return KIT.enabled() and (id.begins_with("mountain_cabin_village_") or id == "mountain_village_outfitters")


static func chalet_style(id: String) -> String:
	return CHALET_STYLES[posmod(hash(id), CHALET_STYLES.size())]


## Monta o exterior pintado do lugar `data` (definição do PlaceCatalog) e devolve o
## nó raiz já posicionado em `data.exterior_position` dentro de `chunk`.
static func build(chunk: Node3D, data: Dictionary) -> Node3D:
	var id := str(data.id)
	var style := "loja-casacos" if id == "mountain_village_outfitters" else chalet_style(id)
	var size := SHOP_SIZE
	if style != "loja-casacos":
		var natural := KIT.natural_size(style)
		size = Vector3(CHALET_WIDTH, CHALET_WIDTH * natural.y / natural.x, CHALET_DEPTH)
	var art := Node3D.new()
	art.name = "PaintedPlace_" + id
	art.position = data.exterior_position
	chunk.add_child(art)
	var door_z: float = PLACES.walkup_door_z(PLACES.walkup_family(id))
	var door_x := KIT.nearest_door_x(style, size.x, 0.0)
	var holder := Node3D.new()
	holder.name = "Building"
	# Frente na linha da porta do acesso e vão de entrada em x=0.
	holder.position = Vector3(-door_x, 0, door_z - size.z * 0.5)
	art.add_child(holder)
	KIT.build(holder, style, size, holder, door_x, {"snow": true})
	_entry_steps(art, style, size, door_z)
	return art


## A porta pintada pode começar acima do chão (base de pedra do chalé de cedro):
## degraus de madeira até a soleira, para a porta não ficar no ar.
static func _entry_steps(art: Node3D, style: String, size: Vector3, door_z: float) -> void:
	var sill := 0.0
	for opening in KIT.openings(style, "front"):
		if opening.leaf and absf(KIT.nearest_door_x(style, size.x, 0.0) - (-size.x * 0.5 + size.x * (float(opening.rect[0]) + float(opening.rect[2])) * 0.5)) < 0.05:
			sill = size.y * (1.0 - float(opening.rect[3]))
	if sill < 0.35: return
	var count := ceili(sill / 0.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("8a6a4c")
	mat.roughness = 0.9
	var body := StaticBody3D.new()
	body.name = "PaintedEntrySteps"
	body.collision_mask = 0
	art.add_child(body)
	for step in count:
		var top := sill * float(count - step) / float(count)
		var depth := 0.32
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.6, top, depth)
		mesh.mesh = box
		mesh.material_override = mat
		mesh.position = Vector3(0, top * 0.5, door_z + depth * (float(step) + 0.5))
		art.add_child(mesh)
		var shape := CollisionShape3D.new()
		var collision := BoxShape3D.new()
		collision.size = box.size
		shape.shape = collision
		shape.position = mesh.position
		body.add_child(shape)
