extends RefCounted
## One cached radial texture; sizes are world pixels, independent of texture size.
static var _texture: GradientTexture2D

static func texture() -> Texture2D:
	if _texture == null:
		_texture = GradientTexture2D.new()
		_texture.width = 64
		_texture.height = 64
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.gradient = Gradient.new()
		_texture.gradient.offsets = PackedFloat32Array([0.0, 0.28, 0.65, 1.0])
		_texture.gradient.colors = PackedColorArray([Color.WHITE, Color(1,1,1,0.8), Color(1,1,1,0.25), Color(1,1,1,0)])
	return _texture

static func configure(emitter: CPUParticles2D, fire: bool) -> void:
	emitter.texture = texture()
	emitter.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	emitter.local_coords = false
	emitter.amount = 18 if fire else 20
	emitter.lifetime = 0.7 if fire else 1.6
	emitter.direction = Vector2.UP
	emitter.spread = 22.0 if fire else 32.0
	emitter.gravity = Vector2(8, -36 if fire else -18)
	emitter.initial_velocity_min = 20.0 if fire else 10.0
	emitter.initial_velocity_max = 45.0 if fire else 22.0
	emitter.scale_amount_min = (10.0 if fire else 18.0) / 64.0
	emitter.scale_amount_max = (22.0 if fire else 32.0) / 64.0
	emitter.color = Color.WHITE
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.15, 0.55, 1.0])
	colors.colors = PackedColorArray([Color(1,0.95,0.55,0), Color(1,0.8,0.22,0.9), Color(1,0.22,0.035,0.65), Color(0.4,0.12,0.04,0)]) if fire else PackedColorArray([Color(0.35,0.36,0.38,0), Color(0.35,0.36,0.38,0.5), Color(0.48,0.49,0.51,0.32), Color(0.6,0.61,0.63,0)])
	emitter.color_ramp = colors
	var size := Curve.new()
	size.add_point(Vector2(0, 0.45))
	size.add_point(Vector2(0.35, 1.0))
	size.add_point(Vector2(1, 0.15 if fire else 1.0))
	emitter.scale_amount_curve = size
