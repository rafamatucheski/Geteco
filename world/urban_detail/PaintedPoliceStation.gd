extends RefCounted
class_name PaintedPoliceStation

## Delegacia "HARBOR PATROL" (id Police) com a fachada pintada do estilo `delegacia`.
##
## O kit monta paredes, telhado e portas, mas a entrada da delegacia tem regras que ele
## não conhece: a colisão do casco deixa um vestíbulo raso atrás da porta (a transição
## para o interior acontece nele) e a abertura vem de WeaponShopEntrance
## (`set_open_amount`, com admissão por estrelas de procurado), não da proximidade. Por
## isso aqui: o casco inteiro do kit e a zona que abre a porta sozinha são removidos, e
## a colisão é refeita como a do prédio antigo (corpo mais raso, alas da frente, laterais
## do vestíbulo), medida pelo vão da fachada pintada.
## Coordenadas em escala de origem: o editor de mundo estica o prédio inteiro depois
## (WorldServiceBuildings.apply_art), colisão e malha juntas.

const STYLE := "delegacia"
## Fundo do vestíbulo atrás da porta; o interior só começa depois dele.
const VESTIBULE_DEPTH := 1.5


static func build(building: UrbanBuildingBase) -> Array[PaintedFacadeKit.PaintedDoor]:
	var size := building.building_size
	var natural := PaintedFacadeKit.natural_size(STYLE)
	var visual := Node3D.new()
	visual.name = "PaintedPoliceOffset"
	building.visuals_root.add_child(visual)
	var solid := Node3D.new()
	solid.name = "PaintedPoliceSolidScratch"
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
	_add_hull(building, size, natural.y - sink, _opening_half_width(size.x))
	return doors


static func _opening_half_width(width: float) -> float:
	var rects: Array = PaintedFacadeKit.openings(STYLE, "front")
	if rects.is_empty(): return 1.2
	var rect: Array = rects[0].rect
	return (float(rect[2]) - float(rect[0])) * width * 0.5


## Mesma colisão que _build_police_precinct fazia: corpo raso, alas finas dos dois lados
## da porta, laterais do vestíbulo e verga acima dele.
static func _add_hull(building: UrbanBuildingBase, size: Vector2, wall_h: float, half_opening: float) -> void:
	var half_w := size.x * 0.5
	var front_z := size.y * 0.5
	var body := StaticBody3D.new()
	body.name = "PaintedPoliceHullSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	building.collision_root.add_child(body)
	_box(body, Vector3(0, wall_h * 0.5, -VESTIBULE_DEPTH * 0.5), Vector3(size.x, wall_h, size.y - VESTIBULE_DEPTH))
	var wing := half_w - half_opening
	for side in [-1.0, 1.0]:
		_box(body, Vector3(side * (half_opening + wing * 0.5), wall_h * 0.5, front_z - 0.12), Vector3(wing, wall_h, 0.24))
		_box(body, Vector3(side * (half_opening + 0.1), 1.5, front_z - VESTIBULE_DEPTH * 0.5 - 0.05), Vector3(0.2, 3.0, VESTIBULE_DEPTH - 0.1))
	# Verga: fecha o vão acima da porta (a folha tem ~2,7 m; a parede pintada segue até o telhado).
	_box(body, Vector3(0, (wall_h + 3.0) * 0.5, front_z - VESTIBULE_DEPTH * 0.5), Vector3(half_opening * 2.0 + 0.4, wall_h - 3.0, VESTIBULE_DEPTH))


static func _box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
