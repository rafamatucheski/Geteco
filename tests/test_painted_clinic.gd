extends SceneTree

## Ala oeste da clínica (Clinic, BAY MEDICAL) pintada: frente/fundos/lateral/telhado vêm do
## PaintedFacadeKit (estilo clinica-oeste-v2), mas portas 3D (pública e da ambulância),
## colisão, `interior_solid_id` e acesso continuam os do HarborHospitalModel3D. Confere:
##  - kit único, sem porta pintada (nem corredor escuro do kit), base rente ao chão;
##  - as portas públicas e da ambulância continuam e abrem pelos mesmos métodos;
##  - PublicDoorSolid e hospital_public_west_jamb continuam, com colisão derivada;
##  - o vão pintado casa com a abertura da porta pública 3D;
##  - equipamento de telhado não flutua sobre o telhado pintado;
##  - GETECO_PAINTED_CLINIC=0 volta às caixas antigas (A/B).
## Uso: tools/run_godot_locked.sh --path . --script res://tests/test_painted_clinic.gd

const STYLE := "clinica-oeste-v2"
const PPM := 18.0
const FLOOR_RATIO := 0.76822128

var failures: Array = []
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("FAIL: " + label)


func _init() -> void:
	run.call_deferred()


func clinic_row() -> Dictionary:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	for row in rows:
		if str(row.get("id", "")) == "Clinic":
			var entry: Dictionary = row.duplicate()
			entry["position"] = Vector3(float(row.position[0]) / 16.0, 0, float(row.position[1]) / 16.0)
			entry["size"] = Vector2(float(row.size[0]) / 16.0, float(row.size[1]) / 16.0)
			return entry
	return {}


func floor_x(px: float) -> float:
	return px / PPM


func floor_z(py: float) -> float:
	return py / (PPM * FLOOR_RATIO)


func build_clinic() -> Node3D:
	var building: Node3D = UrbanBuildingFactory.build_building(clinic_row())
	root.add_child(building)
	await process_frame
	await physics_frame
	await physics_frame
	return building


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, to, 1)
	return root.get_world_3d().direct_space_state.intersect_ray(params)


func in_node(node: Node, ancestor: Node) -> bool:
	var current := node
	while current != null:
		if current == ancestor: return true
		current = current.get_parent()
	return false


func run() -> void:
	OS.set_environment("GETECO_PAINTED_CLINIC", "1")
	check(PaintedFacadeKit.all_styles().has(STYLE), "estilo %s importado em assets/facades" % STYLE)
	check(not clinic_row().is_empty(), "Clinic existe em OriginalWorldData")
	var building := await build_clinic()
	var origin := building.global_position
	check(building.get_script() != null and str(building.get_script().resource_path).ends_with("HarborHospitalModel3D.gd"), "Clinic continua sendo o HarborHospitalModel3D")

	# 1. Kit pintado único, sem porta pintada.
	var wing := building.get_node_or_null("PaintedWestWing")
	check(wing != null, "ala oeste pintada existe (PaintedWestWing)")
	var kits := building.find_children("PaintedFacade_" + STYLE, "Node3D", true, false)
	check(kits.size() == 1, "um só kit PaintedFacade_%s (achou %d)" % [STYLE, kits.size()])
	var kit: Node3D = kits[0] if not kits.is_empty() else null
	if kit != null:
		for part in ["Front", "Back", "Sides", "Roof", "Cornice"]:
			check(kit.get_node_or_null(part) != null, "kit tem %s" % part)
		check(kit.find_children("Door", "Node3D", true, false).is_empty() and kit.find_children("Door2", "Node3D", true, false).is_empty(), "nenhuma porta pintada (Door/Door2) no kit")
		check(kit.find_children("Corridor", "MeshInstance3D", true, false).is_empty(), "sem corredor escuro atrás do vão")
		check(kit.find_children("LeafSolid", "StaticBody3D", true, false).is_empty(), "sem colisão de folha pintada")
		check(kit.find_children("PaintedFacadeSolid", "StaticBody3D", true, false).is_empty(), "o kit não traz colisão própria (as caixas escondidas fazem)")
		check(kit.get_meta("ground_sink", 1.0) == 0.0, "base rente ao chão: o kit não afunda o prédio")
		check(absf(kit.global_position.y - origin.y) < 0.01, "raiz do kit na altura do chão (%.3f)" % (kit.global_position.y - origin.y))
		var front: MeshInstance3D = kit.get_node("Front")
		var bounds := front.get_aabb()
		check(absf(bounds.position.y) < 0.01, "base da frente pintada em y=0 (%.3f)" % bounds.position.y)
		check(absf(bounds.end.y - 5.0) < 0.02, "frente com 5,0 m de altura (%.3f)" % bounds.end.y)
		# Nenhuma malha do kit ganhou colisão derivada (as caixas escondidas já fazem).
		for mesh in kit.find_children("*", "MeshInstance3D", true, false):
			for child in mesh.get_children():
				if child is StaticBody3D and not child.get_children().is_empty():
					check(false, "malha do kit %s com colisão derivada" % mesh.name)
	check(kit == null or kit.find_children("PaintedDoor*", "Node3D", true, false).is_empty(), "nenhuma folha PaintedDoor no kit")

	# 2. Letreiro 3D antigo fora (a frente pintada já traz BAY MEDICAL).
	check(building.get_node_or_null("HospitalName") == null and building.get_node_or_null("HospitalNameplate") == null, "sem HospitalName/HospitalNameplate 3D")

	# 3. Portas 3D continuam e abrem pelos mesmos métodos.
	var public_leaves: Array = building.get("public_leaves")
	var door_leaves: Array = building.get("door_leaves")
	check(public_leaves.size() == 2, "duas folhas públicas 3D (%d)" % public_leaves.size())
	check(door_leaves.size() == 2, "duas folhas da ambulância 3D (%d)" % door_leaves.size())
	for method in ["set_public_door_amount", "set_open_amount", "set_door_amount"]:
		check(building.has_method(method), "método %s existe" % method)
	check(building.get_node_or_null("EmergencyGlassCanopy") != null and building.get_node_or_null("AdmissionWingRoof") != null, "marquise da ambulância e teto da admissão continuam")
	var solids := building.find_children("PublicDoorSolid", "StaticBody3D", true, false)
	check(solids.size() == 2, "dois PublicDoorSolid (%d)" % solids.size())
	for solid in solids:
		check(str(solid.get_meta("interior_solid_id", "")) == "hospital_public_door" and (solid.collision_layer & 1) != 0, "PublicDoorSolid com id e camada 1")
	building.call("set_public_door_amount", 0.0)
	building.call("set_door_amount", 0.0)
	var closed_x: Array = [public_leaves[0].position.x, public_leaves[1].position.x]
	check(absf(closed_x[0] + floor_x(15.0)) < 0.001 and absf(closed_x[1] - floor_x(15.0)) < 0.001, "folhas públicas fechadas em +-15 px")
	building.call("set_open_amount", 1.0)
	check(absf(public_leaves[0].position.x + floor_x(39.0)) < 0.001 and absf(public_leaves[1].position.x - floor_x(39.0)) < 0.001, "set_open_amount(1) abre as folhas públicas (+-39 px)")
	check(float(building.get("open_amount")) == 1.0, "open_amount guardado")
	building.call("set_open_amount", 0.0)
	check(absf(public_leaves[0].position.x - closed_x[0]) < 0.001, "set_open_amount(0) fecha")
	var bay_closed: float = door_leaves[1].position.z
	building.call("set_door_amount", 1.0)
	check(door_leaves[1].position.z > bay_closed + 1.0, "set_door_amount(1) abre as folhas da ambulância")
	building.call("set_public_door_amount", 1.0)
	check(absf(public_leaves[1].position.x - floor_x(39.0)) < 0.001, "set_public_door_amount(1) abre a porta pública")
	building.call("set_public_door_amount", 0.0)
	building.call("set_door_amount", 0.0)

	# 4. Colisão: caixas escondidas continuam e geraram colisão; jamb mantém o id.
	var hidden_with_body := 0
	var jamb: MeshInstance3D = null
	for mesh in building.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.get_meta("interior_solid_id", "")) == "hospital_public_west_jamb": jamb = mesh
		if not mesh.visible and not in_node(mesh, kit):
			for child in mesh.get_children():
				if child is StaticBody3D and (child.collision_layer & 1) != 0 and child.get_child_count() > 0: hidden_with_body += 1
	check(jamb != null, "hospital_public_west_jamb continua")
	if jamb != null:
		check(not jamb.visible, "jamb escondido (só colisão)")
		check(jamb.get_children().any(func(c): return c is StaticBody3D and (c.collision_layer & 1) != 0), "jamb com colisão derivada na camada 1")
	check(hidden_with_body >= 2, "ala oeste escondida mantém colisão (%d caixas)" % hidden_with_body)
	# Raios de verdade: paredes oeste, leste do corpo, fundos e a porta fechada seguram.
	var y := origin.y + 1.0
	var cx := origin.x + floor_x(-50.0)
	check(not ray(Vector3(origin.x + floor_x(-140.0), y, origin.z), Vector3(origin.x + floor_x(-100.0), y, origin.z)).is_empty(), "parede oeste da ala segura (raio)")
	check(not ray(Vector3(cx, y, origin.z + floor_z(-125.0)), Vector3(cx, y, origin.z + floor_z(-90.0))).is_empty(), "parede dos fundos da ala segura (raio)")
	check(not ray(Vector3(origin.x + floor_x(-100.0), y, origin.z + floor_z(130.0)), Vector3(origin.x + floor_x(-100.0), y, origin.z + floor_z(100.0))).is_empty(), "ombreira oeste da entrada segura (raio)")
	var door_x := origin.x + floor_x(-1.0)
	await physics_frame
	await physics_frame
	var closed_hit := ray(Vector3(door_x + 0.2, y, origin.z + floor_z(130.0)), Vector3(door_x + 0.2, y, origin.z + floor_z(100.0)))
	check(not closed_hit.is_empty(), "porta pública fechada barra o jogador (raio)")
	building.call("set_open_amount", 1.0)
	await physics_frame
	await physics_frame
	var open_hit := ray(Vector3(door_x, y, origin.z + floor_z(130.0)), Vector3(door_x, y, origin.z + floor_z(106.0)))
	check(open_hit.is_empty(), "porta pública aberta deixa passar até o vestíbulo (raio)")
	building.call("set_open_amount", 0.0)

	# 5. O vão pintado casa com a abertura da porta pública 3D.
	if kit != null:
		var opening: Dictionary = PaintedFacadeKit.openings(STYLE, "front")[0]
		var rect: Array = opening.rect
		var width := 160.0 / PPM
		var left := kit.global_position.x - width * 0.5 + float(rect[0]) * width
		var right := kit.global_position.x - width * 0.5 + float(rect[2]) * width
		var opening_left := origin.x + floor_x(-32.0)
		var opening_right := origin.x + floor_x(30.0)
		print("vão pintado x %.3f..%.3f (%.2f m) | abertura 3D %.3f..%.3f (%.2f m)" % [left, right, right - left, opening_left, opening_right, opening_right - opening_left])
		check(not bool(opening.leaf), "vão pintado sem folha (a porta é a 3D)")
		check(absf(left - opening_left) < 0.12 and absf(right - opening_right) < 0.12, "vão pintado casa com a abertura 3D (esq %.3f, dir %.3f m)" % [left - opening_left, right - opening_right])
		var leaf_left := origin.x + floor_x(-15.0 - 14.5)
		var leaf_right := origin.x + floor_x(15.0 + 14.5)
		print("folhas fechadas x %.3f..%.3f | sobra esq %.3f m, dir %.3f m" % [leaf_left, leaf_right, leaf_left - left, right - leaf_right])
		check(leaf_left - left < 0.2 and right - leaf_right < 0.2 and left - leaf_left < 0.1 and leaf_right - right < 0.1, "folhas 3D cobrem o vão pintado sem fresta nem sobreposição relevantes")
		var front_z := kit.global_position.z + float(floor_z(230.0)) * 0.5
		check(absf(front_z - (origin.z + floor_z(115.0))) < 0.01, "plano da frente pintada na mesma face da antiga (y=115 px)")

	# 6. Equipamento de telhado não flutua sobre o telhado pintado (5,0 m).
	var floating := 0
	var on_roof := 0
	for mesh in building.find_children("*", "MeshInstance3D", true, false):
		if in_node(mesh, kit) or not mesh.visible or mesh.mesh == null: continue
		var local: Transform3D = building.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = local * mesh.mesh.get_aabb()
		var center_px := Vector2(box.get_center().x * PPM, box.get_center().z * PPM * FLOOR_RATIO)
		if center_px.x < -130.0 or center_px.x > 30.0 or center_px.y < -115.0 or center_px.y > 96.0: continue
		# Antes o equipamento apoiava na laje antiga (5,265 m): base em 5,2-5,3 m = flutuando.
		if box.position.y > 5.15 and box.position.y < 5.30: floating += 1
		if box.position.y > 4.99 and box.position.y < 5.03: on_roof += 1
	check(floating == 0, "equipamento de telhado da ala oeste não flutua na altura da laje antiga (%d)" % floating)
	check(on_roof >= 3, "equipamento de telhado apoiado no telhado pintado em 5,0 m (%d peças)" % on_roof)
	building.queue_free()
	await process_frame

	# 7. Interruptor GETECO_PAINTED_CLINIC=0: caixas antigas de volta.
	OS.set_environment("GETECO_PAINTED_CLINIC", "0")
	var old_style := await build_clinic()
	check(old_style.get_node_or_null("PaintedWestWing") == null, "GETECO_PAINTED_CLINIC=0: sem ala pintada")
	check(old_style.find_children("PaintedFacade_*", "Node3D", true, false).is_empty(), "GETECO_PAINTED_CLINIC=0: sem kit")
	check(old_style.get_node_or_null("HospitalName") != null, "GETECO_PAINTED_CLINIC=0: letreiro 3D de volta")
	var old_visible_ward := false
	for mesh in old_style.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh is BoxMesh and mesh.visible and (mesh.mesh as BoxMesh).size.is_equal_approx(Vector3(160.0 / PPM, 5.0, floor_z(211.0))): old_visible_ward = true
	check(old_visible_ward, "GETECO_PAINTED_CLINIC=0: caixa da ala visível")
	check(old_style.get("public_leaves").size() == 2 and old_style.get("door_leaves").size() == 2, "GETECO_PAINTED_CLINIC=0: portas 3D iguais")
	old_style.queue_free()
	await process_frame
	OS.unset_environment("GETECO_PAINTED_CLINIC")

	print("test_painted_clinic: %d checagens, %d falhas" % [checks, failures.size()])
	for failure in failures: print("  FALHOU: ", failure)
	quit(1 if not failures.is_empty() else 0)
