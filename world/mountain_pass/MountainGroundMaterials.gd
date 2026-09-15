extends RefCounted
## Shared, seeded surface textures. Generated once; no frame-by-frame noise.
static var _textures: Dictionary = {}
static var _normals: Dictionary = {}
static var _canvas: Dictionary = {}
const SIZE := 256
const SURFACE_SHADER := preload("res://world/mountain_pass/MountainGround.gdshader")

static func grain(item: CanvasItem) -> void:
	if not _canvas.has("grain"):
		var material := ShaderMaterial.new()
		material.shader = SURFACE_SHADER
		material.set_shader_parameter("surface",texture("gravel"))
		material.set_shader_parameter("tint_existing",true)
		_canvas["grain"] = material
	item.material = _canvas["grain"]
	item.set_meta("mountain_surface","road_grain")
	item.add_to_group("audio_ground")

static func apply(item: CanvasItem, kind: String) -> void:
	if not _canvas.has(kind):
		var material := ShaderMaterial.new()
		material.shader = SURFACE_SHADER
		material.set_shader_parameter("surface", texture(kind))
		_canvas[kind] = material
	item.material = _canvas[kind]
	item.set_meta("mountain_surface",kind)
	item.add_to_group("audio_ground")
	if item is Polygon2D and kind in ["earth", "forest", "snow", "packed"] and not item.has_node("WheelRuts"):
		var ruts := preload("res://world/mountain_pass/MountainWheelRuts.gd").new()
		ruts.name = "WheelRuts"
		item.add_child(ruts)

static func material_3d(kind: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture(kind)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * (18.0 / SIZE)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.normal_enabled = true
	material.normal_texture = _normals[kind]
	material.normal_scale = 0.65 if kind in ["snow","packed"] else 0.85
	material.roughness = 0.94
	return material

static func texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var noise := FastNoiseLite.new()
	noise.seed = 9137
	noise.frequency = 0.035
	noise.fractal_octaves = 3
	var broad := FastNoiseLite.new()
	broad.seed = 1209
	broad.frequency = 0.012
	var rng := RandomNumberGenerator.new()
	rng.seed = 91309 + kind.hash()
	var palette: Array = {
		"snow":[Color("b2c5cf"),Color("edf0eb")],
		"packed":[Color("8c999a"),Color("d6dcd7")],
		"gravel":[Color("586365"),Color("a2aaa5")],
		"asphalt":[Color("303b42"),Color("657177")],
		"stone":[Color("617174"),Color("b3b9b3")],
		"forest":[Color("25372e"),Color("5d6853")],
		"earth":[Color("302319"),Color("97764c")]
	}.get(kind,[Color("80939d"),Color("e1e8e6")])
	var img := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	var heights := PackedFloat32Array()
	heights.resize(SIZE*SIZE)
	for y in SIZE:
		for x in SIZE:
			var point := Vector2(x,y)
			var n := _tile_noise(noise,point)*0.5+0.5
			var cloud := _tile_noise(broad,point)*0.5+0.5
			var grain := rng.randf()
			var value := clampf(0.32+n*0.46+(cloud-0.5)*0.65+(grain-0.5)*0.14,0,1)
			if kind == "snow":
				value = clampf(0.53+n*0.45+(cloud-0.5)*0.5+(grain-0.5)*0.07,0,1)
			elif kind in ["gravel","asphalt"]:
				value = clampf(n*0.48+grain*0.46,0,1)
			elif kind == "stone":
				var offset := 16 if (y/20)%2 else 0
				var seam := posmod(x+offset,32)<1 or y%20<1
				value = 0.09 if seam else 0.35+n*0.4+(grain-0.5)*0.16
			elif kind == "packed":
				# Exposed aggregate mixed with compacted, dirty snow.
				value = clampf(value+(cloud-0.48)*0.8,0,1)
				if grain<0.025: value*=0.64
			elif kind in ["earth", "forest"]:
				value = clampf(value + (cloud - 0.5) * 0.9, 0, 1)
				if grain < 0.09: value *= 0.45
				if grain > 0.965: value = minf(value + 0.3, 1.0)
			heights[y*SIZE+x] = value
			img.set_pixel(x,y,palette[0].lerp(palette[1],value))
	var normal := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var dx := heights[y*SIZE+(x+1)%SIZE]-heights[y*SIZE+posmod(x-1,SIZE)]
			var dy := heights[((y+1)%SIZE)*SIZE+x]-heights[posmod(y-1,SIZE)*SIZE+x]
			var n := Vector3(-dx*1.5,-dy*1.5,1).normalized()
			normal.set_pixel(x,y,Color(n.x*0.5+0.5,n.y*0.5+0.5,n.z*0.5+0.5))
	img.generate_mipmaps()
	normal.generate_mipmaps()
	_textures[kind] = ImageTexture.create_from_image(img)
	_normals[kind] = ImageTexture.create_from_image(normal)
	return _textures[kind]

static func _tile_noise(noise: FastNoiseLite, p: Vector2) -> float:
	var u := p.x/SIZE
	var v := p.y/SIZE
	return lerpf(lerpf(noise.get_noise_2d(p.x,p.y),noise.get_noise_2d(p.x-SIZE,p.y),u),lerpf(noise.get_noise_2d(p.x,p.y-SIZE),noise.get_noise_2d(p.x-SIZE,p.y-SIZE),u),v)
