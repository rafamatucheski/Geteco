extends RefCounted
class_name PaintedBankBranch

## Banco "NORTH PIER" (id NorthFrontage0) com a fachada pintada do estilo `banco`.
##
## O kit monta paredes, telhado e portas, mas a entrada do banco tem regras que ele não
## conhece: a abertura vem de WeaponShopEntrance (`set_open_amount`, com a admissão do
## banco fechado para investigação e por estrelas de procurado), não da proximidade, e a
## transição para o interior acontece num vestíbulo raso atrás da folha. Por isso, como
## na delegacia (PaintedPoliceStation): o casco inteiro do kit e as zonas que abrem a
## porta sozinhas saem, e a colisão é refeita (corpo mais raso, alas da frente, laterais
## do vestíbulo e verga), medida pelo vão da fachada pintada.
## O caixa eletrônico e o letreiro NORTH PIER já vêm na pintura; o jogo não tem caixa
## eletrônico interativo, então o 3D antigo (BankATM_*, letreiro) simplesmente não existe.

const STYLE := "banco"
## Fundo do vestíbulo atrás da porta; o interior só começa depois dele.
const VESTIBULE_DEPTH := 1.5


static func build(building: UrbanBuildingBase) -> Array[PaintedFacadeKit.PaintedDoor]:
	var size := building.building_size
	var natural := PaintedFacadeKit.natural_size(STYLE)
	var visual := Node3D.new()
	visual.name = "PaintedBankOffset"
	building.visuals_root.add_child(visual)
	var solid := Node3D.new()
	solid.name = "PaintedBankSolidScratch"
	building.collision_root.add_child(solid)
	# Entrada no meio da fachada (o vão pintado é central); `walk_in` dá o verso da folha.
	var root := PaintedFacadeKit.build(visual, STYLE, Vector3(size.x, natural.y, size.y), solid, 0.0)
	building.set_meta("painted_facade_style", STYLE)
	# Casco de caixa cheia e área de abertura por proximidade não servem aqui.
	for hull in solid.find_children("PaintedFacadeSolid", "StaticBody3D", true, false): hull.free()
	var doors: Array[PaintedFacadeKit.PaintedDoor] = []
	var anchor := root.get_node_or_null("Doorway_front")
	if anchor != null and anchor.has_meta("walk_in"):
		for leaf_name in ["Door", "Door2"]:
			var leaf := anchor.get_node_or_null(leaf_name) as PaintedFacadeKit.PaintedDoor
			if leaf == null: continue
			for zone in leaf.find_children("DoorZone", "Area3D", false, false): zone.free()
			doors.append(leaf)
	var sink: float = root.get_meta("ground_sink", 0.0)
	_add_hull(building, size, natural.y - sink, opening_half_width(size.x), _opening_height(natural.y))
	return doors


## Entrada de verdade num prédio de pegada `size` (frente em +Z): centro do vão pintado,
## no chão e no plano das folhas fechadas. WeaponShopEntrance seguia a porta de vidro do
## banco 3D antigo, 0,72 m recuada, e a entrada ficava 0,68 m atrás das folhas pintadas,
## dentro do vestíbulo (auditoria de portas, 19/10).
static func entrance_local(size: Vector2) -> Vector3:
	return Vector3(PaintedFacadeKit.nearest_door_x(STYLE, size.x, 0.0), 0.0, size.y * 0.5 - PaintedFacadeKit.LEAF_INSET)


## Altura da parede pintada acima do chão (o kit afunda o prédio até a soleira).
static func wall_height() -> float:
	var wall_h := PaintedFacadeKit.natural_size(STYLE).y
	var lowest := INF
	for opening in PaintedFacadeKit.openings(STYLE, "front"):
		if bool(opening.leaf): lowest = minf(lowest, (1.0 - float(opening.rect[3])) * wall_h)
	var sink := maxf(0.0, lowest - 0.03) if lowest < INF else 0.0
	return wall_h - sink


## Altura do piso do telhado acima do chão (mesma folga de +0,14 m que o catálogo dava).
static func roof_height() -> float:
	return wall_height() + 0.14


## Meia largura do vão pintado da frente num prédio de `width` metros.
static func opening_half_width(width: float) -> float:
	var rects: Array = PaintedFacadeKit.openings(STYLE, "front")
	if rects.is_empty(): return 1.2
	var rect: Array = rects[0].rect
	return (float(rect[2]) - float(rect[0])) * width * 0.5


static func _opening_height(wall_h: float) -> float:
	var rects: Array = PaintedFacadeKit.openings(STYLE, "front")
	if rects.is_empty(): return 3.0
	var rect: Array = rects[0].rect
	return (float(rect[3]) - float(rect[1])) * wall_h


## Corpo raso, alas finas dos dois lados da porta, laterais do vestíbulo e verga acima dele.
static func _add_hull(building: UrbanBuildingBase, size: Vector2, wall_h: float, half_opening: float, opening_h: float) -> void:
	var half_w := size.x * 0.5
	var front_z := size.y * 0.5
	var body := StaticBody3D.new()
	body.name = "PaintedBankHullSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	building.collision_root.add_child(body)
	_box(body, Vector3(0, wall_h * 0.5, -VESTIBULE_DEPTH * 0.5), Vector3(size.x, wall_h, size.y - VESTIBULE_DEPTH))
	var wing := half_w - half_opening
	for side in [-1.0, 1.0]:
		_box(body, Vector3(side * (half_opening + wing * 0.5), wall_h * 0.5, front_z - 0.12), Vector3(wing, wall_h, 0.24))
		_box(body, Vector3(side * (half_opening + 0.1), opening_h * 0.5, front_z - VESTIBULE_DEPTH * 0.5 - 0.05), Vector3(0.2, opening_h, VESTIBULE_DEPTH - 0.1))
	# Verga: fecha o vão acima da folha (a parede pintada segue até o telhado).
	_box(body, Vector3(0, (wall_h + opening_h) * 0.5, front_z - VESTIBULE_DEPTH * 0.5), Vector3(half_opening * 2.0 + 0.4, wall_h - opening_h, VESTIBULE_DEPTH))


static func _box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
