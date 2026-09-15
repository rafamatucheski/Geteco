extends "res://world/mountain_pass/MountainStaticModelView.gd"
## Port-only view. Ground projection exactly matches the existing collision AABB.
const MODEL := preload("res://world/harbor/HarborPortModel3D.gd")
const PPM := 20.0
const FLOOR_Y := .8
var footprint := Rect2()
var kind := ""

func setup(model_kind: String, rect: Rect2, variant: int) -> void:
	kind = model_kind
	footprint = rect
	position = rect.get_center()
	z_index = 4
	viewport_3d = SubViewport.new()
	viewport_3d.name = "PortModelViewport"
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport_3d.msaa_3d = Viewport.MSAA_2X
	add_child(viewport_3d)
	model = MODEL.new()
	viewport_3d.add_child(model)
	model.build(kind,rect.size.x/PPM,rect.size.y/PPM/FLOOR_Y,variant)
	var projected_height: float = rect.size.y+model.height*.6*PPM
	viewport_3d.size = Vector2i(clampi(ceili(rect.size.x+50),128,1536),clampi(ceili(projected_height+70),128,1024))
	camera_3d = Camera3D.new()
	camera_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.keep_aspect = Camera3D.KEEP_WIDTH
	camera_3d.size = float(viewport_3d.size.x)/PPM
	viewport_3d.add_child(camera_3d)
	var target := Vector3(0,model.height*.5,0)
	camera_3d.position = target+Vector3(0,24,18)
	camera_3d.look_at(target)
	camera_3d.force_update_transform()
	camera_3d.reset_physics_interpolation()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60,-60,0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b3c6d0")
	env.environment.ambient_light_energy = .35
	viewport_3d.add_child(env)
	sprite_3d = Sprite2D.new()
	sprite_3d.texture = viewport_3d.get_texture()
	var metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE*PPM/metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO)-Vector2(viewport_3d.size)*.5)*sprite_3d.scale
	add_child(sprite_3d)
	if kind in ["warehouse", "office"]:
		for id in model.solid_floor_bounds:
			var body := add_solid(model.solid_floor_bounds[id], String(id))
			body.add_to_group("building_geodata")
			body.add_to_group("building_blocker")
			var polygon: PackedVector2Array = body.get_child(0).polygon
			var bounds := Rect2(polygon[0], Vector2.ZERO)
			for point in polygon: bounds = bounds.expand(point)
			body.set_meta("solid_rects_local", [bounds])
		preload("res://systems/interiors/ExteriorOcclusion.gd").attach(sprite_3d, rect.size.y * .5)

	# Retain one rendered image per object, with no continuous 3D simulation.
	set_process(false)
	queue_redraw()

func _draw() -> void:
	if kind == "crane": return
	var r := Rect2(-footprint.size*.5,footprint.size)
	draw_rect(Rect2(r.position+Vector2(10,12),r.size),Color(0.035,.07,.085,.28))
