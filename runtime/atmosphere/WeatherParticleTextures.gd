extends RefCounted
## V1 tapered rain streak plus soft native snow/hail silhouettes, cached once.
static var _textures: Dictionary = {}

static func release_cache() -> void:
	# Live materials retain their own references; do not outlive RenderingServer.
	_textures.clear()

static func texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var size := Vector2i(3,18) if kind=="rain" else Vector2i(16,16)
	var image := Image.create_empty(size.x,size.y,false,Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var alpha: float
			if kind=="rain":
				alpha = sin(PI*float(y)/17.0)*(1.0 if x==1 else .25)
			else:
				var p := (Vector2(x,y)-Vector2(7.5,7.5))/7.5
				alpha = 1.0-smoothstep(.35,1.0,p.length()) if kind=="snow" else 1.0-smoothstep(.6,1.0,absf(p.x)+absf(p.y))
			image.set_pixel(x,y,Color(1,1,1,alpha))
	var result := ImageTexture.create_from_image(image)
	_textures[kind] = result
	return result

## Atlas 4×1 de 16 px dos detritos do vento (WindDebris): papel amassado, tira de jornal, folha
## seca e folha verde-oliva. Cor no próprio texel: papel não fica verde ao sortear o quadro.
static func litter() -> Texture2D:
	if _textures.has("litter"): return _textures["litter"]
	var image := Image.create_empty(64,16,false,Image.FORMAT_RGBA8)
	for frame in 4:
		for y in 16:
			for x in 16:
				var p := (Vector2(x,y)-Vector2(7.5,7.5))/7.5
				var color := Color(0,0,0,0)
				match frame:
					0:
						# Bola de papel: quadrado de cantos comidos, dobras em xadrez.
						if absf(p.x)+absf(p.y)*.8 < 1.15 and maxf(absf(p.x),absf(p.y)) < .82:
							var fold := .08 if (x/3+y/3)%2==0 else 0.0
							color = Color(.93-fold,.92-fold,.87-fold)
					1:
						# Tira de jornal com linhas de texto.
						if absf(p.x) < .9 and absf(p.y) < .45:
							color = Color(.82,.81,.77) if y%2==0 or absf(p.x) > .75 else Color(.45,.45,.44)
					2, 3:
						# Folha em gota com nervura; a oliva é menor.
						var q := p*(1.0 if frame==2 else 1.3)
						if q.x*q.x*1.9+q.y*q.y*(1.0+.5*q.x) < .9:
							color = Color(.58,.36,.14) if frame==2 else Color(.42,.44,.18)
							if absf(q.y) < .08: color = color.darkened(.35)
				image.set_pixel(frame*16+x,y,color)
	var result := ImageTexture.create_from_image(image)
	_textures["litter"] = result
	return result
