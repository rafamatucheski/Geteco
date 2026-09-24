extends StaticBody2D
## The impassable basin follows the visible deep-water polygon exactly.
const DECK := preload("res://world/mountain_pass/MountainLakeGeometry.gd").DECK

var water := PackedVector2Array()
var _recovery_clock := 0.0

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("mountain_geodata")
	set_meta("geometry_contract", "deep_water_minus_bridge_deck")
	for outline in Geometry2D.clip_polygons(water, _deck_polygon()):
		var collision := CollisionPolygon2D.new()
		collision.polygon = outline
		add_child(collision)

func _physics_process(delta: float) -> void:
	_recovery_clock += delta
	if _recovery_clock < 0.25:
		return
	_recovery_clock = 0.0
	# Old saves can place a player or vehicle inside the new solid basin.
	for group in ["player", "vehicle"]:
		for actor in get_tree().get_nodes_in_group(group):
			if not actor is Node2D or not actor.is_visible_in_tree():
				continue
			var point := to_local(actor.global_position)
			if DECK.has_point(point) or not Geometry2D.is_point_in_polygon(point, water):
				continue
			var nearest := Vector2.ZERO
			var distance := INF
			for index in water.size():
				var edge := Geometry2D.get_closest_point_to_segment(point, water[index], water[(index + 1) % water.size()])
				if point.distance_squared_to(edge) < distance:
					distance = point.distance_squared_to(edge)
					nearest = edge
			var outward := point.direction_to(nearest)
			actor.global_position = to_global(nearest + outward * (65.0 if group == "vehicle" else 18.0))
			if actor is CharacterBody2D:
				actor.velocity = Vector2.ZERO
			actor.reset_physics_interpolation()

func _deck_polygon() -> PackedVector2Array:
	return PackedVector2Array([
		DECK.position, Vector2(DECK.end.x, DECK.position.y),
		DECK.end, Vector2(DECK.position.x, DECK.end.y)
	])
