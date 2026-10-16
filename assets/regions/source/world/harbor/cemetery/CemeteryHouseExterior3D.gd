extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"

const KIT := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const PAINTED_STYLE := "casa-zelador"
## Casco do chalé (m): o mesmo das caixas antigas, para colisão, interior e porta baterem.
const HULL := Vector3(7.1, 2.7, 5.4)
## Plano da folha: logo à frente do casco, na linha da dobradiça do WalkupFacadeDoor (z 2,8).
const LEAF_Z := 2.77
static var _recess_material: StandardMaterial3D

var door: Node3D
var window_light: MeshInstance3D


## PROVISÓRIO: desligado por padrão até esclarecer o travamento de test_keeper_house;
## só liga com GETECO_PAINTED_KEEPER=1. Ao fechar, inverter para `!= "0"` (liga por padrão).
static func painted_enabled() -> bool:
	return KIT.enabled() and OS.get_environment("GETECO_PAINTED_KEEPER") == "1"

func _ready() -> void:
	box("StoneFoundation", Vector3(7.6, .3, 5.9), Vector3(0, .05, 0), "666657")
	box("LimewashedCottage", Vector3(7.1, 2.7, 5.4), Vector3(0, 1.5, 0), "99947a").set_meta("interior_solid_id", &"CottageWalls")
	for z in [-2.65, 2.65]:
		box("DarkWoodLintel", Vector3(7.3, .16, .18), Vector3(0, 2.73, z), "494639")
	for x in [-3.45, 3.45]:
		box("CornerStone", Vector3(.23, 2.6, .25), Vector3(x, 1.4, 2.7), "747463")
	# Two sloped roof planes, narrow tile courses, a capped chimney.
	for side in [-1.0, 1.0]:
		var roof := box("TerracottaRoof", Vector3(4.0, .16, 6.1), Vector3(side * 1.78, 3.28, 0), "714c3c")
		roof.rotation.z = -side * .25
		for row in 9:
			var strip := box("TileCourse", Vector3(.075, .05, 6.12), Vector3(side * (.1 + row * .43), 3.75 - row * .11, 0), "925f46")
			strip.rotation.z = -side * .25
	box("RidgeCap", Vector3(.22, .17, 6.25), Vector3(0, 3.83, 0), "b07b56")
	box("Chimney", Vector3(.62, 1.2, .67), Vector3(2.3, 3.65, -1.5), "77766a")
	box("ChimneyCap", Vector3(.78, .16, .83), Vector3(2.3, 4.3, -1.5), "414a40")
	box("DoorRecess", Vector3(1.25, 2.2, .06), Vector3(0, 1.24, 2.74), "242e29")
	door = Node3D.new()
	door.name = "HingedDoor"
	door.position = Vector3(-.55, .18, 2.8)
	add_child(door)
	for i in 6: box("DoorPlank", Vector3(.18, 2.06, .10), Vector3(.09 + i * .18, 1.03, 0), "53614b", door)
	box("DoorHandle", Vector3(.035, .16, .045), Vector3(.93, 1.05, .075), "b69a62", door)
	box("StoneStep", Vector3(1.6, .15, .65), Vector3(0, .03, 3.07), "a4a18a")
	box("SignBoard", Vector3(3.4, .42, .09), Vector3(0, 2.55, 2.86), "3d4b3f")
	lettering("CASA DO COVEIRO", Vector3(0, 2.57, 2.93), 30)
	for x in [-2.2, 2.2]:
		box("WindowFrame", Vector3(1.42, 1.23, .14), Vector3(x, 1.62, 2.79), "414d3d")
		window_light = box("WindowGlass", Vector3(1.13, .93, .05), Vector3(x, 1.62, 2.88), "c8a56a")
		window_light.set_meta("city_window", true)
		box("WindowMullion", Vector3(.065, 1.02, .08), Vector3(x, 1.62, 2.94), "656a51")
		box("WindowSill", Vector3(1.55, .10, .26), Vector3(x, 1.0, 2.89), "696b54")
		for side in [-1, 1]: box("GreenShutter", Vector3(.45, 1.2, .10), Vector3(x + side * .91, 1.62, 2.79), "4d5d46")
	lantern(Vector3(.88, 1.5, 2.88))
	for i in 3:
		box("Firewood", Vector3(.8, .17, .22), Vector3(2.75, .22 + i * .16, 3.0), "5e4a34")
	var sign_node := lettering("06h — 00h\nNÃO ENTRE DE MADRUGADA", Vector3(-2.2, .70, 2.96), 14)
	sign_node.modulate = Color("dfc894")
	if painted_enabled(): _paint_over()


## Troca o visual por PaintedFacadeKit sem tocar no que o jogo usa do chalé:
## - `LimewashedCottage` fica (escondido): é o sólido do interior (`interior_solid_id`) e a
##   colisão das paredes, que o WalkupFacadeDoor recorta para o vão da porta;
## - `HingedDoor` fica vazio: o WalkupFacadeDoor leva os filhos dele para a dobradiça que o
##   empurrão do jogador gira, então a folha pintada é filha dele (a única porta que abre);
## - fundação, degrau, telhado, janelas, placa, lenha e lampião 3D saem (o desenho já os traz;
##   escondidos, a fundação e o degrau seriam um meio-fio invisível sem pintura por cima).
func _paint_over() -> void:
	for node in get_children():
		if node.name == &"LimewashedCottage" or node == door: continue
		if node is MeshInstance3D or node is Label3D or node.name == &"OilLantern": node.free()
	window_light = null
	for node in door.get_children(): node.free()
	# Pivô na origem: a folha pintada usa coordenadas da casa e o adaptador a leva à dobradiça.
	door.position = Vector3.ZERO
	var cottage := get_node("LimewashedCottage") as MeshInstance3D
	# O desenho assenta no chão (a fundação saiu): o casco desce até y=0.
	(cottage.mesh as BoxMesh).size = Vector3(HULL.x, HULL.y + .15, HULL.z)
	cottage.position.y = (HULL.y + .15) * .5
	cottage.visible = false
	var holder := Node3D.new()
	holder.name = "PaintedKeeperHouse"
	add_child(holder)
	var facade := KIT.build(holder, PAINTED_STYLE, HULL, null, NAN, {"snow": false})
	var opening: Array = KIT.openings(PAINTED_STYLE, "front")[0].rect
	# O kit põe a própria folha no vão; aqui a folha é a do WalkupFacadeDoor.
	for node in facade.get_children():
		if str(node.name).begins_with("Doorway_front"):
			for child in node.get_children(): child.free()
	var leaf_w := (float(opening[2]) - float(opening[0])) * HULL.x
	var leaf_h := (float(opening[3]) - float(opening[1])) * HULL.y
	var center_x := (-.5 + (float(opening[0]) + float(opening[2])) * .5) * HULL.x
	var bottom := (1.0 - float(opening[3])) * HULL.y - float(facade.get_meta("ground_sink", 0.0))
	var recess := MeshInstance3D.new()
	recess.name = "DoorRecessPainted"
	var recess_mesh := BoxMesh.new()
	recess_mesh.size = Vector3(leaf_w, leaf_h, .5)
	recess.mesh = recess_mesh
	recess.position = Vector3(center_x, bottom + leaf_h * .5, HULL.z * .5 - .25)
	recess.material_override = _recess()
	holder.add_child(recess)
	for inside in [false, true]:
		var leaf := MeshInstance3D.new()
		leaf.name = "PaintedDoorLeaf" + ("Inside" if inside else "")
		leaf.mesh = QuadMesh.new()
		(leaf.mesh as QuadMesh).size = Vector2(leaf_w, leaf_h)
		leaf.material_override = KIT.material(PAINTED_STYLE, "door_front_inside" if inside else "door_front")
		leaf.position = Vector3(center_x, bottom + leaf_h * .5, LEAF_Z - (.01 if inside else 0.0))
		if inside: leaf.rotation.y = PI
		door.add_child(leaf)


static func _recess() -> StandardMaterial3D:
	if _recess_material == null:
		_recess_material = StandardMaterial3D.new()
		_recess_material.albedo_color = Color("1c1a17")
		_recess_material.roughness = .95
		# Só as faces de dentro: de fora se vê o fundo do vão.
		_recess_material.cull_mode = BaseMaterial3D.CULL_FRONT
	return _recess_material

func set_door_open(open: bool) -> void:
	if door:
		var tween := create_tween()
		tween.tween_property(door, "rotation:y", -1.3 if open else 0.0, .35)
