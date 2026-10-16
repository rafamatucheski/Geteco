extends SceneTree

## Banco "NORTH PIER" (id NorthFrontage0) com fachada pintada `banco`: um só kit, sem a
## geometria 3D antiga (colunas, caixas eletrônicos, janelas, porta de vidro, letreiro 3D),
## porta dupla que abre junta pelo mesmo `set_open_amount` que WeaponShopEntrance usa,
## vestíbulo com colisão (porta fechada barra, aberta deixa passar, alas barram), largura
## natural do estilo em todos os consumidores (prédio e telhado) e o interruptor
## GETECO_PAINTED_FACADES=0 devolvendo o banco autoral (rodar também com ele).

var failures: Array[String] = []
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _initialize() -> void: run.call_deferred()

## Alguma colisão da camada 1 dentro de uma caixa (centro em espaço de mundo).
func blocked(center: Vector3, size: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = size
	query.shape = box
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = 1
	return not root.world_3d.direct_space_state.intersect_shape(query, 8).is_empty()

func run() -> void:
	var painted := PaintedFacadeKit.enabled()
	check(PaintedHarborHouses.style_for("NorthFrontage0", "bank_branch") == ("banco" if painted else ""), "style_for(NorthFrontage0)")
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	var row := {}
	for candidate in rows:
		if str(candidate.get("id", "")) == "NorthFrontage0": row = candidate
	check(not row.is_empty(), "NorthFrontage0 existe em OriginalWorldData")
	var chunk := Node3D.new()
	chunk.position = Vector3(500, 0, 500)
	root.add_child(chunk)
	var building: UrbanLandmarkFrontage3D = UrbanBuildingFactory.build_building(row)
	check(building != null, "fábrica monta o banco como LandmarkFrontage")
	building.position = Vector3.ZERO
	building.set_meta("_urban_data", row)
	chunk.add_child(building)
	await process_frame
	await physics_frame
	await physics_frame
	var kits := building.find_children("PaintedFacade_banco", "Node3D", true, false)
	if not painted:
		# Interruptor desligado: o 3D autoral continua inteiro.
		check(kits.is_empty(), "sem kit com GETECO_PAINTED_FACADES=0")
		check(not building.find_children("BankColumnShaft_0", "Node", true, false).is_empty(), "colunas 3D antigas voltam")
		check(not building.find_children("EntranceDoorHinge", "Node", true, false).is_empty(), "porta de vidro antiga volta")
		check(absf(building.building_size.x - 14.375) < 0.01, "largura 14,375 m com o interruptor desligado (%.3f)" % building.building_size.x)
		finish()
		return
	check(kits.size() == 1, "um kit PaintedFacade_banco (%d)" % kits.size())
	if kits.size() != 1:
		finish()
		return
	var kit: Node3D = kits[0]
	check(building.has_meta("painted_facade_style"), "prédio marcado como pintado")
	# Largura natural do estilo (14,375 m passa de 15% do módulo de 12 m).
	check(absf(building.building_size.x - 12.0) < 0.01, "largura natural do estilo (%.3f)" % building.building_size.x)
	var roof: Dictionary = load("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd").find("harbor_bank")
	check(not roof.is_empty() and absf(float(roof.size.x) - building.building_size.x) < 0.01, "telhado do banco com a mesma largura do prédio")
	check(not roof.is_empty() and absf(float(roof.roof_height) - (PaintedBankBranch.wall_height() + 0.14)) < 0.01, "telhado na altura da pintura")
	# Sem a geometria antiga: colunas, caixas eletrônicos, janelas, frontão, porta e letreiro.
	for old in ["BankColumn", "BankATM", "BankWindow", "BankEntablature", "BankPediment", "BankRosette", "BankDoorJamb", "BankDoorHeader", "EntranceDoor", "BankSkylight", "LandmarkRearBody", "LandmarkFront", "LandmarkDoorLintel"]:
		check(building.find_children(old + "*", "Node", true, false).is_empty(), "sem geometria antiga: " + old)
	check(building.find_children("*", "Label3D", true, false).is_empty(), "sem texto 3D (NORTH PIER é o pintado)")
	check(not building.has_node("ProperNameSign") and building.find_children("*Sign*", "Node3D", true, false).is_empty(), "sem letreiro 3D duplicado")
	for node in building.find_children("*Door*", "Node3D", true, false):
		var inside := false
		var current: Node = node
		while current != null:
			if current == kit: inside = true
			current = current.get_parent()
		check(inside, "porta fora do kit: " + str(node.name))
	check(kit.find_children("DoorZone", "", true, false).is_empty(), "nenhuma folha abre por proximidade (a admissão é de WeaponShopEntrance)")
	check(building.find_children("PaintedFacadeSolid", "", true, false).is_empty(), "casco cheio do kit removido (o vestíbulo tem de ficar aberto)")
	# Um vão na frente, porta dupla, as duas seguem set_open_amount.
	check(kit.find_children("Doorway_front*", "Node3D", false, false).size() == 1, "um só vão de frente")
	var anchor: Node3D = kit.get_node("Doorway_front")
	check(anchor.has_node("Door") and anchor.has_node("Door2"), "vão central com Door e Door2")
	check(building.painted_doors.size() == 2, "duas folhas registradas para a abertura")
	check(is_instance_valid(building.entrance_door) and building.entrance_door == anchor.get_node("Door"), "contato da porta aponta para a folha pintada")
	var sill: float = anchor.global_position.y - building.global_position.y
	check(absf(sill) < 0.08, "soleira rente ao chão (%.2f m)" % sill)
	# Colisão do vestíbulo (espaço de origem; o chunk está em 500,0,500).
	var size := building.building_size
	var origin: Vector3 = building.global_position
	var door_z := origin.z + size.y * 0.5
	var through := Vector3(origin.x, 1.0, door_z - 0.05)
	building.set_open_amount(0.0)
	await physics_frame
	await physics_frame
	check(blocked(through, Vector3(1.5, 1.8, 0.1)), "porta fechada barra a passagem")
	building.set_open_amount(1.0)
	await physics_frame
	await physics_frame
	check(not blocked(through, Vector3(1.5, 1.8, 0.1)), "porta aberta deixa passar pelo vestíbulo")
	check(not blocked(Vector3(origin.x, 1.0, door_z - 0.8), Vector3(1.5, 1.8, 0.8)), "vestíbulo livre atrás da folha aberta")
	check(not blocked(Vector3(origin.x, 1.0, door_z + 0.8), Vector3(1.0, 1.8, 0.8)), "calçada em frente à porta livre")
	check(blocked(Vector3(origin.x + 4.0, 1.5, door_z - 0.1), Vector3(1.0, 2.0, 0.2)), "ala da frente barra ao lado da porta")
	check(blocked(Vector3(origin.x - 4.0, 1.5, door_z - 0.1), Vector3(1.0, 2.0, 0.2)), "ala da frente barra do outro lado")
	check(blocked(Vector3(origin.x, 1.5, origin.z), Vector3(2.0, 2.0, 2.0)), "corpo do prédio sólido atrás do vestíbulo")
	for leaf in building.painted_doors:
		check(leaf.open_amount > 0.99, "folha aberta junto")
	building.set_open_amount(0.0)
	check(building.painted_doors[0].open_amount < 0.01 and building.painted_doors[1].open_amount < 0.01, "as duas folhas fecham juntas")
	# Contato medido por WeaponShopEntrance: a folha no plano da fachada, 0,04 m para dentro.
	var contact: float = building.entrance_door.global_position.z - door_z
	check(absf(contact + 0.04) < 0.02, "folha no plano da frente (%.3f m)" % contact)
	# Largura da zona de empurrar vem do vão pintado, não dos 0,48 m da porta antiga.
	var entrance := preload("res://runtime/WeaponShopEntrance.gd").new()
	check(entrance._half_width("harbor_bank") > 1.0, "zona de empurrar cobre o vão pintado")
	entrance.free()
	finish()

func finish() -> void:
	print("PAINTED_BANK checks=", checks, " failures=", failures.size())
	for failure in failures: print("  FALHA: ", failure)
	quit(0 if failures.is_empty() else 1)
