extends Node2D
## One bounded burst per collision, with ballistic fall, roof landing and melt.
const LIMIT := 6
const ROOF_HEIGHT := 7.0
var pieces: Array[Dictionary] = []
var age := 0.0
var ground_layer: Node2D
var roof_hits := 0
var ground_hits := 0

static func spawn(tree: Node2D, vehicle: CharacterBody2D, direction: Vector2, speed: float) -> Node2D:
	var active := tree.get_tree().get_nodes_in_group("tree_ice_burst")
	if active.size()>=LIMIT: return null
	var burst := load("res://world/mountain_pass/TreeIceFall.gd").new() as Node2D
	tree.get_parent().add_child(burst)
	burst.global_position=tree.global_position
	burst.z_as_relative=false
	burst.z_index=32
	burst.add_to_group("tree_ice_burst")
	var rng := RandomNumberGenerator.new()
	rng.seed=tree.variant_seed+Time.get_ticks_msec()
	for i in 24:
		var point: Vector2 = Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(3,25)*tree.tree_scale
		var drift := direction*minf(speed*.035,10)+Vector2(rng.randf_range(-7,7),rng.randf_range(-7,7))
		# Some pieces begin over the part of the canopy above the striking car.
		if i%3==0 and is_instance_valid(vehicle):
			point=burst.to_local(vehicle.to_global(Vector2(rng.randf_range(-10,10),rng.randf_range(-3,3))))
			drift=Vector2(rng.randf_range(-2,2),rng.randf_range(-1,1))
		burst.pieces.append({"p":point,"v":drift,"h":rng.randf_range(32,70)*tree.tree_scale,"up":rng.randf_range(-8,8),"landed":false,"roof":null,"offset":Vector2.ZERO,"size":rng.randf_range(1.0,2.8),"turn":rng.randf()*TAU})
	return burst

func _ready() -> void:
	ground_layer=Node2D.new()
	ground_layer.z_as_relative=false
	ground_layer.z_index=5
	add_child(ground_layer)
	ground_layer.draw.connect(_draw_ground)

func _process(delta: float) -> void:
	age+=delta
	for piece in pieces:
		if piece.roof!=null:
			var car: Node2D = piece.roof.get_ref()
			if is_instance_valid(car):
				piece.p=to_local(car.to_global(piece.offset))
			else:
				piece.roof=null
				piece.landed=false
		if piece.landed: continue
		var previous_height: float = piece.h
		piece.p+=piece.v*delta
		piece.up-=110*delta
		piece.h+=piece.up*delta
		piece.turn+=delta*2
		if previous_height>ROOF_HEIGHT and piece.h<=ROOF_HEIGHT:
			var car := _vehicle_below(to_global(piece.p))
			if car!=null:
				piece.roof=weakref(car)
				piece.offset=car.to_local(to_global(piece.p))
				piece.landed=true
				piece.h=ROOF_HEIGHT
				roof_hits+=1
		if piece.h<=0 and not piece.landed:
			piece.h=0.0
			piece.landed=true
			ground_hits+=1
	modulate.a=1.0-smoothstep(3.5,6.0,age)
	queue_redraw()
	ground_layer.queue_redraw()
	if age>=6.0: queue_free()

func _vehicle_below(point: Vector2) -> Node2D:
	# Queried once as each shard reaches roof height, never for idle trees.
	for candidate in get_tree().get_nodes_in_group("vehicle"):
		if not candidate is Node2D or not candidate.is_visible_in_tree(): continue
		if candidate.global_position.distance_squared_to(point)>6400: continue
		var hull := candidate.get_node_or_null("Collision") as CollisionShape2D
		if hull==null:
			for child in candidate.get_children():
				if child is CollisionShape2D: hull=child; break
		if hull==null or not hull.shape is RectangleShape2D: continue
		# Roof is narrower than the chassis; ice outside falls beside the car.
		var extent: Vector2 = hull.shape.size*Vector2(.20,.17)
		if Rect2(-extent,extent*2).has_point(hull.to_local(point)): return candidate
	return null

func _draw() -> void:
	for piece in pieces:
		if piece.landed and piece.roof==null: continue
		_shard(self,piece.p-Vector2(0,piece.h),piece)

func _draw_ground() -> void:
	for piece in pieces:
		if not piece.landed or piece.roof!=null: continue
		_shard(ground_layer,piece.p,piece)

func _shard(canvas: Node2D, point: Vector2, piece: Dictionary) -> void:
	var s: float=piece.size
	canvas.draw_set_transform(point,piece.turn)
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(-s,0),Vector2(-s*.3,-s),Vector2(s*.8,-s*.35),Vector2(s*.45,s*.7)]),Color("cee7ee"))
	canvas.draw_line(Vector2(-s*.3,-s),Vector2(s*.8,-s*.35),Color("f1faf9"),.8,true)
	canvas.draw_set_transform(Vector2.ZERO)
