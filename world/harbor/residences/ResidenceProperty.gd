class_name ResidenceProperty
extends "res://world/mountain_pass/MountainStaticModelView.gd"

var property_id := ""
var display_name := "CASA"
var price := 0
var footprint := Vector2(200,120)
var entrance_offset := Vector2.ZERO
var garage_offset := Vector2.ZERO
var monaliza_offset := Vector2.ZERO
var extra_vehicle_offset := Vector2.ZERO
var checkpoint_offset := Vector2.ZERO
var standalone := true
var accent := Color("d2a95f")
var active := false
var checkpoint: Marker2D
var variant_index := 0
var driveway := PackedVector2Array()
var walkway := PackedVector2Array()
var parking_rects: Array[Rect2] = []
var access_surface: Node2D
var inline_room: Node2D

func configure(definition: Dictionary) -> void:
	property_id = definition.id
	display_name = definition.name
	price = definition.price
	variant_index = definition.variant
	monaliza_offset = definition.monaliza_offset
	extra_vehicle_offset = definition.extra_vehicle_offset
	garage_offset = (monaliza_offset+extra_vehicle_offset)*.5
	driveway = PackedVector2Array(definition.driveway)
	walkway = PackedVector2Array(definition.walkway)
	standalone = definition.standalone
	accent = definition.accent

func _ready() -> void:
	add_to_group("residence_property")
	# Static 3D is rendered once. Disable interpolation before creating meshes
	# so the cache cannot freeze them at their pre-construction transforms.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	build_view(preload("res://world/harbor/residences/ResidenceExterior3D.gd"),14.0,22.0,Vector3(0,1.2,0),Vector3(0,24,20))
	viewport_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	sprite_3d.z_index = 4
	_build_geodata()
	entrance_offset = project_floor(Vector2(0,3.9))
	checkpoint_offset = entrance_offset+Vector2(0,23)
	checkpoint = Marker2D.new()
	checkpoint.name = "Checkpoint"
	checkpoint.position = checkpoint_offset
	add_child(checkpoint)
	access_surface = Node2D.new()
	access_surface.name = "SidewalkAndDriveway"
	access_surface.z_index = 1
	access_surface.draw.connect(_draw_access)
	add_child(access_surface)
	for center in [monaliza_offset,extra_vehicle_offset]:
		parking_rects.append(Rect2(center-Vector2(43,28),Vector2(86,56)))
	access_surface.queue_redraw()
	_prime_render.call_deferred()

func get_solid_rects() -> Array[Rect2]:
	var front_y: float = project_floor(Vector2(0.0, 3.1)).y
	var min_y := 99999.0
	var min_x := 99999.0
	var max_x := -99999.0
	if is_instance_valid(model):
		for child in model.get_children():
			if child is MeshInstance3D and child.mesh != null:
				var aabb: AABB = child.mesh.get_aabb()
				for i in 8:
					var pt3d: Vector3 = child.transform * aabb.get_endpoint(i)
					if pt3d.y > 0.30 or pt3d.z < 3.2:
						var pt2d: Vector2 = project_point(pt3d)
						min_y = minf(min_y, pt2d.y)
						min_x = minf(min_x, pt2d.x)
						max_x = maxf(max_x, pt2d.x)
	if min_x >= max_x or min_y >= front_y:
		var bounds := Rect2(-footprint * 0.5, footprint).grow(-1)
		return [bounds]
	return [Rect2(min_x, min_y, max_x - min_x, front_y - min_y)]

func _build_geodata() -> void:
	var solids := get_solid_rects()
	var body := StaticBody2D.new()
	body.name = "HouseFootprint"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("building_blocker")
	body.add_to_group("building_geodata")
	body.set_meta("solid_rects_local", solids)
	for solid in solids:
		var collision := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = solid.size
		collision.shape = shape
		collision.position = solid.get_center()
		body.add_child(collision)
	add_child(body)

func _prime_render() -> void:
	if DisplayServer.get_name() == "headless": return
	# Uploads and pipeline creation can finish after the first rendered frame
	# of a large map. Cache only after a bounded warmup, never a partial house.
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in 4:
		await RenderingServer.frame_post_draw
		await get_tree().process_frame
	viewport_3d.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_access() -> void:
	# Concrete sidewalk encloses the drive and reaches the authored road lane.
	access_surface.draw_polyline(driveway,Color("bebcaf"),108,true)
	access_surface.draw_polyline(driveway,Color("676f70"),78,true)
	for i in range(1,driveway.size()):
		var segment := driveway[i]-driveway[i-1]
		var side := segment.normalized().orthogonal()*49
		for sign_value in [-1,1]:
			access_surface.draw_line(driveway[i-1]+side*sign_value,driveway[i]+side*sign_value,Color("d8d3c2"),3,true)
	for rect in parking_rects:
		access_surface.draw_rect(rect.grow(10),Color("bbb9aa"))
		access_surface.draw_rect(rect,Color("707777"))
		access_surface.draw_rect(rect.grow(-5),Color("e3dec9"),false,1.6)
		access_surface.draw_line(rect.position+Vector2(10,7),rect.position+Vector2(10,rect.size.y-7),Color("c9c6b6"),4)
	var path := PackedVector2Array([entrance_offset])
	path.append_array(walkway)
	access_surface.draw_polyline(path,Color("cbc6b4"),24,true)

func set_active(value: bool) -> void:
	active = value

func entrance_position() -> Vector2: return to_global(entrance_offset)
func garage_position() -> Vector2: return to_global(garage_offset)
func monaliza_position() -> Vector2: return to_global(monaliza_offset)
func extra_vehicle_position() -> Vector2: return to_global(extra_vehicle_offset)
func checkpoint_position() -> Vector2: return checkpoint.global_position
func minimap_position() -> Vector2: return entrance_position()

func contains_parked_vehicle(vehicle: Node2D) -> bool:
	# Require the complete physical car footprint in the bay, not the road.
	var collision := vehicle.get_node_or_null("Collision") as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D: return false
	var half: Vector2 = collision.shape.size*.5
	for rect in parking_rects:
		var contained := true
		for corner in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
			if not rect.has_point(to_local(collision.to_global(corner))):
				contained = false
		if contained: return true
	return false
