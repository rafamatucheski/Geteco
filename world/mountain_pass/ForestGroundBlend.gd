extends RefCounted
## Static terrain meshes: world-aligned soil and a narrow, feathered perimeter.
## No physics, SubViewports, timers or per-frame terrain generation.
const GROUND = preload("res://world/mountain_pass/MountainGroundMaterials.gd")
const SHADER = preload("res://world/mountain_pass/ForestGroundBlend.gdshader")
static var _materials: Dictionary = {}
static var _litter: Texture2D

static func material(kind: String, shade := 1.0) -> ShaderMaterial:
	var key := kind+str(shade)
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("surface",GROUND.texture(kind))
		mat.set_shader_parameter("litter",litter_texture())
		mat.set_shader_parameter("litter_amount",.75 if kind=="forest" else .12)
		mat.set_shader_parameter("shade",shade)
		mat.set_shader_parameter("base_tint",Color("3c4934") if kind=="forest" else Color("695339"))
		_materials[key] = mat
	return _materials[key]

static func polygon(item: Polygon2D, kind := "earth", feather := 22.0, shade := 1.0) -> void:
	if item.has_node("SoilTransition"): return
	# Courtyards can be children of elevated building/prop containers. Ground
	# must never inherit that elevation and cover the facade's low-depth state.
	var depth := item.z_index
	var ancestor := item.get_parent()
	var relative := item.z_as_relative
	while relative and ancestor is CanvasItem:
		depth += ancestor.z_index
		relative = ancestor.z_as_relative
		ancestor = ancestor.get_parent()
	item.z_as_relative = false
	item.z_index = mini(depth,0)
	item.material = material(kind,shade)
	item.set_meta("mountain_surface",kind)
	item.add_to_group("audio_ground")
	# Preserve the authored footprint (and any wheel impressions using it).
	# Only the visual fringe extends beyond its perimeter.
	if feather <= 0.0: return
	var ring := MeshInstance2D.new()
	ring.name = "SoilTransition"
	ring.material = item.material
	ring.mesh = fringe_mesh(item.polygon,feather)
	ring.show_behind_parent = true
	item.add_child(ring)

static func path(line: Line2D, feather := 13.0, wheel_tracks := false) -> void:
	if line.points.size()<2 or line.has_node("SoilBed"): return
	var outlines := Geometry2D.offset_polyline(line.points,line.width*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND)
	if outlines.is_empty(): return
	# The existing line remains the road/audio footprint; only its flat paint is replaced.
	line.default_color = Color.TRANSPARENT
	line.set_meta("mountain_surface","earth")
	line.add_to_group("audio_ground")
	for outline in outlines:
		var bed := Polygon2D.new()
		bed.name = "SoilBed"
		bed.polygon = outline
		line.add_child(bed)
		polygon(bed,"earth",feather)
		bed.remove_from_group("audio_ground")
	if wheel_tracks:
		for side in [-1.0,1.0]:
			var rut := Line2D.new()
			rut.width = 5.5
			rut.default_color = Color(.16,.115,.075,.25)
			rut.antialiased = true
			rut.begin_cap_mode = Line2D.LINE_CAP_ROUND
			rut.end_cap_mode = Line2D.LINE_CAP_ROUND
			var fade := Gradient.new()
			fade.set_color(0,Color(rut.default_color,0))
			fade.set_color(1,Color(rut.default_color,0))
			fade.add_point(.12,rut.default_color)
			fade.add_point(.88,rut.default_color)
			rut.gradient = fade
			for i in line.points.size():
				var tangent := line.points[mini(i+1,line.points.size()-1)]-line.points[maxi(i-1,0)]
				rut.add_point(line.points[i]+tangent.normalized().orthogonal()*line.width*.24*side)
			line.add_child(rut)

static func fringe_mesh(outline: PackedVector2Array, width: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var contour := outline.duplicate()
	if Geometry2D.is_polygon_clockwise(contour): contour.reverse()
	var noise := FastNoiseLite.new()
	noise.seed = 13913
	noise.frequency = .035
	for i in contour.size():
		var a := contour[i]
		var b := contour[(i+1)%contour.size()]
		var previous := contour[posmod(i-1,contour.size())]
		var following := contour[(i+2)%contour.size()]
		var normal := (b-a).normalized().orthogonal()
		var first := ((a-previous).normalized().orthogonal()+normal).normalized()
		var last := ((following-b).normalized().orthogonal()+normal).normalized()
		first /= maxf(.65,first.dot(normal))
		last /= maxf(.65,last.dot(normal))
		var steps := maxi(1,int(ceil(a.distance_to(b)/18.0)))
		var start := vertices.size()
		for step in steps+1:
			var t := float(step)/steps
			var inner := a.lerp(b,t)
			var outward := first.lerp(last,t)
			var distance := width*(1.0+noise.get_noise_2dv(inner)*.4)
			var outer := inner+outward*distance
			vertices.append(Vector3(inner.x,inner.y,0))
			vertices.append(Vector3(outer.x,outer.y,0))
			colors.append(Color.WHITE)
			colors.append(Color(1,1,1,0))
			if step<steps:
				var at := start+step*2
				indices.append_array(PackedInt32Array([at,at+1,at+2,at+1,at+3,at+2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func litter_texture() -> Texture2D:
	if _litter!=null: return _litter
	var img := Image.create(256,256,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1392026
	for i in 650:
		var center := Vector2(rng.randf()*256,rng.randf()*256)
		var axis := Vector2.from_angle(rng.randf()*TAU)
		var length := rng.randf_range(1.5,4.2)
		var leaf := i%5==0
		var tint := Color("786044") if leaf else Color("4d4933")
		if i%9==0: tint=Color("8b8871") # scattered small stones
		for y in range(-5,6):
			for x in range(-5,6):
				var p := Vector2(x,y)
				var along := p.dot(axis)/length
				var across := p.dot(axis.orthogonal())/(1.1 if leaf else .35)
				var alpha := clampf(1.2-along*along-across*across,0.0,1.0)*.75
				if alpha<=0: continue
				var px := posmod(int(center.x)+x,256)
				var py := posmod(int(center.y)+y,256)
				img.set_pixel(px,py,Color(tint,alpha))
	img.generate_mipmaps()
	_litter = ImageTexture.create_from_image(img)
	return _litter
