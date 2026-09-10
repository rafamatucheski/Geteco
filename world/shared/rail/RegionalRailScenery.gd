@tool
extends Node2D
## Tabuleiros divididos em trechos curtos para permitir o descarte fora da câmera.
var rail: Node2D
var supports: Array[Rect2] = []

class Deck extends Node2D:
	var rail: Node2D
	var from_offset := 0.0
	var to_offset := 0.0
	var bridge := false
	func _draw() -> void:
		rail.draw_track(self, from_offset, to_offset)
		var offset := from_offset
		while offset < to_offset:
			var next := minf(offset + 88.0, to_offset)
			var a: Vector2 = rail._route.sample_baked(offset, true)
			var b: Vector2 = rail._route.sample_baked(next, true)
			var normal: Vector2 = a.direction_to(b).orthogonal()
			if bridge:
				for side in [-1.0, 1.0]:
					var base_a: Vector2 = a + normal * 27.0 * side
					var base_b: Vector2 = b + normal * 27.0 * side
					var upper_a: Vector2 = base_a + Vector2(0, -15)
					var upper_b: Vector2 = base_b + Vector2(0, -15)
					draw_line(upper_a, upper_b, Color("94a6a3"), 3, true)
					draw_line(upper_a, base_a, Color("617d7d"), 3, true)
					draw_line(base_a, upper_b, Color("617d7d"), 2, true)
					draw_line(upper_a, base_b, Color("617d7d"), 2, true)
			elif a.y < -6460:
				draw_line(a - normal * 21.0, b - normal * 21.0, Color("dce6eb"), 5, true)
			offset = next

class Piers extends Node2D:
	var lines: Array[PackedVector2Array] = []
	var supports: Array[Rect2] = []
	func _draw() -> void:
		for line in lines:
			var shadow := PackedVector2Array()
			for point in line: shadow.append(point + Vector2(16, 35))
			draw_polyline(shadow, Color(0.015,0.03,0.035,0.27), 52.0, true)
		for rect in supports:
			draw_rect(Rect2(rect.position + Vector2(9, 14), rect.size + Vector2(10,10)), Color(0.02,0.03,0.03,0.3))
			draw_rect(rect.grow(4), Color("5f6c68"))
			draw_rect(rect, Color("a3ada3"))

func build(owner_rail: Node2D) -> void:
	rail = owner_rail
	var piers := Piers.new()
	piers.name = "RegionalRailPiers"
	piers.z_as_relative = false
	piers.z_index = 3
	add_child(piers)
	var body := StaticBody2D.new()
	body.name = "RegionalRailSupports"
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("rail_safety_boundary")
	add_child(body)
	for section in rail.regional_route.sections:
		if String(section.id) == "harbor": continue
		var from: float = section.start
		piers.lines.append(rail.regional_route.sampled_section(section, 24.0))
		while from < float(section.end):
			var deck := Deck.new()
			deck.name = "RailDeck_%s_%d" % [section.id, int(from)]
			deck.rail = rail
			deck.from_offset = from
			deck.to_offset = minf(from + 640.0, section.end)
			deck.bridge = String(section.id) == "bay"
			deck.z_as_relative = false
			deck.z_index = 14
			deck.material = rail.get_underpass_material()
			add_child(deck)
			from = deck.to_offset
		var offset: float = section.start + 180.0
		while offset < float(section.end) - 140.0:
			var point: Vector2 = rail._route.sample_baked(offset, true)
			var rect := Rect2(point - Vector2(7, 9), Vector2(14, 18))
			if rail._pillar_is_clear(rect):
				supports.append(rect)
				var shape := CollisionShape2D.new()
				shape.shape = RectangleShape2D.new()
				shape.shape.size = rect.size
				shape.position = rect.get_center()
				body.add_child(shape)
			offset += 300.0
	piers.supports = supports
	piers.queue_redraw()
