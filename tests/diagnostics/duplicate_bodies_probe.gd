extends "res://tests/test_maciota_workshop_session.gd"
## Sonda de corpos duplicados no jogo real (Main.tscn). Separa três ocorrências distintas:
##   A) corpo duplicado: duas instâncias visíveis de CivilianModel na mesma subárvore de um modelo;
##   B) malha antiga visível: modelo com `rig_body` (RigBodySwap) que ainda tem MeshInstance3D visível
##      fora do corpo novo e fora da lista `keep` (arma, maca etc. aparecem como "acessório plausível");
##   C) atores sobrepostos: dois corpos visíveis de modelos DIFERENTES a menos de 0,25 m um do outro.
## Também conta a geometria antiga escondida e os nós que ainda rodam `_process` por causa dela.
## É uma foto de alguns pontos do mundo, não prova ausência do problema em outros lugares.
## Uso: "$GODOT" --path . --script res://tests/diagnostics/duplicate_bodies_probe.gd -- --out=res://evidence/npc-meshy/duplicates
const POINTS := [["inicio", Vector3.ZERO], ["rua_166_111", Vector3(166, .08, 111.8)], ["vertice_digo", Vector3(-226.7, .13, -39)]]
var output_dir := "res://evidence/npc-meshy/duplicates"
var report := {"points": []}

func _initialize() -> void:
	create_timer(300).timeout.connect(func(): push_error("DUPLICATES timeout"); quit(3))
	_run.call_deferred()

func _is_body(node: Node) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if script.resource_path.ends_with("/CivilianModel.gd"): return true
		script = script.get_base_script()
	return false

func _model_of(body: Node) -> Node:
	# O "modelo" é o pai do RigBody quando há RigBodySwap; senão, o próprio pai do corpo.
	var parent := body.get_parent()
	if parent != null and parent.name == "RigBody" and parent.get_parent() != null: return parent.get_parent()
	return parent if parent != null else body

func _scan(label: String) -> Dictionary:
	var bodies: Array[Node3D] = []
	for node in root.find_children("*", "Node3D", true, false):
		if _is_body(node): bodies.append(node)
	var visible_bodies: Array[Node3D] = []
	var models := {}
	for body in bodies:
		if not body.is_visible_in_tree(): continue
		visible_bodies.append(body)
		var model := _model_of(body)
		models[model.get_instance_id()] = models.get(model.get_instance_id(), 0) + 1
	var meshy := 0
	for body in visible_bodies:
		if body.get("skeleton") != null: meshy += 1
	var result := {"label": label, "bodies": bodies.size(), "visible_bodies": visible_bodies.size(), "visible_meshy_bodies": meshy}
	# A) mais de um corpo visível dentro do mesmo modelo.
	var double: Array = []
	for id in models:
		if int(models[id]) > 1:
			var model := instance_from_id(id) as Node
			var members: Array = []
			for body in visible_bodies:
				if _model_of(body) == model: members.append({"path": str(body.get_path()), "position": str(body.global_position), "class": body.get_script().resource_path.get_file()})
			var spread := 0.0
			for a in visible_bodies:
				for b in visible_bodies:
					if a != b and _model_of(a) == model and _model_of(b) == model: spread = maxf(spread, a.global_position.distance_to(b.global_position))
			# Dois funcionários filhos do mesmo local (ex.: Vertice) são pessoas distintas: só conta como corpo
			# duplicado quando os corpos ocupam praticamente o mesmo ponto.
			if spread >= 0.5: continue
			double.append({"model": model.name, "script": str(model.get_script().resource_path) if model.get_script() else "", "visible_bodies": models[id], "max_distance_between_bodies": spread, "members": members})
	result.double_body_in_one_model = double
	# B) malha antiga visível em modelos com rig_body.
	var old_visible: Dictionary = {}
	var hidden_old := 0
	var hidden_old_triangles := 0
	var models_with_swap := 0
	var processing_old := {}
	for body in bodies:
		var model := _model_of(body)
		if model == body or not model.has_meta("rig_body"): continue
		if model.get_instance_id() in processing_old: continue
		processing_old[model.get_instance_id()] = true
		models_with_swap += 1
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			var in_new_body := false
			var up: Node = mesh
			while up != null and up != model:
				if up == body.get_parent(): in_new_body = true; break
				up = up.get_parent()
			if in_new_body or (mesh as MeshInstance3D).mesh == null: continue
			if (mesh as MeshInstance3D).is_visible_in_tree():
				var key := "%s/%s" % [model.get_script().resource_path.get_file() if model.get_script() else model.name, mesh.name]
				old_visible[key] = int(old_visible.get(key, 0)) + 1
			else:
				hidden_old += 1
	result.models_with_old_body_swapped = models_with_swap
	result.hidden_old_meshes = hidden_old
	result.old_meshes_still_visible = old_visible
	# C) atores sobrepostos.
	var overlaps: Array = []
	for i in visible_bodies.size():
		for j in range(i + 1, visible_bodies.size()):
			if visible_bodies[i].global_position.distance_to(visible_bodies[j].global_position) < 0.25 and _model_of(visible_bodies[i]) != _model_of(visible_bodies[j]):
				overlaps.append({"a": str(_model_of(visible_bodies[i]).get_path()), "b": str(_model_of(visible_bodies[j]).get_path()), "position": str(visible_bodies[i].global_position)})
	result.overlapping_actors = overlaps
	print("DUP ", label, " corpos=", bodies.size(), " visíveis=", visible_bodies.size(), " meshy=", meshy, " duplo_no_modelo=", double.size(), " malha_antiga_visível=", old_visible.size(), " sobrepostos=", overlaps.size(), " escondidas=", hidden_old)
	return result

func _run() -> void:
	if DisplayServer.get_name() == "headless": _finish(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output_dir = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	folder = FIXTURE.output_dir("duplicate-bodies")
	path = FIXTURE.write_fixture(folder, "checkpoint.json", _seed())
	var launch := root.get_node_or_null("V2Launch")
	old_launch_path = str(launch.selected_path)
	launch.selected_path = path
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	world.set_meta("menu_save_path", path)
	root.add_child(world)
	current_scene = world
	if not await _ready_world(): _finish(1); return
	root.size = Vector2i(1280, 720)
	world.gameplay.god_mode = true
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	var start: Vector3 = world.player.global_position
	for point in POINTS:
		var where: Vector3 = start if point[1] == Vector3.ZERO else point[1]
		world.player.teleport(where)
		await create_timer(14.0).timeout
		report.points.append(_scan(point[0]))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [output_dir, point[0]]))
	# Garagem do Maciota: o mecânico e os residentes de interior.
	if await world.session.enter_place("maciota", false):
		await _frames(30)
		report.points.append(_scan("garagem_maciota"))
	var out := FileAccess.open(ProjectSettings.globalize_path("%s/duplicates.json" % output_dir), FileAccess.WRITE)
	out.store_string(JSON.stringify(report, "\t"))
	print("DUP_OUTPUT ", output_dir)
	_finish(0)
