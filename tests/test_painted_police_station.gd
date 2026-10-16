extends SceneTree

## Delegacia (id Police) com fachada pintada `delegacia`: um só kit, sem a geometria
## antiga de porta/escudo/letreiro, porta dupla que abre junta pelo mesmo
## `set_open_amount` que WeaponShopEntrance usa, vestíbulo com colisão como antes
## (porta fechada barra, aberta deixa passar, alas ao lado barram) e o adereço de rua
## do PoliceStationDressing sem o texto 3D "POLÍCIA" nem a marquise.

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
	check(PaintedHarborHouses.style_for("Police", "police_precinct") == "delegacia", "style_for(Police) = delegacia")
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	var row := {}
	for candidate in rows:
		if str(candidate.get("id", "")) == "Police": row = candidate
	check(not row.is_empty(), "Police existe em OriginalWorldData")
	var chunk := Node3D.new()
	chunk.position = Vector3(500, 0, 500)
	root.add_child(chunk)
	var building: UrbanServiceBuilding = UrbanBuildingFactory.build_building(row)
	building.position = Vector3.ZERO
	building.set_meta("_urban_data", row)
	chunk.add_child(building)
	await process_frame
	await physics_frame
	await physics_frame
	var kits := building.find_children("PaintedFacade_delegacia", "Node3D", true, false)
	check(kits.size() == 1, "um kit PaintedFacade_delegacia (%d)" % kits.size())
	if kits.size() != 1:
		finish()
		return
	var kit: Node3D = kits[0]
	check(building.has_meta("painted_facade_style"), "prédio marcado como pintado (a decoração se ajusta)")
	# Sem geometria antiga da entrada, do brasão, do letreiro nem do portão de viaturas.
	for old in ["PrecinctBody", "PrecinctFrontWing", "EntryDoor", "EntryGlass", "PoliceShield", "BlueBand", "MotorPoolShutter", "SecFrame", "EntryPortalTop"]:
		check(building.find_children(old + "*", "Node", true, false).is_empty(), "sem geometria antiga: " + old)
	for node in building.find_children("*Door*", "Node3D", true, false):
		var inside := false
		var current: Node = node
		while current != null:
			if current == kit: inside = true
			current = current.get_parent()
		check(inside, "porta fora do kit: " + str(node.name))
	check(kit.find_children("DoorZone", "", true, false).is_empty(), "nenhuma folha abre por proximidade (a admissão é de WeaponShopEntrance)")
	check(building.find_children("PaintedFacadeSolid", "", true, false).is_empty(), "casco cheio do kit removido (o vestíbulo tem de ficar aberto)")
	# Porta dupla: duas folhas, as duas seguem set_open_amount.
	var anchor: Node3D = kit.get_node("Doorway_front")
	check(anchor.has_node("Door") and anchor.has_node("Door2"), "vão central com Door e Door2")
	check(building.painted_police_doors.size() == 2, "duas folhas registradas para a abertura")
	check(building.police_door_visuals.size() == 2, "contato da porta aponta para as dobradiças")
	var sill: float = anchor.global_position.y - building.global_position.y
	check(absf(sill) < 0.08, "soleira rente ao chão (%.2f m)" % sill)
	# Colisão do vestíbulo (espaço de origem; o chunk está em 500,0,500).
	var size := building.building_size
	var origin: Vector3 = building.global_position
	var door_z := origin.z + size.y * 0.5
	# A folha fica no plano da porta (0,04 m para dentro da parede).
	var through := Vector3(origin.x, 1.0, door_z - 0.05)
	building.set_open_amount(0.0)
	await physics_frame
	await physics_frame
	check(blocked(through, Vector3(1.5, 1.8, 0.1)), "porta fechada barra a passagem")
	building.set_open_amount(1.0)
	await physics_frame
	await physics_frame
	check(not blocked(through, Vector3(1.5, 1.8, 0.1)), "porta aberta deixa passar pelo vestíbulo")
	check(not blocked(Vector3(origin.x, 1.0, door_z + 0.8), Vector3(1.0, 1.8, 0.8)), "calçada em frente à porta livre")
	check(blocked(Vector3(origin.x + 4.0, 1.5, door_z - 0.1), Vector3(1.0, 2.0, 0.2)), "ala da frente barra ao lado da porta")
	check(blocked(Vector3(origin.x, 1.5, origin.z), Vector3(2.0, 2.0, 2.0)), "corpo do prédio sólido atrás do vestíbulo")
	for leaf in building.painted_police_doors:
		check(leaf.open_amount > 0.99, "folha aberta junto")
	building.set_open_amount(0.0)
	check(building.painted_police_doors.size() == 2 and building.painted_police_doors[0].open_amount < 0.01 and building.painted_police_doors[1].open_amount < 0.01, "as duas folhas fecham juntas")
	# Decoração: adereço de rua fica, letreiro 3D e marquise saem.
	var roof_y := PaintedFacadeKit.natural_size("delegacia").y - float(kit.get_meta("ground_sink", 0.0)) + 0.012
	preload("res://world/city_look/PoliceStationDressing.gd").decorate(chunk, building, roof_y, Vector2.ZERO, size, [], {})
	var labels := chunk.find_children("*", "Label3D", true, false)
	check(labels.is_empty(), "sem texto 3D (o letreiro HARBOR PATROL é o pintado): %d Label3D" % labels.size())
	check(chunk.find_children("PoliceGlow_lightbox", "", true, false).is_empty(), "sem marquise luminosa POLÍCIA")
	check(chunk.find_children("PoliceGlow_globe", "", true, false).is_empty(), "sem lampiões 3D (a pintura já tem os dois)")
	check(chunk.find_children("PoliceStationDetail", "", true, false).size() == 1, "adereços de rua e telhado montados")
	check(chunk.find_children("ParkedHelicopter", "", true, false).size() == 1, "helicóptero no heliponto")
	finish()

func finish() -> void:
	print("PAINTED_POLICE checks=", checks, " failures=", failures.size())
	for failure in failures: print("  FALHA: ", failure)
	quit(0 if failures.is_empty() else 1)
