extends Node2D

var direction := Vector2(160,180)
var is_lit := false
var pools: Array[PointLight2D] = []
var glows: Array[Sprite2D] = []

func _ready() -> void:
	add_to_group("port_floodlight")
	var texture := GradientTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.5,.5)
	texture.fill_to = Vector2(1,.5)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0,.25,.7,1])
	gradient.colors = PackedColorArray([Color.WHITE,Color(1,1,1,.8),Color(1,1,1,.2),Color(1,1,1,0)])
	texture.gradient = gradient
	for side in [-1,1]:
		var pool := PointLight2D.new()
		pool.texture = texture
		pool.position = direction+Vector2(side*90,0)
		pool.texture_scale = 2.8
		pool.color = Color("fff2db")
		pool.energy = 0.70
		pool.height = 100
		add_child(pool)
		pools.append(pool)
		var glow := Sprite2D.new()
		glow.texture = texture
		glow.position = Vector2(side*20,-96)
		glow.scale = Vector2(.18,.12)
		glow.modulate = Color(1.0, 0.94, 0.85, 0.25)
		glow.z_index = 9
		var additive := CanvasItemMaterial.new()
		additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = additive
		add_child(glow)
		glows.append(glow)
	set_lit(false)
	_bind.call_deferred()

func _bind() -> void:
	var weather := get_tree().get_first_node_in_group("day_night_manager")
	if weather:
		weather.time_changed.connect(set_lit)
		set_lit(weather.is_dark)

func set_lit(value: bool) -> void:
	is_lit = value
	for pool in pools: pool.visible = value
	for glow in glows: glow.visible = value
