extends RefCounted
## Um único perfil construtivo para os dois braços. Os lotes de desenho são curtos
## para respeitar as luzes por objeto do Mobile; as juntas não mudam o acabamento.
const MeshKit := preload("res://world/regions/bridge_look/BridgeLookMesh.gd")
const Paving := preload("res://world/urban_detail/HarborPaving.gd")
const THICKNESS := 0.75
const WALK_HEIGHT := 0.07
const WALK_BEVEL := 0.40
const EDGE_LINE_INSET := 0.18
const EDGE_LINE_WIDTH := 0.10
const EAST_START := 393.75
const EAST_END := 631.25
const EAST_Z := -285.0
static var _materials: Dictionary = {}
static var _north_footprint := PackedVector2Array()
static var _north_asphalt := PackedVector2Array()
static var _north_entry_paint := PackedVector2Array()
static var _east_sections: Array[Dictionary] = []
static var _east_polygon := PackedVector2Array()
static var _east_asphalt := PackedVector2Array()
static var _east_bounds := Rect2()
static var _east_mouth := Vector2.ZERO
var _mesh := MeshKit.new(PackedFloat32Array())
var _faces := PackedVector3Array()
var _boxes: Array[Dictionary] = []
var _distance := 0.0
var _surface_exclusions: Array[PackedVector2Array] = []

static func enabled() -> bool:
	return OS.get_environment("GETECO_UNIFIED_BRIDGE") != "0"

static func east_road_half_width(x: float) -> float:
	return lerpf(10.5,4.375,smoothstep(405.0,468.25,x))

static func east_deck_half_width(x: float) -> float:
	return lerpf(13.125,7.2,smoothstep(405.0,468.25,x))

static func east_sections() -> Array[Dictionary]:
	_prepare_east()
	return _east_sections

static func east_bounds() -> Rect2:
	_prepare_east()
	return _east_bounds

static func east_footprint() -> PackedVector2Array:
	_prepare_east()
	return _east_polygon

static func east_asphalt_footprint() -> PackedVector2Array:
	_prepare_east()
	return _east_asphalt

static func east_mouth_limits() -> Vector2:
	if _east_mouth != Vector2.ZERO: return _east_mouth
	var band := PackedVector2Array([Vector2(361.875,-270),Vector2(364.5,-270),Vector2(364.5,-240),Vector2(361.875,-240)])
	var low := -254.0
	var high := -254.0
	for polygon in Geometry2D.intersect_polygons(north_footprint(),band):
		for point in polygon:
			low = minf(low,point.y)
			high = maxf(high,point.y)
	_east_mouth = Vector2(low-.20,high+.20)
	return _east_mouth

static func _prepare_east() -> void:
	if not _east_sections.is_empty(): return
	var points := PackedVector3Array()
	var mouth := east_mouth_limits()
	var zs: Array[float] = [-125.0,-133.0,-135.0,-136.0,mouth.x-2.0,mouth.x,mouth.y,mouth.y+2.0,-262.5]
	for i in range(1,18): zs.append(lerpf(-125.0,-262.5,float(i)/18.0))
	zs.sort()
	zs.reverse()
	for z in zs: points.append(Vector3(375,0,z))
	# Eixo medio das duas alcas V1: a interna tem raio17.5; a externa tem
	# raio22.5 e um trecho reto inicial5m. O grafo continua nas pistas autoradas.
	for i in range(1,33):
		var t := float(i)/32.0
		var outbound := Vector2(400,-262.5)+Vector2.from_angle(PI+PI*.5*t)*17.5
		var run := (5.0+22.5*PI*.5)*t
		var inbound := Vector2(367.5,-262.5-run) if run <= 5.0 else Vector2(390,-267.5)+Vector2.from_angle(PI+(run-5.0)/22.5)*22.5
		var midpoint := (outbound+inbound)*.5
		points.append(Vector3(midpoint.x,0,midpoint.y))
	points.append(Vector3(405,0,EAST_Z))
	for i in range(1,25): points.append(Vector3(lerpf(405,468.25,float(i)/24.0),0,EAST_Z))
	var xs: Array[float] = [559.375,578.125,EAST_END-.60,EAST_END]
	for i in range(1,22): xs.append(lerpf(468.25,EAST_END,float(i)/21.0))
	xs.sort()
	for x in xs:
		if x-points[-1].x > .00001: points.append(Vector3(x,0,EAST_Z))
	var opposite := PackedVector2Array()
	var road_opposite := PackedVector2Array()
	var distance := 0.0
	for i in points.size():
		var point := points[i]
		var direction := points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]
		var side := Vector3(-direction.z,0,direction.x).normalized()
		if i>0: distance += point.distance_to(points[i-1])
		var road := 10.5 if i < zs.size()+32 else east_road_half_width(point.x)
		var deck := 13.125 if i < zs.size()+32 else east_deck_half_width(point.x)
		var west_mouth := is_equal_approx(point.x,375.0) and point.z>=mouth.x and point.z<=mouth.y
		_east_sections.append({"point":point,"side":side,"road":road,"deck":deck,"distance":distance,"west_mouth":west_mouth})
		_east_polygon.append(Vector2(point.x+side.x*deck,point.z+side.z*deck))
		opposite.append(Vector2(point.x-side.x*deck,point.z-side.z*deck))
		_east_asphalt.append(Vector2(point.x+side.x*road,point.z+side.z*road))
		road_opposite.append(Vector2(point.x-side.x*road,point.z-side.z*road))
	for i in range(opposite.size()-1,-1,-1): _east_polygon.append(opposite[i])
	for i in range(road_opposite.size()-1,-1,-1): _east_asphalt.append(road_opposite[i])
	_east_bounds = Rect2(_east_polygon[0],Vector2.ZERO)
	for point in _east_polygon: _east_bounds = _east_bounds.expand(point)

static func owns_east_point(point: Vector2) -> bool:
	return enabled() and east_bounds().grow(.001).has_point(point) and Geometry2D.is_point_in_polygon(point,east_footprint())

static func north_footprint() -> PackedVector2Array:
	if not _north_footprint.is_empty(): return _north_footprint
	var layout := preload("res://world/north_gateway/NorthGatewayLayout.gd")
	var points := layout.centerline()
	var opposite := PackedVector2Array()
	var asphalt_opposite := PackedVector2Array()
	for i in points.size():
		var direction := points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]
		var axis := Vector3(-direction.z,0,direction.x).normalized()
		var side := axis*layout.deck_half_width(points[i])
		_north_footprint.append(Vector2(points[i].x+side.x,points[i].z+side.z))
		opposite.append(Vector2(points[i].x-side.x,points[i].z-side.z))
		var road: float = layout.ROAD_HALF_WIDTH if points[i].z > -343.0 else lerpf(layout.ROAD_HALF_WIDTH,5.0,clampf((-343.0-points[i].z)/30.5,0.0,1.0))
		var road_side := axis*road
		_north_asphalt.append(Vector2(points[i].x+road_side.x,points[i].z+road_side.z))
		asphalt_opposite.append(Vector2(points[i].x-road_side.x,points[i].z-road_side.z))
	for i in range(opposite.size()-1,-1,-1): _north_footprint.append(opposite[i])
	for i in range(asphalt_opposite.size()-1,-1,-1): _north_asphalt.append(asphalt_opposite[i])
	return _north_footprint

static func north_asphalt_footprint() -> PackedVector2Array:
	north_footprint()
	return _north_asphalt

static func north_entry_paint_footprint() -> PackedVector2Array:
	if not _north_entry_paint.is_empty(): return _north_entry_paint
	_north_entry_paint = north_asphalt_footprint().duplicate()
	var points := preload("res://world/north_gateway/NorthGatewayLayout.gd").centerline()
	var forward := (points[0]-points[1]).normalized()
	# A tinta fica18cm para dentro da pista principal. Prolongar somente a
	# mascara de pintura ate sua borda evita uma faixa branca fechando a entrada.
	var paint_edge := 375.0-east_road_half_width(375.0)+EDGE_LINE_INSET+EDGE_LINE_WIDTH*.5+.002
	var head_x := minf(_north_entry_paint[0].x,_north_entry_paint[-1].x)
	var extension := maxf(0.0,(paint_edge-head_x)/forward.x)
	var shift := Vector2(forward.x,forward.z)*extension
	_north_entry_paint[0] += shift
	_north_entry_paint[-1] += shift
	return _north_entry_paint

static func owns_surface_point(point: Vector2) -> bool:
	if not enabled(): return false
	if owns_east_point(point): return true
	return Rect2(328.75,-374.25,36.55,126.0).has_point(point) and Geometry2D.is_point_in_polygon(point,north_footprint())

static func material(id: String) -> Material:
	var key := {"asfalto":"asphalt", "concreto":"concrete", "metal":"steel", "branco":"white", "amarelo":"yellow"}.get(id,id) as String
	if _materials.has(key): return _materials[key]
	var result: Material
	if key == "asphalt":
		result = preload("res://world/regions/unified_bridge/UnifiedRoadAsphalt.gd").material()
	elif key == "concrete":
		result = Paving.material()
	else:
		var finish := StandardMaterial3D.new()
		finish.albedo_color = Color({"steel":"53676c","white":"d9dedb","yellow":"d4b85b"}.get(key,"979f9f"))
		finish.roughness = .7 if key == "steel" else .94
		finish.metallic = .32 if key == "steel" else 0.0
		result = finish
	_materials[key] = result
	return result

static func materials() -> Array:
	for id in ["asphalt","concrete","steel","white","yellow"]: material(id)
	return _materials.values()

static func set_wetness(value: float) -> void:
	(material("asphalt") as ShaderMaterial).set_shader_parameter("wetness",clampf(value,0.0,1.0))

func add_segment(a: Vector3, b: Vector3, sa: Vector3, sb: Vector3, ra: float, rb: float, wa: float, wb: float, guards := true, options: Dictionary = {}) -> void:
	if a.distance_squared_to(b) < .000001: return
	_mesh.forced_segment = floori(_distance/32.0)
	var structural_exclusions: Array = options.get("exclusions",[])
	var walk_exclusions: Array = options.get("walk_exclusions",structural_exclusions)
	_surface_exclusions.assign(options.get("road_exclusions",structural_exclusions))
	var solid := bool(options.get("solid",true))
	var walk_a := float(options.get("walk_height_a",WALK_HEIGHT))
	var walk_b := float(options.get("walk_height_b",WALK_HEIGHT))
	var road := PackedVector3Array([a+sa*ra,a-sa*ra,b-sb*rb,b+sb*rb])
	var raised := PackedVector3Array()
	for point in road: raised.append(point+Vector3.UP*.026)
	_face("asphalt",raised,Vector3.UP,false)
	if solid: _collision_face(road,Vector3.UP)
	for sign_value in [-1.0,1.0]:
		var side_walk_a := float(options.get("walk_negative_a" if sign_value < 0 else "walk_positive_a",walk_a))
		var side_walk_b := float(options.get("walk_negative_b" if sign_value < 0 else "walk_positive_b",walk_b))
		var edge_a: Vector3 = sa*sign_value
		var edge_b: Vector3 = sb*sign_value
		var inner_a := a+edge_a*ra
		var inner_b := b+edge_b*rb
		var bevel_a := a+edge_a*minf(ra+WALK_BEVEL,wa)+Vector3.UP*side_walk_a
		var bevel_b := b+edge_b*minf(rb+WALK_BEVEL,wb)+Vector3.UP*side_walk_b
		var outer_a := a+edge_a*wa+Vector3.UP*side_walk_a
		var outer_b := b+edge_b*wb+Vector3.UP*side_walk_b
		_surface_exclusions.assign(walk_exclusions)
		_face("concrete",PackedVector3Array([inner_a,inner_b,bevel_b,bevel_a]),Vector3.UP,solid)
		_face("concrete",PackedVector3Array([bevel_a,bevel_b,outer_b,outer_a]),Vector3.UP,solid)
		_surface_exclusions.assign(structural_exclusions)
		if bool(options.get("structure",true)):
			_face("concrete",PackedVector3Array([outer_a,outer_b,b+edge_b*wb-Vector3.UP*THICKNESS,a+edge_a*wa-Vector3.UP*THICKNESS]),(edge_a+edge_b).normalized(),solid)
		if guards and bool(options.get("guard_negative" if sign_value < 0 else "guard_positive",true)):
			var ga := a+edge_a*(wa-.18)
			var gb := b+edge_b*(wb-.18)
			_beam("concrete",ga+Vector3.UP*(side_walk_a+.30),gb+Vector3.UP*(side_walk_b+.30),.32,.60,solid)
			_beam("steel",ga+Vector3.UP*(side_walk_a+1.03),gb+Vector3.UP*(side_walk_b+1.03),.12,.12,false)
			_beam("steel",ga+Vector3.UP*(side_walk_a+.80),gb+Vector3.UP*(side_walk_b+.80),.07,.07,false)
			# A contenção contínua mantém o carro dentro mesmo entre montantes.
			_beam("",ga+Vector3.UP*(side_walk_a+.84),gb+Vector3.UP*(side_walk_b+.84),.20,.48,solid)
			add_box("steel",ga+Vector3.UP*(side_walk_a+.83),Vector3(.10,.48,.10))
			if bool(options.get("guard_end",false)):
				add_box("steel",gb+Vector3.UP*(side_walk_b+.83),Vector3(.10,.48,.10))
	if bool(options.get("structure",true)):
		_face("concrete",PackedVector3Array([a+sa*wa-Vector3.UP*THICKNESS,b+sb*wb-Vector3.UP*THICKNESS,b-sb*wb-Vector3.UP*THICKNESS,a-sa*wa-Vector3.UP*THICKNESS]),Vector3.DOWN,solid)
		for cap in [0,1]:
			if not bool(options.get("start_cap" if cap == 0 else "end_cap",false)): continue
			var p := a if cap == 0 else b
			var side := sa if cap == 0 else sb
			var width := wa if cap == 0 else wb
			_face("concrete",PackedVector3Array([p-side*width,p+side*width,p+side*width-Vector3.UP*THICKNESS,p-side*width-Vector3.UP*THICKNESS]),(a-b).normalized() if cap == 0 else (b-a).normalized(),solid)
	if bool(options.get("markings",true)):
		for sign_value in [-1.0,1.0]:
			_surface_exclusions.assign(options.get("white_negative_exclusions" if sign_value<0 else "white_positive_exclusions",structural_exclusions))
			var white_a: Vector3 = a+sa*(ra-EDGE_LINE_INSET)*sign_value+Vector3.UP*.038
			var white_b: Vector3 = b+sb*(rb-EDGE_LINE_INSET)*sign_value+Vector3.UP*.038
			_face("white",PackedVector3Array([white_a+sa*EDGE_LINE_WIDTH*.5,white_a-sa*EDGE_LINE_WIDTH*.5,white_b-sb*EDGE_LINE_WIDTH*.5,white_b+sb*EDGE_LINE_WIDTH*.5]),Vector3.UP,false)
		_surface_exclusions.assign(structural_exclusions)
		for offset in [-.10,.10]:
			_beam("yellow",a+sa*offset+Vector3.UP*.035,b+sb*offset+Vector3.UP*.035,.075,.006,false)
	_distance += a.distance_to(b)

func _face(id: String, points: PackedVector3Array, normal: Vector3, solid: bool) -> void:
	# Rampa longitudinal e chanfro lateral precisam da normal da face, não da
	# normal horizontal usada apenas para escolher o lado exterior.
	var actual := (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	if actual.dot(normal)<0.0: actual = -actual
	for piece in _clipped_faces(points,actual):
		_mesh.polygon(id,piece,actual,Color.WHITE)
		if solid: _raw_collision_face(piece,actual)

func _collision_face(points: PackedVector3Array, normal: Vector3) -> void:
	var actual := (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	if actual.dot(normal)<0.0: actual = -actual
	for piece in _clipped_faces(points,actual): _raw_collision_face(piece,actual)

## Apenas a boca compartilhada precisa de recorte. Faces verticais ficam no
## contorno estrutural; pisos e suas colisoes usam exatamente os mesmos recortes.
func _clipped_faces(points: PackedVector3Array, normal: Vector3) -> Array[PackedVector3Array]:
	if _surface_exclusions.is_empty() or absf(normal.y)<.001: return [points]
	var planar := PackedVector2Array()
	for point in points: planar.append(Vector2(point.x,point.z))
	var pieces: Array[PackedVector2Array] = [planar]
	for exclusion in _surface_exclusions:
		var next: Array[PackedVector2Array] = []
		for piece in pieces: next.append_array(Geometry2D.clip_polygons(piece,exclusion))
		pieces = next
	var result: Array[PackedVector3Array] = []
	var plane := normal.dot(points[0])
	for piece in pieces:
		var indices := Geometry2D.triangulate_polygon(piece)
		for offset in range(0,indices.size(),3):
			var triangle := PackedVector3Array()
			for i in range(3):
				var point := piece[indices[offset+i]]
				triangle.append(Vector3(point.x,(plane-normal.x*point.x-normal.z*point.y)/normal.y,point.y))
			result.append(triangle)
	return result

func _raw_collision_face(points: PackedVector3Array, normal: Vector3) -> void:
	for i in range(1,points.size()-1):
		var a := points[0]
		var b := points[i]
		var c := points[i+1]
		if (b-a).cross(c-a).dot(normal)>0.0:
			_faces.append(a); _faces.append(c); _faces.append(b)
		else:
			_faces.append(a); _faces.append(b); _faces.append(c)

func add_box(id: String, center: Vector3, size: Vector3, solid := false) -> void:
	if not id.is_empty(): _mesh.box(id,center,size,Color.WHITE)
	if solid: _boxes.append({"center":center,"size":size,"basis":Basis.IDENTITY})

func section_at(distance: float) -> void:
	_mesh.forced_segment = floori(maxf(0.0,distance)/32.0)

func _beam(id: String, a: Vector3, b: Vector3, width: float, height: float, solid: bool) -> void:
	var delta := b-a
	var length := delta.length()
	if length < .0001: return
	var axis := delta/length
	var lateral := axis.cross(Vector3.UP).normalized()
	var up := lateral.cross(axis).normalized()
	var basis := Basis(axis,up,lateral)
	var center := (a+b)*.5
	var half := Vector3(length,height,width)*.5
	if not id.is_empty():
		for face_axis in range(3):
			var next := (face_axis+1)%3
			var last := (face_axis+2)%3
			for sign_value in [-1.0,1.0]:
				var points := PackedVector3Array()
				for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
					var local := Vector3.ZERO
					local[face_axis] = half[face_axis]*sign_value
					local[next] = half[next]*corner.x
					local[last] = half[last]*corner.y
					points.append(center+basis*local)
				_face(id,points,basis[face_axis]*sign_value,false)
	if solid: _boxes.append({"center":center,"size":Vector3(length,height,width),"basis":basis})

func commit(parent: Node3D, label: String) -> Array[MeshInstance3D]:
	var settings := {}
	for id in ["asphalt","concrete","steel","white","yellow"]:
		settings[id] = [material(id),id in ["concrete","steel"]]
	var result: Array[MeshInstance3D] = _mesh.commit(parent,label,settings)
	var body := StaticBody3D.new()
	body.name = label+"Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	if not _faces.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(_faces)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
	for entry in _boxes:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = entry.size
		collider.shape = shape
		collider.transform = Transform3D(entry.basis,entry.center)
		body.add_child(collider)
	parent.add_child(body)
	_faces.clear()
	_boxes.clear()
	return result
