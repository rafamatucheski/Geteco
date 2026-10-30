extends SceneTree

## Loja Tônico com fachada pintada: kit único no lugar do casco, porta pintada central
## que coincide com a entrada do catálogo (e abre), colisão do casco e cobertura do posto
## preservadas, sem letreiro/porta/janelas 3D duplicados, e o interruptor
## GETECO_PAINTED_TONICO=0 devolve a caixa antiga.

const VILLAGE := preload("res://gameplay/urban_v1/TruckersVillageVisuals.gd")
## Estilo em uso: loja compacta do posto compacto (padrão) ou a larga.
var STYLE: String = PaintedTonicoShop.style()
var failures: Array = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void: run.call_deferred()

func _tonico_labels(village: Node) -> int:
	var count := 0
	for label in village.find_children("*", "Label3D", true, false):
		if label.text == "Tonico": count += 1
	return count

func run() -> void:
	OS.set_environment("GETECO_PAINTED_TONICO", "1")
	var scene := Node3D.new()
	root.add_child(scene)
	var village: Node3D = VILLAGE.new()
	scene.add_child(village)
	village.tonico.set_physics_process(false)
	for frame in 3: await physics_frame
	STYLE = PaintedTonicoShop.style()
	var kits := village.find_children("PaintedFacade_" + STYLE, "Node3D", true, false)
	check(kits.size() == 1, "um kit PaintedFacade_%s (achou %d)" % [STYLE, kits.size()])
	# No posto compacto o letreiro do poste é a faixa pintada, sem Label3D.
	var labels_expected := 0 if PaintedTonicoShop.compact_enabled() else 1
	check(_tonico_labels(village) == labels_expected, "letreiros Label3D Tonico: %d (esperado %d)" % [_tonico_labels(village), labels_expected])
	if kits.size() != 1:
		print("PAINTED_TONICO checks=%d failures=%s" % [checks, failures])
		quit(1)
		return
	var kit: Node3D = kits[0]
	var def: Dictionary = load("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").for_source("TruckersStationStore")
	check(not def.is_empty(), "catálogo tem TruckersStationStore")
	# Largura e posição batem com o catálogo (casco, entrada e interior usam o mesmo retângulo).
	var natural := PaintedFacadeKit.natural_size(STYLE)
	check(absf(natural.x - float(def.size.x)) < 0.1, "módulo %.2f m = largura do catálogo %.2f m" % [natural.x, def.size.x])
	check(absf(natural.z - float(def.size.y)) < 0.1, "lateral %.2f m = profundidade do catálogo %.2f m" % [natural.z, def.size.y])
	var center: Vector3 = kit.get_parent().global_position
	var expected: Vector3 = def.exterior_position
	check(Vector2(center.x - expected.x, center.z - expected.z).length() < 0.05, "centro do kit %s = centro do catálogo %s" % [center, expected])
	# Uma só porta de frente, no vão central, que é a entrada do catálogo; sem Door2 (vão de 1,3 m).
	var anchors := kit.find_children("Doorway_front*", "Node3D", false, false)
	check(anchors.size() == 1, "um vão de frente (achou %d)" % anchors.size())
	if anchors.size() == 1:
		var anchor: Node3D = anchors[0]
		check(anchor.has_meta("walk_in"), "o vão é a entrada de verdade (walk_in)")
		check(anchor.has_node("Door") and not anchor.has_node("Door2"), "porta simples (Door sem Door2)")
		var rect: Array = PaintedFacadeKit.openings(STYLE, "front")[0].rect
		var door_w: float = (float(rect[2]) - float(rect[0])) * natural.x
		var door_center: Vector3 = anchor.global_position + anchor.global_basis * Vector3(door_w * 0.5, 0, 0)
		var entrance_world: Vector3 = Vector3(expected.x, 0, expected.z) + Vector3(float(def.entrance_local.x), 0, float(def.size.y) * 0.5)
		check(absf(door_center.x - entrance_world.x) < 0.1, "porta pintada x=%.2f = entrada do catálogo x=%.2f" % [door_center.x, entrance_world.x])
		check(absf(door_center.z - entrance_world.z) < 0.3, "porta pintada z=%.2f na frente do catálogo z=%.2f" % [door_center.z, entrance_world.z])
		check(absf(anchor.global_position.y - expected.y + 0.12) < 0.08, "soleira rente ao chão (y=%.2f)" % anchor.global_position.y)
		var door = anchor.get_node("Door")
		door.set_open_amount(0.0)
		door.swing(true)
		await create_timer(PaintedFacadeKit.DOOR_OPEN_SECONDS + 0.4).timeout
		check(door.open_amount > 0.99, "a porta pintada abre (%.2f)" % door.open_amount)
	# Colisão e cobertura do posto preservadas.
	check(village.solids.any(func(body): return body.get_meta("interior_solid_id") == "TonicoShop"), "colisão TonicoShop preservada")
	check(kit.get_parent().find_children("PaintedFacadeSolid", "StaticBody3D", true, false).is_empty() and village.find_children("PaintedFacadeSolid", "StaticBody3D", true, false).is_empty(), "sem casco de colisão duplicado do kit")
	check(village.get_node("StationCanopy").get_child_count() > 0, "cobertura de bombas (StationCanopy) preservada")
	var access := village.get_node_or_null("BuildingAccess")
	check(access != null, "acesso do catálogo instalado")
	if access != null:
		# Preparar o acesso e abrir a vista do térreo: o kit entra na varredura sem a
		# caixa metálica fixa de porta (que duplicaria a folha pintada).
		access.set_floor_view(0, float(def.storey_height))
		check(access.find_children("OpenDoorLeaf", "Node3D", false, false).is_empty(), "sem folha metálica extra de porta")
		check(not access._meshes.is_empty(), "acesso capturou as peças visuais")
	scene.queue_free()
	await process_frame
	# Interruptor: caixa antiga de volta, sem kit.
	OS.set_environment("GETECO_PAINTED_TONICO", "0")
	var plain_scene := Node3D.new()
	root.add_child(plain_scene)
	var plain: Node3D = VILLAGE.new()
	plain_scene.add_child(plain)
	plain.tonico.set_physics_process(false)
	await physics_frame
	check(plain.find_children("PaintedFacade_" + STYLE, "Node3D", true, false).is_empty(), "interruptor: sem kit")
	check(_tonico_labels(plain) == 2, "interruptor: letreiros antigos de volta (%d)" % _tonico_labels(plain))
	OS.set_environment("GETECO_PAINTED_TONICO", "1")
	print("PAINTED_TONICO checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
