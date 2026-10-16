extends RefCounted
class_name PaintedFireStation

## Quartel NorthFireStation com a fachada pintada "bombeiros".
##
## O kit põe um casco de bloco único até a fachada; o quartel antigo tinha alas cheias e
## um vestíbulo de ~1,8 m atrás da baia central, onde o ator entra (o lugar
## harbor_fire_station abre por proximidade em x ≈ +2,33 m, dentro do portão da direita).
## Aqui o casco cheio sai e a colisão volta a ser a antiga, medida pelo vão pintado: alas
## de profundidade total dos dois lados do portão central, corpo raso atrás dele e verga
## acima do vão. Coordenadas em escala de origem (o editor de mundo estica tudo depois).

const STYLE := "bombeiros"
## Fundo do vestíbulo atrás do portão central (igual ao do quartel antigo).
const VESTIBULE_DEPTH := 1.8


static func build(building: UrbanBuildingBase) -> void:
	PaintedHarborHouses.build(building, STYLE)
	for hull in building.collision_root.find_children("PaintedFacadeSolid", "StaticBody3D", true, false):
		hull.free()
	var kit := building.visuals_root.find_child("PaintedFacade_" + STYLE, true, false)
	var sink: float = kit.get_meta("ground_sink", 0.0) if kit != null else 0.0
	var size := building.building_size
	var wall_h := PaintedFacadeKit.natural_size(STYLE).y
	var gate := _central_gate(size.x)
	_add_hull(building, size, wall_h - sink, gate, (1.0 - gate.top) * wall_h - sink)


## Portão central: o vão sem folha que contém a entrada do lugar (PlaceCatalog).
static func _central_gate(width: float) -> Dictionary:
	var entry_x: float = preload("res://world/places/PlaceCatalog.gd").FIRE_STATION_DOOR_OFFSET.x
	var best := {"x0": -1.0, "x1": 1.0, "top": 0.56}
	for opening in PaintedFacadeKit.openings(STYLE, "front"):
		if opening.leaf: continue
		var x0 := (float(opening.rect[0]) - 0.5) * width
		var x1 := (float(opening.rect[2]) - 0.5) * width
		if entry_x > x0 and entry_x < x1:
			best = {"x0": x0, "x1": x1, "top": float(opening.rect[1])}
	return best


static func _add_hull(building: UrbanBuildingBase, size: Vector2, wall_h: float, gate: Dictionary, gate_top: float) -> void:
	var half_w := size.x * 0.5
	var body := StaticBody3D.new()
	body.name = "PaintedFireHullSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	building.collision_root.add_child(body)
	var x0: float = gate.x0
	var x1: float = gate.x1
	# Alas de profundidade total dos dois lados do portão central.
	_box(body, Vector3((-half_w + x0) * 0.5, wall_h * 0.5, 0), Vector3(x0 + half_w, wall_h, size.y))
	_box(body, Vector3((x1 + half_w) * 0.5, wall_h * 0.5, 0), Vector3(half_w - x1, wall_h, size.y))
	# Corpo raso atrás do portão: o vestíbulo fica livre na frente.
	_box(body, Vector3((x0 + x1) * 0.5, wall_h * 0.5, -VESTIBULE_DEPTH * 0.5), Vector3(x1 - x0, wall_h, size.y - VESTIBULE_DEPTH))
	# Verga: fecha o vão acima do portão.
	_box(body, Vector3((x0 + x1) * 0.5, (wall_h + gate_top) * 0.5, size.y * 0.5 - VESTIBULE_DEPTH * 0.5), Vector3(x1 - x0, wall_h - gate_top, VESTIBULE_DEPTH))


static func _box(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = center
	body.add_child(shape)
