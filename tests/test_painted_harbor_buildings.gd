extends SceneTree

## Prédios comerciais do porto com fachada pintada: montam o kit (não a geometria
## antiga), uma só entrada na frente (sem módulo repetido), porta dupla quando o vão é
## largo (as duas folhas abrem juntas), soleira da frente rente ao chão e largura
## igual à do catálogo/interior.

const IDS := {"Laundry": "lavanderia", "UnionWorkshop": "oficina-artesao", "MarketHall": "mercado-municipal",
	"FreightOffice": "escritorio-frete", "Aquarium": "aquario", "MaritimeMuseum": "museu-maritimo",
	"ColdStorage": "camara-fria",
	"CornerDiner": "lanchonete-esquina", "IslandGrocer": "mercado-ilha", "IslandCinema": "cinema",
	"PromenadeCafe": "cafe-orla",
	# Rodada "restantes" (17/10): o portão largo da NorthbankHomes2 é passagem aberta, não folha.
	"RoadsideSupplies": "loja-estrada", "ParcelOffice": "escritorio-encomendas", "ServiceCafe": "cafe-servico",
	"CycleWorkshop": "oficina-bicicletas", "CornerPharmacy": "farmacia-esquina", "NorthbankHomes2": "oficina-margem-norte",
	"CommunityHall": "salao-comunitario", "ServiceLodge": "pousada-servico"}

func _init() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	var failures: Array = []
	var checks := 0
	for id in IDS:
		var style: String = IDS[id]
		checks += 1
		if PaintedHarborHouses.style_for(id, "x") != style: failures.append("%s: style_for" % id)
		var row := {}
		for r in rows:
			if str(r.get("id", "")) == id: row = r
		if row.is_empty(): failures.append("%s: sem linha em OriginalWorldData" % id); continue
		var building: Node3D = UrbanBuildingFactory.build_building(row)
		root.add_child(building)
		await process_frame
		var kits := building.find_children("PaintedFacade_" + style, "Node3D", true, false)
		checks += 1
		if kits.size() != 1: failures.append("%s: %d kits PaintedFacade_%s" % [id, kits.size(), style]); building.queue_free(); continue
		var kit: Node3D = kits[0]
		# Geometria antiga de porta/entrada fora do kit.
		for node in building.find_children("*Door*", "Node3D", true, false):
			checks += 1
			var inside := false
			var current: Node = node
			while current != null:
				if current == kit: inside = true
				current = current.get_parent()
			if not inside: failures.append("%s: porta fora do kit (%s)" % [id, node.name])
		# Largura do prédio = largura do catálogo (interior e entrada usam a mesma).
		var def: Dictionary = load("res://world/places/harbor_buildings/HarborBuildingCatalog.gd").for_source(id)
		checks += 1
		if def.is_empty() or absf(float(def.size.x) - float(building.building_size.x)) > 0.01:
			failures.append("%s: largura do catálogo %s != prédio %s" % [id, def.get("size", "?"), building.building_size.x])
		# Uma entrada na frente por vão (módulo único): sem porta repetida.
		var openings: Array = PaintedFacadeKit.openings(style, "front")
		var anchors := kit.find_children("Doorway_front*", "Node3D", false, false)
		checks += 1
		if anchors.size() != openings.size(): failures.append("%s: %d vãos de frente no kit, %d no estilo" % [id, anchors.size(), openings.size()])
		# Porta dupla nos vãos largos; as duas folhas abrem juntas.
		var width: float = float(building.building_size.x)
		for i in mini(anchors.size(), openings.size()):
			var opening: Dictionary = openings[i]
			if not opening.leaf: continue
			var rect: Array = opening.rect
			var leaf_w: float = (float(rect[2]) - float(rect[0])) * width
			var anchor: Node3D = anchors[i]
			var wide := leaf_w > PaintedFacadeKit.DOUBLE_DOOR_MIN
			checks += 1
			if wide != anchor.has_node("Door2"): failures.append("%s: vão de %.2f m, Door2=%s" % [id, leaf_w, anchor.has_node("Door2")])
			if wide and anchor.has_node("Door2"):
				var left = anchor.get_node("Door")
				var right = anchor.get_node("Door2")
				left.set_open_amount(0.0); right.set_open_amount(0.0)
				left.swing(true)
				await create_timer(PaintedFacadeKit.DOOR_OPEN_SECONDS + 0.4).timeout
				checks += 1
				if left.open_amount < 0.99 or right.open_amount < 0.99: failures.append("%s: porta dupla não abriu junta (%.2f/%.2f)" % [id, left.open_amount, right.open_amount])
				checks += 1
				if right.hinge.rotation.y >= 0.0: failures.append("%s: folha direita gira para o lado errado" % id)
		# Soleira da frente rente ao chão (a base do kit afunda o embasamento pintado).
		for anchor in anchors:
			if not anchor.has_node("Door"): continue
			checks += 1
			var sill: float = anchor.global_position.y - building.global_position.y
			if absf(sill) > 0.08: failures.append("%s: soleira a %.2f m do chão" % [id, sill])
		building.queue_free()
		await process_frame
	print("PAINTED_HARBOR_BUILDINGS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
