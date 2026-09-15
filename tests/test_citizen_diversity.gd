extends SceneTree
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func create_actor(stage: Node, body: int, beard: int) -> AnimatedPedestrian3D:
	var actor:=AnimatedPedestrian3D.new()
	actor.body_type_override=body
	actor.appearance_seed=84
	actor.appearance_gender=1
	actor.beard_style_override=beard
	actor.archetype_override=1
	stage.add_child(actor)
	actor.ensure_presentation()
	actor.set_physics_process(false)
	return actor
func run() -> void:
	seed(914)
	var stage:=Node2D.new()
	root.add_child(stage)
	current_scene=stage
	var slim:=create_actor(stage,1,0)
	var heavy:=create_actor(stage,2,0)
	var slim_body: MeshInstance3D=slim.torso_node.get_node("BodyShell")
	var heavy_body: MeshInstance3D=heavy.torso_node.get_node("BodyShell")
	var slim_size: Vector3=slim_body.mesh.get_aabb().size*slim.torso_node.scale
	var heavy_size: Vector3=heavy_body.mesh.get_aabb().size*heavy.torso_node.scale
	check(heavy_size.x>slim_size.x*1.7,"Thin and heavy bodies have clearly different width")
	check(heavy_size.z>slim_size.z*1.8,"Full abdomen changes the side silhouette")
	check(slim.get_node("CollisionShape2D").shape.radius==heavy.get_node("CollisionShape2D").shape.radius,"Body diversity preserves collision contracts")
	check(slim.base_walk_speed==heavy.base_walk_speed,"Body diversity preserves movement speed")
	var bounds: Array[AABB]=[]
	for style in 6:
		var actor:=create_actor(stage,0,style)
		var hair:=actor.head_node.get_node_or_null("FacialHair") as MeshInstance3D
		if style==0:
			check(hair==null,"Clean shaven face has no beard geometry")
			bounds.append(AABB())
		else:
			check(hair!=null and hair.mesh.get_faces().size()>0,"Facial hair has rendered geometry")
			bounds.append(hair.mesh.get_aabb())
		actor.free()
	check(bounds[3].position.y<bounds[2].position.y-.04,"Full beard extends below the short beard")
	check(bounds[2].position.y<bounds[1].position.y,"Short beard is longer than stubble")
	check(bounds[5].size.y<.04,"Moustache remains above the chin")
	check(bounds[4].size.x<bounds[3].size.x*.6,"Goatee has a narrow silhouette")
	# Rebuilding the same seeded citizen must not shuffle facial hair.
	var first:=AnimatedPedestrian3D.new()
	first.appearance_seed=128
	first.appearance_gender=1
	first.archetype_override=1
	stage.add_child(first)
	var chosen: int=first.get_meta("beard_style")
	first.free()
	var second:=AnimatedPedestrian3D.new()
	second.appearance_seed=128
	second.appearance_gender=1
	second.archetype_override=1
	stage.add_child(second)
	check(int(second.get_meta("beard_style"))==chosen,"Facial hair identity is stable across reconstruction")
	stage.queue_free()
	await process_frame
	print("CITIZEN_DIVERSITY ",failures)
	quit(0 if failures.is_empty() else 1)
