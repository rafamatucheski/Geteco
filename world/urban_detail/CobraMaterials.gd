extends RefCounted
## Acabamentos locais, compartilhados e sem atualização por frame.
static var cache: Dictionary = {}

static func ground(kind := "grass") -> StandardMaterial3D:
	var key := "ground_"+kind
	if cache.has(key): return cache[key]
	if kind == "grass":
		cache[key] = preload("res://world/urban_detail/HarborPaving.gd").lawn_material(Color("6a7559"))
		return cache[key]
	var mat: StandardMaterial3D = preload("res://world/urban_detail/HarborGrassTufts.gd").ground_material(kind).duplicate()
	mat.albedo_color = Color("899075") if kind=="grass" else Color("78796d")
	cache[key]=mat
	return mat

static func surface(kind: String, tint: Color) -> StandardMaterial3D:
	var key := kind + tint.to_html()
	if cache.has(key): return cache[key]
	var image := Image.create_empty(256,256,false,Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 770017
	for y in 256:
		for x in 256:
			var shade := 1.0 + rng.randf_range(-.055,.055)
			match kind:
				"wood":
					shade += sin(float(x)*.65+sin(float(y)*.08))*.075
					if x%32<2: shade = .55
					if y%128<2: shade *= .75
				"metal":
					shade += sin(float(x)*TAU/16.0)*.16
					if y%128<3: shade *= .6
					if (x*13+y*7)%101<8: shade *= .73
				"shingle":
					@warning_ignore("integer_division")
					var row := y/16
					if y%16<2 or (x+(row%2)*16)%32<2: shade = .55
					shade += sin(float(row)*13.0)*.09
			image.set_pixel(x,y,Color(tint.r*shade,tint.g*shade,tint.b*shade))
	image.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE*.25
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.roughness = .87
	cache[key] = material
	return material

static func emblem() -> ArrayMesh:
	if cache.has("emblem"): return cache.emblem
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Capelo grande, corpo enrolado e presas de marfim ficam claros na altura do jogo.
	var ink := Color("a34a32")
	var bone := Color("c4bb92")
	var body := PackedVector2Array([Vector2(0,.05),Vector2(.9,.55),Vector2(1.2,1.3),Vector2(.55,1.95),Vector2(-.85,1.85),Vector2(-1.35,1.25),Vector2(-.7,.75),Vector2(.15,.8),Vector2(.55,1.25)])
	for i in body.size()-1:
		var side := (body[i+1]-body[i]).normalized().orthogonal()*.26
		_quad(tool,[body[i]-side,body[i]+side,body[i+1]+side,body[i+1]-side],ink)
	for i in 48:
		var a := Vector2(cos(i*TAU/48),sin(i*TAU/48))
		var b := Vector2(cos((i+1)*TAU/48),sin((i+1)*TAU/48))
		_quad(tool,[a*2.75,a*2.61,b*2.61,b*2.75],ink)
	_polygon(tool,PackedVector2Array([Vector2(0,-2.25),Vector2(-.6,-1.95),Vector2(-1.25,-1.75),Vector2(-1.6,-1.05),Vector2(-1.42,-.3),Vector2(-.65,.35),Vector2(0,.55),Vector2(.65,.35),Vector2(1.42,-.3),Vector2(1.6,-1.05),Vector2(1.25,-1.75),Vector2(.6,-1.95)]),ink)
	# As marcas em camadas sobem 1 mm, então todos os triângulos têm profundidade sem ambiguidade.
	_polygon(tool,PackedVector2Array([Vector2(-.53,-1.75),Vector2(0,-1.93),Vector2(.53,-1.75),Vector2(.64,-1.08),Vector2(0,-.2),Vector2(-.64,-1.08)]),Color("202922"),.001)
	for sign_value in [-1.0,1.0]:
		_polygon(tool,PackedVector2Array([Vector2(.08*sign_value,-1.38),Vector2(.48*sign_value,-1.58),Vector2(.4*sign_value,-1.29)]),bone,.002)
		_polygon(tool,PackedVector2Array([Vector2(.23*sign_value,-1.02),Vector2(.43*sign_value,-1.08),Vector2(.25*sign_value,-.42)]),bone,.002)
		for rib in 3:
			var y := -.95+rib*.28
			_quad(tool,[Vector2(sign_value*.75,y-.3),Vector2(sign_value*1.22,y-.48),Vector2(sign_value*1.17,y-.35),Vector2(sign_value*.75,y-.19)],Color("67382b"),.002)
	cache.emblem = tool.commit()
	return cache.emblem

static func _polygon(tool: SurfaceTool,points: PackedVector2Array,color: Color,y := 0.0) -> void:
	for index in Geometry2D.triangulate_polygon(points):
		tool.set_normal(Vector3.UP)
		tool.set_color(color)
		tool.add_vertex(Vector3(points[index].x,y,points[index].y))

static func _quad(tool: SurfaceTool, points: Array, color: Color,y := 0.0) -> void:
	for i in [0,2,1,0,3,2]:
		tool.set_normal(Vector3.UP)
		tool.set_color(color)
		tool.add_vertex(Vector3(points[i].x,y,points[i].y))
