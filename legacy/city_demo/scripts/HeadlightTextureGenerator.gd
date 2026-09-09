class_name HeadlightTextureGenerator
extends RefCounted

static var _cached_texture: Texture2D = null

static func get_conical_headlight_texture() -> Texture2D:
	if _cached_texture != null:
		return _cached_texture

	var w: int = 340
	var h: int = 240
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cy: float = float(h) * 0.5
	var max_dist: float = float(w) - 15.0
	var max_angle_rad: float = deg_to_rad(34.0)

	for y in range(h):
		var dy: float = float(y) - cy
		for x in range(w):
			var dx: float = float(x)
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= 1.0 or dist > max_dist or dx < 2.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var angle: float = absf(atan2(dy, dx))
			if angle > max_angle_rad:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			# Transição suave cônica nas bordas
			var cone_fade: float = smoothstep(max_angle_rad, 0.0, angle)
			# Queda suave de alcance com a distância
			var dist_fade: float = smoothstep(max_dist, 6.0, dist)
			var core_intensity: float = clampf(1.0 - (dist / max_dist), 0.0, 1.0)
			
			var alpha: float = pow(cone_fade * dist_fade, 1.25) * 0.92
			var r: float = 1.0
			var g: float = lerp(0.92, 0.98, core_intensity)
			var b: float = lerp(0.72, 0.90, core_intensity)

			img.set_pixel(x, y, Color(r, g, b, alpha))

	_cached_texture = ImageTexture.create_from_image(img)
	return _cached_texture
