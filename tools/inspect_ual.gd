extends SceneTree
func _init() -> void:
	var s: Node = (load("res://assets/animation_library/AnimationLibrary_Godot_Standard.glb") as PackedScene).instantiate()
	var sk := s.find_child("Skeleton3D", true, false) as Skeleton3D
	var names := []
	for i in sk.get_bone_count(): names.append(sk.get_bone_name(i))
	print("BONES ", sk.get_bone_count(), ": ", ", ".join(names))
	var ap := s.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("ANIMS ", ap.get_animation_list().size(), ": ", ", ".join(ap.get_animation_list()))
	var d: Node = load("res://assets/dante.glb").instantiate()
	var dk := d.find_child("Skeleton3D", true, false) as Skeleton3D
	var dn := []
	for i in dk.get_bone_count(): dn.append(dk.get_bone_name(i))
	print("DANTE ", dk.get_bone_count(), ": ", ", ".join(dn))
	quit()
