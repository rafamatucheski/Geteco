extends RefCounted
## Casca pintada (PaintedFacadeKit) das seis casas rurais da Vila dos Caminhoneiros.
##
## As casas NÃO são UrbanBuildingBase: TruckersVillageHomes monta casco, interior,
## porta (`DoorPivot` + colisão `EntryDoor`), telhado (`Roof`) e paredes altas
## (`UpperWalls`) numa peça só, e guardas, moradores, porão e quest dependem desses
## nomes. Por isso o kit entra só como VISUAL externo: as caixas de colisão e o
## interior ficam como estavam, e o kit é pendurado nos mesmos ganchos de
## recorte (paredes em `UpperWalls`, telhado em `Roof`), que somem ao entrar.
##
## A porta pintada do kit NÃO é usada (seria uma segunda porta): o vão pintado é a
## abertura onde a `DoorPivot` 3D de sempre gira, e ela só ganha a imagem `door_front`.
##
## Interruptor: GETECO_PAINTED_TRUCKERS_HOMES (provisório: =1 liga; depois =0 desliga) e GETECO_PAINTED_FACADES=0 voltam
## às caixas antigas, para A/B.

## Mesma ordem de HOME_LAYOUT. Cores antigas das paredes -> estilo mais próximo:
## a49673 areia -> b (bege); 989e82 cinza-oliva -> c (verde-oliva); ac8d72 marrom
## claro -> b; 929e94 cinza azulado -> chapa; b4aa87 bege -> b; 9f8976 -> chapa.
const STYLES := ["casa-rural-chapa-b", "casa-rural-chapa-c", "casa-rural-chapa-b",
	"casa-rural-chapa", "casa-rural-chapa-b", "casa-rural-chapa"]
## Face externa das paredes de caixa: x = ±6,5 e z = ±4,5. O kit fica 2 cm para fora
## para a pintura não brigar (z-fighting) com a caixa que continua atrás dela.
const SHELL_SIZE := Vector3(13.04, 3.0, 9.04)
const DEFAULT_DOOR_WIDTH := 1.8
const DEFAULT_DOOR_HEIGHT := 2.28


static func enabled() -> bool:
	# PROVISÓRIO: desligado por padrão até o teste e as capturas passarem. Quando passarem,
	# inverter para `== "0"` (ligado por padrão, "0" desliga).
	if not PaintedFacadeKit.enabled() or OS.get_environment("GETECO_PAINTED_TRUCKERS_HOMES") != "1": return false
	# Pacote de textura ausente (ainda não importado): cai nas caixas em vez de quebrar.
	return not PaintedFacadeKit.style_data(STYLES[0]).is_empty()


static func style_for(index: int) -> String:
	return STYLES[index % STYLES.size()]


## Vão de porta da casa no quadro local: centro X, largura e altura do vão pintado
## (medidos da imagem, por estilo). Sem kit: porta 1,8 x 2,28 centrada, como antes.
static func door_layout(index: int) -> Dictionary:
	if not enabled(): return {"x": 0.0, "width": DEFAULT_DOOR_WIDTH, "height": DEFAULT_DOOR_HEIGHT, "painted": false}
	var style := style_for(index)
	for opening in PaintedFacadeKit.openings(style, "front"):
		if not bool(opening.leaf): continue
		var rect: Array = opening.rect
		var width := (float(rect[2]) - float(rect[0])) * SHELL_SIZE.x
		var height := (float(rect[3]) - float(rect[1])) * SHELL_SIZE.y
		var center := -SHELL_SIZE.x * 0.5 + (float(rect[0]) + float(rect[2])) * 0.5 * SHELL_SIZE.x
		return {"x": center, "width": width, "height": height, "painted": true}
	return {"x": 0.0, "width": DEFAULT_DOOR_WIDTH, "height": DEFAULT_DOOR_HEIGHT, "painted": false}


## Monta a casca pintada da casa `room` e devolve o nó do kit. Paredes (Front, Back,
## Sides) ficam em `UpperWalls`; o telhado vai para `Roof`. Os dois escondem juntos
## quando o jogador entra (TruckersVillageHomes._set_inside) e quando ele desce ao
## porão (TruckersVillageSecretPassage).
static func build_shell(room: Dictionary) -> Node3D:
	var style := style_for(int(room.index))
	var upper: Node3D = room.upper
	var roof: Node3D = room.roof
	# Sem collision_parent: a colisão das paredes e da porta já é da casa. Sem
	# walk_in_x: a folha do kit não é usada (removida abaixo).
	var kit := PaintedFacadeKit.build(upper, style, SHELL_SIZE, null, NAN)
	# O kit cria uma âncora `Doorway_front` com a folha pintada no vão. A porta que
	# gira é a DoorPivot 3D: duas portas seriam o erro que o usuário proibiu.
	for child in kit.get_children():
		if String(child.name).begins_with("Doorway_"):
			kit.remove_child(child)
			child.free()
	var roof_mesh := kit.get_node_or_null("Roof") as Node3D
	if roof_mesh != null:
		kit.remove_child(roof_mesh)
		roof.add_child(roof_mesh)
		roof_mesh.position = kit.position
	kit.set_meta("style", style)
	return kit


## Imagem da folha pintada (frente e verso) na `DoorPivot` 3D, que continua sendo a
## única porta: dobradiça na ombreira esquerda, gira por proximidade como sempre.
static func dress_door(pivot: Node3D, index: int, width: float, height: float, thickness: float) -> void:
	var style := style_for(index)
	var half := thickness * 0.5
	var front := MeshInstance3D.new()
	front.name = "PaintedDoorFront"
	var front_mesh := QuadMesh.new()
	front_mesh.size = Vector2(width, height)
	front.mesh = front_mesh
	front.position = Vector3(width * 0.5, height * 0.5, half + 0.004)
	front.material_override = PaintedFacadeKit.material(style, "door_front")
	pivot.add_child(front)
	var back := MeshInstance3D.new()
	back.name = "PaintedDoorBack"
	var back_mesh := QuadMesh.new()
	back_mesh.size = Vector2(width, height)
	back.mesh = back_mesh
	back.position = Vector3(width * 0.5, height * 0.5, -half - 0.004)
	back.rotation.y = PI
	back.material_override = PaintedFacadeKit.material(style, "door_front_inside")
	pivot.add_child(back)
