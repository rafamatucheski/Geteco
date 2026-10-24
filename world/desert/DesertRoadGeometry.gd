extends RefCounted
## The render mesh, wheel contact and traffic all use DesertLayout's centre-lines.
## Prepared once per region; only clipped, batched surfaces are built per chunk.
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const G := preload("res://world/desert/DesertGeometry.gd")
const DETAIL := preload("res://world/desert/DesertSurfaceDetail.gd")
const JUNCTIONS := preload("res://gameplay/traffic_junctions/TrafficJunctions.gd")
const TOWN_MATERIALS := preload("res://world/desert/DesertTownMaterials.gd")
const UNIFIED_BRIDGE := preload("res://world/regions/unified_bridge/UnifiedBridgeKit.gd")
var _roads: Array[Dictionary] = []
var corridors: Array[Dictionary] = []
var shoulders: Array[Dictionary] = []
var paint: Array[Dictionary] = []
var junctions: Array[Dictionary] = []
var _delineators := preload("res://world/desert/DesertRoadDelineators.gd").new()
const EDGE_BLEND := .35

func configure(roads: Array[Dictionary]) -> void:
	_roads=roads
	corridors.clear(); shoulders.clear(); paint.clear(); junctions.clear()
	for road in roads:
		var path := PackedVector2Array()
		for p: Vector3 in road.points: path.append(Vector2(p.x,p.z))
		for polygon in Geometry2D.offset_polyline(path,float(road.width)*.5,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT):
			corridors.append(_record(polygon,str(road.id)))
		for polygon in Geometry2D.offset_polyline(path,float(road.width)*.5+2.4,Geometry2D.JOIN_ROUND,Geometry2D.END_BUTT):
			shoulders.append(_record(polygon,str(road.id)))
		if road.id=="desert_bank_approach":
			# Authored drop-off ends before the pedestrian portico. A same-width
			# round cap closes its asphalt silhouette without paving into the bank.
			for extra in [0.0,2.4]:
				var cap := PackedVector2Array()
				for i in 24:
					var angle := TAU*float(i)/24.0
					cap.append(path[-1]+Vector2(cos(angle),sin(angle))*(float(road.width)*.5+float(extra)))
				if extra==0.0: corridors.append(_record(cap,str(road.id)))
				else: shoulders.append(_record(cap,str(road.id)))
	_build_junctions(roads)
	for road in roads: _build_paint(road)
	_build_stop_lines()
	_delineators.configure(roads, self)

func build_chunk(parent: Node3D, rect: Rect2) -> void:
	# Avoid coincident triangles at T/crossings instead of relying on depth ties.
	var shoulder_segments := DETAIL.prepare_shoulder_segments(rect,_roads)
	_emit(parent,"GravelShoulder",_unique(shoulders,rect),rect,.008,DETAIL.shoulder_material(),false,shoulder_segments)
	var asphalt: Material = UNIFIED_BRIDGE.material("asphalt") if UNIFIED_BRIDGE.enabled() else G.material(Color("706d61"),false,true)
	_emit(parent,"WeatheredAsphalt",_unique(corridors,rect),rect,.026 if UNIFIED_BRIDGE.enabled() else .018,asphalt,true)
	var white: Array[PackedVector2Array] = []
	var yellow: Array[PackedVector2Array] = []
	for row in paint:
		if not row.bounds.intersects(rect,true): continue
		if row.id=="white": white.append(row.polygon)
		else: yellow.append(row.polygon)
	_emit(parent,"WornEdge",white,rect,.035 if UNIFIED_BRIDGE.enabled() else .027,UNIFIED_BRIDGE.material("white") if UNIFIED_BRIDGE.enabled() else G.material(Color("c5bea7")),false)
	_emit(parent,"LaneDash",yellow,rect,.035 if UNIFIED_BRIDGE.enabled() else .028,UNIFIED_BRIDGE.material("yellow") if UNIFIED_BRIDGE.enabled() else G.material(Color("bbad73")),false)
	_bank_walk(parent,rect)
	_delineators.build_chunk(parent,rect)
	# A areia e a pista compartilham a cota física. A posse da pista também
	# precisa valer para colisão, sem depender do desempate entre faces coplanares.
	preload("res://world/desert/DesertGroundOwnership.gd").compose_collision(parent, rect, corridors)

func _bank_walk(parent: Node3D, rect: Rect2) -> void:
	var section := Rect2(-211.4,-570.73,2.8,1.13).intersection(rect)
	if not section.has_area(): return
	var points := PackedVector3Array()
	for p: Vector2 in [section.position,Vector2(section.end.x,section.position.y),section.end,Vector2(section.position.x,section.end.y)]:
		var height := lerpf(.024,.082,clampf(inverse_lerp(-569.6,-570.675,p.y),0.0,1.0))
		points.append(Vector3(p.x,height,p.y))
	G.quad(parent,"CobrePedestrianRamp",points,TOWN_MATERIALS.material("stone"),true)

func _record(polygon: PackedVector2Array, id: String) -> Dictionary:
	var bounds := Rect2(polygon[0],Vector2.ZERO)
	for p in polygon: bounds=bounds.expand(p)
	return {"polygon":polygon,"bounds":bounds,"id":id}

func _unique(rows: Array[Dictionary], rect: Rect2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var previous: Array[Dictionary] = []
	for row in rows:
		if not row.bounds.intersects(rect,true): continue
		result.append_array(_subtract(row.polygon,previous))
		previous.append(row)
	return result

func _subtract(polygon: PackedVector2Array, masks: Array[Dictionary]) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [polygon]
	var bounds: Rect2 = _record(polygon,"").bounds
	for mask in masks:
		if not bounds.intersects(mask.bounds,true): continue
		var remaining: Array[PackedVector2Array] = []
		for part in parts: remaining.append_array(Geometry2D.clip_polygons(part,mask.polygon))
		parts=remaining
		if parts.is_empty(): break
	return parts

func _build_junctions(roads: Array[Dictionary]) -> void:
	var nodes: Dictionary = {}
	for road in roads:
		var points: PackedVector3Array = road.points
		for i in points.size():
			var at := Vector2(points[i].x,points[i].z)
			var key := Vector2i(roundi(at.x*100),roundi(at.y*100))
			if not nodes.has(key): nodes[key]={"at":at,"arms":[]}
			for neighbor in [i-1,i+1]:
				if neighbor<0 or neighbor>=points.size(): continue
				var direction := Vector2(points[neighbor].x,points[neighbor].z)-at
				nodes[key].arms.append({"direction":direction.normalized(),"width":float(road.width),"id":str(road.id),"traffic":bool(road.get("traffic",true))})
	for node: Dictionary in nodes.values():
		var arms: Array = node.arms
		if arms.size()<3: continue
		junctions.append(node)
		for i in arms.size():
			for j in range(i+1,arms.size()):
				var u: Vector2 = arms[i].direction
				var v: Vector2 = arms[j].direction
				if absf(u.dot(v))>.1: continue
				var radius := 8.0 if maxf(arms[i].width,arms[j].width)>=10 else 5.0
				var corner: Vector2 = node.at+u*float(arms[j].width)*.5+v*float(arms[i].width)*.5
				var center := corner+(u+v)*radius
				var polygon := PackedVector2Array([corner])
				for k in 9:
					var angle := float(k)/8.0*PI*.5
					polygon.append(center-v*cos(angle)*radius-u*sin(angle)*radius)
				var patch := _record(polygon,"junction")
				corridors.append(patch)
				for shoulder in Geometry2D.offset_polygon(polygon,2.4,Geometry2D.JOIN_ROUND): shoulders.append(_record(shoulder,"junction"))

func _build_paint(road: Dictionary) -> void:
	var path := PackedVector2Array()
	for p: Vector3 in road.points: path.append(Vector2(p.x,p.z))
	var masks: Array[Dictionary] = []
	for row in corridors:
		if row.id==str(road.id): continue
		# A branch ends on the other road's centre-line: include the full width of
		# its paint, so clipping does not leave a half-width dash through the T.
		for expanded in Geometry2D.offset_polygon(row.polygon,.2,Geometry2D.JOIN_ROUND): masks.append(_record(expanded,row.id))
	# Junction fillets extend into corner approaches: remove side paint there too.
	var edge_inset: float = UNIFIED_BRIDGE.EDGE_LINE_INSET if UNIFIED_BRIDGE.enabled() else .25
	var edge_width: float = UNIFIED_BRIDGE.EDGE_LINE_WIDTH if UNIFIED_BRIDGE.enabled() else .11
	for side in [-1.0,1.0]:
		var edge := _offset_path(path,side*(float(road.width)*.5-edge_inset))
		for i in range(1,edge.size()): _paint_strip(edge[i-1],edge[i],edge_width,"white",masks)
	var travelled := 0.0
	for i in range(1,path.size()):
		var a := path[i-1]
		var b := path[i]
		var length := a.distance_to(b)
		var cursor := 0.0
		while cursor<length-.0001:
			var phase := fposmod(travelled+cursor,12.0)
			var step := minf(length-cursor,(4.0 if phase<4.0 else 12.0)-phase)
			if step<.0001: step=minf(.001,length-cursor)
			if phase<4.0:
				_paint_strip(a.lerp(b,cursor/length),a.lerp(b,(cursor+step)/length),.16,"white" if str(road.id)=="desert_drag_strip" else "yellow",masks)
			cursor+=step
		travelled+=length

func _build_stop_lines() -> void:
	# Native unsignalized junctions stop every incoming arm at the same 7m line.
	# Race-only spurs do not create an ambient stop on the through highway.
	for junction in junctions:
		var arms: Array = junction.arms.filter(func(arm: Dictionary): return arm.traffic)
		if arms.size()<3: continue
		for arm: Dictionary in arms:
			var direction: Vector2 = arm.direction
			var right := Vector2(direction.y,-direction.x)
			var center: Vector2 = junction.at+direction*JUNCTIONS.DEFAULT_STOP_LINE
			_paint_strip(center+right*.18,center+right*(float(arm.width)*.5-.3),.28,"white",[])

func _offset_path(path: PackedVector2Array, offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in path.size():
		var before := (path[i]-path[i-1]).normalized() if i>0 else (path[1]-path[0]).normalized()
		var after := (path[i+1]-path[i]).normalized() if i<path.size()-1 else before
		var normal := Vector2(-before.y,before.x)
		var next := Vector2(-after.y,after.x)
		var bisector := (normal+next).normalized()
		result.append(path[i]+bisector*offset/maxf(.5,bisector.dot(normal)))
	return result

func _paint_strip(a: Vector2, b: Vector2, width: float, color: String, masks: Array[Dictionary]) -> void:
	if a.distance_squared_to(b)<.000001: return
	var direction := a.direction_to(b)
	var normal := Vector2(-direction.y,direction.x)*width*.5
	var polygon := PackedVector2Array([a+normal,b+normal,b-normal,a-normal])
	var parts := _subtract(polygon,masks)
	if color == "yellow" and UNIFIED_BRIDGE.enabled():
		# A primeira marca regional comecava no fim das duas linhas da ponte.
		# Ownership exato e respiro curto conservam o restante da pintura autorada.
		var terminal_z: float = LAYOUT.BRIDGE_END.z
		var terminal_gap := PackedVector2Array([Vector2(341.5,terminal_z+.001),Vector2(343.5,terminal_z+.001),
			Vector2(343.5,terminal_z-.75),Vector2(341.5,terminal_z-.75)])
		var bounds: Rect2 = _record(polygon,"").bounds
		if bounds.intersects(Rect2(328.75,terminal_z-.75,36.55,126.75),true):
			parts = preload("res://world/urban_detail/GroundCut.gd").subtract_exact(parts,[UNIFIED_BRIDGE.north_footprint(),terminal_gap])
	for part in parts: paint.append(_record(part,color))

func _emit(parent: Node3D, id: String, polygons: Array[PackedVector2Array], rect: Rect2, offset: float, material: Material, solid: bool, shoulder_segments: Array = []) -> void:
	if polygons.is_empty(): return
	var vertices := PackedVector3Array()
	var edge_faces := PackedVector3Array()
	var colors := PackedColorArray()
	var weights: Dictionary = {}
	# Same eight-metre support profile as DesertRegion; no ramp paint floats above it.
	for polygon in polygons:
		var bounds: Rect2 = _record(polygon,"").bounds.intersection(rect)
		if not bounds.has_area(): continue
		var tiles: Array[Rect2] = [bounds]
		if id=="GravelShoulder":
			# Two metres resolves the narrow blend and exactly divides the ramp grid.
			# Only intersecting road bounds are tiled, never all 96x96m of a chunk.
			tiles.clear()
			for z in range(floori(bounds.position.y/2),ceili(bounds.end.y/2)):
				for x in range(floori(bounds.position.x/2),ceili(bounds.end.x/2)):
					tiles.append(bounds.intersection(Rect2(float(x)*2,float(z)*2,2,2)))
		elif bounds.end.y>-448:
			tiles.clear()
			for z in range(floori(bounds.position.y/8),ceili(bounds.end.y/8)):
				tiles.append(bounds.intersection(Rect2(bounds.position.x,float(z)*8,bounds.size.x,8)))
		for tile in tiles:
			var clip := PackedVector2Array([tile.position,Vector2(tile.end.x,tile.position.y),tile.end,Vector2(tile.position.x,tile.end.y)])
			for part in Geometry2D.intersect_polygons(polygon,clip):
				if Geometry2D.is_polygon_clockwise(part): part.reverse()
				if solid and not UNIFIED_BRIDGE.enabled():
					# The raised asphalt used to present a vertical collision edge to
					# cars on sand. Bevel its perimeter into the existing shoulder.
					# Clipped tile seams also taper below the adjacent asphalt surface.
					for i in part.size():
						var a: Vector2 = part[i]
						var b: Vector2 = part[(i+1)%part.size()]
						var outward := Vector2((b-a).y,-(b-a).x).normalized()*EDGE_BLEND
						var c := b+outward
						var d := a+outward
						var top_a := Vector3(a.x,_height(a)+offset,a.y)
						var top_b := Vector3(b.x,_height(b)+offset,b.y)
						var low_c := Vector3(c.x,_height(c),c.y)
						var low_d := Vector3(d.x,_height(d),d.y)
						var bevel := PackedVector3Array([top_b,top_a,low_d,top_b,low_d,low_c])
						# The bridge transition is visible asphalt too. This strip lies
						# outside the road polygon, meeting its top only at the edge.
						if absf(a.y-LAYOUT.BOUNDS.end.y)<.0001 and absf(b.y-LAYOUT.BOUNDS.end.y)<.0001:
							vertices.append_array(bevel)
						else:
							edge_faces.append_array(bevel)
				var indices := Geometry2D.triangulate_polygon(part)
				for index in indices:
					var p := part[index]
					vertices.append(Vector3(p.x,_height(p)+offset,p.y))
					if id=="GravelShoulder":
						if not weights.has(p): weights[p]=DETAIL.shoulder_weight(p,shoulder_segments)
						colors.append(Color(float(weights[p]),0,0,1))
	if vertices.is_empty(): return
	var normals := PackedVector3Array()
	for i in range(0,vertices.size(),3):
		var normal := (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
		for j in 3: normals.append(normal)
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	if not colors.is_empty(): arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new(); node.name=id; node.mesh=mesh; node.material_override=material
	node.set_meta("vehicle_surface","hard" if solid else "dirt")
	parent.add_child(node)
	if solid:
		var body := StaticBody3D.new(); body.collision_layer=1; body.collision_mask=0
		body.set_meta("vehicle_surface","hard")
		var collider := CollisionShape3D.new(); var shape := ConcavePolygonShape3D.new()
		var physical_faces := vertices.duplicate()
		# A ponte nova e o terreno compartilham a cota física; o acabamento sobe
		# apenas no desenho. Assim não há lâmina de 18 mm nem rampa sobreposta
		# avançando para dentro do tabuleiro na chegada ao deserto.
		if UNIFIED_BRIDGE.enabled():
			for i in physical_faces.size(): physical_faces[i].y -= offset
		physical_faces.append_array(edge_faces)
		shape.set_faces(physical_faces); collider.shape=shape; body.add_child(collider); node.add_child(body)

func _height(point: Vector2) -> float:
	# The perimeter bevel reaches onto the flat bridge deck. Extrapolating the
	# first descending terrain interval raised its foot by 1.2 mm, enough for a
	# grounded box hull to strike its edge instead of climbing the bevel.
	if point.y>=LAYOUT.BOUNDS.end.y: return LAYOUT.BRIDGE_END.y
	if point.y<=-448: return 0.0
	var low := floorf(point.y/8)*8
	var high := minf(low+8,LAYOUT.BOUNDS.end.y)
	if high<=low: return LAYOUT.surface_height(point)
	return lerpf(LAYOUT.surface_height(Vector2(point.x,low)),LAYOUT.surface_height(Vector2(point.x,high)),(point.y-low)/(high-low))
