class_name ResidenceInterior
extends "res://world/harbor/interiors/HarborInteriorBase.gd"

var property_id := ""
var variant_index := 0
var manager: Node
var stations: Array[Dictionary] = []
var viewport_3d: SubViewport
var room_camera: Camera3D
var room_display: Sprite2D
var art: Node3D
var actor_scale: Node
var _active := false

func configure(definition: Dictionary,index: int,owner_manager: Node) -> void:
	property_id = definition.id
	interior_id = StringName("residence_"+property_id)
	display_name = ""
	variant_index = index
	manager = owner_manager
	room_size = Vector2(650,510)
	set_meta("fixed_camera",true)

func _build_lights() -> void: pass
func _build_walls_and_floor() -> void: pass

func _setup_interior_content() -> void:
	viewport_3d = SubViewport.new()
	viewport_3d.name = "ResidenceRoomViewport"
	viewport_3d.size = Vector2i(1440,1000)
	viewport_3d.own_world_3d = true
	viewport_3d.transparent_bg = true
	viewport_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport_3d)
	art = preload("res://world/harbor/residences/ResidenceInterior3D.gd").new()
	art.variant_index = variant_index
	viewport_3d.add_child(art)
	room_camera = Camera3D.new()
	viewport_3d.add_child(room_camera)
	room_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	room_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	room_camera.size = 15.8
	room_camera.look_at_from_position(Vector3(0,14,10),Vector3(0,.4,0))
	room_camera.reset_physics_interpolation()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("ccd3d5")
	env.environment.ambient_light_energy = .6
	viewport_3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62,-24,0)
	sun.light_color = Color("fff0d6")
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	viewport_3d.add_child(sun)
	room_display = Sprite2D.new()
	room_display.name = "ProjectedResidence"
	room_display.texture = viewport_3d.get_texture()
	var metre := room_camera.unproject_position(Vector3.RIGHT).distance_to(room_camera.unproject_position(Vector3.ZERO))
	room_display.scale = Vector2.ONE*40.0/metre
	add_child(room_display)
	walls_body = StaticBody2D.new()
	walls_body.name = "ProjectedSolids"
	walls_body.collision_layer = 1
	walls_body.collision_mask = 0
	add_child(walls_body)
	for id in art.solid_rects:
		var r: Rect2 = art.solid_rects[id]
		var shape := CollisionPolygon2D.new()
		shape.name = id
		shape.polygon = PackedVector2Array([project_floor(r.position),project_floor(Vector2(r.end.x,r.position.y)),project_floor(r.end),project_floor(Vector2(r.position.x,r.end.y))])
		walls_body.add_child(shape)
	spawn_point = Marker2D.new()
	spawn_point.name = "SpawnPoint"
	spawn_point.position = project_floor(Vector2(0,3.7))
	add_child(spawn_point)
	var labels := {"wardrobe":"[E] TROCAR DE ROUPA","arsenal":"[E] ARSENAL","food":"[E] COMER","time":"[E] DESCANSAR","exit":"[E] SAIR"}
	for kind in art.station_points:
		stations.append({"kind":kind,"position":project_floor(art.station_points[kind]),"radius":38.0,"label":labels[kind]})
	set_process(false)

func project_floor(point: Vector2) -> Vector2:
	return (room_camera.unproject_position(Vector3(point.x,0,point.y))-Vector2(viewport_3d.size)*.5)*room_display.scale

func station_near(world_position: Vector2) -> Dictionary:
	var nearest: Dictionary = {}
	var best := INF
	for station in stations:
		var distance := to_local(world_position).distance_to(station.position)
		if distance < station.radius and distance < best:
			nearest = station
			best = distance
	return nearest

func set_npc_rendering_active(value: bool) -> void:
	if not is_instance_valid(viewport_3d): return
	if value == _active: return
	_active = value
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE if value else SubViewport.UPDATE_DISABLED
	if value and not is_instance_valid(actor_scale):
		var actor := get_tree().get_first_node_in_group("player")
		if actor != null and actor.get("viewport_3d") is SubViewport:
			actor_scale = preload("res://world/mountain_pass/MountainInteriorActorScale.gd").new()
			add_child(actor_scale)
			actor_scale.configure(actor,room_camera,room_display)
	elif not value and is_instance_valid(actor_scale):
		actor_scale.restore()
		actor_scale.queue_free()
		actor_scale = null

func _exit_tree() -> void:
	if is_instance_valid(actor_scale): actor_scale.restore()
