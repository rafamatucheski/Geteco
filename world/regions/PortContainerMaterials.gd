extends RefCounted
## Small cached PBR textures: painted steel chips/oxidation and directional timber.
## Built once per palette during region warm-up, never per frame or per cargo.
static var cache: Dictionary = {}
static func material(color: Color, timber := false) -> StandardMaterial3D:
	var key := color.to_html()+str(timber)
	if cache.has(key): return cache[key]
	# A carga gasta pertence à mesma paleta contida do cais; nenhuma camada de
	# material ou objeto extra é introduzido para o acabamento novo.
	if not timber: color = color.lerp(Color("7f7968"),.18).darkened(.12)
	var surface_material := StandardMaterial3D.new()
	surface_material.resource_name = "Cargo_"+key
	surface_material.roughness = .94 if timber else .86
	surface_material.metallic = 0.0 if timber else .20
	surface_material.uv1_triplanar = true
	surface_material.uv1_scale = Vector3(.8,.8,.8)
	var image := Image.create_empty(128,128,false,Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 5917
	noise.frequency = .055
	noise.fractal_octaves = 3
	for y in 128:
		for x in 128:
			var n := noise.get_noise_2d(float(x),float(y))*.5+.5
			var fine := noise.get_noise_2d(x*5.0,y*5.0)*.5+.5
			var tint := color * lerpf(.64,1.08,n)
			if timber:
				var grain := noise.get_noise_2d(x*.18,y*2.7)*.5+.5
				tint = color * lerpf(.45,1.15,grain)
			else:
				var chip := smoothstep(.65,.78,n+fine*.12)
				tint = tint.lerp(Color("624333")*lerpf(.65,1.1,fine),chip*.88)
				tint *= lerpf(.92,1.04,fine)
			image.set_pixel(x,y,tint)
	image.generate_mipmaps()
	surface_material.albedo_texture = ImageTexture.create_from_image(image)
	cache[key] = surface_material
	return surface_material
