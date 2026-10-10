extends SceneTree
## Imprime a árvore, os ossos principais, o tamanho e os clipes de um corpo importado do Meshy.
## Uso: "$GODOT" --path . --script res://tools/inspect_meshy_body.gd -- --glb=res://assets/civilians/meshy/mechanic/mechanic_walk.glb
const KEY := ["Hips", "Spine", "Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightArm", "RightForeArm", "RightHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot"]

func _initialize() -> void:
	var path := "res://assets/civilians/meshy/mechanic/mechanic_walk.glb"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--glb="): path = arg.substr(6)
	var scene := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(scene)
	_dump(scene, 0)
	var skeleton := scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	print("ossos: ", skeleton.get_bone_count())
	for bone in skeleton.get_bone_count():
		var bone_name := skeleton.get_bone_name(bone)
		var short := bone_name.replace("mixamorig:", "").replace("mixamorig_", "")
		if short in KEY:
			var rest := skeleton.get_bone_global_rest(bone)
			print("  %-14s pai=%-12s pos=%s" % [short, skeleton.get_bone_name(skeleton.get_bone_parent(bone)).replace("mixamorig:", "") if skeleton.get_bone_parent(bone) >= 0 else "-", rest.origin.snapped(Vector3.ONE * 0.001)])
	var triangles := 0
	for mesh_node: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var aabb := mesh_node.get_aabb()
		print("malha ", mesh_node.name, " aabb=", aabb, " superfícies=", mesh_node.mesh.get_surface_count(), " escala=", mesh_node.scale)
		for s in mesh_node.mesh.get_surface_count():
			triangles += mesh_node.mesh.surface_get_array_len(s, ) if false else 0
	for player: AnimationPlayer in scene.find_children("*", "AnimationPlayer", true, false):
		for clip_name in player.get_animation_list():
			var clip := player.get_animation(clip_name)
			print("clipe ", clip_name, " duração=", clip.length, " trilhas=", clip.get_track_count())
	quit(0)

func _dump(node: Node, depth: int) -> void:
	if depth > 3 and not node is MeshInstance3D and not node is AnimationPlayer and not node is Skeleton3D: return
	print("  ".repeat(depth), node.name, " [", node.get_class(), "]", (" tr=" + str((node as Node3D).transform)) if node is Node3D and depth < 2 else "")
	for child in node.get_children():
		if child.get_parent() is Skeleton3D and not child is MeshInstance3D: continue
		_dump(child, depth + 1)
