extends SceneTree
## Catálogo de pedestres do Meshy: cada corpo cumpre o contrato do CivilianModel (um só corpo visível, altura,
## pés no chão, mãos no alvo, sentar), a escolha é determinística pela identidade e respeita sexo/corpulência,
## pedestres reais do `Actor` recebem corpo do catálogo e a montanha (guarda-roupa fixo) continua procedural.
## Não mede desempenho.
const CATALOG := preload("res://assets/civilians/CivilianBodyCatalog.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const ACTOR := preload("res://scripts/Actor.gd")
const DEATH := preload("res://gameplay/MixamoDeath.gd")
var failures: Array[String] = []

func _check(ok: bool, label: String) -> bool:
	print("CATALOGO ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _bone_world(skeleton: Skeleton3D, short_name: String) -> Vector3:
	var index := skeleton.find_bone("mixamorig_" + short_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin

func _run() -> void:
	var entries := CATALOG.available()
	_check(entries.size() >= 4, "o catálogo tem corpos disponíveis (%d)" % entries.size())
	for entry in entries: await _check_body(entry)
	await _check_selection()
	await _check_actors()
	print("CATALOGO failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _check_body(entry: Dictionary) -> void:
	var tag := String(entry.id)
	var walker := Node3D.new()
	root.add_child(walker)
	var model := CIVILIAN.new() as Node3D
	model.appearance_locked = true
	model.appearance_variant = 7
	model.body_source = CATALOG.FOLDER + String(entry.file)
	walker.add_child(model)
	for i in 8: await process_frame
	var skeleton: Skeleton3D = model.skeleton
	var meshes: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null: meshes.append(node)
	_check(meshes.size() == 1 and meshes[0].is_visible_in_tree(), "%s: uma única malha visível" % tag)
	_check(model.find_children("*", "AnimationPlayer", true, false).is_empty(), "%s: sem AnimationPlayer" % tag)
	_check(skeleton != null and skeleton.get_bone_count() <= 26, "%s: esqueleto leve (%d ossos)" % [tag, skeleton.get_bone_count() if skeleton else -1])
	_check(not DEATH.joints_of(model).is_empty(), "%s: juntas das mortes do Mixamo" % tag)
	var triangles := 0
	if meshes.size() == 1:
		for s in meshes[0].mesh.get_surface_count(): triangles += meshes[0].mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
	_check(triangles > 3500 and triangles < 4600, "%s: ~4,1 mil triângulos (%d)" % [tag, triangles])
	var aabb: AABB = meshes[0].global_transform * meshes[0].get_aabb()
	_check(absf(aabb.size.y - 1.76) < 0.05, "%s: altura 1,76 m (%.3f)" % [tag, aabb.size.y])
	var toe := minf(_bone_world(skeleton, "LeftToeBase").y, _bone_world(skeleton, "RightToeBase").y)
	_check(toe > -0.02 and toe < 0.08, "%s: em pé, pés no chão (%.3f)" % [tag, toe])
	# Andando: sempre um pé no chão e nenhum osso longe.
	var min_ground := 1.0
	var farthest := 0.0
	for frame in 120:
		walker.position.z += 1.4 / 60.0
		await physics_frame
		await process_frame
		if frame > 30:
			min_ground = minf(min_ground, minf(_bone_world(skeleton, "LeftToeBase").y, _bone_world(skeleton, "RightToeBase").y))
		for index in skeleton.get_bone_count(): farthest = maxf(farthest, (skeleton.global_transform * skeleton.get_bone_global_pose(index).origin).distance_to(model.global_position))
	_check(min_ground < 0.07, "%s: andando, sempre há um pé no chão (%.3f)" % [tag, min_ground])
	_check(farthest < 2.0, "%s: nenhum osso a mais de 2 m do corpo (%.2f)" % [tag, farthest])
	# Mãos num alvo.
	# Alvo alcançável pelo braço DESTE corpo: 80% do alcance a partir do ombro, para frente e um pouco para baixo.
	# (Um ponto fixo a ~0,5 m do ombro passa do alcance dos braços mais curtos e mede o comprimento do braço.)
	var reach: float = (model.upper_arm_len + model.forearm_len) * 0.8
	var direction := Vector3(0.12, -0.35, 0.93).normalized()
	var shoulder_origin: Vector3 = model.pelvis.position + model.SPINE_OFFSET
	var target_left: Vector3 = model.to_global(shoulder_origin + model._shoulders[0] + Vector3(-direction.x, direction.y, direction.z) * reach)
	var target_right: Vector3 = model.to_global(shoulder_origin + model._shoulders[1] + direction * reach)
	model.hand_provider = func() -> Array: return [target_left, target_right]
	for i in 20: await process_frame
	var error := maxf(_bone_world(skeleton, "RightHand").distance_to(target_left), _bone_world(skeleton, "LeftHand").distance_to(target_right))
	_check(error < 0.08, "%s: mãos chegam ao alvo alcançável (%.3f m)" % [tag, error])
	model.hand_provider = Callable()
	model.hand_targets = [null, null]
	var before := _bone_world(skeleton, "Hips").y
	model.sit_amount = 1.0
	for i in 30: await process_frame
	_check(_bone_world(skeleton, "Hips").y < before - 0.2, "%s: sentado, a bacia desce" % tag)
	walker.queue_free()

func _check_selection() -> void:
	var seen := {}
	var deterministic := true
	var sexes_ok := true
	var authored_hues := true
	for identity in range(0, 400):
		var a := CIVILIAN.new() as Node3D
		a.appearance_locked = true
		a.appearance_variant = identity
		CATALOG.apply(a, identity)
		if not is_zero_approx(float(a.body_tint.hue)): authored_hues = false
		var b := CIVILIAN.new() as Node3D
		b.appearance_locked = true
		b.appearance_variant = identity
		CATALOG.apply(b, identity)
		if a.body_source != b.body_source or not is_equal_approx(float(a.body_tint.hue), float(b.body_tint.hue)): deterministic = false
		seen[a.body_source] = int(seen.get(a.body_source, 0)) + 1
		var wardrobe: Dictionary = CIVILIAN._appearance_wardrobe(identity, a.coat_color, a.pants_color, Color.TRANSPARENT, {})
		var entry_female := false
		for entry in CATALOG.available():
			if CATALOG.FOLDER + String(entry.file) == a.body_source: entry_female = bool(entry.female)
		if entry_female != bool(wardrobe.female): sexes_ok = false
		a.free()
		b.free()
	_check(deterministic, "a escolha é determinística pela identidade")
	_check(authored_hues, "texturas sem máscara preservam o matiz autorado da pele em 400 identidades")
	_check(seen.size() == CATALOG.available().size(), "400 identidades usam todos os %d corpos (%d)" % [CATALOG.available().size(), seen.size()])
	_check(sexes_ok, "o corpo sempre combina com o sexo sorteado pelo kit")
	var locked := CIVILIAN.new() as Node3D
	locked.wardrobe_overrides = {"top": 3}
	_check(not CATALOG.apply(locked, 5) and locked.body_source == "", "guarda-roupa fixo continua procedural")
	locked.free()

func _check_actors() -> void:
	var ok_count := 0
	var meshy_count := 0
	var actors: Array[Node3D] = []
	for identity in range(0, 24):
		var actor := ACTOR.new() as Node3D
		actor.identity = identity
		root.add_child(actor)
		actors.append(actor)
	for i in 6: await process_frame
	for actor in actors:
		var model: Node3D = actor.visual.get_child(0)
		if model.skeleton != null: meshy_count += 1
		if model.pelvis != null and actor.visual.get_child_count() == 1: ok_count += 1
	_check(ok_count == actors.size(), "24 pedestres do Actor nasceram com um único modelo cada (%d)" % ok_count)
	_check(meshy_count == actors.size(), "todos os pedestres da rua usam corpo do Meshy (%d/24)" % meshy_count)
	var mountain := ACTOR.new() as Node3D
	mountain.identity = 3
	mountain.set_meta("region_id", "mountain")
	root.add_child(mountain)
	await process_frame
	_check(mountain.visual.get_child(0).skeleton == null, "pedestre da montanha continua procedural")
