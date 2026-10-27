extends RefCounted
## Prédios pintados (PaintedFacadeKit) da serra: os quatro chalés e a loja "Casacos da Vila" da
## vila e, desde 27/10, os lugares com pacote próprio (Estação Zero, Cume Branco, Boutique Alpina,
## Último Abrigo, Ammu-Nation, cabanas de toras e Posto Florestal). O terminal fica em
## OriginalVillageArchitecture.
##
## Por que um arquivo à parte: os lugares saem do PlaceCatalog (lugares com interior) e os modelos
## 3D antigos (cabana de lenhador, ResortShop3D, SummitSkiLodge3D...) continuam valendo quando o kit
## está desligado (GETECO_PAINTED_FACADES=0) ou o pacote não foi importado.
##
## A entrada de verdade é a do WalkupFacadeDoor: porta em x=0 e z=walkup_door_z, para dentro em -Z
## (a loja de armas usa o plano da WeaponShopEntrance). O prédio pintado é deslocado para que o vão
## da porta caia ali.
const KIT := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const PLACES := preload("res://world/places/PlaceCatalog.gd")
const CHALET_STYLES := ["chale-cedro", "chale-pedra", "chale-enxaimel"]
## Os chalés da vila ficam a 8,75 m um do outro (V1): 7,2 m de largura deixa passagem.
const CHALET_WIDTH := 7.2
## Fundo curto: o chalé 03 tem um banco da praça logo atrás.
const CHALET_DEPTH := 5.5
const SHOP_SIZE := Vector3(10.0, 5.0, 6.0)
## Pacotes do GPT de 27/10: estilo e fundo (m) de cada lugar. Largura e altura vêm do módulo da
## pintura, escolhido pelo tamanho da porta (tools/painted_facades_serra.json); as frentes da
## Estação Zero e do Cume Branco vieram mais altas que o pedido e o prédio segue a imagem.
const PLACE_STYLES := {
	"mountain_bunker": ["estacao-zero", 7.4],
	"ski_lodge": ["cume-branco", 8.4],
	"mountain_boutique": ["boutique-alpina", 4.0],
	"mountain_outfitters": ["ultimo-abrigo", 4.0],
	"mountain_gunshop": ["ammunation-serra", 5.0],
	"mountain_cabin": ["cabana-toras", 4.6],
	"mountain_cabin_encosta": ["cabana-toras", 4.6],
	"lumberjack_shelter": ["cabana-toras", 4.6],
	"mountain_cabin_forest": ["posto-florestal", 4.6],
}
## Plano da porta da loja de armas: WeaponShopEntrance usa exterior + 2,7 m em Z.
const GUNSHOP_DOOR_Z := 2.7


## Frente pintada que a WeaponShopEntrance abre como as lojas 3D (set_open_amount), girando a
## folha pintada da entrada. `leaves` dá o plano de contato da porta.
class PaintedShopFront extends Node3D:
	var leaves: Array[Node3D] = []
	var open_amount := 0.0

	func set_open_amount(amount: float) -> void:
		open_amount = clampf(amount, 0.0, 1.0)
		for leaf in leaves:
			if is_instance_valid(leaf): leaf.set_open_amount(open_amount)


static func handles(id: String) -> bool:
	if not KIT.enabled(): return false
	if id.begins_with("mountain_cabin_village_") or id == "mountain_village_outfitters": return true
	return PLACE_STYLES.has(id) and FileAccess.file_exists(KIT.ROOT + str(PLACE_STYLES[id][0]) + "/style.json")


static func chalet_style(id: String) -> String:
	return CHALET_STYLES[posmod(hash(id), CHALET_STYLES.size())]


static func style_for(id: String) -> String:
	if PLACE_STYLES.has(id): return PLACE_STYLES[id][0]
	return "loja-casacos" if id == "mountain_village_outfitters" else chalet_style(id)


static func size_for(id: String) -> Vector3:
	var style := style_for(id)
	var natural := KIT.natural_size(style)
	if PLACE_STYLES.has(id): return Vector3(natural.x, natural.y, float(PLACE_STYLES[id][1]))
	if style == "loja-casacos": return SHOP_SIZE
	return Vector3(CHALET_WIDTH, CHALET_WIDTH * natural.y / natural.x, CHALET_DEPTH)


static func door_z(id: String) -> float:
	if id == "mountain_gunshop": return GUNSHOP_DOOR_Z
	return PLACES.walkup_door_z(PLACES.walkup_family(id))


## Centro local do prédio (a origem é o ponto de acesso do lugar): frente na linha da porta e
## vão da entrada em x=0.
static func building_center(id: String) -> Vector3:
	var size := size_for(id)
	return Vector3(-KIT.nearest_door_x(style_for(id), size.x, 0.0), 0, door_z(id) - size.z * 0.5)


## Monta o exterior pintado do lugar `data` (definição do PlaceCatalog) e devolve o
## nó raiz já posicionado em `data.exterior_position` dentro de `chunk`.
static func build(chunk: Node3D, data: Dictionary) -> Node3D:
	var id := str(data.id)
	var style := style_for(id)
	var size := size_for(id)
	var art: Node3D = PaintedShopFront.new() if id == "mountain_gunshop" else Node3D.new()
	art.name = "PaintedPlace_" + str(data.get("access_id", id))
	art.position = data.exterior_position
	chunk.add_child(art)
	var door_x := KIT.nearest_door_x(style, size.x, 0.0)
	var holder := Node3D.new()
	holder.name = "Building"
	# Frente na linha da porta do acesso e vão de entrada em x=0.
	holder.position = building_center(id)
	art.add_child(holder)
	# O kit afunda o prédio até a soleira tocar o chão: sem degraus de acesso.
	var root := KIT.build(holder, style, size, holder, door_x, {"snow": true})
	if art is PaintedShopFront:
		for anchor in root.find_children("Doorway_front*", "Node3D", true, false):
			if not anchor.has_meta("walk_in"): continue
			for leaf in anchor.get_children():
				if leaf is PaintedFacadeKit.PaintedDoor: art.leaves.append(leaf)
	if id == "mountain_bunker":
		# Gerador, mastro, radar e heliponto continuam 3D; o que ia no teto sobe para a laje pintada.
		var props = preload("res://world/places/BunkerExteriorNative.gd").new()
		props.painted_roof_y = size.y - float(root.get_meta("ground_sink", 0.0))
		props.painted_center = holder.position
		props.painted_size = size
		art.add_child(props)
	return art
