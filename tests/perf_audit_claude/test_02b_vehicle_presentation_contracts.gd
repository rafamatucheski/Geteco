extends SceneTree
## GETECO-PERF-02B — contratos de estado independente e ciclo de vida da
## apresentação de veículos depois dos caches de construção.
## Uso: --script res://tests/perf_audit_claude/test_02b_vehicle_presentation_contracts.gd
const FACTORY := preload("res://emergency/ModernTrafficFactory.gd")
const BATCHER := preload("res://cars/VehicleMeshBatcher.gd")
const CLEARANCE := preload("res://prototypes/living_cast/VehicleWheelClearance.gd")
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _vertices(model: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for node in model.originals:
		if is_instance_valid(node): result.append_array(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	return result

func _run() -> void:
	create_timer(120).timeout.connect(func(): push_error("timeout"); quit(2))
	var budget := root.get_node("PresentationBudget")
	budget.set_process(false)
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.make_current()
	await process_frame

	# 1. Dois carros do mesmo arquétipo: dano, pintura, faróis e reparo independentes.
	var a = FACTORY.spawn_parked_vehicle(world, "A", Vector2(0, 0), 0, "union_sedan", 0, Color.RED)
	var b = FACTORY.spawn_parked_vehicle(world, "B", Vector2(120, 0), 0, "union_sedan", 0, Color.BLUE)
	a.ensure_presentation()
	b.ensure_presentation()
	check(is_instance_valid(a.body_model) and is_instance_valid(b.body_model), "ambos construídos")
	check(a.body_model.paint != b.body_model.paint, "pintura é material próprio")
	check(a.body_model.paint.albedo_color == Color.RED and b.body_model.paint.albedo_color == Color.BLUE, "cores preservadas")
	a.repaint_vehicle(Color.GREEN)
	check(b.body_model.paint.albedo_color == Color.BLUE, "repintar A não altera B")
	check(a.wheels.size() >= 4 and a.wheels.size() == b.wheels.size() and a.spinners.size() == a.wheels.size(), "pivôs de roda montados")
	var b_before := _vertices(b.body_model)
	a.body_model.apply_impact(Vector3(0.9, 0.8, -1.5), Vector3(-1, 0, 0), 14.0)
	check(a.body_model.max_deformation() > 0.0, "dano deforma A")
	check(_vertices(b.body_model) == b_before and b.body_model.damaged_vertices.is_empty(), "dano em A não altera a malha de B")
	a.body_model.apply_impact(Vector3(-0.7, 0.7, -2.1), Vector3(0, 0, 1), 20.0)
	var lamps_b: Array = b.body_model.broken_lamps.duplicate()
	check(b.body_model.broken_lamps == [false, false] and lamps_b == [false, false], "faróis de B intactos")
	a.body_model.repair()
	check(a.body_model.max_deformation() == 0.0 and a.body_model.broken_lamps == [false, false], "reparo restaura A")

	# 2. Portas extraídas do corpo restaurado batem com um modelo sem cache.
	var reference: Node3D = load("res://prototypes/living_cast/models/UnionSedanModel.gd").new()
	var holder := SubViewport.new()
	holder.own_world_3d = true
	world.add_child(holder)
	holder.add_child(reference)
	preload("res://prototypes/living_cast/VehicleWheelRig.gd").new().mount(reference)
	BATCHER.batch_model(reference)
	for side in [-1.0, 1.0]:
		var door_a := preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
		a.body_model.add_child(door_a)
		door_a.configure(a.body_model, side)
		var door_ref := preload("res://prototypes/living_cast/VehicleDoor3D.gd").new()
		reference.add_child(door_ref)
		door_ref.configure(reference, side)
		check(door_a.extracted_triangles > 0 and door_a.extracted_triangles == door_ref.extracted_triangles, "porta lado %s idêntica" % side)
	check(b.body_model.find_children("*DoorHinge*", "", true, false).is_empty(), "portas de A não aparecem em B")

	# 3. Viatura: sirene/lightbar ligada ao modelo próprio.
	var police = FACTORY.spawn_parked_vehicle(world, "Police", Vector2(0, 200), 0, "police_suv", 0)
	police.ensure_presentation()
	check(not police.lightbar_3d.lamps.is_empty(), "lightbar da viatura ligado")
	var police_b = FACTORY.spawn_parked_vehicle(world, "PoliceB", Vector2(120, 200), 0, "police_suv", 0)
	police_b.ensure_presentation()
	check(police.lightbar_3d.lamps[0] != police_b.lightbar_3d.lamps[0], "lâmpadas de sirene não compartilhadas")

	# 4. Reutilização: trocar o arquétipo reconstrói sem restos do anterior.
	var reused = FACTORY.spawn_parked_vehicle(world, "Reused", Vector2(0, 400), 0, "union_sedan", 0)
	reused.ensure_presentation()
	var old_model: Node3D = reused.body_model
	reused.body_model.add_child(Node3D.new())
	reused.body_model.get_child(-1).name = "DanteCabinOccupant"
	reused.defer_presentation = false
	reused.apply_archetype("courier_van", Color.WHITE)
	await process_frame
	check(not is_instance_valid(old_model), "modelo anterior liberado")
	check(is_instance_valid(reused.body_model) and reused.body_model.get_node_or_null("DanteCabinOccupant") == null, "sem ocupante do modelo anterior")
	check(reused.body_viewport.get_child_count() == 4, "viewport reconstruído com modelo, câmera, ambiente e luz")

	# 5. Cancelamento: pedido cujo ator morre antes da construção.
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var doomed = FACTORY.spawn_parked_vehicle(world, "Doomed", Vector2(0, 0), 0, "route_city", 0)
	check(budget.pending.has(doomed), "pedido na fila")
	doomed.queue_free()
	await process_frame
	budget._process(0.016)
	check(not budget.pending.has(doomed), "fila descarta ator liberado")
	await process_frame
	check(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT) <= orphans_before, "sem nós órfãos novos")
	if budget.has_method("get_stats"):
		check(int(budget.get_stats().totals.cancelled) >= 1, "cancelamento contabilizado")

	# 6. Caches invalidam quando a malha-fonte muda.
	var box := BoxMesh.new()
	var first := _batched_boxes(box)
	var original: Mesh = first.get_child(0).mesh
	box.size = Vector3(3, 2, 1)
	await process_frame
	var second := _batched_boxes(box)
	check(second.get_child(0).mesh != original and second.get_child(0).mesh.get_aabb().size.x > original.get_aabb().size.x, "batcher invalida malha alterada")
	first.free()
	second.free()

	# 7. Formato por classe de PrimitiveMesh == formato lido dos arrays reais.
	var primitives: Array[PrimitiveMesh] = []
	for i in 3:
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(0.3 + i, 1.0, 2.0 - i * 0.4)
		box_mesh.subdivide_width = i
		primitives.append(box_mesh)
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.1 * (i + 1)
		cylinder.radial_segments = 6 + i * 5
		cylinder.cap_top = i != 1
		primitives.append(cylinder)
		var sphere := SphereMesh.new()
		sphere.rings = 4 + i
		sphere.is_hemisphere = i == 2
		primitives.append(sphere)
		var torus := TorusMesh.new()
		torus.rings = 8 + i
		primitives.append(torus)
		var prism := PrismMesh.new()
		prism.left_to_right = 0.2 * i
		primitives.append(prism)
		var capsule := CapsuleMesh.new()
		capsule.add_uv2 = i == 1
		primitives.append(capsule)
		var plane := PlaneMesh.new()
		plane.add_uv2 = i == 2
		primitives.append(plane)
	var mismatches := 0
	for mesh in primitives:
		if BATCHER._surface_format(mesh) != BATCHER._format_from_arrays(mesh): mismatches += 1
	check(mismatches == 0, "formato por classe de PrimitiveMesh igual ao dos arrays (%d malhas)" % primitives.size())

	world.free()
	budget._process(0.016)
	budget.set_process(true)
	print("CONTRACTS_02B failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _batched_boxes(mesh: Mesh) -> Node3D:
	var model := Node3D.new()
	var material := StandardMaterial3D.new()
	for i in 2:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = material
		part.position.x = i * 2.0
		model.add_child(part)
	BATCHER.batch_model(model)
	return model
