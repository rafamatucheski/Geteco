extends RefCounted
## Small, opaque ground decoration. Built once, owned/unloaded by its chunk.
## Two shared meshes/material, no scripts on the instances, physics or shadows.
const CANAL := preload("res://world/urban_detail/CanalTunnel3D.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const SKATE := preload("res://activities/skate/SkateParkLayout.gd")
const SPACING := 12.0
const MAX_LEAVES := 96
const MAX_PAPERS := 24
const LIFT := .003
# Used by the rendered A/B harness; production always starts enabled.
static var enabled := true
static var render_visible := true
static var _leaf: ArrayMesh
static var _paper: ArrayMesh
static var _paint: StandardMaterial3D


static func build_chunk(chunk: Node3D, context: Dictionary, furniture: Dictionary, exclusions: Array) -> void:
	var job := begin(chunk,context,furniture,exclusions)
	step(job,INF)


## Prepare cheap candidates; footprint checks are resumed by the streaming
## owner with a 0.5 ms slice budget instead of occupying a whole frame.
static func begin(chunk: Node3D, context: Dictionary, furniture: Dictionary, exclusions: Array) -> Dictionary:
	if not enabled or chunk.has_node("CityGroundLitter"): return {"done":true}
	var geometry = context.geometry
	if geometry == null or geometry._layers.is_empty(): return {"done":true}
	var began := Time.get_ticks_usec()
	var job := {"done":false,"chunk":chunk,"index":0,"candidates":[],"segments":[],"context":context,"exclusions":exclusions,"leaves":[],"papers":[],"leaf_colors":[],"paper_colors":[],"supports":[],"crossings":[],"doors":[],"occupied":[]}
	# Support comes from the polygons actually rendered as sidewalks. The same
	# width overrides, curves and endpoints therefore govern these tiny pieces.
	var layer: Dictionary = geometry._layers[0]
	for index in layer.polygons.size():
		if (context.rect as Rect2).grow(.5).intersects(layer.bounds[index]):
			job.supports.append(layer.polygons[index])
	job.y = float(layer.y) + LIFT
	for index in geometry._crosswalk_tactile.size():
		if (context.rect as Rect2).intersects(geometry._crosswalk_tactile_bounds[index]): job.crossings.append(geometry._crosswalk_tactile[index])
	for entry in context.region.entries:
		var point: Vector3 = entry.get("exterior_position", entry.get("position", Vector3.INF))
		if not point.is_finite(): continue
		if (context.rect as Rect2).grow(3.0).has_point(Vector2(point.x,point.z)): job.doors.append(Vector2(point.x,point.z))
	# Decoration must not float over the feet of the existing street furniture.
	for kind in ["trash_can","dumpster","trash_bags","planter","bench_seat","phone_booth","hydrant","news_box","mailbox","bollard","signal_pole","stop_sign"]:
		for placement: Transform3D in furniture.get(kind,[]):
			job.occupied.append({"point":Vector2(placement.origin.x,placement.origin.z),"radius":1.4 if kind in ["dumpster","bench_seat","phone_booth"] else .65})
	for road in context.roads:
		var points: PackedVector2Array = road.points
		for segment in points.size()-1:
			var bounds := Rect2(points[segment],points[segment+1]-points[segment]).abs().grow(float(road.width)*.5+.5)
			if bounds.intersects((context.rect as Rect2).grow(.5)):
				job.segments.append({"a":points[segment],"b":points[segment+1],"half":float(road.width)*.5})
		var reach := float(road.sidewalk_width)
		if reach < .8: continue
		for segment in points.size()-1:
			var a := points[segment]
			var b := points[segment+1]
			var length := a.distance_to(b)
			if length < .1: continue
			var tangent := (b-a)/length
			var normal := Vector2(tangent.y,-tangent.x)
			# Only sample the part near this chunk; slot/seed belong to the road,
			# not to clipping, so adjacent chunks and reloads keep the same layout.
			var rect: Rect2 = (context.rect as Rect2).grow(float(road.width)*.5+reach+1.0)
			var low := INF
			var high := -INF
			for corner in [rect.position,rect.end,Vector2(rect.position.x,rect.end.y),Vector2(rect.end.x,rect.position.y)]:
				var along := (Vector2(corner)-a).dot(tangent)
				low = minf(low,along)
				high = maxf(high,along)
			for slot in range(maxi(0,floori(low/SPACING)),mini(ceili(length/SPACING),ceili(high/SPACING))):
				for side in [-1.0,1.0]:
					var rng := _rng("%s/%d/%d/%d"%[road.id,segment,slot,int(side)])
					if rng.randf() > .58: continue
					var distance := clampf((float(slot)+.5)*SPACING+rng.randf_range(-2.4,2.4),.4,length-.4)
					var curb_distance := rng.randf_range(.6,minf(1.15,reach-.3))
					var anchor: Vector2 = a+tangent*distance+normal*float(side)*(float(road.width)*.5+curb_distance)
					_cluster(job,anchor,rng,3+rng.randi_range(0,3),rng.randf()<.32)
	# Authored trees use their actual world placement; only their neighbouring
	# sidewalk is eligible, keeping raised beds and unsupported lawns untouched.
	for trunk: Node3D in chunk.find_children("TreeTrunk*","MeshInstance3D",true,false):
		var point := Vector2(trunk.global_position.x,trunk.global_position.z)
		var rng := _rng("tree/%.3f/%.3f"%[point.x,point.y])
		for group in 2:
			var angle := rng.randf()*TAU
			var anchor := point+Vector2(cos(angle),sin(angle))*rng.randf_range(.8,2.0)
			_cluster(job,anchor,rng,7,false)
	for kind in ["trash_can","dumpster","news_box"]:
		for placement: Transform3D in furniture.get(kind,[]):
			var point := Vector2(placement.origin.x,placement.origin.z)
			var rng := _rng("%s/%.3f/%.3f"%[kind,point.x,point.y])
			var angle := rng.randf()*TAU
			var anchor := point+Vector2(cos(angle),sin(angle))*(1.7 if kind=="dumpster" else 1.0)
			# Vídeo de 12/10/2026: papel branco e folhas junto da lixeira liam como
			# estilhaços; papel mais escuro (o sol estourava o branco) e menos peças.
			_cluster(job,anchor,rng,1,true)
	job.work_usec = Time.get_ticks_usec()-began
	job.max_step_usec = job.work_usec
	return job


static func step(job: Dictionary, budget_usec := 500.0) -> bool:
	if job.done: return true
	var began := Time.get_ticks_usec()
	while int(job.index)<job.candidates.size():
		var candidate: Dictionary = job.candidates[int(job.index)]
		job.index = int(job.index)+1
		var leaf: bool = candidate.kind=="Leaves"
		var target: Array = job.leaves if leaf else job.papers
		var limit := MAX_LEAVES if leaf else MAX_PAPERS
		var transform: Transform3D = candidate.transform
		if target.size()<limit and _allowed(job,Vector2(transform.origin.x,transform.origin.z),candidate.radius):
			target.append(transform)
			var colors: Array = job.leaf_colors if leaf else job.paper_colors
			colors.append(candidate.color)
		if Time.get_ticks_usec()-began>=budget_usec:
			_account(job,began)
			return false
	if job.leaves.is_empty() and job.papers.is_empty():
		job.done = true
		return true
	var chunk: Node3D = job.chunk
	var root := Node3D.new()
	root.name = "CityGroundLitter"
	root.visible = render_visible
	chunk.add_child(root)
	_batch(root,chunk,"Leaves",_leaf_mesh(),job.leaves,job.leaf_colors)
	_batch(root,chunk,"Papers",_paper_mesh(),job.papers,job.paper_colors)
	root.set_meta("leaves",job.leaves.size())
	root.set_meta("papers",job.papers.size())
	_account(job,began)
	root.set_meta("build_ms",float(job.work_usec)/1000.0)
	root.set_meta("build_step_max_ms",float(job.max_step_usec)/1000.0)
	job.done = true
	return true


static func _account(job: Dictionary, began: int) -> void:
	var elapsed := Time.get_ticks_usec()-began
	job.work_usec = int(job.work_usec)+elapsed
	job.max_step_usec = maxi(int(job.max_step_usec),elapsed)


static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("ground-litter-v1/"+key).hash()
	return rng


static func _cluster(job: Dictionary, anchor: Vector2, rng: RandomNumberGenerator, count: int, paper: bool) -> void:
	if not (job.context.rect as Rect2).grow(.6).has_point(anchor): return
	for index in count:
		var point := anchor+Vector2(rng.randf_range(-.5,.5),rng.randf_range(-.4,.4))
		var scale := rng.randf_range(.75,1.35)
		var yaw := rng.randf()*TAU
		var tint: Color = [Color("976943"),Color("79603f"),Color("a1844d"),Color("7d744e")][rng.randi_range(0,3)]
		job.candidates.append({"kind":"Leaves","transform":Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale),Vector3(point.x,job.y,point.y)),"radius":.16*scale,"color":tint.srgb_to_linear()})
	if paper:
		var point := anchor+Vector2(rng.randf_range(-.55,.55),rng.randf_range(-.45,.45))
		var scale := rng.randf_range(.8,1.15)
		var yaw := rng.randf()*TAU
		var tint: Color = [Color("a8a18c"),Color("a09c8b"),Color("b0a283")][rng.randi_range(0,2)]
		job.candidates.append({"kind":"Papers","transform":Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale),Vector3(point.x,job.y+.001,point.y)),"radius":.21*scale,"color":tint})


static func _allowed(job: Dictionary, point: Vector2, radius: float) -> bool:
	var context: Dictionary = job.context
	# The origin has a single owner at a chunk boundary. Its whole footprint
	# is checked against support/reservations; it may slightly cross that seam.
	if not (context.rect as Rect2).has_point(point): return false
	if CANAL.reserves(point,radius+.15) or CONNECTION.reserves_approach_for_driving(point): return false
	if SKATE.enabled() and SKATE.FOOTPRINT.grow(radius).has_point(point): return false
	for opening in CATALOG.sewer_openings():
		if Rect2(opening.position/16.0,opening.size/16.0).grow(radius+.5).has_point(point): return false
	for area: Rect2 in job.exclusions:
		if area.grow(radius).has_point(point): return false
	for building in context.buildings:
		if (building.rect as Rect2).grow(radius+.25).has_point(point): return false
	for door: Vector2 in job.doors:
		if point.distance_to(door)<2.0+radius: return false
	for item in job.occupied:
		if point.distance_to(item.point)<float(item.radius)+radius: return false
	for junction in context.junctions:
		var width := 0.0
		for index in junction.roads: width = maxf(width,float(context.geometry._roads[int(index)].width))
		if point.distance_to(junction.position)<width*.68+3.0+radius: return false
	# Test an enclosing square, rather than only the centre, for curb/end caps.
	for offset in [Vector2.ZERO,Vector2(-radius,-radius),Vector2(radius,-radius),Vector2(radius,radius),Vector2(-radius,radius)]:
		var probe := point+Vector2(offset)
		if CONNECTION.reserves_approach_for_driving(probe): return false
		for polygon: PackedVector2Array in job.crossings:
			if Geometry2D.is_point_in_polygon(probe,polygon): return false
		var supported := false
		for polygon: PackedVector2Array in job.supports:
			if Geometry2D.is_point_in_polygon(probe,polygon):
				supported = true
				break
		if not supported: return false
		for segment in job.segments:
			if probe.distance_to(Geometry2D.get_closest_point_to_segment(probe,segment.a,segment.b))-float(segment.half)<.34: return false
	return true


static func _batch(root: Node3D, chunk: Node3D, label: String, mesh: Mesh, transforms: Array, colors: Array) -> void:
	if transforms.is_empty(): return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	var local := chunk.global_transform.affine_inverse()
	for index in transforms.size():
		multi.set_instance_transform(index,local*transforms[index])
		multi.set_instance_color(index,colors[index])
	var display := MultiMeshInstance3D.new()
	display.name = label
	display.multimesh = multi
	display.material_override = _material()
	display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	display.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(display)


static func _material() -> StandardMaterial3D:
	if _paint == null:
		_paint = StandardMaterial3D.new()
		_paint.vertex_color_use_as_albedo = true
		_paint.cull_mode = BaseMaterial3D.CULL_DISABLED
		_paint.roughness = 1.0
	return _paint


static func _face(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, colors: Array) -> void:
	var normal := (b-a).cross(c-a).normalized()
	if normal.y<0: normal = -normal
	for index in 3:
		tool.set_normal(normal)
		tool.set_color(colors[index])
		tool.add_vertex([a,b,c][index])


static func _leaf_mesh() -> ArrayMesh:
	if _leaf != null: return _leaf
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := [Vector3(0,0,-.13),Vector3(.052,0,-.045),Vector3(.04,.001,.055),Vector3(0,0,.115),Vector3(-.047,0,.05),Vector3(-.055,0,-.047)]
	var ridge := Vector3(0,.005,0)
	for index in outline.size():
		_face(tool,ridge,outline[index],outline[(index+1)%outline.size()],[Color(.95,.9,.8),Color(.78,.76,.72),Color(.86,.84,.78)])
	_leaf = tool.commit()
	return _leaf


static func _paper_mesh() -> ArrayMesh:
	if _paper != null: return _paper
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := [Vector3(-.105,0,-.148),Vector3(.10,0,-.145),Vector3(.102,0,.096),Vector3(.073,.011,.145),Vector3(-.102,0,.148)]
	var center := Vector3(0,.001,0)
	for index in outline.size():
		_face(tool,center,outline[index],outline[(index+1)%outline.size()],[Color.WHITE,Color(.88,.87,.83),Color(.94,.93,.9)])
	# Two muted printed marks, baked into this shared mesh; no text or texture.
	for z in [-.055,-.023]:
		var a := Vector3(-.058,.002,z)
		var b := a+Vector3(.098,0,0)
		var c := b+Vector3(0,0,.007)
		var d := a+Vector3(0,0,.007)
		var ink := Color(.5,.52,.51)
		_face(tool,a,b,c,[ink,ink,ink])
		_face(tool,a,c,d,[ink,ink,ink])
	_paper = tool.commit()
	return _paper
