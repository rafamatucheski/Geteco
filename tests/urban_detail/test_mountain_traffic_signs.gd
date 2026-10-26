extends SceneTree
const REGION := preload("res://world/regions/NativeRegion.gd")
const SIGNS := preload("res://world/mountain_detail/MountainTrafficSigns.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const ROADSIDE := preload("res://world/mountain_detail/MountainRoadside3D.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if ok: print("PASS: ",message)
	else: failures += 1; push_error(message)
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var hash_before := DATA.disk_hash()
	var region = REGION.build_region("mountain")
	region.prepare_data()
	var signs := SIGNS.new()
	signs.configure(region)
	check(not signs.records.is_empty(),"Resident mountain roads receive traffic signs")
	var kinds := {}
	var clear := true
	var paths_clear := true
	var fronts := true
	var entries_clear := true
	for row in signs.records:
		kinds[row.kind] = int(kinds.get(row.kind,0))+1
		clear = clear and not region.route_geometry.contains(row.position,1.85)
		fronts = fronts and row.basis.determinant()>.99 and absf(row.basis.z.y)<.001
		for path: Dictionary in region.walkways:
			for i in range(path.points.size()-1):
				var a: Vector3 = path.points[i]
				var b: Vector3 = path.points[i+1]
				var at := Vector2(row.position.x,row.position.z)
				paths_clear = paths_clear and at.distance_to(Geometry2D.get_closest_point_to_segment(at,Vector2(a.x,a.z),Vector2(b.x,b.z))) >= float(path.width)*.5+1.2
		for entry: Dictionary in region.entries:
			var at: Vector3 = entry.get("entry_position",entry.get("position",Vector3.INF))
			entries_clear = entries_clear and Vector2(at.x,at.z).distance_to(Vector2(row.position.x,row.position.z))>=6
	for kind in ["curve_left","curve_right","chevron_left","chevron_right","destination"]:
		check(int(kinds.get(kind,0))>0,"Actual route includes "+kind)
	check(clear,"All posts clear road edges and walking shoulders")
	check(paths_clear,"Cave, village and activity paths remain unobstructed")
	check(entries_clear,"No signs occupy entrance thresholds")
	check(fronts,"Sign fronts remain upright without mirrored transforms")
	var holder := Node3D.new()
	root.add_child(holder)
	signs.build(holder)
	await physics_frame
	await physics_frame
	check(holder.get_child_count()>1,"Signs are batched in multiple bounded spatial cells")
	check(holder.find_children("*","Light3D",true,false).is_empty(),"No additional real lights")
	var collision_ok := true
	for row in signs.records:
		var at: Vector3 = row.position+Vector3.UP
		var query := PhysicsRayQueryParameters3D.create(at-row.basis.x*.2,at+row.basis.x*.2,1)
		collision_ok = collision_ok and not root.world_3d.direct_space_state.intersect_ray(query).is_empty()
	check(collision_ok,"Every physical signpost has a matching solid")
	var count := signs.records.size()
	signs.configure(region)
	check(signs.records.size()==count,"Rebuilding the region does not duplicate signs")
	check(DATA.disk_hash()==hash_before,"Saved map remains unchanged")
	var roadside := ROADSIDE.new()
	root.add_child(roadside)
	roadside.set_process(false)
	roadside._build_traffic_signs(region)
	check(roadside.find_child("MountainTrafficSigns",false,false)!=null,"Roadside runtime mounts the signs")
	roadside._process_traced(.5)
	await process_frame
	check(roadside.find_child("MountainTrafficSigns",false,false)==null,"Region unload removes sign visuals and physical posts")
	print("MOUNTAIN_SIGNS checks=",checks," failures=",failures," signs=",count," kinds=",kinds)
	roadside.free()
	holder.free()
	region.free()
	quit(0 if failures==0 else 1)
