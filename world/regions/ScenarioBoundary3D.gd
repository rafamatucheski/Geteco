extends RefCounted
## Continuous visible escarpments owned by surface chunks, never teleport triggers.
const DESERT := preload("res://world/desert/DesertLayout.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const GROUP := "scenario_boundary"
const WIDTH := 10.0
const INSET := 4.0

static func build_desert(parent: Node3D, rect: Rect2, height: Callable) -> void:
	var bounds := DESERT.BOUNDS
	var west := bounds.position.x + INSET
	var east := bounds.end.x - INSET
	# Leave the north road's existing terminal (-1945) and guardrail accessible.
	var north := bounds.position.y + 1.0
	var south := bounds.end.y - INSET
	_strip(parent, rect, Vector2(west,north), Vector2(west,south), height, false)
	_strip(parent, rect, Vector2(east,north), Vector2(east,south), height, false)
	# The only southern route is the campaign bridge. Its physical deck and
	# shoulders fit inside this opening; the old scattered rocks left 156 m open.
	var bridge_x := DESERT.BRIDGE_END.x
	_strip(parent, rect, Vector2(west,south), Vector2(bridge_x-14,south), height, false)
	_strip(parent, rect, Vector2(bridge_x+14,south), Vector2(east,south), height, false)
	# The mission opens the pass, not an unbuilt next map. A ridge behind its
	# terminal also stops a pedestrian jumping over the existing low guardrail.
	_strip(parent, rect, Vector2(west,north), Vector2(east,north), height, false, 2.0)

static func build_mountain(parent: Node3D, rect: Rect2, height: Callable) -> void:
	# Stay on the supported side of the logical seam. The bridge void row
	# (-320..-256) already has its authored shore, rails and tunnel opening.
	var west := CONNECTION.SEAM.x + INSET
	_strip(parent, rect, Vector2(west,-1000000), Vector2(west,-320), height, true)
	_strip(parent, rect, Vector2(west,-256), Vector2(west,CONNECTION.LOGICAL_NORTH_LIMIT_Z-INSET), height, true)
	_strip(parent, rect, Vector2(west,CONNECTION.LOGICAL_NORTH_LIMIT_Z-INSET), Vector2(1000000,CONNECTION.LOGICAL_NORTH_LIMIT_Z-INSET), height, true)

static func _strip(parent: Node3D, rect: Rect2, a: Vector2, b: Vector2, height: Callable, snow: bool, width := WIDTH) -> void:
	var vertical := is_equal_approx(a.x,b.x)
	var fixed := a.x if vertical else a.y
	var low := maxf(a.y if vertical else a.x, rect.position.y if vertical else rect.position.x)
	var high := minf(b.y if vertical else b.x, rect.end.y if vertical else rect.end.x)
	# The wall has one owner, including when a boundary aligns to the grid.
	if high <= low or fixed < (rect.position.x if vertical else rect.position.y) or fixed >= (rect.end.x if vertical else rect.end.y): return
	var cuts: Array[float] = [low]
	var cut := (floorf(low/8.0)+1)*8.0
	while cut < high:
		cuts.append(cut)
		cut += 8.0
	cuts.append(high)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_color(Color("939e9f") if snow else Color("ad8c64"))
	for index in range(cuts.size()-1):
		var first := _section(fixed,cuts[index],vertical,height,width)
		var last := _section(fixed,cuts[index+1],vertical,height,width)
		for side in first.size():
			var next := (side+1)%first.size()
			var face: Array=[first[side],first[next],last[next],first[side],last[next],last[side]]
			# Swapping the extrusion axis reverses handedness. Horizontal strips
			# previously rendered their inside, exposing sky through the rock.
			if not vertical: face.reverse()
			for vertex in face:
				surface.set_color(_color(vertex, snow))
				surface.add_vertex(vertex)
		for side in range(1,first.size()-1):
			var caps: Array=[]
			if index==0: caps.append_array([first[0],first[side+1],first[side]])
			if index==cuts.size()-2: caps.append_array([last[0],last[side],last[side+1]])
			if not vertical: caps.reverse()
			for vertex in caps:
				surface.set_color(_color(vertex, snow))
				surface.add_vertex(vertex)
	surface.generate_normals()
	var mesh := surface.commit()
	var ridge := MeshInstance3D.new()
	ridge.name = "ScenarioBoundaryRidge"
	ridge.mesh = mesh
	ridge.material_override = preload("res://world/desert/DesertHorizonRelief.gd").material()
	parent.add_child(ridge)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group(GROUP)
	var collider := CollisionShape3D.new()
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	ridge.add_child(body)

static func _section(fixed: float, along: float, vertical: bool, height: Callable, width: float) -> PackedVector3Array:
	var center := Vector2(fixed,along) if vertical else Vector2(along,fixed)
	var floor_y: float = height.call(center)
	var crest := floor_y+9.0+1.2*sin(along*.037)+.6*sin(along*.113)
	var profile := [Vector2(-width*.5,floor_y-18),Vector2(-width*.5,floor_y+.6),Vector2(-width*.43,crest-3),Vector2(-width*.2,crest-.4),Vector2(width*.07,crest),Vector2(width*.43,crest-2.5),Vector2(width*.5,floor_y+.6),Vector2(width*.5,floor_y-18)]
	var points := PackedVector3Array()
	for point: Vector2 in profile:
		var plan := center+(Vector2(point.x,0) if vertical else Vector2(0,point.x))
		points.append(Vector3(plan.x,point.y,plan.y))
	return points

static func _color(point: Vector3, snow: bool) -> Color:
	var variation := .06*sin(point.y*.8+point.x*.07+point.z*.04)
	return (Color("939e9f") if snow else Color("ad8c64")).lightened(variation)
