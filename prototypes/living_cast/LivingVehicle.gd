extends "res://PlayerCar.gd"

## Opt-in bodies over the existing drivable/crash/door system. No catalog edits.
const SPECS := ["sedan_classic", "station_wagon", "dock_delivery_van", "ranch_pickup", "sport_coupe", "taxi_yellow"]
const COLORS := [Color("43566a"), Color("66774b"), Color("c6bda6"), Color("a25037"), Color("712f42"), Color("c6a348")]
@export_range(0, 5) var body_variant := 0
var body_panels: Array[Polygon2D] = []
var original_panels: Array[PackedVector2Array] = []
var original_colors: Array[Color] = []
var collision_animations := 0
var _dent_tween: Tween

func _ready() -> void:
	super._ready()
	apply_archetype(SPECS[body_variant])
	sprite.hide()
	if active_roof_prop_node: active_roof_prop_node.hide()
	_build_body()

func panel(points: PackedVector2Array, color: Color, deformable := true) -> Polygon2D:
	var node := Polygon2D.new()
	node.polygon = points
	node.color = color
	add_child(node)
	if deformable:
		body_panels.append(node)
		original_panels.append(points.duplicate())
		original_colors.append(color)
	return node

func _clear_all_dents() -> void:
	super._clear_all_dents()
	if _dent_tween and _dent_tween.is_valid(): _dent_tween.kill()
	for i in body_panels.size():
		body_panels[i].polygon = original_panels[i].duplicate()
		body_panels[i].color = original_colors[i]

func _explode() -> void:
	if is_exploded: return
	super._explode()
	for piece in body_panels:
		piece.color = piece.color.darkened(0.78)

func rectangle(rect: Rect2, color: Color, deformable := true) -> Polygon2D:
	return panel(PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)]), color, deformable)

func _build_body() -> void:
	var spec: Dictionary = VehicleCatalog.get_vehicle_spec(SPECS[body_variant])
	var length: float = spec.get("target_length", 78.0)
	var width: float = spec.get("target_width", 32.0)
	var half := length * 0.5
	var w := width * 0.5
	var paint: Color = COLORS[body_variant]
	var nose_cut: float = [8.0, 6.0, 3.0, 5.0, 13.0, 8.0][body_variant]
	for x in [-half * 0.57, half * 0.56]:
		for y in [-w, w]:
			rectangle(Rect2(x - 7, y - 3, 14, 6), Color("191c20"), false)
	panel(PackedVector2Array([Vector2(-half + 5, -w), Vector2(half - nose_cut, -w), Vector2(half, -w + nose_cut * 0.7), Vector2(half, w - nose_cut * 0.7), Vector2(half - nose_cut, w), Vector2(-half + 5, w), Vector2(-half, w - 5), Vector2(-half, -w + 5)]), paint)
	rectangle(Rect2(-half + 2, -w + 4, 3, width - 8), Color("32373b"))
	rectangle(Rect2(half - 3, -w + 5, 3, width - 10), Color("333a3c"))
	var cabin_length: float = length * [0.43, 0.57, 0.25, 0.30, 0.38, 0.43][body_variant]
	var cabin_x := -length * 0.12
	if body_variant in [2, 3]: cabin_x = length * 0.10
	rectangle(Rect2(cabin_x - cabin_length / 2, -w + 3, cabin_length, width - 6), paint.darkened(0.20))
	rectangle(Rect2(cabin_x + cabin_length / 2 - 7, -w + 4, 6, width - 8), Color("243c47"))
	rectangle(Rect2(cabin_x - cabin_length / 2 + 1, -w + 4, 5, width - 8), Color("263b46"))
	rectangle(Rect2(cabin_x - cabin_length / 2 + 7, -w + 6, cabin_length - 15, width - 12), paint.lightened(0.12))
	for y in [-w + 2, w - 3]:
		rectangle(Rect2(cabin_x - cabin_length / 2 + 7, y, cabin_length - 14, 2), Color("233a43"))
	for side in [-1.0, 1.0]:
		rectangle(Rect2(cabin_x + cabin_length / 2 - 7, side * w - 2, 5, 4), paint.lightened(0.12))
		rectangle(Rect2(cabin_x - 2, side * (w - 2), 4, 1), Color("b2b3a7"))
		if body_variant != 2:
			rectangle(Rect2(cabin_x + cabin_length / 2 + 2, side * (w - 7), maxf(1, half - cabin_x - cabin_length / 2 - 10), 0.7), paint.lightened(0.18))
	match body_variant:
		1:
			for y in [-w + 7, w - 8]: rectangle(Rect2(-half + 10, y, length * 0.45, 1.5), Color("aaa899"))
		2:
			rectangle(Rect2(-half + 5, -w + 3, length * 0.53, width - 6), paint.lightened(0.08))
			for i in 4: rectangle(Rect2(-half + 9 + i * 9, -w + 5, 1, width - 10), paint.darkened(0.10))
		3:
			rectangle(Rect2(-half + 5, -w + 4, length * 0.42, width - 8), Color("343a37"))
			for y in [-7, 0, 7]: rectangle(Rect2(-half + 8, y, length * 0.35, 1), Color("575d56"))
		4:
			rectangle(Rect2(-half + 4, -w - 1, 4, width + 2), paint.darkened(0.25))
		5:
			rectangle(Rect2(cabin_x - 4, -5, 8, 10), Color("e1cb89"))
	for y in [-w + 4, w - 8]:
		rectangle(Rect2(half - 5, y, 3, 4), Color("eee0b9"))
		rectangle(Rect2(-half + 1, y, 2, 4), Color("ad3932"))

func _apply_crash_deformation(impact_normal: Vector2, impact_force: float, hit_world_pos: Vector2 = Vector2.ZERO) -> void:
	super._apply_crash_deformation(impact_normal, impact_force, hit_world_pos)
	if body_panels.is_empty() or impact_force < 35: return
	collision_animations += 1
	if _dent_tween and _dent_tween.is_valid(): _dent_tween.kill()
	var local_hit := to_local(hit_world_pos)
	var displacement := global_transform.basis_xform_inv(impact_normal).normalized() * clampf(impact_force / 65, 1, 5)
	var from: Array[PackedVector2Array] = []
	var to: Array[PackedVector2Array] = []
	for i in body_panels.size():
		var points := body_panels[i].polygon.duplicate()
		from.append(points.duplicate())
		for j in points.size():
			var weight := maxf(0, 1 - points[j].distance_to(local_hit) / 26)
			var moved := points[j] + displacement * weight
			points[j] = original_panels[i][j] + (moved - original_panels[i][j]).limit_length(7)
		to.append(points)
	_dent_tween = create_tween()
	_dent_tween.tween_method(func(amount: float):
		for i in body_panels.size():
			var points := from[i].duplicate()
			for j in points.size(): points[j] = from[i][j].lerp(to[i][j], amount)
			body_panels[i].polygon = points
	, 0.0, 1.0, 0.20).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
