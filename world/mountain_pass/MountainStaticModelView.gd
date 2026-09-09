extends Node2D
## A ground-anchored, metrically calibrated model; physical footprints use the
## exact same projection as the displayed render, including camera foreshortening.
var viewport_3d: SubViewport
var camera_3d: Camera3D
var sprite_3d: Sprite2D
var model: Node3D
func build_view(script: Script, metres_in_view: float, pixels_per_metre: float, target := Vector3.ZERO, view_direction := Vector3(0,24,20)) -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "ModelViewport3D"
	viewport_3d.size = Vector2i(960,800)
	viewport_3d.transparent_bg = true
	viewport_3d.own_world_3d = true
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport_3d)
	model = script.new()
	viewport_3d.add_child(model)
	camera_3d = Camera3D.new()
	viewport_3d.add_child(camera_3d)
	camera_3d.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera_3d.size = metres_in_view
	camera_3d.position = target + view_direction
	camera_3d.look_at(target)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55,-24,0)
	sun.light_energy = 1.0
	viewport_3d.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("b8c8d0")
	env.environment.ambient_light_energy = 0.65
	viewport_3d.add_child(env)
	sprite_3d = Sprite2D.new()
	sprite_3d.name = "GroundAnchoredModel"
	sprite_3d.texture = viewport_3d.get_texture()
	var rendered_metre := camera_3d.unproject_position(Vector3.RIGHT).distance_to(camera_3d.unproject_position(Vector3.ZERO))
	sprite_3d.scale = Vector2.ONE * pixels_per_metre / rendered_metre
	sprite_3d.position = -(camera_3d.unproject_position(Vector3.ZERO)-Vector2(viewport_3d.size)*0.5)*sprite_3d.scale
	add_child(sprite_3d)
func project_floor(point: Vector2) -> Vector2:
	return project_point(Vector3(point.x,0,point.y))
func project_point(point: Vector3) -> Vector2:
	return sprite_3d.position+(camera_3d.unproject_position(point)-Vector2(viewport_3d.size)*0.5)*sprite_3d.scale
func unproject_floor(world_point: Vector2) -> Vector2:
	var image := sprite_3d.to_local(world_point)+Vector2(viewport_3d.size)*0.5
	var ray := camera_3d.project_ray_normal(image)
	var origin := camera_3d.project_ray_origin(image)
	var hit := origin+ray*(-origin.y/ray.y)
	return Vector2(hit.x,hit.z)
func add_solid(rect: Rect2, label: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionPolygon2D.new()
	shape.polygon = PackedVector2Array([project_floor(rect.position),project_floor(Vector2(rect.end.x,rect.position.y)),project_floor(rect.end),project_floor(Vector2(rect.position.x,rect.end.y))])
	body.add_child(shape)
	add_child(body)
	return body
