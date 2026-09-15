class_name JunctionSignalVisual2D
extends Node2D

## Fixed 3D signal heads anchored exclusively to a canonical junction and its
## graph-provided approaches. No world coordinate is authored in this class.

const SIGNAL := preload("res://geodata/roads/traffic/FixedTrafficSignal.gd")
const SIDEWALK_CLEARANCE := 10.0
const POLE_ARM_LENGTH := 12.0
const SPACING := preload("res://geodata/roads/RoadPostSpacing.gd")

var junction_id: StringName = &""
var junction_radius := 48.0
var approaches: Array = []
var road_states: Dictionary = {}
var signal_posts: Array[StaticBody2D] = []
var extra_sidewalk_clearance := 0.0
var ground_source: Node2D
var curb_surfaces: Array = []
var sidewalk_surfaces: Array = []


func _ready() -> void:
	add_to_group("junction_signal_visual")
	_rebuild_posts()


func configure(id: StringName, radius: float, source_approaches: Array) -> void:
	junction_id = id
	junction_radius = maxf(24.0, radius)
	approaches = source_approaches.duplicate(true)
	if is_inside_tree(): _rebuild_posts()


func set_road_states(states: Dictionary) -> void:
	road_states = states.duplicate()
	for post in signal_posts:
		post.set_signal_state(int(road_states.get(post.road_index, 0)))


func _rebuild_posts() -> void:
	for post in signal_posts:
		remove_child(post)
		post.queue_free()
	signal_posts.clear()
	for layout in get_signal_layout():
		var post := SIGNAL.new()
		post.name = "SignalPost%d" % signal_posts.size()
		post.position = layout.pole_base
		post.road_index = int(layout.road_index)
		post.entry_tangent = layout.entry_tangent
		post.signal_state = int(road_states.get(post.road_index, 0))
		add_child(post)
		signal_posts.append(post)


func get_signal_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for approach_value in approaches:
		var approach := approach_value as Dictionary
		var road_index := int(approach.get("road_index", -1))
		if road_index < 0:
			continue
		var tangent := _approach_tangent(approach)
		if tangent.is_zero_approx():
			continue
		var outward := -tangent
		# In Godot's y-down top view, +90 degrees is the driver's right.
		var driver_right := tangent.rotated(PI * 0.5).normalized()
		var road_width := maxf(24.0, float(approach.get("road_width", 96.0)))
		var lateral_distance := road_width * 0.5 + SIDEWALK_CLEARANCE + extra_sidewalk_clearance
		var longitudinal_distance := junction_radius + maxf(8.0, road_width * 0.08) + extra_sidewalk_clearance
		var pole_base := outward * longitudinal_distance + driver_right * lateral_distance
		if is_inside_tree():
			var world_base := to_global(pole_base)
			var world_outward := global_transform.basis_xform(outward).normalized()
			for station in get_tree().get_nodes_in_group("urban_bus_stop"):
				if station.has_method("clear_signal_position"):
					world_base = station.clear_signal_position(world_base, world_outward)
			pole_base = to_local(world_base)
		pole_base = _clear_ground_position(pole_base, outward, driver_right, result)
		# The housing reaches back only to the kerb edge; the mast remains fully
		# on the sidewalk and cannot land in a live lane.
		var head_center := pole_base - driver_right * POLE_ARM_LENGTH
		result.append({
			"road_index": road_index,
			"road_width": road_width,
			"entry_tangent": tangent,
			"driver_right": driver_right,
			"pole_base": pole_base,
			"head_center": head_center,
			"housing_axis": outward,
			"lateral_distance": lateral_distance,
		})
	return result


func _clear_ground_position(base: Vector2, outward: Vector2, side: Vector2, placed: Array = []) -> Vector2:
	if _position_clear(base, placed):
		return base
	# Search nearest first against the same polygons used to draw the street.
	# Curves, merged junctions and wider neighboring arms invalidate width-only offsets.
	for radius in range(2, 97, 2):
		for step in range(32):
			var angle := TAU * float(step) / 32.0
			var candidate := base + (side * cos(angle) + outward * sin(angle)) * float(radius)
			if _position_clear(candidate, placed):
				return candidate
	push_warning("No sidewalk foundation found for signal at %s" % junction_id)
	return base

func _position_clear(base: Vector2, placed: Array) -> bool:
	for layout in placed:
		if base.distance_to(layout.pole_base) < SPACING.CLEARANCE: return false
	if is_inside_tree() and not SPACING.is_clear(self, to_global(base), self): return false
	if is_inside_tree():
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = SIGNAL.BASE_RADIUS + 1.0
		query.shape = circle
		query.transform = Transform2D(0, to_global(base))
		query.collision_mask = 1
		var excluded: Array[RID] = []
		for post in signal_posts:
			if is_instance_valid(post): excluded.append(post.get_rid())
		query.exclude = excluded
		for hit in get_world_2d().direct_space_state.intersect_shape(query, 32):
			if hit.collider is StaticBody2D: return false
	return sidewalk_surfaces.is_empty() or not is_instance_valid(ground_source) or _foundation_on_sidewalk(base)


func _foundation_on_sidewalk(base: Vector2) -> bool:
	for sample in range(9):
		var offset := Vector2.ZERO if sample == 0 else Vector2.from_angle(TAU * float(sample - 1) / 8.0) * (SIGNAL.BASE_RADIUS + 1.0)
		var point := ground_source.to_local(to_global(base + offset))
		for polygon in curb_surfaces:
			if Geometry2D.is_point_in_polygon(point, polygon):
				return false
		var supported := false
		for polygon in sidewalk_surfaces:
			if Geometry2D.is_point_in_polygon(point, polygon):
				supported = true
				break
		if not supported:
			return false
	return true


func _approach_tangent(approach: Dictionary) -> Vector2:
	# UnifiedRoadNetwork already publishes entry_tangent = base_tangent *
	# direction. Consuming it directly avoids reversing reverse approaches twice.
	var tangent: Vector2 = approach.get("entry_tangent", approach.get("tangent", Vector2.ZERO))
	if tangent.is_zero_approx() and approach.has("angle"):
		tangent = Vector2.RIGHT.rotated(float(approach.angle))
	return tangent.normalized()
