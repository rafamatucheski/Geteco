@tool
extends RefCounted
## Shared, mipmapped surface tiles. No per-frame generation or extra physics.
static var _tiles: Dictionary = {}

static func texture(kind: String) -> Texture2D:
	if _tiles.has(kind): return _tiles[kind]
	var img := Image.create(256,256,false,Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed=91327
	noise.frequency=.075
	var rng := RandomNumberGenerator.new()
	rng.seed=91327
	for y in 256:
		for x in 256:
			# Periodic coordinates avoid visible joins at the edge of the tile.
			var a := TAU*x/256.0
			var b := TAU*y/256.0
			var grain := noise.get_noise_3d(cos(a)*40,sin(a)*40,cos(b)*40+sin(b)*20)
			var value := .91+grain*.10+rng.randf_range(-.035,.035)
			var warm := 0.0
			if kind=="concrete":
				# Whole-number grouping/index; preserve integer truncation and precision.
				@warning_ignore("integer_division")
				var cell := Vector2i(x/64,y/64)
				value+=sin(cell.x*13.7+cell.y*9.1)*.025
				if x%64==0 or y%64==0: value-=.12
			elif kind=="stone" or kind=="brick":
				var height := 32 if kind=="stone" else 16
				var width := 64 if kind=="stone" else 32
				# Whole-number grouping/index; preserve integer truncation and precision.
				@warning_ignore("integer_division")
				var row := y/height
				# Whole-number grouping/index; preserve integer truncation and precision.
				@warning_ignore("integer_division")
				var shifted := x+(width/2 if row%2==0 else 0)
				# Whole-number grouping/index; preserve integer truncation and precision.
				@warning_ignore("integer_division")
				value+=sin(float(shifted/width)*17.3+row*4.7)*.06
				if shifted%width<2 or y%height<2: value-=.17
				if kind=="brick": warm=.065
			elif kind=="gravel":
				value+=grain*.25
			elif kind=="grass":
				value+=grain*.20
			img.set_pixel(x,y,Color(clampf(value+warm,0,1),clampf(value,0,1),clampf(value-warm,0,1)))
	img.generate_mipmaps()
	var tile := ImageTexture.create_from_image(img)
	_tiles[kind]=tile
	return tile

static func paint(canvas: CanvasItem, rect: Rect2, tint: Color, kind := "concrete") -> void:
	canvas.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Rect source uses the same coordinate space as the district's footprints.
	canvas.draw_texture_rect_region(texture(kind),rect,rect,tint,false,false)

static func yard(canvas: CanvasItem, rect: Rect2, seed_value: int, working := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=seed_value
	# Flush drains and stains are traversable; they add no solid obstacles.
	for corner in [rect.position+Vector2(13,14),rect.end-Vector2(37,20)]:
		canvas.draw_rect(Rect2(corner,Vector2(24,9)),Color("4b504d"))
		for i in 6:
			canvas.draw_line(corner+Vector2(3+i*3,2),corner+Vector2(3+i*3,7),Color("252c2d"),1)
	if working:
		for i in 7:
			var p := rect.position+Vector2(rng.randf_range(.12,.88)*rect.size.x,rng.randf_range(.15,.85)*rect.size.y)
			canvas.draw_set_transform(p,0,Vector2(1,.52))
			canvas.draw_circle(Vector2.ZERO,rng.randf_range(5,13),Color(.09,.075,.05,.16))
			canvas.draw_circle(Vector2(2,-1),rng.randf_range(2,5),Color(.06,.07,.07,.20))
			canvas.draw_set_transform(Vector2.ZERO)
		for i in 2:
			var p := rect.position+Vector2(rect.size.x*(.3+i*.4),rect.size.y*.28)
			for side in [-8,8]:
				canvas.draw_line(p+Vector2(side,0),p+Vector2(side+3,rect.size.y*.32),Color(.12,.13,.12,.16),3,true)

static func garden_edge(canvas: CanvasItem, rect: Rect2, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=seed_value
	for i in maxi(6,int(rect.size.x/18)):
		var p := rect.position+Vector2(rng.randf_range(3,rect.size.x-3),rng.randf_range(2,9))
		canvas.draw_circle(p,rng.randf_range(2,4),Color(.28,.24,.16,.38))
		canvas.draw_line(p,p+Vector2(2,-3),Color("6d7952"),1)
		if i%3==0: canvas.draw_line(p+Vector2(1,2),p+Vector2(4,3),Color("9c8051"),1.5)
	for i in 5:
		var p := rect.position+Vector2(rect.size.x*(.08+i*.19),minf(rect.size.y-5,14))
		for flower in 3:
			var q := p+Vector2(flower*3,rng.randf_range(-3,3))
			canvas.draw_line(q,q+Vector2(1,5),Color("52633d"),1)
			canvas.draw_circle(q,1.6,Color("bfa46f") if seed_value%2 else Color("a76c56"))

static func foundations(canvas: CanvasItem, sites: Array[Dictionary]) -> void:
	for site in sites:
		var rect: Rect2=site.bounds
		# Damp/dusty contact at the wall, drawn with the ground below the facade.
		canvas.draw_line(Vector2(rect.position.x,rect.end.y+2),rect.end+Vector2(0,2),Color(.19,.18,.14,.15),4)
		for i in 4:
			var p := Vector2(rect.position.x+5+i*9,rect.end.y+5)
			canvas.draw_line(p,p+Vector2(3,-2),Color(.33,.36,.22,.45),1)
