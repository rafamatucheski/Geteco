extends "res://world/harbor/interiors/HarborInteriorBase.gd"
var winter_stock := false
var shop: ClothingStore

func _init() -> void:
	room_size=Vector2(450,310)
	floor_color=Color("51483e")
	accent_color=Color("827564")
	display_name="ROUPAS"

func _build_lights() -> void:
	pass

func _setup_interior_content() -> void:
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
	for x in [-7,7]: build.piece(room,Vector3(.15,2.8,10),Vector3(x,1.3,0),Color("776e64"))
	for x in [-4.5,4.5]:
		build.piece(room,Vector3(3,.15,.8),Vector3(x,2,-2),Color("394247"))
		for side in [-1,1]: build.piece(room,Vector3(.08,2,.08),Vector3(x+side*1.4,1,-2),Color("555d61"))
		for i in 6:
			var tint: Color = [Color("536e80"),Color("735342"),Color("59604a"),Color("7d4049")][i%4]
			build.piece(room,Vector3(.34,1.05,.35),Vector3(x-1.1+i*.43,1.3,-2),tint)
	build.piece(room,Vector3(3,1.1,1.3),Vector3(0,.55,-3.6),Color("44352e"))
	build.piece(room,Vector3(.6,.4,.5),Vector3(.6,1.3,-3.6),Color("252f34"))
	for x in [-3,3]:
		build.piece(room,Vector3(.8,.08,.8),Vector3(x,.04,1),Color("938a78"))
		build.piece(room,Vector3(.12,.65,.12),Vector3(x,.4,1),Color("4e5457"))
		build.piece(room,Vector3(.55,.85,.35),Vector3(x,1.1,1),Color("59788a") if winter_stock else Color("775147"),true)
		build.piece(room,Vector3(.25,.28,.25),Vector3(x,1.67,1),Color("b4a995"),true)
	build.piece(room,Vector3(2.1,2.4,.15),Vector3(5.7,1.2,-4.8),Color("748a91"))
	for i in 3:
		build.piece(room,Vector3(1.2,.16,.75),Vector3(-5.5,.6+i*.55,-4.5),Color("b6a78a"))
	var camera := Camera3D.new()
	view.add_child(camera)
	camera.position=Vector3(0,13,9)
	camera.look_at(Vector3.ZERO)
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
	label.text="[E] VER E EXPERIMENTAR ROUPAS"
	label.position=Vector2(-145,55)
	label.add_theme_font_size_override("font_size",14)
	add_child(label)
	shop=ClothingStore.new()
	add_child(shop)
	shop.store_closed.connect(func(): set_modal_state(false))

func _process(_delta: float) -> void:
	if is_instance_valid(exit_door):
		var prompt := exit_door.get_node_or_null("Prompt") as Label
		if prompt and not prompt.text.is_empty(): prompt.text="[E] SAIR"

func _unhandled_input(event: InputEvent) -> void:
	var actor := get_tree().get_first_node_in_group("player") as Node2D
	if not actor or not get_camera_rect().has_point(actor.global_position) or shop.is_active: return
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT
	if (event.is_action_pressed("interact") or click) and actor.global_position.distance_to(global_position)<135:
		set_modal_state(true)
		shop.open_store(actor)
		get_viewport().set_input_as_handled()
