extends "res://world/mountain_pass/MountainStaticModelView.gd"
## One shared 3D viewport for furniture and both patrons; no viewport per guest.
const MODEL := preload("res://world/harbor/restaurants/RestaurantTable3D.gd")
const PPM := 20.0
var variant := 0
var fabric := Color("b66342")
var venue_id := "anchor"
var table_index := 0
var guest_count := 0
var rain := 0.0
var active := false
var alarm_remaining := 0.0
var render_clock := 0.0
var _requested := false
var _settle_remaining := .4

func _ready() -> void:
	add_to_group("restaurant_terrace")
	z_index = 4
	# Match the table/chair floor footprint, keeping the centre entry unobstructed.
	for index in 3:
		var body := StaticBody2D.new()
		body.name = "TableSolid" if index == 0 else "ChairSolid%d" % index
		body.collision_layer = 1
		body.collision_mask = 0
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(18,12) if index == 0 else Vector2(9,8)
		collision.shape = shape
		body.position.x = 0.0 if index == 0 else (-17.2 if index == 1 else 17.2)
		body.add_child(collision)
		add_child(body)
	set_process(false)
	queue_redraw()

func _draw() -> void:
	# Ground dressing only; the table, chairs and people are all real 3D meshes.
	if venue_id != "anchor":
		draw_rect(Rect2(-27,-10,54,21),Color("af9980"))
		for x in range(-27,28,9):
			draw_line(Vector2(x,-10),Vector2(x,11),Color("97856f"),.6)
		for y in [-3,4]:
			draw_line(Vector2(-27,y),Vector2(27,y),Color("97856f"),.6)
	draw_set_transform(Vector2(3,2),0,Vector2(1,.5))
	draw_circle(Vector2.ZERO,15,Color(.06,.08,.07,.19))
	draw_set_transform(Vector2.ZERO)

func ensure_presentation() -> void:
	_requested = false
	if is_instance_valid(viewport_3d): return
	viewport_3d = SubViewport.new()
	viewport_3d.name = "RestaurantViewport"
	viewport_3d.size = Vector2i(224,224)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	add_child(viewport_3d)
	model = MODEL.new()
	viewport_3d.add_child(model)
	model.build(variant,fabric)
	model.set_conditions(guest_count if alarm_remaining<=0.0 else 0,rain,0.0,true)
	camera_3d = Camera3D.new()
	camera_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.keep_aspect = Camera3D.KEEP_WIDTH
	camera_3d.size = 4.8
	viewport_3d.add_child(camera_3d)
	var target := Vector3(0,1.0,0)
	camera_3d.position = target+Vector3(0,24,18)
	camera_3d.look_at(target)
	camera_3d.reset_physics_interpolation()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-35,0)
	sun.light_energy = .95
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c7d6da")
	environment.environment.ambient_light_energy = .65
	viewport_3d.add_child(environment)
	sprite_3d = Sprite2D.new()
	sprite_3d.name = "TerracePresentation"
	sprite_3d.texture = viewport_3d.get_texture()
	var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE*PPM/metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO)-Vector2(viewport_3d.size)*.5)*sprite_3d.scale
	add_child(sprite_3d)

func update_context(count: int, wetness: float, focus: Vector2, delta: float) -> void:
	guest_count = count
	rain = wetness
	alarm_remaining = maxf(0.0,alarm_remaining-delta)
	var screen_position := get_global_transform_with_canvas().origin
	active = global_position.distance_squared_to(focus)<1100.0*1100.0 and get_viewport_rect().grow(160).has_point(screen_position) and is_visible_in_tree()
	if not active:
		if is_instance_valid(viewport_3d): viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if not is_instance_valid(viewport_3d):
		if not _requested:
			var budget := get_node_or_null("/root/PresentationBudget")
			if budget:
				_requested = true
				budget.request(self)
			else: ensure_presentation()
		return
	model.set_conditions(guest_count if alarm_remaining<=0.0 else 0,rain,delta)
	var moving: bool = model.guest_progress[0]>0.0 or model.guest_progress[1]>0.0 or guest_count>0 or (model.opening>0.0 and model.opening<1.0)
	_settle_remaining = .4 if moving else maxf(0.0,_settle_remaining-delta)
	render_clock += delta
	# 12 fps gestures when visible. Closed, settled tables keep their last frame.
	if render_clock >= 1.0/12.0:
		render_clock = 0.0
		viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if _settle_remaining>0.0 else SubViewport.UPDATE_DISABLED

func hear_gunfire(origin: Vector2, _end: Vector2) -> void:
	if global_position.distance_squared_to(origin)>240.0*240.0: return
	var query := PhysicsRayQueryParameters2D.create(origin,global_position,1)
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and not is_ancestor_of(hit.collider): return
	alarm_remaining = 20.0+table_index*2.5

func get_status() -> Dictionary:
	return {"venue":venue_id,"guests":guest_count if alarm_remaining<=0.0 else 0,"alarmed":alarm_remaining>0.0,"render_active":active,"built":is_instance_valid(viewport_3d),"rain":rain}
