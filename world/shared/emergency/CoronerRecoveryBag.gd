extends Node2D
var is_dead := true
var retry := 0.0
const FOOTPRINT := Rect2(-8,-18,16,36)
var solid: StaticBody2D
var room_mesh: MeshInstance3D
var projection: Node
var footprint := PackedVector2Array()
var clearance_radius := 20.0

func _ready() -> void:
	set_meta("coroner_recovery",true)
	footprint = PackedVector2Array([FOOTPRINT.position,Vector2(FOOTPRINT.end.x,FOOTPRINT.position.y),FOOTPRINT.end,Vector2(FOOTPRINT.position.x,FOOTPRINT.end.y)])
	z_index = 5
	solid = StaticBody2D.new()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = FOOTPRINT.size
	solid.add_child(shape)
	add_child(solid)
	visibility_changed.connect(func():
		if is_instance_valid(room_mesh): room_mesh.visible = is_visible_in_tree())
	queue_redraw()

func _draw() -> void:
	if is_instance_valid(room_mesh): return
	draw_style_box(_bag_style(), FOOTPRINT)
	draw_line(Vector2(0,-15),Vector2(0,15),Color("636775"),1)

func _bag_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202329")
	style.set_corner_radius_all(6)
	return style

func configure_room(room: Node2D) -> bool:
	for pair in [["camera_3d","sprite_3d"],["room_camera","room_display"]]:
		if not room.get(pair[0]) is Camera3D or not room.get(pair[1]) is Sprite2D: continue
		projection = preload("res://world/shared/interiors/InteriorActorPresentation.gd").new()
		projection.room_camera = room.get(pair[0])
		projection.room_display = room.get(pair[1])
		add_child(projection)
		projection.set_process(false)
		room_mesh = MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(.44,.18,1.54)
		room_mesh.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("202329")
		material.roughness = .95
		room_mesh.material_override = material
		projection.room_camera.get_parent().add_child(room_mesh)
		for child in solid.get_children(): child.free()
		var polygon := CollisionPolygon2D.new()
		solid.add_child(polygon)
		place(global_position)
		room_mesh.visible = is_visible_in_tree()
		queue_redraw()
		return true
	return false

func place(point: Vector2) -> void:
	global_position = point
	if not is_instance_valid(room_mesh): return
	var floor_point: Vector3 = projection.floor_position(point)
	room_mesh.global_position = floor_point+Vector3(0,.09,0)
	footprint.clear()
	clearance_radius = 0
	# The projected mesh bounds also define the physical obstruction.
	var bounds := room_mesh.mesh.get_aabb()
	for corner in [Vector3(bounds.position.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.position.z),Vector3(bounds.end.x,0,bounds.end.z),Vector3(bounds.position.x,0,bounds.end.z)]:
		var local: Vector2 = to_local(projection.project_world(floor_point+corner))
		footprint.append(local)
		clearance_radius = maxf(clearance_radius,local.length()+1)
	(solid.get_child(0) as CollisionPolygon2D).polygon = footprint

func collection_position(worker: Node2D) -> Vector2:
	if footprint.is_empty(): return global_position
	var best := Vector2.INF
	for i in footprint.size():
		var edge := Geometry2D.get_closest_point_to_segment(worker.global_position,to_global(footprint[i]),to_global(footprint[(i+1)%footprint.size()]))
		if worker.global_position.distance_to(edge)<worker.global_position.distance_to(best): best = edge
	return best+global_position.direction_to(best)*10

func _exit_tree() -> void:
	if is_instance_valid(room_mesh): room_mesh.queue_free()

func _process(delta: float) -> void:
	retry -= delta
	if retry <= 0:
		retry = 4.0
		request_service()

func request_service() -> void:
	if get_meta("service_complete", false): return
	var director: Node = get_node("/root/NPCMedicalCare")._nearest_director(self)
	if director:
		var unit: Node = director.request_dispatch("coroner", self)
		if unit: get_node("/root/CoronerCare").assigned(self, unit)
