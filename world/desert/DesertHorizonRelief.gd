extends RefCounted
## Static sandstone escarpments. All horizon vertices stay outside the playable basin.
## build() returns relief only: DesertHorizon retains its existing DistantBasin quad.
const L := preload("res://world/desert/DesertLayout.gd")
const BASE := Color("9f7d56")
const ROCK := Color("b99771")
const PALE := Color("cbb18a")
const CREVICE := Color("755940")
const DISTANT := Color("888274")
const MARGIN := 24.0
const STEP := 18.0
const CROSS_SECTION := [
	Vector2(0,0),Vector2(.055,.02),Vector2(.14,.085),Vector2(.25,.20),
	Vector2(.30,.32),Vector2(.325,.49),Vector2(.35,.68),Vector2(.395,.84),
	Vector2(.46,.93),Vector2(.52,.98),Vector2(.57,1),Vector2(.66,.87),
	Vector2(.77,.61),Vector2(.89,.27),Vector2(1,0),
]
# The north escarpment is the drag camera's skyline. A retreating talus,
# steep fractured wall and broad cap read as rock instead of rounded dunes.
const DRAG_SECTION := [
	Vector2(0,0),Vector2(.07,.025),Vector2(.20,.13),Vector2(.29,.27),
	Vector2(.34,.42),Vector2(.36,.63),Vector2(.39,.85),Vector2(.42,.96),
	Vector2(.48,.99),Vector2(.56,1),Vector2(.65,.98),Vector2(.70,.89),
	Vector2(.79,.58),Vector2(.90,.23),Vector2(1,0),
]
static var _stone: ShaderMaterial

static func material() -> ShaderMaterial:
	if _stone!=null: return _stone
	_stone=ShaderMaterial.new()
	_stone.shader=preload("res://world/desert/sandstone_horizon.gdshader")
	_stone.set_shader_parameter("stone_noise",preload("res://runtime/atmosphere/drag_cloud_noise.tres"))
	return _stone

static func build() -> Node3D:
	var root := Node3D.new()
	root.name="DesertErodedHorizon"
	var near := _buffer()
	var far := _buffer()
	# Authored high points and asymmetric saddles prevent a regular row of identical mesas.
	# Endpoint heights taper into buried feet; no vertical rectangular cut at the ends.
	var north := {"side":"north","from":-1720.0,"to":680.0,"width":360.0,"seed":73,"profile":[Vector2(0,.05),Vector2(.055,.30),Vector2(.10,.86),Vector2(.20,.89),Vector2(.24,.38),Vector2(.32,.31),Vector2(.36,.73),Vector2(.46,.77),Vector2(.50,.36),Vector2(.58,.40),Vector2(.62,.94),Vector2(.75,.91),Vector2(.80,.51),Vector2(.88,.56),Vector2(.94,.22),Vector2(1,.06)]}
	var west := {"side":"west","from":-2200.0,"to":-305.0,"width":310.0,"seed":29,"profile":[Vector2(0,.06),Vector2(.10,.44),Vector2(.21,.92),Vector2(.28,.72),Vector2(.42,.33),Vector2(.53,.67),Vector2(.65,.91),Vector2(.78,.36),Vector2(.90,.68),Vector2(1,.04)]}
	var east := {"side":"east","from":-2180.0,"to":-565.0,"width":225.0,"seed":51,"profile":[Vector2(0,.04),Vector2(.14,.68),Vector2(.26,.43),Vector2(.39,.89),Vector2(.46,.98),Vector2(.60,.39),Vector2(.74,.78),Vector2(.86,.45),Vector2(1,.03)]}
	var south := {"side":"south","from":-1690.0,"to":90.0,"width":210.0,"seed":97,"profile":[Vector2(0,.03),Vector2(.10,.66),Vector2(.21,.38),Vector2(.35,.89),Vector2(.41,.76),Vector2(.55,.29),Vector2(.69,.68),Vector2(.82,.42),Vector2(.92,.30),Vector2(1,.02)]}
	for range_data in [north,west,east,south]: _ridge(near,range_data,false)
	# A second, less saturated crest rises beyond two ranges; eastern mountain/bridge stay open.
	_ridge(far,north,true)
	_ridge(far,west,true)
	root.add_child(_mesh("DistantErodedRanges",far,false))
	root.add_child(_mesh("SandstoneEscarpments",near,false))
	root.set_meta("horizon_margin_metres",MARGIN)
	root.set_meta("triangle_count",int(near.vertices.size()/3)+int(far.vertices.size()/3))
	return root

static func _buffer() -> Dictionary:
	return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}

static func _ridge(data: Dictionary, definition: Dictionary, distant: bool) -> void:
	var section_points: Array = DRAG_SECTION if definition.side=="north" else CROSS_SECTION
	var steps := ceili((float(definition.to)-float(definition.from))/STEP)
	var rows: Array=[]
	var colors: Array=[]
	for i in steps+1:
		var t := float(i)/float(steps)
		var along := lerpf(float(definition.from),float(definition.to),t)
		var phase := float(definition.seed)*.071
		var crest := _profile(definition.profile,t)
		if distant: crest=_profile(definition.profile,clampf(t*.91+.067,0,1))*.82+.13*sin(t*11+phase)+.12
		var end_blend := smoothstep(0,.055,t)*smoothstep(0,.065,1-t)
		var height := (29.0+crest*(138.0 if distant else 102.0))*end_blend
		# Unequal drainage cuts break the skyline and recess the wall all the way into the talus.
		var gullies := 0.0
		for g in 7:
			var center := .075+float(g)*.137+sin(phase+float(g)*2.7)*.027
			var width := .009+float(g%3)*.004
			gullies=maxf(gullies,exp(-pow((t-center)/width,2)))
		var broken_crest := sin(along*.039+phase)*4.5+sin(along*.017+phase*.8)*7.5
		# Fracture blocks have unequal tops with straight geological breaks, not smooth dune humps.
		var fracture := _fracture(along,float(definition.seed))
		broken_crest+=fracture*16.0
		height=maxf(0.0,height*(1.0-gullies*.27)+broken_crest*end_blend)
		var front := MARGIN+17.0+11.0*sin(t*15+phase)+8.0*sin(t*33+phase*.4)+gullies*29.0
		# near minimum front=22 before this clamp; reserve every triangle, not merely its centre.
		front=maxf(MARGIN,front)
		if distant: front+=175.0
		var depth := float(definition.width)*(1.0+.13*sin(t*8+phase))
		if distant: depth*=.92
		var ring := PackedVector3Array()
		var tones := PackedColorArray()
		var previous_depth := MARGIN-.5
		for j in section_points.size():
			var section: Vector2=section_points[j]
			var erosion := gullies*sin(section.y*PI)*height*.23
			var shoulder := sin(along*.021+phase+section.x*4.1)*height*.06*sin(section.y*PI)
			var y := maxf(-.7,section.y*height-erosion+shoulder-.7)
			# Large vertical buttresses replace parallel shelves. Channels retreat, ribs project.
			var d := front+section.x*depth
			var wall_weight := sin(section.y*PI)*smoothstep(.07,.27,section.y)
			d+=(sin(along*.028+phase)*19.0+sin(along*.061+phase*.7)*6.0+gullies*39.0)*wall_weight
			d+=fracture*21.0*wall_weight
			d=maxf(MARGIN,d)
			if definition.side=="north":
				# Keep a single visible rock face. Deep drainage displacement used
				# to fold adjacent wall rows backwards, exposing triangular holes
				# from the low race camera when back-face culling removed the fold.
				d=maxf(previous_depth+.5,d)
				previous_depth=d
			var point := _position(str(definition.side),along,d,y)
			ring.append(point)
			# Mineral variation follows eroded faces; no full-width pale bands around each hill.
			var mineral := .40+.11*sin(along*.037+phase+section.y*3.0)+.055*sin(along*.079+section.y*11.0)
			var tone := BASE.lerp(ROCK,mineral).lerp(CREVICE,(gullies*.17+maxf(-fracture,0)*.095)*wall_weight)
			var broken_seam := smoothstep(.25,.80,sin(along*.024+phase+section.y*6.0))
			if j==5 or j==8: tone=tone.lerp(PALE,broken_seam*.075)
			if distant: tone=tone.lerp(DISTANT,.66)
			tones.append(tone)
		rows.append(ring)
		colors.append(tones)
	var normals: Array=[]
	for i in rows.size():
		var row_normals := PackedVector3Array()
		for j in CROSS_SECTION.size():
			var along_tangent: Vector3=rows[mini(i+1,steps)][j]-rows[maxi(i-1,0)][j]
			var across_tangent: Vector3=rows[i][mini(j+1,CROSS_SECTION.size()-1)]-rows[i][maxi(j-1,0)]
			var normal := along_tangent.cross(across_tangent).normalized()
			if normal.y<0: normal=-normal
			row_normals.append(normal if normal.length_squared()>.1 else Vector3.UP)
		normals.append(row_normals)
	for i in steps:
		for j in CROSS_SECTION.size()-1:
			var a: Vector3=rows[i][j]
			var b: Vector3=rows[i+1][j]
			var c: Vector3=rows[i+1][j+1]
			var d: Vector3=rows[i][j+1]
			# Alternating diagonals avoid long repeated triangular highlights on the talus.
			if (i+j)%2==0:
				_triangle(data,a,b,c,colors[i][j],colors[i+1][j],colors[i+1][j+1],Vector3.UP,normals[i][j],normals[i+1][j],normals[i+1][j+1])
				_triangle(data,a,c,d,colors[i][j],colors[i+1][j+1],colors[i][j+1],Vector3.UP,normals[i][j],normals[i+1][j+1],normals[i][j+1])
			else:
				_triangle(data,a,b,d,colors[i][j],colors[i+1][j],colors[i][j+1],Vector3.UP,normals[i][j],normals[i+1][j],normals[i][j+1])
				_triangle(data,b,c,d,colors[i+1][j],colors[i+1][j+1],colors[i][j+1],Vector3.UP,normals[i+1][j],normals[i+1][j+1],normals[i][j+1])

static func _profile(points: Array, t: float) -> float:
	for i in range(1,points.size()):
		var a: Vector2=points[i-1]
		var b: Vector2=points[i]
		if t<=b.x:
			var blend := smoothstep(a.x,b.x,t)
			return lerpf(a.y,b.y,blend)
	return float(points.back().y)

static func _fracture(along: float, seed_value: float) -> float:
	# Continuous piecewise-linear ledges: deterministic unequal blocks, without white-noise spikes.
	var coordinate := along/63.0
	var cell := floorf(coordinate)
	var a := sin(cell*1.71+seed_value*.113)*.64+sin(cell*.73+seed_value)*.36
	var b := sin((cell+1.0)*1.71+seed_value*.113)*.64+sin((cell+1.0)*.73+seed_value)*.36
	return lerpf(a,b,coordinate-cell)

static func _position(side: String, along: float, depth: float, height: float) -> Vector3:
	match side:
		"north": return Vector3(along,height,L.BOUNDS.position.y-depth)
		"west": return Vector3(L.BOUNDS.position.x-depth,height,along)
		"east": return Vector3(L.BOUNDS.end.x+depth,height,along)
		_: return Vector3(along,height,L.BOUNDS.end.y+depth)

static func _stratum_color(row: int) -> Color:
	match row:
		0,1: return BASE
		2: return BASE.lerp(ROCK,.35)
		3,6,9: return BASE.lerp(ROCK,.48)
		4,7: return BASE.lerp(CREVICE,.075)
		5,8,10: return BASE.lerp(ROCK,.60)
		11: return BASE.lerp(ROCK,.5)
		_: return BASE.lerp(ROCK,.2)

static func _triangle(data: Dictionary,a: Vector3,b: Vector3,c: Vector3,ca: Color,cb: Color,cc: Color,outward: Vector3,na: Vector3=Vector3.ZERO,nb: Vector3=Vector3.ZERO,nc: Vector3=Vector3.ZERO) -> void:
	var normal := (c-a).cross(b-a)
	if normal.length_squared()<.000001: return
	# Godot front faces are clockwise. Keep normals consistent with the emitted winding.
	if normal.dot(outward)<0:
		var swap := b
		b=c
		c=swap
		var color_swap := cb
		cb=cc
		cc=color_swap
		var normal_swap := nb
		nb=nc
		nc=normal_swap
		normal=-normal
	normal=normal.normalized()
	data.vertices.append_array(PackedVector3Array([a,b,c]))
	# Retain readable rock faces while avoiding the fully flat triangulated-fabric appearance.
	data.normals.append_array(PackedVector3Array([na.lerp(normal,.32).normalized(),nb.lerp(normal,.32).normalized(),nc.lerp(normal,.32).normalized()]) if na.length_squared()>.1 else PackedVector3Array([normal,normal,normal]))
	data.colors.append_array(PackedColorArray([ca,cb,cc]))

static func _mesh(id: String,data: Dictionary,shadows: bool) -> MeshInstance3D:
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.vertices
	arrays[Mesh.ARRAY_NORMAL]=data.normals
	arrays[Mesh.ARRAY_COLOR]=data.colors
	var geometry := ArrayMesh.new()
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name=id
	node.mesh=geometry
	node.material_override=material()
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

static func create_outcrop(parent: Node3D,at: Vector3,radius: float,height: float,seed_value: int,solid: bool,visual := true) -> Node3D:
	# Three connected convex frusta share every seam; collision is made from the same vertices.
	# Unlike a cylinder collider, it follows the irregular footprint and each retreating rock face.
	var root := Node3D.new()
	root.name="ErodedSandstoneOutcrop"
	root.position=at
	parent.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed=seed_value
	var points := PackedVector2Array()
	for i in 13:
		var angle := float(i)*TAU/13.0+rng.randf_range(-.10,.10)
		var distance := radius*rng.randf_range(.64,.91)
		points.append(Vector2(cos(angle),sin(angle)*.82)*distance)
	var outline := Geometry2D.convex_hull(points)
	outline.resize(outline.size()-1)
	var skew := Vector2(rng.randf_range(-.07,.07),rng.randf_range(-.07,.07))*radius
	var scales := [1.0,.86,.72,.585,.45,.225,0.0]
	var levels := [0.0,.12,.24,.55,.86,.95,1.04]
	var centers := [Vector2.ZERO,skew*.5,skew,skew+Vector2(-.045,.025)*radius,skew+Vector2(-.09,.05)*radius,skew+Vector2(.025,.085)*radius,skew+Vector2(.14,.12)*radius]
	var rings: Array[PackedVector3Array]=[]
	var data := _buffer()
	for row in levels.size():
		var ring := PackedVector3Array()
		for point in outline:
			var xz: Vector2=point*float(scales[row])+centers[row]
			# Common tilted bedding plane gives each convex volume a sloped, uneven skyline.
			var y := float(levels[row])*height+(xz.x*.035+xz.y*.027)*float(levels[row])
			ring.append(Vector3(xz.x,y,xz.y))
		rings.append(ring)
	# Mid-band rings lie exactly on each volume's ruled face, so colour bands add no collider bulge.
	for row in [1,3,5]:
		for i in outline.size(): rings[row][i]=rings[row-1][i].lerp(rings[row+1][i],.5)
	for row in rings.size()-1:
		for i in outline.size():
			var next := (i+1)%outline.size()
			var a: Vector3=rings[row][i]
			var b: Vector3=rings[row][next]
			var c: Vector3=rings[row+1][next]
			var d: Vector3=rings[row+1][i]
			var outward := Vector3((a.x+b.x)*.5,0,(a.z+b.z)*.5).normalized()+Vector3.UP*.15
			var low := _stratum_color(row+1)
			var high := _stratum_color(row+2)
			_triangle(data,a,b,c,low,low,high,outward)
			_triangle(data,a,c,d,low,high,high,outward)
	if visual: root.add_child(_mesh("IrregularSandstone",data,true))
	if solid:
		var body := StaticBody3D.new()
		body.name="SandstoneVolumes"
		body.collision_layer=1
		body.collision_mask=0
		body.set_meta("vehicle_surface","hard")
		root.add_child(body)
		for part in 3:
			var shape := ConvexPolygonShape3D.new()
			var hull := PackedVector3Array()
			hull.append_array(rings[part*2])
			hull.append_array(rings[part*2+1])
			hull.append_array(rings[part*2+2])
			shape.points=hull
			var collider := CollisionShape3D.new()
			collider.shape=shape
			body.add_child(collider)
	root.set_meta("footprint_radius",radius)
	root.set_meta("rock_height",height*1.04)
	return root
