extends Node
## One vacancy clock per authored parking place, not per stolen vehicle.
const RESPAWN_SECONDS := 120.0
const MAX_OUTSTANDING := 3
var vehicle: Node2D
var stock: Array[WeakRef] = []
var owner_ref: WeakRef
var slot_name: String
var position: Vector2
var rotation := 0.0
var archetype: String
var visual_index := 0
var paint: Color
var occupied_shape: Shape2D
var shape_transform := Transform2D.IDENTITY
var elapsed := 0.0
var clock := 0.0
var respawn_seconds := RESPAWN_SECONDS

func configure(parent: Node2D, car: Node2D, at: Vector2, angle: float, id: String, index: int, color: Color) -> void:
	owner_ref = weakref(parent)
	vehicle = car
	slot_name = String(car.name)
	position = at
	rotation = angle
	archetype = id
	visual_index = index
	paint = color
	var collision := car.get_node("Collision") as CollisionShape2D
	occupied_shape = collision.shape.duplicate()
	shape_transform = collision.transform
	clock = float(posmod(slot_name.hash(),10))*.05

func _process(delta: float) -> void:
	clock += delta
	if clock < .5: return
	var step := clock
	clock = 0
	tick(step)

func tick(delta: float) -> void:
	var parent := owner_ref.get_ref() as Node2D
	if not is_instance_valid(parent):
		queue_free()
		return
	var origin := parent.to_global(position)
	if is_instance_valid(vehicle) and vehicle.global_position.distance_to(origin)<80 and vehicle.get("is_broken") != true:
		elapsed = 0
		return
	elapsed += delta
	if elapsed < respawn_seconds: return
	for i in range(stock.size()-1,-1,-1):
		if not is_instance_valid(stock[i].get_ref()): stock.remove_at(i)
	# Keep player-taken cars intact while bounding each slot's live population.
	if stock.size() >= MAX_OUTSTANDING: return
	var viewport := parent.get_viewport()
	if viewport.get_visible_rect().grow(160).has_point(viewport.get_canvas_transform()*origin): return
	for actor in get_tree().get_nodes_in_group("player"):
		if actor is Node2D and actor.global_position.distance_to(origin) < 900: return
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = occupied_shape
	query.transform = parent.global_transform*Transform2D(rotation,position)*shape_transform
	query.margin = 5.0
	query.collision_mask = 15
	if not parent.get_world_2d().direct_space_state.intersect_shape(query,1).is_empty(): return
	if is_instance_valid(vehicle):
		stock.append(weakref(vehicle))
		# Keep the authored node name for its replacement, without losing the car.
		vehicle.name = slot_name+"_Taken_"+str(vehicle.get_instance_id())
	vehicle = preload("res://emergency/ModernTrafficFactory.gd").spawn_parked_vehicle(parent,slot_name,position,rotation,archetype,visual_index,paint,false)
	elapsed = 0
