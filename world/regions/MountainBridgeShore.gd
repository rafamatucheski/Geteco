extends RefCounted
## Permanent banks around the deliberately empty bridge cells. Streamed chunk
## edges are not shorelines: only an explicit VOID neighbour admits this mesh.
const CELL := 64.0
const STEP := 4.0
const BOTTOM := -5.5
const CORNER_BLEND := 16.0
const BRIDGE_CENTER_Z := -285.0
const RINGS := [0.0,0.16,0.48,1.0]
const COLLISION_FACES := preload("res://world/chunk_bake/CollisionFaces.gd")
static var _rock: StandardMaterial3D

static func frontiers(key: Vector2i, void_cells: Array, owns: Callable) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if key in void_cells or not owns.call(key): return result
	for outward in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
		if not key+outward in void_cells: continue
		var tangent := Vector2i.RIGHT if outward.y != 0 else Vector2i.DOWN
		var start := Vector2(key)*CELL
		if outward.x > 0: start.x += CELL
		if outward.y > 0: start.y += CELL
		var edge := {"start":start,"outward":Vector2(outward),"tangent":Vector2(tangent),"length":CELL}
		for endpoint in [-1,1]:
			var peer: Vector2i = key+tangent*endpoint
			var straight: bool = bool(owns.call(peer)) and peer+outward in void_cells
			# A concave corner has land on the diagonal and VOID beside both banks.
			var corner: bool = not straight and bool(owns.call(peer)) and bool(owns.call(peer+outward))
			var suffix := "start" if endpoint < 0 else "end"
			edge["corner_"+suffix] = corner
			edge["cap_"+suffix] = not straight and not corner
		result.append(edge)
	return result

static func _reach(point: Vector2, outward: Vector2) -> float:
	var reach := 7.5+.55*sin(point.x*.065+point.y*.027)+.35*sin(point.x*.171-point.y*.091)
	# At the east abutment the closure stays below its existing deck; it never
	# adds a sloping embankment across the reserved driving/walking corridor.
	if outward.x != 0.0: reach *= smoothstep(9.0,14.0,absf(point.y-BRIDGE_CENTER_Z))
	return reach

static func point_at(terrain: RefCounted, edge: Dictionary, along: float, fraction: float) -> Vector3:
	var origin: Vector2 = edge.start+edge.tangent*along
	var distance := _reach(origin,edge.outward)*fraction
	var flat: Vector2 = origin+edge.outward*distance
	if edge.corner_start: flat += edge.tangent*distance*(1.0-smoothstep(0.0,CORNER_BLEND,along))
	if edge.corner_end: flat -= edge.tangent*distance*(1.0-smoothstep(0.0,CORNER_BLEND,float(edge.length)-along))
	var descent := pow(fraction,1.16)+sin(origin.x*.16+origin.y*.11)*.045*fraction*(1.0-fraction)
	return Vector3(flat.x,lerpf(float(terrain.height_at(origin)),BOTTOM,descent),flat.y)

static func _normal(terrain: RefCounted, edge: Dictionary, along: float, fraction: float) -> Vector3:
	var point: Vector2 = edge.start+edge.tangent*along
	if fraction == 0.0:
		return Vector3(terrain.height_at(point-Vector2.RIGHT)-terrain.height_at(point+Vector2.RIGHT),2.0,terrain.height_at(point-Vector2.DOWN)-terrain.height_at(point+Vector2.DOWN)).normalized()
	var normal: Vector3
	var corner_start: bool = edge.corner_start and is_zero_approx(along)
	var corner_end: bool = edge.corner_end and is_equal_approx(along,float(edge.length))
	if corner_start or corner_end:
		# Both owners use the same corner normal, as well as the same vertex.
		var outward: Vector2 = (edge.outward+edge.tangent*(1.0 if corner_start else -1.0)).normalized()
		var drop: float = terrain.height_at(point)-BOTTOM
		return Vector3(outward.x*drop,_reach(point,edge.outward)*sqrt(2.0),outward.y*drop).normalized()
	var along_delta := point_at(terrain,edge,along+.25,fraction)-point_at(terrain,edge,along-.25,fraction)
	var across_delta := point_at(terrain,edge,along,minf(1.0,fraction+.01))-point_at(terrain,edge,along,maxf(0.0,fraction-.01))
	normal = along_delta.cross(across_delta).normalized()
	var facing := Vector3(edge.outward.x,1.0,edge.outward.y)
	return -normal if normal.dot(facing)<0.0 else normal

static func _material() -> StandardMaterial3D:
	if _rock == null:
		_rock = preload("res://world/urban_detail/HarborGrassTufts.gd").ground_material("gravel").duplicate() as StandardMaterial3D
		# Cascalho do porto lia como feltro cinza nos taludes da ponte: mapa de granito com
		# relevo, em tile de 3 m, mantendo o tom (o vertex color continua tingindo).
		var surfaces := preload("res://assets/urban_detail/UrbanSurfaces.gd")
		surfaces.detail(_rock, "granite", 3.0, 1.4)
		var tint := Color("b3bfc0")
		var gain: float = _rock.albedo_color.r
		_rock.vertex_color_use_as_albedo = true
		_rock.albedo_color = Color(minf(tint.r * gain, 1.0), minf(tint.g * gain, 1.0), minf(tint.b * gain, 1.0))
		_rock.roughness = 1.0
		_rock.metallic_specular = .10
	return _rock

static func _color(fraction: float) -> Color:
	return Color("819475").lerp(Color("92998e"),smoothstep(0.0,.32,fraction)).lerp(Color("666c64"),smoothstep(.40,1.0,fraction))

static func _triangle(surface: SurfaceTool, points: Array[Vector3], normals: Array[Vector3], colors: Array[Color], facing: Vector3) -> void:
	var cross := (points[1]-points[0]).cross(points[2]-points[0])
	if cross.length_squared()<0.00000001: return
	var order := [0,1,2] if cross.dot(facing)<0.0 else [0,2,1]
	for index in order:
		surface.set_normal(normals[index])
		surface.set_color(colors[index])
		surface.set_uv(Vector2(points[index].x,points[index].z))
		surface.add_vertex(points[index])

static func _flat_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3) -> void:
	var normal := facing.normalized()
	var color := _color(1.0)
	_triangle(surface,[a,b,c],[normal,normal,normal],[color,color,color],facing)
	_triangle(surface,[a,c,d],[normal,normal,normal],[color,color,color],facing)

static func build_chunk(parent: Node3D, rect: Rect2, terrain: RefCounted, edges: Array[Dictionary]) -> MeshInstance3D:
	if edges.is_empty(): return null
	if rect.size != Vector2.ONE*CELL:
		push_error("MountainBridgeShore requires the aligned terrain chunk")
		return null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in edges:
		var outward := Vector3(edge.outward.x,0.0,edge.outward.y)
		for step in int(CELL/STEP):
			var along := float(step)*STEP
			for ring in RINGS.size()-1:
				var u: float = RINGS[ring]
				var v: float = RINGS[ring+1]
				var a := point_at(terrain,edge,along,u)
				var b := point_at(terrain,edge,along+STEP,u)
				var c := point_at(terrain,edge,along+STEP,v)
				var d := point_at(terrain,edge,along,v)
				var na := _normal(terrain,edge,along,u)
				var nb := _normal(terrain,edge,along+STEP,u)
				var nc := _normal(terrain,edge,along+STEP,v)
				var nd := _normal(terrain,edge,along,v)
				_triangle(surface,[a,b,c],[na,nb,nc],[_color(u),_color(u),_color(v)],outward+Vector3.UP)
				_triangle(surface,[a,c,d],[na,nc,nd],[_color(u),_color(v),_color(v)],outward+Vector3.UP)
			var top_a := point_at(terrain,edge,along,0.0)
			var top_b := point_at(terrain,edge,along+STEP,0.0)
			var back_a := Vector3(top_a.x,BOTTOM,top_a.z)
			var back_b := Vector3(top_b.x,BOTTOM,top_b.z)
			var toe_a := point_at(terrain,edge,along,1.0)
			var toe_b := point_at(terrain,edge,along+STEP,1.0)
			# The protected abutment has zero outward reach. Its single vertical
			# face already closes the bank; a reverse face would duplicate collision.
			if toe_a.distance_squared_to(back_a)>.000001 or toe_b.distance_squared_to(back_b)>.000001:
				_flat_quad(surface,top_a,top_b,back_b,back_a,-outward)
				_flat_quad(surface,back_a,back_b,toe_b,toe_a,Vector3.DOWN)
		for endpoint in [0.0,CELL]:
			if not edge.cap_start and endpoint == 0.0 or not edge.cap_end and endpoint == CELL: continue
			var rim: Array[Vector3] = []
			for fraction in RINGS: rim.append(point_at(terrain,edge,endpoint,float(fraction)))
			var base := Vector3(rim[0].x,BOTTOM,rim[0].z)
			var facing := Vector3(edge.tangent.x,0,edge.tangent.y)*(-1.0 if endpoint == 0.0 else 1.0)
			for index in rim.size()-1:
				_triangle(surface,[base,rim[index],rim[index+1]],[facing,facing,facing],[_color(1.0),_color(1.0),_color(1.0)],facing)
	# Malha e colisão das mesmas arrays da CPU: create_trimesh_shape lia a malha de volta da GPU no streaming.
	var built: Array = COLLISION_FACES.commit_with_shape(surface)
	var result := MeshInstance3D.new()
	result.name = "MountainBridgeShore"
	result.mesh = built[0]
	result.material_override = _material()
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	var body := StaticBody3D.new()
	body.name = "MountainBridgeShoreSolid"
	body.set_meta("mountain_terrain",true)
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = built[1]
	body.add_child(collision)
	result.add_child(body)
	return result
