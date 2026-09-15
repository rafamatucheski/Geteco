@tool
extends RefCounted
## Materiais compartilhados: o movimento acontece na GPU sem redesenhar o cenário.
const SHADER := preload("res://geodata/nature/WaterSurface.gdshader")
static var _materials: Dictionary = {}

static func apply(surface: CanvasItem, kind: String = "sea", animated: bool = true) -> void:
	var key := kind + str(animated)
	if not _materials.has(key):
		var effect := ShaderMaterial.new()
		effect.shader = SHADER
		effect.set_shader_parameter("running", 1.0 if animated else 0.0)
		var flow := Vector2(-21, 18) if kind in ["stream", "foam"] else Vector2(7, 2)
		if kind == "lake": flow = Vector2(2.5, 0.8)
		effect.set_shader_parameter("flow", flow)
		effect.set_shader_parameter("strength", 0.65 if kind == "lake" else 1.0)
		effect.set_shader_parameter("foam", 1.0 if kind == "foam" else 0.0)
		effect.set_shader_parameter("fountain", 1.0 if kind == "fountain" else 0.0)
		_materials[key] = effect
	surface.material = _materials[key]
	surface.add_to_group("animated_water_visual")

static func rectangle(parent: Node2D, bounds: Rect2, tint: Color, animated: bool = true) -> Polygon2D:
	var surface := Polygon2D.new()
	surface.name = "AnimatedWater"
	surface.polygon = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
	surface.color = tint
	surface.show_behind_parent = true
	apply(surface, "sea", animated)
	parent.add_child(surface)
	return surface

static func sound_zone(surface: Node2D, kind: String) -> void:
	surface.set_meta("water_sound_kind", kind)
	surface.add_to_group("water_sound_zone")

static func fountain(parent: Node2D, point := Vector2(1750, 1005)) -> void:
	var surface := Polygon2D.new()
	surface.name = "FountainWater"
	surface.position = point
	surface.color = Color("397d86")
	var rim := PackedVector2Array()
	for i in 64:
		rim.append(Vector2.from_angle(TAU * i / 64.0) * 50.0)
	surface.polygon = rim
	apply(surface, "fountain")
	sound_zone(surface, "fountain")
	parent.add_child(surface)
	var nozzle := Polygon2D.new()
	nozzle.color = Color("c4c4ad")
	var center := PackedVector2Array()
	for i in 32:
		center.append(Vector2.from_angle(TAU * i / 32.0) * 13.0)
	nozzle.polygon = center
	surface.add_child(nozzle)
