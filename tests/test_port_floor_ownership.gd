extends "res://tests/measure/audit_territory_ground.gd"
## Integrated render-face census plus physical support across both boarding routes.
func run() -> void:
	var region = NATIVE.build_region("harbor")
	region.initial_prewarm_only=true
	root.add_child(region)
	region.set_process(false)
	region.prepare_data()
	port_only=true
	for x in range(2,7):
		for z in range(0,6):
			var key := Vector2i(x,z)
			region._build_chunk(key)
			scan(region.chunks[key])
	var findings := result()
	var failures := 0
	var redundant_area := 0.0
	for pair in findings.pairs:
		var a: String=pair.a.label
		var b: String=pair.b.label
		if ("SantaMarePaintedDeck" in a or "SantaMarePaintedDeck" in b) and "BatchedSteel" not in a and "BatchedSteel" not in b:
			redundant_area+=pair.area_m2
		if a in ["NorthstarDeck","NorthstarGangway"] and b in ["NorthstarDeck","NorthstarGangway"]:
			redundant_area+=pair.area_m2
	if redundant_area>0:
		push_error("Port deck/base or boarding overlap remains: %s m2"%redundant_area)
		failures+=1
	await physics_frame
	await physics_frame
	var supports: Array=[]
	for point in [Vector3(288,0,186),Vector3(250,0,190),Vector3(204,0,110),Vector3(210.74,0,110),Vector3(210.76,0,110)]:
		var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.15,point-Vector3.UP*.5,1)
		var hit:=region.get_world_3d().direct_space_state.intersect_ray(query)
		var supported: bool=not hit.is_empty() and absf(hit.position.y)<.035
		supports.append({"point":str(point),"supported":supported})
		if not supported:
			push_error("Boarding support missing at %s"%point)
			failures+=1
	findings["support_checks"]=supports
	findings["target_redundant_area_m2"]=redundant_area
	findings["failures"]=failures
	DirAccess.make_dir_recursive_absolute("res://evidence/port-floor-fix-20261014")
	FileAccess.open("res://evidence/port-floor-fix-20261014/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(findings,"\t"))
	print("PORT_FLOOR_OWNERSHIP failures=",failures," overlap_m2=",redundant_area)
	region.free()
	quit(0 if failures==0 else 1)
