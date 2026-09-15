extends "res://world/harbor/interiors/HarborInteriorBase.gd"
var winter_stock := false
var shop: ClothingStore
var _room_camera: Camera3D
var _room_sprite: Sprite2D
var _actor_scale: Node
var _counter_hint: Label

func _at_counter(actor: Node2D) -> bool:
	return Rect2(-150,-100,300,145).has_point(to_local(actor.global_position))

func _init() -> void:
	room_size=Vector2(450,310)
	floor_color=Color("51483e")
	accent_color=Color("827564")
	display_name="ROUPAS"

func _build_lights() -> void:
	pass

func _setup_interior_content() -> void:
	display_name = "ÚLTIMO ABRIGO / ROUPAS DE NEVE" if winter_stock else "UNION / ROUPAS"
	_create_spawn_and_exit(Vector2(0,90),Vector2(0,135),&"clothing_exit","SAIR")
	var view := SubViewport.new()
	view.size=Vector2i(800,600)
	view.transparent_bg=true
	view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(view)
	var room := Node3D.new()
	view.add_child(room)
	var build := preload("res://world/shared/pedestrians/CitizenDetails.gd")
	build.piece(room,Vector3(14,.15,10),Vector3(0,-.1,0),Color("51483e"))
	for x in range(-6,7):
		build.piece(room,Vector3(.018,.012,10),Vector3(x,0,0),Color("645747"))
	build.piece(room,Vector3(14,2.8,.15),Vector3(0,1.3,-5),Color("938777"))
	# Warm timber, a woven runner and brass detailing unite both branches.
	build.piece(room,Vector3(3.7,.018,5.8),Vector3(0,.012,.5),Color("52676d") if winter_stock else Color("657068"))
	for x in [-1.7,1.7]:
		build.piece(room,Vector3(.045,.008,5.5),Vector3(x,.025,.5),Color("c8b68b"))
	build.piece(room,Vector3(13.8,.12,.12),Vector3(0,.25,-4.85),Color("ccb68c"))
	for x in [-7,7]: build.piece(room,Vector3(.15,2.8,10),Vector3(x,1.3,0),Color("776e64"))
	for x in [-4.5,4.5]:
		build.piece(room,Vector3(3,.15,.8),Vector3(x,2,-2),Color("394247"))
		for side in [-1,1]: build.piece(room,Vector3(.08,2,.08),Vector3(x+side*1.4,1,-2),Color("555d61"))
		for i in 6:
			var tint: Color = [Color("536e80"),Color("735342"),Color("59604a"),Color("7d4049")][i%4]
			build.piece(room,Vector3(.34,1.05,.35),Vector3(x-1.1+i*.43,1.3,-2),tint)
			var coat_x: float = x-1.1+i*.43
			for side in [-1,1]:
				build.piece(room,Vector3(.11,.65,.28),Vector3(coat_x+side*.21,1.42,-2),tint.darkened(.08))
			build.piece(room,Vector3(.025,.9,.025),Vector3(coat_x,1.3,-1.815),Color("d1bf9d"))
			build.piece(room,Vector3(.025,.16,.025),Vector3(coat_x,1.91,-2),Color("c8b68b"))
	build.piece(room,Vector3(3,1.1,1.3),Vector3(0,.55,-3.6),Color("44352e"))
	build.piece(room,Vector3(.6,.4,.5),Vector3(.6,1.3,-3.6),Color("252f34"))
	build.piece(room,Vector3(3.12,.1,1.4),Vector3(0,1.14,-3.6),Color("b19a78"))
	for i in 3:
		build.piece(room,Vector3(.65,.1,.5),Vector3(-.7,1.25+i*.1,-3.6),Color("79949a") if i%2==0 else Color("d0bfa2"))
	for x in [-3,3]:
		build.piece(room,Vector3(.8,.08,.8),Vector3(x,.04,1),Color("938a78"))
		build.piece(room,Vector3(.12,.65,.12),Vector3(x,.4,1),Color("4e5457"))
		build.piece(room,Vector3(.55,.85,.35),Vector3(x,1.1,1),Color("59788a") if winter_stock else Color("775147"),true)
		build.piece(room,Vector3(.25,.28,.25),Vector3(x,1.67,1),Color("b4a995"),true)
		for side in [-1,1]:
			build.piece(room,Vector3(.18,.7,.3),Vector3(x+side*.36,1.14,1),Color("59788a") if winter_stock else Color("775147"),true)
		build.piece(room,Vector3(.04,.78,.04),Vector3(x,1.1,1.19),Color("e1c99c"))
	build.piece(room,Vector3(2.1,2.4,.15),Vector3(5.7,1.2,-4.8),Color("748a91"))
	for x in [4.6,6.8]:
		build.piece(room,Vector3(.09,2.45,.2),Vector3(x,1.2,-4.7),Color("c5af86"))
	build.piece(room,Vector3(2.3,.09,.2),Vector3(5.7,2.4,-4.7),Color("c5af86"))
	# Subtle woven stripes keep the runner from reading as a flat placeholder.
	for i in 12:
		build.piece(room,Vector3(3.2,.006,.026),Vector3(0,.03,-2.1+i*.45),Color("8b9995") if not winter_stock else Color("80949d"))
	for i in 3:
		build.piece(room,Vector3(1.2,.16,.75),Vector3(-5.5,.6+i*.55,-4.5),Color("b6a78a"))
		for j in 2:
			build.piece(room,Vector3(.42,.22,.46),Vector3(-5.8+j*.55,.8+i*.55,-4.5),Color("76908d") if j==0 else Color("d0b996"))
	for x in [-5.8,5.8]:
		build.piece(room,Vector3(.55,.5,.55),Vector3(x,.25,2.7),Color("8c6c52"),true)
		for i in 3:
			build.piece(room,Vector3(.65-i*.13,.5,.65-i*.13),Vector3(x,.75+i*.3,2.7),Color("4e6a57"),true)
	for x in [-4.5,4.5]:
		var lamp := OmniLight3D.new()
		lamp.position=Vector3(x,2.5,-1.5)
		lamp.light_color=Color("ffd9a0")
		lamp.light_energy=.65
		lamp.omni_range=5
		room.add_child(lamp)
		build.piece(room,Vector3(1.8,.08,.18),Vector3(x,2.6,-2),Color("cfb98f"))
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.position=Vector3(0,13,9)
	camera.look_at(Vector3(0,.7,0))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=16
	var light := DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-65,-20,0)
	light.light_energy=1.3
	view.add_child(light)
	var sprite := Sprite2D.new()
	sprite.texture=view.get_texture()
	sprite.scale=Vector2(.85,.85)
	add_child(sprite)
	_room_camera = camera
	_room_sprite = sprite
	var shop_sign := Label.new()
	shop_sign.text = "ÚLTIMO ABRIGO  /  ROUPAS DE NEVE" if winter_stock else "UNION  /  ROUPAS E ACESSÓRIOS"
	shop_sign.position=Vector2(-200,-173)
	shop_sign.size=Vector2(400,24)
	shop_sign.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	shop_sign.add_theme_font_size_override("font_size",14)
	shop_sign.add_theme_color_override("font_color",Color("efdbb2"))
	shop_sign.z_index=6
	add_child(shop_sign)
	for box in [Rect2(-192,-112,94,42),Rect2(98,-112,94,42),Rect2(-48,-140,96,48)]:
		var solid := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size=box.size
		shape.shape=rectangle
		solid.position=box.get_center()
		solid.add_child(shape)
		add_child(solid)
	var label := Label.new()
	label.text="[E] EXPERIMENTAR ROUPAS"
	label.position=Vector2(-110,24)
	label.add_theme_color_override("font_color",Color("efdbb2"))
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",14)
	add_child(label)
	_counter_hint=label
	_counter_hint.hide()
	shop=ClothingStore.new()
	shop.winter_stock=winter_stock
	shop.store_title="ÚLTIMO ABRIGO" if winter_stock else "UNION / ROUPAS"
	add_child(shop)
	shop.store_closed.connect(func(): set_modal_state(false))

func _process(_delta: float) -> void:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	var inside := actor != null and get_camera_rect().has_point(actor.global_position)
	_counter_hint.visible = inside and _at_counter(actor) and not shop.is_active
	if inside and _actor_scale == null and actor.get("viewport_3d") is SubViewport:
		_actor_scale = preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
		add_child(_actor_scale)
		_actor_scale.configure(actor,_room_camera,_room_sprite)
	elif not inside and _actor_scale != null:
		_actor_scale.restore()
		_actor_scale.queue_free()
		_actor_scale=null
	if is_instance_valid(exit_door):
		var prompt := exit_door.get_node_or_null("Prompt") as Label
		if prompt and not prompt.text.is_empty(): prompt.text="E"

func _unhandled_input(event: InputEvent) -> void:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if not actor or not get_camera_rect().has_point(actor.global_position) or shop.is_active: return
	if event.is_action_pressed("interact") and not event.is_echo() and _at_counter(actor):
		set_modal_state(true)
		shop.open_store(actor)
		get_viewport().set_input_as_handled()
