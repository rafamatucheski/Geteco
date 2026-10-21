extends SceneTree
## Monstros da Umbra com corpo do Meshy (21/10/2026): cada estação de susto e o fantasma do salão usam o
## GLB da pasta umbra, a aranha saiu, o monstrão do palco cabe sob o teto e, no susto, as mãos avançam
## para o visitante. Não mede desempenho nem aparência; capturas em tools/capture_umbra_monsters.gd.
const INTERIOR := preload("res://world/places/amusement_park/HauntedHouseInterior.gd")
const CREATURE := preload("res://world/places/amusement_park/UmbraCreature.gd")
var failures: Array[String] = []

func _check(ok: bool, label: String) -> bool:
	print("UMBRA_MONSTERS ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func _initialize() -> void:
	_run.call_deferred()

func _hands(body: Node3D) -> Array:
	var skeleton: Skeleton3D = body.skeleton
	var found := []
	for name in ["mixamorig_LeftHand", "mixamorig_RightHand"]:
		var index := skeleton.find_bone(name)
		found.append(skeleton.global_transform * skeleton.get_bone_global_pose(index).origin)
	return found

func _visible_meshes(node: Node) -> int:
	var count := 0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		if (child as MeshInstance3D).mesh != null and (child as MeshInstance3D).is_visible_in_tree(): count += 1
	return count

func _run() -> void:
	var room := INTERIOR.new()
	root.add_child(room)
	for i in 15: await process_frame
	var creatures: Array[Node3D] = [room.puppet, room.brute]
	for station in room.annex.scares: creatures.append(station.rig)
	_check(room.annex.scares.size() == 4, "quatro estações no anexo (%d)" % room.annex.scares.size())
	for creature in creatures:
		_check(creature.kind != "spider", "sem aranha (%s)" % creature.name)
		var body: Node3D = creature.body
		_check(is_instance_valid(body) and String(body.body_source).begins_with(CREATURE.MESHY_FOLDER), "%s usa corpo do Meshy" % creature.name)
		if not is_instance_valid(body): continue
		_check(_visible_meshes(creature) == 1, "%s tem uma única malha visível (%d)" % [creature.name, _visible_meshes(creature)])
	var brute: Node3D = room.brute
	if is_instance_valid(brute.body):
		var top := -INF
		for child in brute.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = (child as MeshInstance3D).global_transform * (child as MeshInstance3D).get_aabb()
			top = maxf(top, box.end.y)
		_check(top > 2.4 and top < 3.3, "monstrão alto e abaixo do teto de 3,4 m (topo %.2f m)" % top)
		var rest: Array = _hands(brute.body)
		var visitor := Vector3(0, 0, 3.2)
		for i in 90:
			room.update_visitor(visitor, 1.0 / 60.0)
			await process_frame
		var face := room.to_global(visitor + Vector3.UP * 1.6)
		var scared: Array = _hands(brute.body)
		var before := minf(rest[0].distance_to(face), rest[1].distance_to(face))
		var after := minf(scared[0].distance_to(face), scared[1].distance_to(face))
		_check(after < before - .25, "no susto as mãos avançam para o visitante (%.2f → %.2f m)" % [before, after])
	print("UMBRA_MONSTERS ", "OK" if failures.is_empty() else "FALHOU %d" % failures.size())
	quit(0 if failures.is_empty() else 1)
