extends SceneTree
## Peças de cabeça (bonés, chapéus, óculos) em corpos importados do Meshy: ficam sobre o crânio de cada corpo,
## seguem o osso da cabeça quando ela gira e o sorteio por identidade é estável e respeita o interruptor.
## Não mede desempenho.
const CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const ACCESSORIES := preload("res://assets/civilians/MeshyAccessories.gd")
var failures: Array[String] = []

func _check(ok: bool, label: String) -> bool:
	print("ACESSORIOS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _head_world(skeleton: Skeleton3D) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Head")).origin

func _run() -> void:
	for entry in CATALOG.available():
		for kind in ACCESSORIES.KINDS:
			await _check_piece(CATALOG.FOLDER + String(entry.file), kind, String(entry.id))
	_check_roll()
	print("ACESSORIOS failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _check_piece(path: String, kind: String, tag: String) -> void:
	var model := CIVILIAN.new() as Node3D
	model.appearance_locked = true
	model.appearance_variant = 3
	model.body_source = path
	model.body_accessories = [{"kind": kind, "color": Color("6b4a2c")}]
	root.add_child(model)
	for i in 4: await process_frame
	var skeleton: Skeleton3D = model.skeleton
	var pieces := model.find_children("Acc_*", "MeshInstance3D", true, false)
	var label := "%s/%s" % [tag, kind]
	if not _check(pieces.size() == 1, "%s: uma peça criada" % label):
		model.queue_free()
		return
	var piece := pieces[0] as MeshInstance3D
	var body_top: float = (model.mesh_node.global_transform * model.mesh_node.get_aabb()).end.y
	var box: AABB = piece.global_transform * piece.get_aabb()
	var head := _head_world(skeleton)
	_check(box.end.y > body_top - 0.12 and box.end.y < body_top + 0.17, "%s: altura da peça junto ao topo do crânio (topo %.2f, peça %.2f)" % [label, body_top, box.end.y])
	_check(absf(box.get_center().x - head.x) < 0.05, "%s: centrada na cabeça (%.3f m)" % [label, box.get_center().x - head.x])
	_check(piece.get_parent() is BoneAttachment3D, "%s: presa ao osso da cabeça" % label)
	var visible_meshes := 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null and (node as MeshInstance3D).is_visible_in_tree(): visible_meshes += 1
	_check(visible_meshes == 2, "%s: corpo + uma peça visíveis (%d)" % [label, visible_meshes])
	# A peça acompanha a cabeça quando ela inclina.
	var before := (piece.global_transform * piece.get_aabb()).get_center() - head
	model.head_node.rotation.x = 0.6
	model.set_process(false)
	for i in 4: await process_frame
	model._meshy.sync()
	await process_frame
	var after := (piece.global_transform * piece.get_aabb()).get_center() - _head_world(skeleton)
	_check(after.distance_to(before) > 0.02 and absf(after.length() - before.length()) < 0.01, "%s: gira junto com a cabeça (desloca %.3f m)" % [label, after.distance_to(before)])
	model.queue_free()

func _check_roll() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	_check(str(CATALOG.roll_accessories(a, 0.5, 0.5, CATALOG.HATS)) == str(CATALOG.roll_accessories(b, 0.5, 0.5, CATALOG.HATS)), "o sorteio é determinístico pela semente")
	var hats := 0
	var glasses := 0
	for identity in 600:
		var model := CIVILIAN.new() as Node3D
		model.appearance_locked = true
		model.appearance_variant = identity
		CATALOG.apply(model, identity)
		for piece in model.body_accessories:
			if piece.kind == "sunglasses": glasses += 1
			else: hats += 1
		model.free()
	_check(hats > 60 and hats < 180, "cerca de 20%% dos pedestres usam chapéu (%d/600)" % hats)
	_check(glasses > 40 and glasses < 130, "cerca de 14%% usam óculos escuros (%d/600)" % glasses)
