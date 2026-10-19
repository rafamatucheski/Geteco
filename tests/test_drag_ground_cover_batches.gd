extends "res://tests/tank_control/test_heavy_impacts.gd"
## Exact content equivalence, not a headless FPS test. The reference uses the
## same original generation rectangle with spatial partitioning disabled.
const COVER := preload("res://world/desert/DesertGroundCover.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const RELEASE := preload("res://runtime/GpuReleaseQueue.gd")
var totals := {"cells":0,"instances":0,"batches":0,"split_usec":0,"unsplit_usec":0,"max_slice_usec":0,"max_commit_slice_usec":0}

func run() -> void:
	if DisplayServer.get_name()=="headless":
		printerr("DRAG_GROUND_BATCHES requires the real renderer: dummy bulk MultiMesh readback returns identity transforms")
		quit(2)
		return
	create_timer(120).timeout.connect(func(): push_error("DRAG_GROUND_BATCHES timeout"); quit(3))
	world=Node3D.new()
	root.add_child(world)
	street=Street.new()
	world.add_child(street)
	Engine.set_meta("geteco_live_preview_build",true)
	for row in 2:
		for column in 13:
			var rect:=Rect2(COVER.DRAG_CORRIDOR.position+Vector2(column,row)*96.0,Vector2.ONE*96.0)
			await compare_cell(rect,column==4 and row==0,column==12 and row==1)
	var outside:=Node3D.new()
	world.add_child(outside)
	var outside_rect:=Rect2(-480,-864,96,96)
	var outside_state:=COVER.begin(outside_rect)
	check(outside_state.parts.is_empty(),"outside corridor retains original batching")
	COVER.step(outside,outside_rect,outside_state,flat,open,INF)
	var unchanged:=outside.get_child_count()==5
	for node: MultiMeshInstance3D in outside.get_children():
		var kind:=COVER.KINDS.find(str(node.name).split("_")[-1])
		unchanged=unchanged and node.material_override==COVER.material() and is_equal_approx(node.visibility_range_end,COVER.VISIBILITY[kind])
	check(unchanged,"outside corridor retains original materials and ranges")
	outside.free()
	FRAGILE.query(Vector3(-432,0,-816),80)
	check(FRAGILE.cells.is_empty(),"all discarded chunks leave no stale breakable entries after query")
	Engine.remove_meta("geteco_live_preview_build")
	# Let the real debris collision-grace timers expire before their scene exits.
	await create_timer(.4,false,true).timeout
	world.free()
	RELEASE.flush()
	await process_frame
	check(RELEASE.pending()==0,"GPU release queue is drained")
	print("DRAG_GROUND_BATCHES totals=",JSON.stringify(totals))
	print("DRAG_GROUND_BATCHES checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func flat(_point: Vector2) -> float: return 0.0
func open(_point: Vector2,_radius: float) -> bool: return true
func clear(point: Vector2,radius: float) -> bool:
	return LAYOUT.drag_reservation_clear(point,radius) and LAYOUT.road_clear(point,radius)

func compare_cell(rect: Rect2,exercise_hits: bool,retire: bool) -> void:
	var reference:=Node3D.new()
	var actual:=Node3D.new()
	world.add_child(reference)
	world.add_child(actual)
	var old_state:=COVER.begin(rect)
	old_state.parts.clear()
	var began:=Time.get_ticks_usec()
	COVER.step(reference,rect,old_state,flat,clear,INF)
	totals.unsplit_usec+=Time.get_ticks_usec()-began
	var expected:=rows(reference)
	var center:=Vector3(rect.get_center().x,0,rect.get_center().y)
	var expected_items:=items_for(reference,center)
	var expected_solids:=solid_rows(expected_items)
	expected_items.clear()
	reference.free()
	FRAGILE.query(center,80)
	var state:=COVER.begin(rect)
	began=Time.get_ticks_usec()
	while not state.committed:
		var committing:=state.next==state.cells.size()
		var slice_start:=Time.get_ticks_usec()
		COVER.step(actual,rect,state,flat,clear,1000)
		var elapsed:=Time.get_ticks_usec()-slice_start
		totals.max_slice_usec=maxi(totals.max_slice_usec,elapsed)
		if committing: totals.max_commit_slice_usec=maxi(totals.max_commit_slice_usec,elapsed)
	totals.split_usec+=Time.get_ticks_usec()-began
	var actual_rows:=rows(actual)
	check(expected==actual_rows,"all transform/colour bytes preserved in cell %s"%rect.position)
	var items:=items_for(actual,center)
	check(expected_solids==solid_rows(items),"same breakable positions and local transforms in cell %s"%rect.position)
	var indexed:=true
	for item in items:
		var visual=item.visual.get_ref()
		indexed=indexed and is_instance_valid(visual) and visual.multimesh==item.multimesh and item.index<item.multimesh.instance_count and item.multimesh.get_instance_transform(item.index)==item.base
	check(indexed,"every breakable index addresses its new visual in cell %s"%rect.position)
	var bounded:=true
	var preview_matches:=true
	var count:=0
	var visual_refs: Array[WeakRef]=[]
	for node: MultiMeshInstance3D in actual.get_children():
		visual_refs.append(weakref(node))
		var batch:=node.multimesh
		var bounds:=batch.custom_aabb
		var material:=node.material_override as StandardMaterial3D
		var kind:=COVER.KINDS.find(str(node.name).split("_")[-1])
		bounded=bounded and bounds.has_volume() and bounds.size.x<51 and bounds.size.z<51 and material==COVER._drag_material(kind) and node.visibility_range_end+0.0001>=material.distance_fade_min_distance+bounds.size.length()*.5+2.0
		count+=batch.instance_count
		var preview: Array=node.get_meta("preview_instance_transforms",[])
		var colors: Array=node.get_meta("preview_instance_colors",[])
		preview_matches=preview_matches and preview.size()==batch.instance_count and colors.size()==batch.instance_count
		for index in batch.instance_count:
			var transform:=batch.get_instance_transform(index)
			var geometry: AABB=transform*batch.mesh.get_aabb()
			bounded=bounded and bounds.grow(.001).encloses(geometry)
			preview_matches=preview_matches and transform.is_equal_approx(preview[index]) and batch.get_instance_color(index).is_equal_approx(colors[index])
	check(bounded,"every new lot has real enclosing AABB and fade + radius + 2 m margin in cell %s"%rect.position)
	check(preview_matches,"editor preview transforms and colours retain remapped order in cell %s"%rect.position)
	totals.cells+=1
	totals.instances+=count
	totals.batches+=actual.get_child_count()
	if exercise_hits:
		for part in 4:
			for kind in ["desert_shrub","desert_stone"]:
				var candidates:=items.filter(func(item): return item.kind==kind and str(item.visual.get_ref().name).begins_with("DesertGroundCover_%d_"%part) and item.state=="standing")
				check(not candidates.is_empty(),"part %d includes %s contact"%[part,kind])
				if candidates.is_empty(): continue
				var item: Dictionary=candidates[0]
				var vehicle:=car(1.0)
				vehicle.position=item.point+Vector3(0,0,6)
				CRUSH.set_planar(vehicle,Vector3.FORWARD*20)
				var before:=street.get_child_count()
				# Isolate this indexed contact from neighbouring shrubs. The real car
				# sweep and FragileProps hit/debris path remain unchanged.
				var registry: Dictionary=FRAGILE.cells
				FRAGILE.cells={FRAGILE._key(item.point):[item]}
				street._hit_props(vehicle,vehicle.horizontal_velocity,Vector3.FORWARD*10)
				FRAGILE.cells=registry
				# Rendering and physics interpolation consume the update across ticks.
				for frame in 2: await physics_frame
				await RenderingServer.frame_post_draw
				if item.state!="down" or not is_zero_approx(item.multimesh.get_instance_transform(item.index).basis.determinant()): print("DRAG_BATCH_IMPACT ",part," ",kind," state=",item.state," transform=",item.multimesh.get_instance_transform(item.index)," expected_base=",item.base)
				check(item.state=="down" and is_zero_approx(item.multimesh.get_instance_transform(item.index).basis.determinant()),"part %d %s impact hides exactly its indexed original"%[part,kind])
				check(street.get_child_count()>before,"part %d %s impact creates physical debris"%[part,kind])
				vehicle.free()
	items.clear()
	if retire:
		RELEASE.retire(actual)
		check(FRAGILE.query(center,80).is_empty(),"retired batch stops participating in contact immediately")
		for frame in 4: await process_frame
		RELEASE.flush()
		await process_frame
	else: actual.free()
	FRAGILE.query(center,80)
	check(visual_refs.all(func(ref): return not is_instance_valid(ref.get_ref())),"all subdivided visual nodes release in cell %s"%rect.position)

func rows(chunk: Node3D) -> Dictionary:
	var result: Dictionary={}
	for node: MultiMeshInstance3D in chunk.get_children():
		var kind: String=str(node.name).split("_")[-1]
		if not result.has(kind): result[kind]=[]
		var buffer:=node.multimesh.buffer
		for index in node.multimesh.instance_count: result[kind].append(buffer.slice(index*16,index*16+16).to_byte_array().hex_encode())
	for list: Array in result.values(): list.sort()
	return result

func items_for(chunk: Node3D,point: Vector3) -> Array:
	return FRAGILE.query(point,80).filter(func(item): return item.chunk.get_ref()==chunk)

func solid_rows(items: Array) -> Array[String]:
	var result: Array[String]=[]
	for item in items: result.append(item.kind+"|"+var_to_bytes(item.base).hex_encode()+"|"+str(item.point))
	result.sort()
	return result
