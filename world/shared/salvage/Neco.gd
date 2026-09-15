extends "res://world/harbor/interiors/HarborConversationalNPC.gd"
## Neco's articulated mechanic rig; the yard owns dialogue and transactions.
func _ready() -> void:
	character_name = "Neco"
	shirt_color = Color("c78c4c")
	pants_color = Color("334c49")
	hat_color = Color("384e49")
	has_hat = true
	z_index = 8
	_build_3d_viewport()
	preload("res://world/shared/pedestrians/CitizenDetails.gd").finish_rig(self,"clerk")
	_tailor_neco()
	viewport_3d.size=Vector2i(160,160)
	var camera: Camera3D=viewport_3d.get_camera_3d()
	camera.position=Vector3(0,3.8,4.5)
	camera.look_at(Vector3(0,.65,0))
	sprite_3d_display.scale=Vector2.ONE*.25
	sprite_3d_display.position=-(camera.unproject_position(Vector3.ZERO)-Vector2(80,80))*.25
	model_root.rotation.y=PI+.25
	collision_layer=1
	collision_mask=0
	var collision:=CollisionShape2D.new()
	var circle:=CircleShape2D.new()
	circle.radius=8
	collision.shape=circle
	add_child(collision)
	queue_redraw()

func _tailor_neco() -> void:
	var detail:=preload("res://world/shared/pedestrians/CitizenDetails.gd")
	# Heavy leather apron, shoulder straps, patched pocket and a brass buckle.
	detail.piece(torso_node,Vector3(.32,.44,.06),Vector3(0,-.05,-.18),Color("34534c"))
	for side in [-1,1]:
		detail.piece(torso_node,Vector3(.035,.25,.04),Vector3(side*.10,.13,-.18),Color("bda478"))
	detail.piece(torso_node,Vector3(.19,.12,.035),Vector3(0,-.10,-.225),Color("647367"))
	detail.piece(torso_node,Vector3(.05,.045,.04),Vector3(.13,-.22,-.18),Color("ddb96c"))
	# Grey moustache and safety goggles resting on the cap are unique to Neco.
	for side in [-1,1]:
		detail.piece(head_node,Vector3(.065,.032,.035),Vector3(side*.033,-.052,-.151),Color("a6a292"))
		detail.piece(head_node,Vector3(.09,.06,.04),Vector3(side*.055,.10,-.16),Color("202e2c"))
		detail.piece(head_node,Vector3(.065,.035,.012),Vector3(side*.055,.10,-.187),Color("9ebfb4"))
	for arm in [left_lower_arm,right_lower_arm]:
		detail.piece(arm,Vector3(.09,.11,.10),Vector3(0,-.20,0),Color("b5a06d"))
	var tool:=Node3D.new()
	tool.name="Spanner"
	right_lower_arm.add_child(tool)
	tool.position=Vector3(0,-.22,-.09)
	detail.piece(tool,Vector3(.035,.035,.29),Vector3(0,0,-.1),Color("b9c5bd"))
	for side in [-1,1]:
		detail.piece(tool,Vector3(.035,.035,.08),Vector3(side*.045,0,-.25),Color("d0d8cd"))
		detail.piece(model_root,Vector3(.12,.09,.22),Vector3(side*.09,.055,-.04),Color("332d27"))

func _draw() -> void:
	draw_set_transform(Vector2.ZERO,0,Vector2(1,.5))
	draw_circle(Vector2.ZERO,10,Color(0,0,0,.25))

func _physics_process(delta: float) -> void:
	anim_clock+=delta
	var sway:=sin(anim_clock*1.6)*.008
	torso_node.position.y=.75+sway
	head_node.position.y=1.20+sway
	right_upper_arm.rotation.x=-.25+sin(anim_clock)*.04
	left_upper_arm.rotation.z=.10
	var player:=get_tree().get_first_node_in_group("player") as Node2D
	var near:=player!=null and player.global_position.distance_to(global_position)<1100
	viewport_3d.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE if near else SubViewport.UPDATE_DISABLED

func _unhandled_input(_event: InputEvent) -> void:
	pass
