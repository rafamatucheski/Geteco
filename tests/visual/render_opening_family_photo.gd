extends SceneTree
## A lembrança usa o mesmo construtor de pessoas do jogo, sem rostos externos.
const Rig = preload("res://scripts/player/DantePreviewRig.gd")
const Geometry = preload("res://cutscenes/opening/v3/opening_stage.gd")
var hosts: Array[CharacterBody2D] = []
var geometry: Node3D

func _initialize() -> void: run.call_deferred()

func person(parent: Node3D, x: float, older: bool) -> CharacterBody2D:
	var rig := Rig.new()
	rig.model_root=Node3D.new(); parent.add_child(rig.model_root)
	rig.model_root.add_child(Node3D.new())
	rig.build("dante_classic")
	rig.model_root.position.x=x
	rig.model_root.rotation.y=.08 if older else -.08
	if older:
		# Cabelo curto, rosto sem barba e silhueta própria no mesmo estilo do jogo.
		rig.model_root.scale=Vector3(.94,1.045,.97)
		rig.mat_black_jacket.albedo_texture=null
		rig.mat_black_jacket.albedo_color=Color("59604b")
		for node in rig.torso_node.get_children():
			if node is MeshInstance3D and node.material_override is StandardMaterial3D:
				if node.material_override.albedo_color.is_equal_approx(Color("5e1924")):
					var shirt: StandardMaterial3D=node.material_override.duplicate()
					shirt.albedo_color=Color("435e76"); node.material_override=shirt
		var head: Node3D=rig.head_node
		head.scale=Vector3(.91,.98,.93)
		for node in head.get_children():
			var lock: bool=node is MeshInstance3D and node.material_override is StandardMaterial3D and node.material_override.albedo_color.is_equal_approx(Color("101013"))
			if lock or node.name.begins_with("Hair") or node.name=="ShortBeard" or absf(node.position.y+.049)<.001 or absf(node.position.y+.046)<.001:
				node.hide()
			elif node.name=="Face": node.scale=Vector3(.94,1.03,1)
			elif absf(node.position.y-.039)<.001:
				node.scale.y*=.65; node.rotation.z*=.25
		var hair: StandardMaterial3D=geometry.mat("463e33",1)
		var cropped:=Geometry.Adapter._make_loft([
			Vector4(.071,.099,.081,.007),Vector4(.107,.096,.078,.010),
			Vector4(.145,.070,.060,.014),Vector4(.155,.012,.020,.014)],hair,20)
		cropped.name="BrotherCroppedHair"; head.add_child(cropped)
		for side in [-1,1]:
			geometry.sphere(head,Vector3(side*.096,.051,.022),Vector3(.016,.062,.105),hair)
		var temple: StandardMaterial3D=geometry.mat("84755e",1)
		for side in [-1,1]: geometry.sphere(head,Vector3(side*.099,.048,-.012),Vector3(.009,.035,.032),temple)
	else:
		rig.mat_black_jacket.albedo_color=Color(.9,.9,.9)
	for node in rig.head_node.get_children():
		if absf(node.position.y-.019)<.001: node.scale.y*=.65
		if absf(node.position.y-.020)<.001: node.scale.y*=.55
	rig.head_node.rotation=Vector3(-.015,-.025 if older else .025,.035 if older else -.035)
	hosts.append(rig)
	return rig

func run() -> void:
	root.size=Vector2i(1536,1024); root.content_scale_size=root.size
	root.msaa_3d=Viewport.MSAA_4X
	root.msaa_2d=Viewport.MSAA_DISABLED
	var world:=Node3D.new(); root.add_child(world)
	world.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_OFF
	geometry=Geometry.new()
	var env:=WorldEnvironment.new(); env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("b3afa0")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("c7ced4")
	env.environment.ambient_light_energy=.55
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	world.add_child(env)
	var sun:=DirectionalLight3D.new(); world.add_child(sun)
	sun.rotation_degrees=Vector3(-35,-30,0); sun.light_color=Color("ffe1b5")
	sun.light_energy=1.65; sun.shadow_enabled=true
	var fill:=DirectionalLight3D.new(); world.add_child(fill)
	fill.rotation_degrees=Vector3(-15,135,0); fill.light_energy=.65
	fill.light_color=Color("b6cadd")
	geometry.box(world,Vector3(0,-.065,0),Vector3(8,.10,6),geometry.mat("847b65"))
	geometry.box(world,Vector3(0,1,1.2),Vector3(6,2.5,.12),geometry.mat("a49a7e"))
	geometry.box(world,Vector3(.3,1,.98),Vector3(2.7,2.15,.12),geometry.mat("526264"))
	for i in 17:
		geometry.box(world,Vector3(.3,.05+i*.12,.90),Vector3(2.65,.018,.015),geometry.mat("414d4c"))
	for x in [-1.15,1.75]:
		geometry.box(world,Vector3(x,1,.86),Vector3(.12,2.25,.13),geometry.mat("776852"))
	# Banco de trabalho e ferramentas comunicam a garagem sem texto explicativo.
	geometry.box(world,Vector3(-1.45,.52,.30),Vector3(.75,.06,.45),geometry.mat("65513b"))
	for x in [-1.72,-1.20]: geometry.box(world,Vector3(x,.25,.30),Vector3(.055,.5,.35),geometry.mat("343c3d"))
	geometry.box(world,Vector3(-1.42,.58,.21),Vector3(.28,.07,.18),geometry.mat("714338"))
	var dante:=person(world,-.27,false)
	var brother:=person(world,.27,true)
	# Braço do irmão sobre os ombros; mãos externas relaxadas.
	geometry._arm(brother.left_upper_arm,brother.left_lower_arm,Vector3(-.68,.99,.03),Vector3(-1,1,.2))
	geometry._arm(dante.right_upper_arm,dante.right_lower_arm,Vector3(.42,.87,.08),Vector3(1,0,.4))
	dante.left_lower_arm.rotation.x=-.20
	brother.right_lower_arm.rotation.x=-.18
	var camera:=Camera3D.new(); world.add_child(camera)
	camera.position=Vector3(-.06,1.12,-2.25)
	camera.look_at(Vector3(0,1.035,0)); camera.fov=30; camera.make_current()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image().save_png("res://cutscenes/opening/v3/assets/brothers_photo.png")
	for rig in hosts: rig.free()
	geometry.free(); world.queue_free(); await process_frame
	print("OPENING_FAMILY_PHOTO ","PASS" if result==OK else "FAIL")
	quit(0 if result==OK else 1)
