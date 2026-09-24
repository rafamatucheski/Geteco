extends "res://systems/interiors/InteriorActorPresentation.gd"

# The cargo deck is above the lake plane. Intersect the camera ray with the
# authored deck, keeping the projected feet on the same physical 2D position.
func floor_position(canvas_position: Vector2) -> Vector3:
	var pixel := room_display.to_local(canvas_position) + room_display.texture.get_size() * .5
	var origin := room_camera.project_ray_origin(pixel)
	var direction := room_camera.project_ray_normal(pixel)
	var ground := origin + direction * (-origin.y / direction.y)
	var deck_height := clampf((9.4 - ground.z) * .1, 0.0, .23)
	return origin + direction * ((deck_height - origin.y) / direction.y)
