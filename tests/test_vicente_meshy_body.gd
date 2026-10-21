extends SceneTree
## Corpo próprio do Vicente (Meshy, 20/10/2026): o contato do deserto e o piloto sentado da arrancada
## usam o GLB dele, uma malha só, sem os pontos soltos da marca da turma, pés no chão, juntas que as
## mortes do Mixamo procuram e mãos alcançando os alvos. Não mede desempenho nem aparência.
const CHARACTER := preload("res://runtime/desert/DesertCharacter.gd")
const WARDROBE := preload("res://runtime/desert/drag_meet/DragMeetWardrobe.gd")
const CIVILIAN := preload("res://assets/CivilianModel.gd")
const DEATH := preload("res://gameplay/MixamoDeath.gd")
var failures: Array[String] = []

func _check(ok: bool, label: String) -> bool:
	print("VICENTE_BODY ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if (child as MeshInstance3D).mesh != null and (child as MeshInstance3D).is_visible_in_tree(): found.append(child)
	return found

func _bone_world(skeleton: Skeleton3D, short_name: String) -> Vector3:
	var index := skeleton.find_bone("mixamorig_" + short_name)
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin

func _run() -> void:
	var ground := Node3D.new()
	root.add_child(ground)
	var person := CHARACTER.new()
	person.identity_id = "vicente"
	ground.add_child(person)
	for i in 10: await process_frame
	var body: Node3D = person.visual
	_check(body.body_source == WARDROBE.VICENTE_BODY, "o contato usa o corpo do Vicente (%s)" % body.body_source)
	var skeleton: Skeleton3D = body.skeleton
	_check(skeleton != null and skeleton.find_bone("mixamorig_Hips") >= 0, "esqueleto Mixamo montado")
	var meshes := _meshes(person)
	_check(meshes.size() == 1 and meshes[0].skeleton != NodePath(), "uma única malha visível, ligada ao esqueleto (%d)" % meshes.size())
	_check(person.find_children("CrewStitch", "", true, false).is_empty(), "sem os pontos soltos da marca procedural")
	_check(not DEATH.joints_of(body).is_empty(), "juntas das mortes do Mixamo existem")
	if meshes.size() == 1:
		var aabb: AABB = meshes[0].global_transform * meshes[0].get_aabb()
		_check(aabb.size.y > 1.70 and aabb.size.y < 1.92, "altura plausível (%.3f m)" % aabb.size.y)
	# Sem chão na cena o CharacterBody3D cai: mede os pés a partir da origem dele.
	var toe_left := _bone_world(skeleton, "LeftToeBase").y - person.global_position.y
	var toe_right := _bone_world(skeleton, "RightToeBase").y - person.global_position.y
	_check(toe_left > -0.03 and toe_left < 0.09 and toe_right > -0.03 and toe_right < 0.09, "em pé, pés no chão (%.3f / %.3f)" % [toe_left, toe_right])

	# Piloto sentado: mesmo corpo; as mãos chegam ao volante tão bem quanto um corpo do catálogo
	# posto no mesmo banco com os mesmos alvos (o controle mede o alcance que o rig já tinha).
	var vicente_driver := await _driver("vicente")
	var control := await _driver("raul")
	_check(vicente_driver.model.body_source == WARDROBE.VICENTE_BODY, "o piloto sentado usa o corpo do Vicente")
	_check(control.model.body_source != WARDROBE.VICENTE_BODY and control.model.body_source != "", "o controle usa um corpo do catálogo")
	_check(vicente_driver.reach <= control.reach + 0.05, "mãos no volante como o controle (%.3f m contra %.3f m)" % [vicente_driver.reach, control.reach])

	print("VICENTE_BODY ", "OK" if failures.is_empty() else "FALHOU %d" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _driver(identity: String) -> Dictionary:
	var car := Node3D.new()
	root.add_child(car)
	var driver := CIVILIAN.new()
	var look: Dictionary = CHARACTER.LOOKS[identity]
	driver.appearance_locked = true
	driver.appearance_variant = int(look.variant)
	driver.wardrobe_overrides = {"female": look.female, "build": look.build, "height": look.height}
	WARDROBE.style_rival(driver, identity)
	driver.sit_amount = 1.0
	driver.seat_height = 0.35
	car.add_child(driver)
	var left := Vector3(0.18, 0.75, 0.45)
	var right := Vector3(-0.18, 0.75, 0.45)
	driver.hand_provider = func() -> Array: return [car.to_global(left), car.to_global(right)]
	for i in 20: await process_frame
	var hands := [_bone_world(driver.skeleton, "LeftHand"), _bone_world(driver.skeleton, "RightHand")]
	var reach: float = minf(hands[0].distance_to(car.to_global(left)) + hands[1].distance_to(car.to_global(right)),
		hands[0].distance_to(car.to_global(right)) + hands[1].distance_to(car.to_global(left)))
	return {"model": driver, "reach": reach}
