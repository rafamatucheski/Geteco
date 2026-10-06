extends SceneTree
## Ground ownership, footprint support, exclusions and deterministic reloads.
const REGION := preload("res://world/regions/NativeRegion.gd")
const GEOMETRY := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const LITTER := preload("res://world/city_look/CityGroundLitter.gd")
var checks := 0
var failures := 0


func _initialize() -> void: run.call_deferred()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("GROUND_LITTER: "+label)


func _road(id: String, x: float, reach := 2.625) -> Dictionary:
	return {"id":id,"points":PackedVector3Array([Vector3(x,0,-15),Vector3(x,0,270)]),"width":7.5,"sidewalk_width":reach,"crossings":false}


func _layout(chunk: Node3D) -> Array:
	var result := []
	var litter := chunk.get_node_or_null("CityGroundLitter")
	if litter == null: return result
	for display: MultiMeshInstance3D in litter.get_children():
		var multi := display.multimesh
		for index in multi.instance_count:
			result.append([str(display.name),multi.get_instance_transform(index),multi.get_instance_color(index)])
	return result


func run() -> void:
	# A real renderer is necessary to read the stored MultiMesh transforms;
	# the Godot dummy renderer may return identity instead.
	if DisplayServer.get_name() == "headless": quit(2); return
	var region := REGION.new()
	region.harbor_road_geometry = GEOMETRY.new()
	var roads: Array[Dictionary] = [_road("fixture",13),_road("narrow",42,.3)]
	region.harbor_road_geometry.configure(roads)
	region.entries = [{"exterior_position":Vector3(19,0,28)}]
	var rect := Rect2(0,0,64,64)
	var context := {"region":region,"geometry":region.harbor_road_geometry,"roads":region.harbor_road_geometry._roads,"junctions":[],"buildings":[{"rect":Rect2(6,40,3,9)}],"rect":rect}
	var exclusions: Array = [Rect2(17.2,50,4,8)]
	var first := Node3D.new()
	root.add_child(first)
	LITTER.build_chunk(first,context,{},exclusions)
	var layout := _layout(first)
	_check(layout.size()>0,"fixture actually builds decoration")
	_check(first.get_node("CityGroundLitter").get_child_count()<=2,"at most two draw batches")
	var count := first.get_child_count()
	LITTER.build_chunk(first,context,{},exclusions)
	_check(first.get_child_count()==count and _layout(first)==layout,"reentry cannot duplicate decoration")
	for row in layout:
		var transform: Transform3D = row[1]
		var point := Vector2(transform.origin.x,transform.origin.z)
		_check(rect.has_point(point),"single chunk ownership")
		_check(not exclusions[0].has_point(point),"vehicle access stays empty")
		_check(point.distance_to(Vector2(19,28))>2,"door approach stays empty")
		_check(not Rect2(6,40,3,9).has_point(point),"no decoration in buildings")
		_check(absf(point.x-42)>6,"narrow sidewalks do not receive litter")
		var display: MultiMeshInstance3D = first.get_node("CityGroundLitter/"+row[0])
		var vertices: PackedVector3Array = display.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var world := transform*vertex
			_check(world.y>=.0109 and world.y<.03,"millimetres above the rendered floor")
			_check(absf(world.x-13)>3.75+.34,"whole footprint outside asphalt/curb")
			_check(absf(world.x-13)<3.75+2.625,"whole footprint on sidewalk")
	for display: MultiMeshInstance3D in first.get_node("CityGroundLitter").get_children():
		_check(display.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"no extra shadow pass")
		_check(display.material_override.transparency==BaseMaterial3D.TRANSPARENCY_DISABLED,"opaque material")
		_check(display.get_script()==null and not display.is_processing(),"no per-frame script")
		_check(display.multimesh.instance_count<=(LITTER.MAX_LEAVES if display.name=="Leaves" else LITTER.MAX_PAPERS),"finite instances per chunk")
	_check(first.find_children("*","CollisionObject3D",true,false).is_empty(),"decoration does not alter physical circulation")
	first.free()
	var reloaded := Node3D.new()
	root.add_child(reloaded)
	var job := LITTER.begin(reloaded,context,{},exclusions)
	var slices := 0
	while not bool(job.done) and slices<2000:
		LITTER.step(job,0.0)
		slices += 1
	_check(bool(job.done) and slices>1,"incremental generation finishes across slices")
	_check(_layout(reloaded)==layout,"unload/reload preserves transforms and colours")
	reloaded.free()
	# Denser long roads crossing a shared border: each origin belongs to exactly
	# one chunk, even when the same source segment supplies both chunks.
	var many: Array[Dictionary] = []
	for x in [8.0,22.0,36.0,50.0]:
		for variation in 3: many.append(_road("dense/%s/%d"%[x,variation],x))
	region.harbor_road_geometry.configure(many)
	context.roads = region.harbor_road_geometry._roads
	context.buildings = []
	region.entries = []
	var origins := {}
	var saturated := false
	for z in [0.0,64.0]:
		context.rect = Rect2(0,z,64,64)
		var chunk := Node3D.new()
		root.add_child(chunk)
		LITTER.build_chunk(chunk,context,{},[])
		var litter := chunk.get_node("CityGroundLitter")
		_check(int(litter.get_meta("leaves"))<=LITTER.MAX_LEAVES,"dense chunk stays within leaf budget")
		_check(int(litter.get_meta("papers"))<=LITTER.MAX_PAPERS,"dense chunk stays within paper budget")
		saturated = saturated or int(litter.get_meta("leaves"))==LITTER.MAX_LEAVES
		for row in _layout(chunk):
			var key := str(row[0])+str((row[1] as Transform3D).origin)
			_check(not origins.has(key),"adjacent chunks have no duplicate origins")
			origins[key] = true
		chunk.free()
	_check(saturated,"dense fixture exercises the hard limit")
	# No surface producer means no airborne fallback decoration.
	region.harbor_road_geometry.configure([],false)
	var empty := Node3D.new()
	root.add_child(empty)
	LITTER.build_chunk(empty,context,{},[])
	_check(empty.get_child_count()==0,"missing ground leaves chunk empty")
	empty.free()
	region.free()
	await _streamed_reload()
	print("%s GROUND_LITTER checks=%d failures=%d"%["PASS" if failures==0 else "FAIL",checks,failures])
	quit(0 if failures==0 else 1)


func _idle(region: Node3D) -> bool:
	var began := Time.get_ticks_msec()
	while not region.is_streaming_idle() and Time.get_ticks_msec()-began<30000:
		await process_frame
	return region.is_streaming_idle()


func _streamed_reload() -> void:
	var point := Vector3(86.7,.05,101.5)
	var region = REGION.build_region("harbor",point)
	root.add_child(region)
	_check(await _idle(region),"real initial streaming finishes")
	var key := Vector2i(1,1)
	if not region.chunks.has(key):
		_check(false,"real street chunk exists")
		region.free()
		return
	var original: Node3D = region.chunks[key]
	var layout := _layout(original)
	_check(layout.size()>0,"native production pipeline includes decoration")
	var old_root: WeakRef = weakref(original.get_node("CityGroundLitter"))
	region.set_focus(Vector3(600,.05,250))
	_check(await _idle(region),"streaming away finishes")
	for frame in 12: await process_frame
	_check(not region.chunks.has(key),"original chunk unloaded")
	_check(old_root.get_ref()==null,"decoration freed with original chunk")
	region.set_focus(point)
	_check(await _idle(region),"return streaming finishes")
	_check(region.chunks.has(key),"original street reloads")
	if region.chunks.has(key):
		_check(_layout(region.chunks[key])==layout,"real revisit preserves exact placement and colour")
	region.queue_free()
	for frame in 12: await process_frame
