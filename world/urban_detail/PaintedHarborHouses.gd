extends RefCounted
class_name PaintedHarborHouses

## Casas pintadas (PaintedFacadeKit) do bairro Cobra e do Patrol Court, no porto.
## Arquivo próprio para não disputar PaintedFacadeKit.gd com as outras regiões.

## Cada casa do V1 ganhou um pacote de imagens feito para ela (o prompt citava o
## nome); o hash só cobre um id novo que apareça no bairro.
const COBRA := {
	"PorchHouse": "casa-varanda", "Duplex": "casa-duplex", "ShingleHouse": "casa-telha-madeira",
	"CobraWorkshop": "casa-oficina-cobra", "CourtyardHouse": "casa-patio",
	"BrickDuplex": "casa-tijolo-duplex", "TinRoofHouse": "casa-telha-zinco", "CornerBungalow": "casa-bangalo",
}
const PATROL := ["casa-patrol-a", "casa-patrol-b"]
## Prédios comerciais do porto com pacote próprio (output/imagegen, 15/10). O nome
## pintado vem do prompt (LAUNDRY, UNION WORKSHOP...) e não é o letreiro do jogo.
const HARBOR := {
	"Laundry": "lavanderia", "UnionWorkshop": "oficina-artesao", "MarketHall": "mercado-municipal",
	"FreightOffice": "escritorio-frete", "Aquarium": "aquario",
	"MaritimeMuseum": "museu-maritimo", "ColdStorage": "camara-fria",
	"CornerDiner": "lanchonete-esquina", "IslandGrocer": "mercado-ilha", "IslandCinema": "cinema",
	"PromenadeCafe": "cafe-orla",
	"NorthFireStation": "bombeiros",
	"Police": "delegacia",
	"NorthFrontage0": "banco",
}
## A casa do líder mantém a geometria antiga: CobraLeaderEntrance recorta HouseBody,
## FrontDoor e FrontPorch para a porta trancada da missão, e a fachada pintada não
## tem essas peças.
const KEEP_GEOMETRY := ["CourtyardHouse"]
## Profundidade da varanda que o catálogo tira da casa Cobra (at -0,9; size.y-1,8):
## a frente pintada fica onde está a entrada real do interior.
const COBRA_PORCH := 1.8


## Largura do prédio pintado. O kit repete o módulo da frente em prédio largo, e a
## porta repetia junto (duas portas lado a lado, uma só com interior); estilo de
## porto cabe num módulo só, na largura natural da pintura, e o catálogo, o interior
## e a fábrica usam esta mesma largura para casco, corte da entrada e piso baterem.
## Até 15% de folga a imagem estica; acima disso o prédio fica na largura natural.
static func footprint_width(building_id: String, width: float) -> float:
	if not PaintedFacadeKit.enabled() or not HARBOR.has(building_id): return width
	var natural := PaintedFacadeKit.natural_size(HARBOR[building_id]).x
	return width if width <= natural * 1.15 else natural


## Estilo pintado do prédio, ou "" quando ele continua com a geometria antiga.
static func style_for(building_id: String, kind: String) -> String:
	if not PaintedFacadeKit.enabled() or building_id in KEEP_GEOMETRY: return ""
	if kind == "cobra_house":
		if COBRA.has(building_id): return COBRA[building_id]
		var values: Array = COBRA.values()
		return values[posmod(hash(building_id), values.size())]
	if HARBOR.has(building_id): return HARBOR[building_id]
	if building_id.begins_with("PatrolCourt"):
		return PATROL[posmod(hash(building_id), PATROL.size())]
	return ""


## Monta a casa pintada em `building` (UrbanBuildingBase). A altura de parede é a
## natural do estilo (as imagens foram pintadas para ela; esticar 8,4 m de parede
## num desenho de 6 m deformava portas e janelas); a cumeeira sai de ridge_height.
static func build(building: Node3D, style: String) -> void:
	var size: Vector2 = building.building_size
	var depth := size.y
	var z := 0.0
	if building.building_kind == "cobra_house":
		depth -= COBRA_PORCH
		z = -COBRA_PORCH * 0.5
	var access: Dictionary = load("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").for_source(building.building_id)
	var walk_in_x: float = float((access.entrance_local as Vector3).x) if not access.is_empty() else NAN
	var visual := Node3D.new()
	visual.name = "PaintedHouseOffset"
	visual.position.z = z
	building.visuals_root.add_child(visual)
	var solid := Node3D.new()
	solid.name = "PaintedHouseSolidOffset"
	solid.position.z = z
	building.collision_root.add_child(solid)
	var wall_h := PaintedFacadeKit.natural_size(style).y
	PaintedFacadeKit.build(visual, style, Vector3(size.x, wall_h, depth), solid, walk_in_x)
