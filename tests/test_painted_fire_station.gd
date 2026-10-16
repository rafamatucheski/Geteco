extends SceneTree

## Quartel NorthFireStation com a fachada pintada "bombeiros": monta o kit (e não a
## geometria antiga), sem porta/portão antigo escondido por baixo, a entrada do lugar
## (baia central, x = FIRE_STATION_DOOR_OFFSET.x) cai num vão sem colisão, o prédio
## continua preso ao chão e o abrir/fechar do portão antigo não quebra sem ele.

func _init() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	var failures: Array = []
	var checks := 0
	var row := {}
	for r in rows:
		if str(r.get("id", "")) == "NorthFireStation": row = r
	if row.is_empty():
		print("PAINTED_FIRE_STATION sem linha em OriginalWorldData")
		quit(1)
		return
	checks += 1
	if PaintedHarborHouses.style_for("NorthFireStation", "fire_station") != "bombeiros": failures.append("style_for")
	var building: Node3D = UrbanBuildingFactory.build_building(row)
	root.add_child(building)
	await process_frame
	var kits := building.find_children("PaintedFacade_bombeiros", "Node3D", true, false)
	checks += 1
	if kits.size() != 1: failures.append("%d kits" % kits.size()); print("PAINTED_FIRE_STATION failures=", failures); quit(1); return
	var kit: Node3D = kits[0]
	# Nada da construção antiga: portão de rolo, baias, torre, vitrine.
	for old_name in ["FireWalkupShutter", "FireWalkupShutterSolid", "ApplianceDoor", "FireHouseWing", "HoseTower", "ApplianceSurround"]:
		checks += 1
		if building.find_child(old_name, true, false) != null: failures.append("geometria antiga %s ainda existe" % old_name)
	for node in building.find_children("*Door*", "Node3D", true, false):
		checks += 1
		var inside := false
		var current: Node = node
		while current != null:
			if current == kit: inside = true
			current = current.get_parent()
		if not inside: failures.append("porta fora do kit (%s)" % node.name)
	# Vãos: 2 portões sem folha (corredor escuro) + porta de serviço na frente.
	var openings: Array = PaintedFacadeKit.openings("bombeiros", "front")
	var anchors := kit.find_children("Doorway_front*", "Node3D", false, false)
	checks += 1
	if openings.size() != 3 or anchors.size() != 3: failures.append("vãos de frente %d/%d" % [anchors.size(), openings.size()])
	var corridors := 0
	for anchor in anchors:
		if anchor.has_node("Corridor"): corridors += 1
	checks += 1
	if corridors != 2: failures.append("%d corredores de portão (esperado 2)" % corridors)
	# Largura = natural do estilo (footprint_width), prédio não sai do lugar do catálogo.
	checks += 1
	if absf(building.building_size.x - 16.0) > 0.01: failures.append("largura %.2f" % building.building_size.x)
	# A entrada do lugar (baia central) cai dentro de um vão sem folha, e o ponto de
	# aproximação (1,5 m diante da fachada, PlaceCatalog) fica livre de colisão. O casco
	# é um bloco só até a fachada, como em todo prédio do kit: o jogador entra pela
	# proximidade, não caminhando para dentro do vão.
	var entry_x: float = preload("res://world/places/PlaceCatalog.gd").FIRE_STATION_DOOR_OFFSET.x
	var in_bay := false
	for i in mini(anchors.size(), openings.size()):
		var rect: Array = openings[i].rect
		var x0 := -8.0 + float(rect[0]) * 16.0
		var x1 := -8.0 + float(rect[2]) * 16.0
		if not openings[i].leaf and entry_x > x0 + 0.3 and entry_x < x1 - 0.3: in_bay = true
	checks += 1
	if not in_bay: failures.append("entrada x=%.2f não cai num portão" % entry_x)
	var front_z: float = building.building_size.y * 0.5
	for shape_node in building.collision_root.find_children("*", "CollisionShape3D", true, false):
		var box := shape_node.shape as BoxShape3D
		if box == null: continue
		var center: Vector3 = building.collision_root.to_local(shape_node.global_position)
		checks += 1
		var hits_x: bool = absf(entry_x - center.x) < box.size.x * 0.5
		var hits_z: bool = absf((front_z + 1.5) - center.z) < box.size.z * 0.5
		var hits_y: bool = center.y - box.size.y * 0.5 < 1.5 and center.y + box.size.y * 0.5 > 0.5
		if hits_x and hits_z and hits_y: failures.append("colisão %s bloqueia a entrada" % shape_node.get_parent().name)
	# Abrir/fechar o portão antigo (chamado pela região) não quebra sem a peça.
	building.set_open_amount(0.0)
	building.set_open_amount(1.0)
	checks += 1
	if is_instance_valid(building.fire_door_visual): failures.append("fire_door_visual deveria estar vazio")
	# Preso ao chão: base do kit rente à calçada (sink só afunda o embasamento).
	checks += 1
	for anchor in anchors:
		if anchor.has_node("Door"):
			var sill: float = anchor.global_position.y - building.global_position.y
			if absf(sill) > 0.08: failures.append("soleira a %.2f m do chão" % sill)
	print("PAINTED_FIRE_STATION checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
