extends RefCounted
## Shared forest outline for the visible ground and the physical world coast.
static func outline() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(4650, 1800), Vector2(5500, 1800),
		Vector2(7300, 1700), Vector2(8650, 1450),
		Vector2(9300, 1100), Vector2(9700, 500),
		Vector2(9750, -500), Vector2(10000, -1500),
		Vector2(10000, -5000), Vector2(4650, -5000)
	])
