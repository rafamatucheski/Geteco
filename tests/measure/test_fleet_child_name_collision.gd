extends SceneTree
## Reprodução finita de posse, uma família por processo; sem Main nem afirmação de FPS.
## Rode .NET headless com --disable-crash-handler, --no-save e armazenamento isolado.
## Com a posse de filhos quebrada gravamos o relatório e de propósito NÃO liberamos,
## anexamos nem reaproveitamos esse grafo: destruir um mapa de filhos corrompido pode quebrar no nativo.
const HEAVY := preload("res://runtime/HeavyVehicleDetail.gd")
const POLICE := preload("res://gameplay/police_response/ground/PoliceGroundModels.gd")
const TRANSPORT := preload("res://gameplay/dispatch/PoliceTransportModel.gd")
const CASES := {
	"cargo": ["res://assets/fleet/cargo_flatbed_truck.scn", "HeavyFender2"],
	"bike": ["res://assets/fleet/bike_urban.scn", "PolicePannier2"],
	"transport": ["res://assets/fleet/courier_van.scn", "TacticalStripe2"],
}
const SOURCES := ["res://runtime/HeavyVehicleDetail.gd",
	"res://gameplay/police_response/ground/PoliceGroundModels.gd",
	"res://gameplay/dispatch/PoliceTransportModel.gd",
	"res://tests/measure/test_fleet_child_name_collision.gd"]
var packed: PackedScene # Mantém a origem viva, como o ProductionWorld faz.
var family := "cargo"
var checks := 0
var failures: Array[String] = []
var report: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
	print(("PASS " if ok else "FAIL ") + message)

func hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES: result[path] = FileAccess.get_sha256(path)
	if CASES.has(family): result[CASES[family][0]] = FileAccess.get_sha256(CASES[family][0])
	return result

func finish(code: int) -> void:
	report.merge({"family":family, "checks":checks, "failures":failures,
		"sources_after":hashes(), "user_data_dir":OS.get_user_data_dir()})
	var output := FileAccess.open("user://fleet-child-name-collision.json", FileAccess.WRITE)
	if output == null:
		push_error("Cannot write fleet child-name diagnostic")
		quit(2)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.flush()
	output.close()
	print("FLEET_CHILD_NAME_RESULT ", JSON.stringify(report))
	quit(code)

func next_serial(scratch: Node3D) -> int:
	var node := MeshInstance3D.new()
	scratch.add_child(node)
	var value := str(node.name)
	var serial := int(value.get_slice("@", 2)) if value.begins_with("@MeshInstance3D@") else -1
	node.free()
	return serial

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--model="): family = arg.trim_prefix("--model=")
	check("--no-save" in OS.get_cmdline_user_args(), "--no-save required")
	check(ClassDB.class_exists(&"CSharpScript"), "Godot .NET required")
	check(DisplayServer.get_name() == "headless", "logical headless reproduction only")
	check(CASES.has(family), "known single model")
	if not failures.is_empty(): finish(2); return
	report["sources_before"] = hashes()
	packed = load(CASES[family][0]) as PackedScene
	check(packed != null, "retained real PackedScene loaded")
	if packed == null: finish(2); return
	var model := packed.instantiate() as Node3D
	check(model != null, "real model instantiated")
	if model == null: finish(2); return
	# Existing destination exercises readable-name collision handling as well.
	var authored := Node3D.new()
	authored.name = CASES[family][1]
	model.add_child(authored, true)
	var original: Array[Dictionary] = []
	var serials: Array[int] = []
	for node: Node in model.get_children(true):
		var name_text := str(node.name)
		var row := {"node":node, "id":str(node.get_instance_id()), "name":name_text}
		if node is MeshInstance3D:
			row["mesh"] = node.mesh
			row["transform"] = node.transform
			row["material"] = node.material_override
			if name_text.begins_with("@MeshInstance3D@"):
				serials.append(int(name_text.get_slice("@", 2)))
		original.append(row)
	serials.sort()
	var scratch := Node3D.new()
	var serial := next_serial(scratch)
	var initial_serial := serial
	var target := -1
	for value in serials:
		if value > serial: target = value; break
	check(serial >= 0 and target > serial, "future imported automatic name available")
	if target <= serial or serial < 0:
		scratch.free()
		model.free()
		finish(2)
		return
	var began := Time.get_ticks_usec()
	var consumed := 1
	while serial < target - 1 and consumed < 40000 and Time.get_ticks_usec()-began < 5000000:
		serial = next_serial(scratch)
		consumed += 1
	scratch.free()
	report.merge({"initial_serial":initial_serial, "target_serial":target,
		"last_serial":serial, "consumed":consumed,
		"alignment_usec":Time.get_ticks_usec()-began, "original_children":original.size()})
	check(serial == target-1, "counter aligned within finite budget without reset")
	if serial != target-1:
		model.free()
		finish(2)
		return
	match family:
		"cargo": HEAVY.decorate("cargo_flatbed_truck", model)
		"bike": POLICE.motorcycle(model)
		"transport": TRANSPORT.decorate(model)
	var children := model.get_children(true)
	var lost: Array[Dictionary] = []
	for row: Dictionary in original:
		var node: Node = row.node
		var resolved: Node = model.get_node_or_null(NodePath(row.name))
		var intact := is_instance_valid(node) and node.get_parent() == model and children.has(node) and resolved == node
		if not intact:
			lost.append({"id":row.id, "name":row.name, "listed":children.has(node),
				"resolved_id":str(resolved.get_instance_id()) if resolved != null else "",
				"parent_matches":is_instance_valid(node) and node.get_parent() == model})
	check(children.size() >= original.size(), "child count preserves imported siblings")
	check(lost.is_empty(), "every original child remains listed and resolves to itself")
	report["lost_children"] = lost
	report["children_after"] = children.size()
	if not lost.is_empty():
		report["cleanup"] = "WITHHELD: corrupted off-tree graph retained intentionally; no attach/free/reload after detected child-map loss"
		finish(1)
		return
	var geometry_intact := true
	for row: Dictionary in original:
		var node: Node = row.node
		if node is MeshInstance3D:
			geometry_intact = geometry_intact and node.mesh == row.mesh and node.transform == row.transform and node.material_override == row.material
	check(geometry_intact, "original meshes, transforms and material overrides preserved")
	check(str(authored.name) == str(CASES[family][1]), "existing readable destination name preserved")
	model.free()
	var released := true
	for row: Dictionary in original: released = released and not is_instance_valid(row.node)
	check(released, "uncorrupted model frees all original children")
	check(report.sources_before == hashes(), "sources unchanged")
	report["cleanup"] = "Completed: uncorrupted graph freed normally"
	finish(0 if failures.is_empty() else 1)
