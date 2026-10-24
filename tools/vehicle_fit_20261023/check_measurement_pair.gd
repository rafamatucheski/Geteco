extends "res://tools/vehicle_fit_20261023/measure_integrated.gd"
## Check measurement fixture parity before spending a rendered ABBA block.
## Does not certify visuals or FPS.
func run() -> void:
	world=Node3D.new()
	root.add_child(world)
	var errors: Array[String]=[]
	var rows:=[]
	for id: String in BASE_IDS:
		var body:=BENCH_VEHICLE.new()
		body.archetype=id
		body.vehicle_id="fit_pair_fixture_"+id
		body.paint_color=Color("ad4238")
		body.process_mode=Node.PROCESS_MODE_DISABLED
		world.add_child(body)
		if not id.begins_with("bike_"): body.finish_doors()
		var path: String="res://artifacts/vehicle-fit-20261023/baseline/assets/"+id+".scn"
		var before:=create_ready_baseline(body,path)
		if before==null:
			errors.append(id+": missing prepared baseline")
			body.free()
			continue
		var current:=FLEET_REFRESH.create(id)
		var counts:=mesh_metrics(current)
		var candidate: Node3D=(load("res://assets/fleet/redesigned/"+id+".scn") as PackedScene).instantiate()
		if counts!=mesh_metrics(candidate): errors.append(id+": temporary factory source was not restored")
		if not before.transform.is_equal_approx(body.visual.transform): errors.append(id+": model placement differs")
		if before.find_children("*","MeshInstance3D",true,false).size()==0: errors.append(id+": empty baseline")
		rows.append({"id":id,"ready_baseline":mesh_metrics(before),"ready_final":mesh_metrics(body.visual),"restored_factory":counts})
		current.free(); candidate.free(); body.free()
		await process_frame
	var path:="res://artifacts/vehicle-fit-20261023/pair-preflight.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify({"ok":errors.is_empty(),"errors":errors,"rows":rows},"\t"))
	print("VEHICLE_PAIR_PREFLIGHT vehicles=",rows.size()," errors=",errors)
	world.free()
	quit(0 if errors.is_empty() else 1)
