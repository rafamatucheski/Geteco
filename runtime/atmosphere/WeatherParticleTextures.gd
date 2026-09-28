extends RefCounted
## V1 tapered rain streak plus soft native snow/hail silhouettes, cached once.
static var _textures: Dictionary = {}

static func release_cache() -> void:
	# Live materials retain their own references; do not outlive RenderingServer.
	_textures.clear()

static func texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var size := Vector2i(3,18) if kind=="rain" else Vector2i(16,16)
	var image := Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
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
