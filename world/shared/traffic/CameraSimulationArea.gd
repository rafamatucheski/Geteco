extends RefCounted
const REGIONAL_ACTIVITY_RADIUS := 900.0
const PEDESTRIAN_MARGIN := 120.0
const REGIONAL_PEDESTRIAN_RADIUS := 600.0
static func visible_area(reference: CanvasItem, focus: Vector2, margin := 360.0) -> Rect2:
	var view := reference.get_viewport_rect()
	var world_rect: Rect2 = reference.get_canvas_transform().affine_inverse() * view
	# A folga cobre frenagem e os 200 ms entre revisões. Ao abrir um interior,
	# a simulação externa continua em torno da porta, preservando a ocorrência.
	if not world_rect.grow(500.0).has_point(focus):
		return Rect2(focus-Vector2(850,850),Vector2(1700,1700))
	return world_rect.grow(margin)
