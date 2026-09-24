extends SceneTree
## Run with the ORIGINAL project as --path; writes only V2 standalone resources.
func _initialize() -> void: call_deferred("export_models")
func export_models() -> void:
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	for profile in 3:
		var source := "res://world/harbor/cobras/CobraBoss.gd" if profile == 2 else "res://world/harbor/cobras/CobraResident.gd"
		var actor: Node = load(source).new()
		actor.profile = profile
		actor.combat_role = ["lookout", "enforcer", "leader"][profile]
		actor.ambient_presentation_atlas = false
		actor.defer_presentation = false
		scene.add_child(actor)
		actor.set_physics_process(false)
		actor._build_role_weapon()
		if profile == 2: actor._build_boss_details()
		var model: Node3D = actor.model_root
		for key in ["torso_node", "head_node", "left_upper_arm", "right_upper_arm", "left_lower_arm", "right_lower_arm", "left_upper_leg", "right_upper_leg", "left_lower_leg", "right_lower_leg"]:
			var part: Node = actor.get(key)
			if is_instance_valid(part): part.name = key
		var clone := model.duplicate() as Node3D
		clone.position = Vector3.ZERO
		clone.name = "CobraOriginal"
		clean(clone, clone)
		var packed := PackedScene.new()
		var error := packed.pack(clone)
		if error != OK:
			push_error("Cannot pack Cobra")
			quit(1)
			return
		var path := "res://assets/gameplay/cobra_%d.scn" % profile
		error = ResourceSaver.save(packed, path)
		print("COBRA_EXPORT ", path, " ", error)
		clone.free()
		actor.queue_free()
	await process_frame
	quit()
func clean(node: Node, owner_root: Node) -> void:
	if node != owner_root: node.owner = owner_root
	node.set_script(null)
	for child in node.get_children(): clean(child, owner_root)
