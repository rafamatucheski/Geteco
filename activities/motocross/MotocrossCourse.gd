extends Node3D
## World-space circuit east of Vértice, inside the area marked by the player.
const ENTRY := Vector3(-224,.15,-37)
const BOUNDS := Rect2(-247,-147,155,112)
const HALF_WIDTH := 5.2
var curve := Curve3D.new()
var points := PackedVector3Array()
var length := 0.0
var gates := PackedVector3Array()
var _materials := {}
var wetness := 0.0
var _soil_materials: Array[ShaderMaterial] = []
var _terrain_heights := PackedFloat32Array()
## Shoulder outer-edge heights per side, cached from the mesh build so props can
## be supported on the exact sloped surface without repeating route searches.
var _outer_heights := {}
var stake_tops: Array[PackedVector3Array] = []
var start_gate: Node3D
var trackside: Node3D
static var _soil_texture: NoiseTexture2D

func _init() -> void:
	var knots := PackedVector3Array([Vector3(-218,1,-57),Vector3(-230,4,-87),Vector3(-220,11,-119),Vector3(-190,17,-132),Vector3(-154,12,-128),Vector3(-116,4,-116),Vector3(-104,2,-91),Vector3(-110,1,-60),Vector3(-135,4,-65),Vector3(-152,8,-96),Vector3(-179,5,-92),Vector3(-185,1,-59)])
	curve.bake_interval = 1.5
	for i in knots.size():
		var tangent := (knots[(i+1)%knots.size()]-knots[posmod(i-1,knots.size())])*.16
		curve.add_point(knots[i],-tangent,tangent)
	curve.add_point(knots[0],curve.get_point_in(0),curve.get_point_out(0))
	length = curve.get_baked_length()
	# Sculpted launch faces, tables, landing slopes and a rhythm section.
	var raw := curve.get_baked_points()
	for i in raw.size():
		var p := raw[i]
		var fraction := float(i)/float(raw.size()-1)
		p.y += _jump(fraction,.34,.065,2.8)+_jump(fraction,.50,.055,2.4)
		p.y += _jump(fraction,.68,.065,3.2)
		if fraction > .80 and fraction < .91:
			p.y += sin((fraction-.80)/.11*PI*6)*.75
		points.append(p)
	for i in 32: gates.append(sample(float(i)*length/32.0))
	_build_grid()

func _jump(fraction: float, start: float, span: float, height: float) -> float:
	var t := (fraction-start)/span
	if t < 0 or t > 1: return 0
	if t < .30: return height*pow(t/.30,1.35)
	if t < .46: return height
	return height*(1-smoothstep(.46,1,t))

func sample(distance: float) -> Vector3:
	var index := fposmod(distance,length)/length*(points.size()-1)
	return points[floori(index)].lerp(points[mini(floori(index)+1,points.size()-1)],fposmod(index,1))

func pose(distance: float, lane := 0.0) -> Transform3D:
	var p := sample(distance)
	var direction := sample(distance+1)-p
	direction.y = 0
	var basis := Basis(Vector3.UP,atan2(-direction.x,-direction.z))
	return Transform3D(basis,p+basis.x*lane+Vector3.UP*.15)

const GRID_CELL := 12.0
var _grid: Dictionary = {}

## Segmentos da rota por célula de 8 m: `nearest` era uma varredura de todos os ~380
## segmentos e é chamado ~20 mil vezes ao montar terreno e grama (1,1 s de um quadro só).
func _build_grid() -> void:
	_grid.clear()
	for i in range(points.size()-1):
		var a := points[i]
		var b := points[i+1]
		var lo := Vector2i(floori(minf(a.x,b.x)/GRID_CELL),floori(minf(a.z,b.z)/GRID_CELL))
		var hi := Vector2i(floori(maxf(a.x,b.x)/GRID_CELL),floori(maxf(a.z,b.z)/GRID_CELL))
		for x in range(lo.x,hi.x+1):
			for z in range(lo.y,hi.y+1):
				var key := Vector2i(x,z)
				if not _grid.has(key): _grid[key] = []
				_grid[key].append(i)

func nearest(point: Vector3) -> Dictionary:
	var best := INF
	var distance := 0.0
	var closest := Vector3.ZERO
	var p := Vector2(point.x,point.z)
	var cell := Vector2i(floori(point.x/GRID_CELL),floori(point.z/GRID_CELL))
	var ring := 0
	while ring <= 60:
		for x in range(cell.x-ring,cell.x+ring+1):
			# Só o perímetro do anel: o interior já foi visto nos anéis anteriores.
			var edge := absi(x-cell.x) == ring
			var z_step := 1 if (edge or ring == 0) else 2*ring
			for z in range(cell.y-ring,cell.y+ring+1,z_step):
				var bucket: Variant = _grid.get(Vector2i(x,z))
				if bucket == null: continue
				for i in bucket:
					var a := Vector2(points[i].x,points[i].z)
					var b := Vector2(points[i+1].x,points[i+1].z)
					var t := clampf((p-a).dot(b-a)/maxf(.001,(b-a).length_squared()),0,1)
					var d := p.distance_squared_to(a.lerp(b,t))
					if d < best:
						best = d
						closest = points[i].lerp(points[i+1],t)
						distance = (float(i)+t)/float(points.size()-1)*length
		# Qualquer segmento além do anel `ring` está a pelo menos `ring * GRID_CELL`.
		if best < INF and best <= pow(float(ring)*GRID_CELL,2.0): break
		ring += 1
	return {"distance":distance,"lateral":sqrt(best),"point":closest}

signal built
var complete := false
var _steps: Array[Callable] = []

## A pista inteira custava ~1,4 s montada de uma vez dentro do registro do chunk (o pico
## de 1,3 s ao passar perto do parque). Agora cada etapa roda num quadro; `finish_build`
## termina tudo na hora (testes, capturas). Quem usa a pista sem checar `complete` só vê
## as peças das etapas já feitas.
func _ready() -> void:
	name = "VerticeMotocrossCourse"
	add_to_group("motocross_course")
	_steps = [_step_terrain,_build_ribbon,_build_shoulders,_build_props,_dress_quarry,_step_scenery,_step_paddock,_step_trackside,_step_grass]
	Engine.set_meta("motocross_build_ms",{})
	set_process(true)

func _process(_delta: float) -> void:
	if _steps.is_empty(): return
	_run_step()

var _finishing := false

func finish_build() -> void:
	_finishing = true
	while not _steps.is_empty(): _run_step()
	if is_instance_valid(_scenery_node): _scenery_node.finish_build()
	if is_instance_valid(trackside): trackside.finish_build()
	if is_instance_valid(_paddock_node): _paddock_node.finish_build()
	if is_instance_valid(_grass_node): _grass_node.finish_build()

func _run_step() -> void:
	var step: Callable = _steps.pop_front()
	var began := Time.get_ticks_usec()
	step.call()
	var costs: Dictionary = Engine.get_meta("motocross_build_ms",{})
	costs[str(step.get_method())] = _lap(began)
	Engine.set_meta("motocross_build_ms",costs)
	if _steps.is_empty():
		complete = true
		set_process(false)
		built.emit()

var _terrain_surface: SurfaceTool

func _step_terrain() -> void:
	_build_terrain()
	# Malha e colisão do terreno (normais, commit, trimesh) no quadro seguinte.
	_steps.push_front(_step_terrain_mesh)

func _step_terrain_mesh() -> void:
	_mesh(_terrain_surface,"QuarryHills",true)
	_terrain_surface = null

var _scenery_node: Node

func _step_scenery() -> void:
	var scenery := preload("res://activities/motocross/MotocrossScenery.gd").new()
	scenery.course = self
	add_child(scenery)
	_scenery_node = scenery

var _paddock_node: Node

func _step_paddock() -> void:
	_paddock_node = load("res://activities/motocross/MotocrossPaddock.gd").new()
	add_child(_paddock_node)

func _step_trackside() -> void:
	# A beira de pista lê as árvores e a torre do cenário: espera ele terminar.
	if is_instance_valid(_scenery_node) and not _scenery_node.complete:
		if _finishing: _scenery_node.finish_build()
		else:
			_steps.push_front(_step_trackside)
			return
	start_gate = preload("res://activities/motocross/MotocrossStartGate.gd").new()
	start_gate.course = self
	add_child(start_gate)
	trackside = preload("res://activities/motocross/MotocrossTrackside.gd").new()
	trackside.course = self
	add_child(trackside)

func _step_grass() -> void:
	var grass := preload("res://activities/motocross/MotocrossGroundDetail.gd").new()
	grass.course = self
	add_child(grass)
	_grass_node = grass

var _grass_node: Node

func _lap(since: int) -> float: return snappedf(float(Time.get_ticks_usec()-since)/1000.0,0.1)

## Race-control board text; the controller writes it at a few hertz.
func set_board(title: String, detail: String) -> void:
	if is_instance_valid(trackside): trackside.set_board(title,detail)

func set_wetness(value: float) -> void:
	wetness = clampf(value,0,1)
	for material in _soil_materials: material.set_shader_parameter("wetness",wetness)

func _soil(track_surface: bool) -> ShaderMaterial:
	if _soil_texture == null:
		var noise := FastNoiseLite.new()
		noise.seed = 28926
		noise.frequency = .047
		noise.fractal_octaves = 4
		_soil_texture = NoiseTexture2D.new()
		_soil_texture.width = 256
		_soil_texture.height = 256
		_soil_texture.seamless = true
		_soil_texture.noise = noise
	var material := ShaderMaterial.new()
	material.shader = preload("res://activities/motocross/MotocrossSoil.gdshader")
	material.set_shader_parameter("soil_noise",_soil_texture)
	preload("res://activities/motocross/MotocrossGroundDetail.gd").bind_textures(material)
	material.set_shader_parameter("track_surface",track_surface)
	material.set_shader_parameter("wetness",wetness)
	_soil_materials.append(material)
	return material

func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 1
		_materials[color] = mat
	return _materials[color]

func _mesh(surface: SurfaceTool, title: String, solid: bool) -> MeshInstance3D:
	surface.generate_normals()
	var mesh := surface.commit()
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = mesh
	if title in ["QuarryHills","DirtTrack"]:
		visual.material_override = _soil(title == "DirtTrack")
	add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		add_child(body)
	return visual

func _height(p: Vector2, route: Dictionary = {}) -> float:
	if route.is_empty(): route = nearest(Vector3(p.x,0,p.y))
	var track_height := float(route.point.y)
	var edge := minf(minf(p.x-BOUNDS.position.x,BOUNDS.end.x-p.x),minf(p.y-BOUNDS.position.y,BOUNDS.end.y-p.y))
	var hill := 13.0*exp(-pow((p.x+185)/24,2)-pow((p.y+116)/20,2))
	hill += 4.0*exp(-pow((p.x+134)/12,2)-pow((p.y+91)/18,2))
	var blend := smoothstep(HALF_WIDTH,HALF_WIDTH+11,float(route.lateral))
	return maxf(.002,lerpf(track_height-.25,hill,blend)*smoothstep(0,7,edge))

func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material(Color("695643")))
	var nx := 78
	var nz := 56
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for z in range(nz+1):
		for x in range(nx+1):
			var p := BOUNDS.position+Vector2(float(x)/nx,float(z)/nz)*BOUNDS.size
			var route := nearest(Vector3(p.x,0,p.y))
			var ground_y := _height(p,route)
			_terrain_heights.append(ground_y)
			vertices.append(Vector3(p.x,ground_y,p.y))
			var edge := minf(minf(p.x-BOUNDS.position.x,BOUNDS.end.x-p.x),minf(p.y-BOUNDS.position.y,BOUNDS.end.y-p.y))
			colors.append(Color(maxf(1.0-smoothstep(0,5,edge),smoothstep(HALF_WIDTH+1,HALF_WIDTH+6,float(route.lateral))),0,0))
	for z in nz:
		for x in nx:
			var a := z*(nx+1)+x
			for i in [a,a+1,a+nx+1,a+1,a+nx+2,a+nx+1]:
				st.set_color(colors[i])
				st.add_vertex(vertices[i])
	_terrain_surface = st

func surface_height(point: Vector2) -> float:
	if not BOUNDS.has_point(point) or _terrain_heights.is_empty(): return 0.0
	# Match the actual triangle split, not an analytic hill above/below it.
	var uv := (point-BOUNDS.position)/BOUNDS.size*Vector2(78,56)
	var x := mini(77,floori(uv.x)); var z := mini(55,floori(uv.y))
	var fx := uv.x-x; var fz := uv.y-z
	var a := z*79+x
	if fx+fz<=1.0:
		return _terrain_heights[a]+(_terrain_heights[a+1]-_terrain_heights[a])*fx+(_terrain_heights[a+79]-_terrain_heights[a])*fz
	return _terrain_heights[a+80]+(_terrain_heights[a+1]-_terrain_heights[a+80])*(1-fz)+(_terrain_heights[a+79]-_terrain_heights[a+80])*(1-fx)

func _build_ribbon() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material(Color("b18756")))
	var edges := PackedVector3Array()
	var unique_count := points.size()-1
	for i in points.size():
		var index := i%unique_count
		var tangent := points[(index+1)%unique_count]-points[posmod(index-1,unique_count)]
		edges.append(tangent.cross(Vector3.UP).normalized()*HALF_WIDTH)
	for i in range(points.size()-1):
		var a := points[i]
		var b := points[i+1]
		var side := edges[i]
		var next_side := edges[i+1]
		# Shared cross-sections give corners an outside berm; the center stays rideable.
		for band in 6:
			var left := float(band)/6.0*2-1
			var right := float(band+1)/6.0*2-1
			var corners := [a+side*left+Vector3.UP*_bank(i,left),b+next_side*left+Vector3.UP*_bank(i+1,left),a+side*right+Vector3.UP*_bank(i,right),b+next_side*right+Vector3.UP*_bank(i+1,right)]
			var uvs := [Vector2((left+1)*.5,float(i)*length/unique_count),Vector2((left+1)*.5,float(i+1)*length/unique_count),Vector2((right+1)*.5,float(i)*length/unique_count),Vector2((right+1)*.5,float(i+1)*length/unique_count)]
			for corner in [0,1,2,2,1,3]:
				st.set_uv(uvs[corner])
				st.add_vertex(corners[corner])
	_mesh(st,"DirtTrack",true)

## Height of the rendered/collision clay at a lateral offset from the route,
## following the six-band banked cross-section rather than the flat centerline.
func ribbon_height(distance: float, lateral: float) -> float:
	var n := points.size()-1
	var index := fposmod(distance,length)/length*n
	var i := mini(floori(index),n-1)
	var t := clampf(lateral/HALF_WIDTH,-1.0,1.0)
	var band := clampi(floori((t+1.0)*3.0),0,5)
	var left := float(band)/3.0-1.0
	var u := (t-left)*3.0
	var near := points[i].y+lerpf(_bank(i,left),_bank(i,left+1.0/3.0),u)
	var far := points[i+1].y+lerpf(_bank(i+1,left),_bank(i+1,left+1.0/3.0),u)
	return lerpf(near,far,index-float(i))

## Visible ground at any lateral offset: clay, sculpted shoulder or quarry hill.
func ground_height(distance: float, lateral: float) -> float:
	var reach := absf(lateral)
	if reach <= HALF_WIDTH: return ribbon_height(distance,lateral)
	var n := points.size()-1
	var index := fposmod(distance,length)/length*n
	var i := mini(floori(index),n-1)
	var direction := signf(lateral)
	var heights: Array[float] = []
	for k in [i,i+1]:
		var wrapped: int = k%n
		var side := (points[(wrapped+1)%n]-points[posmod(wrapped-1,n)]).cross(Vector3.UP).normalized()
		var at: Vector3 = points[k]+side*lateral
		if reach >= HALF_WIDTH+3.0:
			heights.append(surface_height(Vector2(at.x,at.z)))
			continue
		var outer_y: float
		if _outer_heights.has(direction): outer_y = _outer_heights[direction][k]
		else:
			var outer: Vector3 = points[k]+side*(HALF_WIDTH+3.0)*direction
			outer_y = _height(Vector2(outer.x,outer.z))
		heights.append(lerpf(points[k].y+_bank(k,direction),outer_y,(reach-HALF_WIDTH)/3.0))
	return lerpf(heights[0],heights[1],index-float(i))

## Signed heading change over ±4.5 m; positive turns left (outside is +x of pose).
func turn_at(index: int) -> float:
	var n := points.size()-1
	index = posmod(index,n)
	var incoming := points[index]-points[posmod(index-3,n)]
	var outgoing := points[(index+3)%n]-points[index]
	incoming.y = 0
	outgoing.y = 0
	return incoming.signed_angle_to(outgoing,Vector3.UP)

func _bank(index: int, lateral: float) -> float:
	var curvature := turn_at(index)
	var outer := maxf(0,signf(curvature)*lateral)
	return pow(outer,2.2)*clampf(absf(curvature)*4,0,1.6)

func _build_shoulders() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_soil(false))
	surface.set_color(Color(0,0,0))
	var sections: Array = []
	var n := points.size()-1
	var outer_left := PackedFloat32Array()
	var outer_right := PackedFloat32Array()
	for i in points.size():
		var index := i%n
		var side := (points[(index+1)%n]-points[posmod(index-1,n)]).cross(Vector3.UP).normalized()
		var section: Array[Vector3] = []
		for direction in [-1.0,1.0]:
			var inner: Vector3 = points[i]+side*HALF_WIDTH*direction+Vector3.UP*_bank(i,direction)
			var outer: Vector3 = points[i]+side*(HALF_WIDTH+3.0)*direction
			outer.y = _height(Vector2(outer.x,outer.z))
			if direction < 0: outer_left.append(outer.y)
			else: outer_right.append(outer.y)
			section.append(inner)
			section.append(outer)
		sections.append(section)
	_outer_heights = {-1.0:outer_left,1.0:outer_right}
	for i in range(n):
		for side in [0,2]:
			var a: Vector3 = sections[i][side]
			var b: Vector3 = sections[i+1][side]
			var c: Vector3 = sections[i][side+1]
			var d: Vector3 = sections[i+1][side+1]
			var vertices := [a,c,b,b,c,d] if side==0 else [a,b,c,b,d,c]
			# The inside offset can reverse locally in the tight hairpin. Keep
			# both physical and visible faces pointing upward, rather than hiding
			# a real support surface behind its back face. Skip zero-area slivers.
			for triangle in [0,3]:
				var p: Vector3 = vertices[triangle]
				var q: Vector3 = vertices[triangle+1]
				var r: Vector3 = vertices[triangle+2]
				var face := (r-p).cross(q-p)
				if face.length_squared() < 0.00000001: continue
				if face.y < 0:
					var swap := q
					q = r
					r = swap
				for vertex in [p,q,r]: surface.add_vertex(vertex)
	_mesh(surface,"SculptedBanks",true)

func _box(title: String, p: Vector3, size: Vector3, color: Color, solid := false) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = mesh
	visual.material_override = _material(color)
	visual.position = p
	add_child(visual)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		visual.add_child(body)
	return visual

func _stake_point(index: int, direction: float) -> Vector3:
	var n := points.size()-1
	var wrapped := index%n
	var side := (points[(wrapped+1)%n]-points[posmod(wrapped-1,n)]).cross(Vector3.UP).normalized()
	var at: Vector3 = points[wrapped]+side*(HALF_WIDTH+.45)*direction
	var distance := float(wrapped)/float(n)*length
	# Lowest point across the (world-aligned, so up to 11 cm diagonal) footprint
	# on the sloped shoulder: no stake hangs over a falling hillside or perches
	# on the berm crest. The post itself is sunk another 5 cm below this.
	at.y = INF
	for along in [-.12,.12]:
		for reach in [.33,.57]: at.y = minf(at.y,ground_height(distance+along,(HALF_WIDTH+reach)*direction))
	return at

func _build_props() -> void:
	# Stakes carry the course tape. Straight tape between them must not cut the
	# riding width on corners, so spacing tightens where the edge bends.
	var n := points.size()-1
	var stakes := MultiMesh.new()
	stakes.transform_format = MultiMesh.TRANSFORM_3D
	var stake_mesh := BoxMesh.new()
	stake_mesh.size = Vector3(.16,.9,.16)
	stakes.mesh = stake_mesh
	var stake_transforms: Array[Transform3D] = []
	var stake_body := StaticBody3D.new()
	stake_body.name = "CourseStakes"
	stake_body.collision_layer = 1
	stake_body.collision_mask = 0
	var stake_shape := BoxShape3D.new()
	stake_shape.size = stake_mesh.size
	for direction in [-1.0,1.0]:
		var edges := PackedVector3Array()
		for index in n+1: edges.append(_stake_point(index,direction))
		var row := PackedVector3Array([edges[0]])
		var last := 0
		for index in range(1,n):
			var arc := float(index+1-last)*length/float(n)
			var bends := false
			for between in range(last+1,index+1):
				var chord := Geometry3D.get_closest_point_to_segment(edges[between],edges[last],edges[index+1])
				if Vector2(edges[between].x-chord.x,edges[between].z-chord.z).length() > .22: bends = true; break
			if arc > 10.5 or bends or index+1 >= n:
				row.append(edges[index])
				last = index
		stake_tops.append(row)
		for base in row:
			stake_transforms.append(Transform3D(Basis.IDENTITY,base+Vector3.UP*.4))
			var shape := CollisionShape3D.new()
			shape.shape = stake_shape
			shape.position = base+Vector3.UP*.4
			stake_body.add_child(shape)
	stakes.instance_count = stake_transforms.size()
	for i in stake_transforms.size(): stakes.set_instance_transform(i,stake_transforms[i])
	var stake_visual := MultiMeshInstance3D.new()
	stake_visual.name = "CourseStake"
	stake_visual.multimesh = stakes
	stake_visual.material_override = _material(Color("e7e1c6"))
	add_child(stake_visual)
	add_child(stake_body)
	var start_pose := pose(0)
	start_pose.origin = sample(0)
	var gate := Node3D.new()
	gate.name = "AlignedStart"
	gate.transform = start_pose
	add_child(gate)
	for x in 10:
		for z in 2:
			var stripe := _box("FinishChecks",Vector3(float(x)-4.5,.04,float(z)*.5),Vector3(.96,.025,.49),Color("e7e1cf") if (x+z)%2 == 0 else Color("292e30"))
			stripe.reparent(gate,false)
	for side_value in [-1,1]:
		var post := _box("StartPost",Vector3(side_value*6,2.4,0),Vector3(.35,4.8,.35),Color("343e42"),true)
		post.reparent(gate,false)
	var beam := _box("StartBeam",Vector3(0,4.8,0),Vector3(12.5,.75,.45),Color("b75b28"))
	beam.reparent(gate,false)
	var sign := Label3D.new()
	sign.text = "VÉRTICE"
	sign.font_size = 64
	sign.pixel_size = .012
	sign.position = Vector3(0,4.8,.26)
	gate.add_child(sign)
	# GroundDetail builds one continuous, gently graded yard and access path.

func _dress_quarry() -> void:
	# Low-poly rocks outside the riding surface, with matching solid bodies.
	var rocks := MultiMesh.new()
	rocks.transform_format = MultiMesh.TRANSFORM_3D
	var stone := SphereMesh.new()
	stone.radial_segments = 7
	stone.rings = 3
	stone.radius = 1
	stone.height = 2
	rocks.mesh = stone
	var transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 280926
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	for i in 80:
		var point := BOUNDS.position+Vector2(rng.randf(),rng.randf())*BOUNDS.size
		if float(nearest(Vector3(point.x,0,point.y)).lateral) < HALF_WIDTH+4: continue
		if point.distance_to(Vector2(ENTRY.x,ENTRY.z)) < 10: continue
		if point.distance_to(preload("res://activities/motocross/MotocrossTrackside.gd").BLEACHER_CENTER) < 7.5:
			# Same two draws as a placed rock: every other rock keeps its spot.
			rng.randf_range(.65,2.1); rng.randf()
			continue
		var radius := rng.randf_range(.65,2.1)
		var p := Vector3(point.x,_height(point)+radius*.3,point.y)
		transforms.append(Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(radius,radius*.65,radius*.8)),p))
		var collision := CollisionShape3D.new()
		var shape := SphereShape3D.new()
		shape.radius = radius*.85
		collision.shape = shape
		collision.position = p
		body.add_child(collision)
	rocks.instance_count = transforms.size()
	for i in transforms.size(): rocks.set_instance_transform(i,transforms[i])
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = rocks
	visual.material_override = _material(Color("746e61"))
	add_child(visual)
	add_child(body)
