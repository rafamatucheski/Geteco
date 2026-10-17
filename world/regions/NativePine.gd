extends RefCounted
## Árvores nativas da montanha, uma malha compartilhada por variante (sem atlas nem viewport).
## 0,1,2,6,7: coníferas com saias de galhos recortadas e caídas; 3: bétula; 4: carvalho; 5: árvore seca.
## Antes as coníferas eram cones empilhados com ponta minúscula e as folhosas, esferas 7x3 nos galhos.
const NATIVE_ROCK := preload("res://world/regions/NativeRock.gd")
static var _material_cache := {}
static var _models := {}

static func create(variant: int, snowy: bool) -> Node3D:
	var key := str(variant)+str(snowy)
	if not _models.has(key): _models[key] = _build(variant,snowy)
	var root := Node3D.new()
	for entry in _models[key]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = entry.mesh
		mesh.material_override = entry.material
		root.add_child(mesh)
	return root

static func _build(variant: int, snowy: bool) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3913+variant*89
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	bark.set_smooth_group(0)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	leaves.set_smooth_group(-1)
	var snow := SurfaceTool.new()
	snow.begin(Mesh.PRIMITIVE_TRIANGLES)
	snow.set_smooth_group(-1)
	match variant:
		3: _birch(bark,leaves,snow,rng,snowy)
		4: _oak(bark,leaves,snow,rng,snowy)
		5: _dead(bark,snow,rng,snowy)
		_: _conifer(bark,leaves,snow,rng,snowy,variant)
	var result: Array = []
	for pair in [[bark,_bark_material(),true],[leaves,_leaf_material(),false],[snow,_snow_material(),false]]:
		var surface: SurfaceTool = pair[0]
		surface.generate_normals()
		var mesh := surface.commit()
		if mesh.get_surface_count() > 0: result.append({"mesh":mesh,"material":pair[1]})
	return result

# ---------------------------------------------------------------- coníferas

static func _conifer(bark: SurfaceTool, leaves: SurfaceTool, snow: SurfaceTool, rng: RandomNumberGenerator, snowy: bool, variant: int) -> void:
	var tall := 1.13 if variant in [1,6,7] else (.77 if variant==2 else 1.0)
	var slim := .76 if variant in [1,2,7] else 1.0
	var tiers := 6
	var lean := Vector3(.05,0,.02) if variant==7 else Vector3.ZERO
	var tint: Color = [Color("233d30"),Color("2c4433"),Color("344b36"),Color("2b4238")][variant%4]
	var first_y := 1.15*tall+(.55 if variant==6 else 0.0)
	var step := .72*tall
	var top_y := first_y+step*(tiers-1)+1.35*tall
	_tube(bark,Vector3.ZERO,Vector3(0,top_y,0)+lean*tiers,.27,.05,9,Color("5a4636"),Color("4d3d30"),rng,.07)
	for root_side in 5:
		var angle := root_side*TAU/5.0+rng.randf()*.4
		_tube(bark,Vector3(0,.34,0),Vector3(cos(angle)*.5,.02,sin(angle)*.5),.1,.05,5,Color("5a4636"),Color("4a3b2e"),rng,0.0)
	for tier in tiers:
		var t := float(tier)/float(tiers-1)
		var y := first_y+step*tier
		var radius := (1.62-t*1.22)*slim
		var shade: Color = tint.lerp(tint.lightened(.18),t*.6)
		var base := Vector3(0,y,0)+lean*tier
		_skirt(leaves,base,radius,1.15*tall,.62*tall,10-int(t*3.0),rng,shade.darkened(.35),shade.lightened(.12),.28)
		_skirt(leaves,base+Vector3(0,.34*tall,0),radius*.72,1.0*tall,.5*tall,8-int(t*2.0),rng,shade.darkened(.25),shade.lightened(.2),.22)
		if snowy:
			_skirt(snow,base+Vector3(0,.07,0),radius*.52,.86*tall,.20*tall,10-int(t*3.0),rng,Color("aeb9b7"),Color("e0dfd5"),.34)
	var tip_base := Vector3(0,top_y-1.1*tall,0)+lean*tiers
	_skirt(leaves,tip_base,.34*slim,1.25*tall,.3*tall,5,rng,tint.darkened(.3),tint.lightened(.25),.15)

## Saia de galhos: ápice no centro e anel de pontas longas alternadas com reentrâncias, caindo para fora.
static func _skirt(st: SurfaceTool, base: Vector3, radius: float, rise: float, droop: float, tips: int, rng: RandomNumberGenerator, col_in: Color, col_out: Color, jag: float) -> void:
	tips = maxi(tips,4)
	var offset := rng.randf()*TAU
	var ring: Array[Vector3] = []
	var colors: Array[Color] = []
	for i in tips*2:
		var angle := offset+TAU*float(i)/float(tips*2)
		var tip := i%2==0
		var r := radius*(1.0+(rng.randf()-.5)*jag) if tip else radius*(.5+rng.randf()*.12)
		var drop := droop*(.8+rng.randf()*.35) if tip else droop*.3
		ring.append(base+Vector3(cos(angle)*r,-drop,sin(angle)*r))
		colors.append(col_out.darkened(rng.randf()*.14) if tip else col_in.lerp(col_out,.5))
	var apex := base+Vector3(0,rise,0)
	var count := ring.size()
	for i in count:
		var j := (i+1)%count
		for pair in [[apex,col_in],[ring[j],colors[j]],[ring[i],colors[i]]]:
			st.set_color(pair[1])
			st.add_vertex(pair[0])

# ---------------------------------------------------------------- folhosas

static func _birch(bark: SurfaceTool, leaves: SurfaceTool, snow: SurfaceTool, rng: RandomNumberGenerator, snowy: bool) -> void:
	var height := 4.4
	var segments := 12
	var previous := Vector3.ZERO
	for s in segments:
		var t := float(s+1)/float(segments)
		var next := Vector3(sin(t*3.1)*.22,height*t,cos(t*2.3)*.16)
		var scar := s%3==1
		_tube(bark,previous,next,.2-.13*float(s)/segments,.2-.13*t,8,Color("2f2b27") if scar else Color("d4d3c6"),Color("2f2b27") if scar else Color("c4c4b6"),rng,.02)
		previous = next
	var green := Color("587c3c") if not snowy else Color("6c7a48")
	for limb in 6:
		var angle := limb*2.4+rng.randf()*.5
		var start := Vector3(sin(.5)*.22,2.0+limb*.34,0)
		var end := start+Vector3(cos(angle)*(.8+rng.randf()*.45),.7+rng.randf()*.4,sin(angle)*(.8+rng.randf()*.45))
		_tube(bark,start,end,.07,.035,6,Color("cbcabb"),Color("b8b7a8"),rng,0.0)
		var radii := Vector3(.82+rng.randf()*.25,.62+rng.randf()*.2,.78+rng.randf()*.25)
		NATIVE_ROCK.append_blob(leaves,end+Vector3(0,.2,0),radii,float(limb)*1.9+.3,.3,green.darkened(.28),green.lightened(.22),1)
		if snowy: NATIVE_ROCK.append_blob(snow,end+Vector3(0,.2+radii.y*.62,0),Vector3(radii.x*.52,.14,radii.z*.52),float(limb)+.5,.18,Color("b6bfb9"),Color("e3e2d9"),0)
	var crown := Vector3(.12,height+.15,.1)
	NATIVE_ROCK.append_blob(leaves,crown,Vector3(.95,.8,.9),2.6,.3,green.darkened(.22),green.lightened(.3),1)
	if snowy: NATIVE_ROCK.append_blob(snow,crown+Vector3(0,.6,0),Vector3(.7,.22,.65),1.1,.18,Color("b6bfb9"),Color("e3e2d9"),0)

static func _oak(bark: SurfaceTool, leaves: SurfaceTool, snow: SurfaceTool, rng: RandomNumberGenerator, snowy: bool) -> void:
	_tube(bark,Vector3.ZERO,Vector3(0,2.1,0),.36,.22,9,Color("5e4a37"),Color("4f3f30"),rng,.1)
	for root_side in 5:
		var angle := root_side*TAU/5.0+.3
		_tube(bark,Vector3(0,.4,0),Vector3(cos(angle)*.62,.02,sin(angle)*.62),.12,.06,5,Color("5e4a37"),Color("4a3b2e"),rng,0.0)
	var green := Color("46703a") if not snowy else Color("56693f")
	var forks := 4
	for fork in forks:
		var angle := fork*TAU/forks+.5
		var start := Vector3(0,1.9+fork%2*.25,0)
		var end := Vector3(cos(angle)*1.05,3.2+rng.randf()*.35,sin(angle)*1.05)
		_tube(bark,start,end,.16,.08,7,Color("62503c"),Color("55453a"),rng,.04)
		var radii := Vector3(1.15+rng.randf()*.3,.9+rng.randf()*.25,1.1+rng.randf()*.3)
		NATIVE_ROCK.append_blob(leaves,end+Vector3(0,.35,0),radii,float(fork)*1.7+.9,.28,green.darkened(.3),green.lightened(.2),1)
		if snowy: NATIVE_ROCK.append_blob(snow,end+Vector3(0,.35+radii.y*.62,0),Vector3(radii.x*.52,.14,radii.z*.52),float(fork)+.2,.18,Color("b6bfb9"),Color("e3e2d9"),0)
	NATIVE_ROCK.append_blob(leaves,Vector3(0,4.1,0),Vector3(1.3,.95,1.25),5.3,.28,green.darkened(.25),green.lightened(.28),1)
	if snowy: NATIVE_ROCK.append_blob(snow,Vector3(0,4.8,0),Vector3(.95,.24,.9),2.1,.18,Color("b6bfb9"),Color("e3e2d9"),0)

static func _dead(bark: SurfaceTool, snow: SurfaceTool, rng: RandomNumberGenerator, snowy: bool) -> void:
	var wood := Color("77705f")
	_tube(bark,Vector3.ZERO,Vector3(.1,3.5,-.05),.24,.07,8,wood.darkened(.12),wood,rng,.08)
	for limb in 8:
		var angle := limb*2.4+rng.randf()*.4
		var start := Vector3(.03*limb,1.2+limb*.28,0)
		var end := start+Vector3(cos(angle)*(.7+rng.randf()*.55),.55+rng.randf()*.45,sin(angle)*(.7+rng.randf()*.55))
		_tube(bark,start,end,.07,.025,6,wood,wood.lightened(.1),rng,0.0)
		var twig_end := end+Vector3(cos(angle+.7)*.4,.42,sin(angle+.7)*.4)
		_tube(bark,end,twig_end,.03,.01,5,wood,wood.lightened(.12),rng,0.0)
		if snowy: NATIVE_ROCK.append_blob(snow,start.lerp(end,.55)+Vector3(0,.06,0),Vector3(.3,.07,.12),float(limb),.15,Color("b6bfb9"),Color("e3e2d9"),0)

# ---------------------------------------------------------------- primitivas

## Tronco/galho cônico entre dois pontos; `ridge` varia o raio por lado para dar casca irregular.
static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int, col_a: Color, col_b: Color, rng: RandomNumberGenerator, ridge: float) -> void:
	var axis := b-a
	if axis.length() < .001: return
	axis = axis.normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.dot(Vector3.RIGHT)) < .9 else Vector3.FORWARD).normalized()
	var front := axis.cross(side).normalized()
	var wobble: Array[float] = []
	for i in sides: wobble.append(1.0+(rng.randf()-.5)*2.0*ridge)
	for i in sides:
		var j := (i+1)%sides
		var ang_i := TAU*float(i)/float(sides)
		var ang_j := TAU*float(j)/float(sides)
		var dir_i := side*cos(ang_i)+front*sin(ang_i)
		var dir_j := side*cos(ang_j)+front*sin(ang_j)
		var pa_i := a+dir_i*ra*wobble[i]
		var pa_j := a+dir_j*ra*wobble[j]
		var pb_i := b+dir_i*rb*wobble[i]
		var pb_j := b+dir_j*rb*wobble[j]
		for corner in [[pa_i,col_a],[pb_i,col_b],[pa_j,col_a],[pa_j,col_a],[pb_i,col_b],[pb_j,col_b]]:
			st.set_color(corner[1])
			st.add_vertex(corner[0])

static func _bark_material() -> StandardMaterial3D:
	return _material("bark",Color.WHITE,true,false)

static func _leaf_material() -> StandardMaterial3D:
	return _material("leaf",Color.WHITE,true,true)

static func _snow_material() -> StandardMaterial3D:
	return _material("snow",Color("deded2"),true,true)

static func _material(key: String, color: Color, vertex_colors: bool, double_sided: bool) -> StandardMaterial3D:
	var cached := _material_cache.get(key) as StandardMaterial3D
	if cached != null: return cached
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = vertex_colors
	# Palette hex values are authored in sRGB; keep deep fir after chunk merging.
	material.vertex_color_is_srgb = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	if double_sided: material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[key] = material
	return material
