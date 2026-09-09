extends RefCounted
## Tiny code-authored particle textures; generated once, no external art dependency.
static var _streak: Texture2D
static var _splash: Texture2D

static func streak() -> Texture2D:
	if _streak == null:
		var image := Image.create(3, 18, false, Image.FORMAT_RGBA8)
		for y in 18:
			var alpha := sin(PI * float(y) / 17.0)
			for x in 3:
				image.set_pixel(x, y, Color(1, 1, 1, alpha * (1.0 if x == 1 else 0.25)))
		_streak = ImageTexture.create_from_image(image)
	return _streak

static func splash() -> Texture2D:
	if _splash == null:
		var image := Image.create(12, 6, false, Image.FORMAT_RGBA8)
		for y in 6:
			for x in 12:
				var radius := Vector2((x - 5.5) / 5.5, (y - 2.5) / 2.5).length()
				image.set_pixel(x, y, Color(1, 1, 1, maxf(0.0, 1.0 - absf(radius - 0.75) * 5.0)))
		_splash = ImageTexture.create_from_image(image)
	return _splash
