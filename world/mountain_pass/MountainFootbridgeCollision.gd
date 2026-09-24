extends RefCounted
## Matches the side cables and four end posts drawn on GorgeneckFootbridge.

static func install(bridge: StaticBody2D) -> void:
	for side in [-1.0, 1.0]:
		var rail := PackedVector2Array([
			Vector2(-180, side * 23), Vector2(-90, side * 32),
			Vector2(90, side * 32), Vector2(220, side * 23)
		])
		for i in range(rail.size() - 1):
			var rail_col := CollisionShape2D.new()
			var segment := SegmentShape2D.new()
			segment.a = rail[i]
			segment.b = rail[i + 1]
			rail_col.shape = segment
			bridge.add_child(rail_col)
	for ppos in [Vector2(-180, -24), Vector2(-180, 24), Vector2(220, -24), Vector2(220, 24)]:
		var pcol := CollisionShape2D.new()
		var pcirc := CircleShape2D.new()
		pcirc.radius = 6.0
		pcol.shape = pcirc
		pcol.position = ppos
		bridge.add_child(pcol)
