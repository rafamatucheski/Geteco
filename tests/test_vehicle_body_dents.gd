extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const DENTS := preload("res://gameplay/vehicle_effects/VehicleBodyDents.gd")
const FLEET := preload("res://runtime/FleetState.gd")
var failures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	if not value: failures.append(label); push_error(label)
func run() -> void:
	for id in ["metro_hatch","sport_coupe","police_cruiser","desert_mirage","jessica_jetta_gli"]:
		var car:=VEHICLE.new()
		car.archetype=id
		root.add_child(car)
		car.set_physics_process(false)
		var originals: Dictionary={}
		for part in car.visual.find_children("*","MeshInstance3D",true,false): originals[part]=part.mesh
		car.receive_impact(18,Vector3(car.half_width*.65,.6,-car.half_length))
		check(car.body_dents.dents.size()==1,id+" records contact")
		check(not car.body_dents.parts.is_empty(),id+" eligible body surfaces")
		var changed:=0
		var displacement:=0.0
		var normal_dot:=0.0
		var normal_count:=0
		for entry in car.body_dents.parts:
			if entry.node.mesh!=entry.mesh: changed+=1
			for surface in entry.arrays.size():
				var rest: PackedVector3Array=entry.arrays[surface][Mesh.ARRAY_VERTEX]
				var dented: PackedVector3Array=entry.node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				var old_normals: PackedVector3Array=entry.arrays[surface][Mesh.ARRAY_NORMAL]
				var new_normals: PackedVector3Array=entry.node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_NORMAL]
				for index in rest.size():
					var distance: float=(entry.transform*rest[index]).distance_to(entry.transform*dented[index])
					displacement=maxf(displacement,distance)
					if not entry.eligible[surface]: check(distance<.00001,id+" unpainted surface unchanged")
					if (entry.transform*rest[index]).y>car.body_height*.82: check(distance<.00001,id+" roof/cabin stable")
					if old_normals.size()==rest.size() and new_normals.size()==rest.size():
						normal_dot+=old_normals[index].dot(new_normals[index]); normal_count+=1
		check(normal_count>0 and normal_dot/normal_count>.5,id+" normals face outward")
		for part in originals:
			if "wheel" in str(part.name).to_lower(): check(part.mesh==originals[part],id+" wheels unchanged")
		check(changed>0 and displacement>.02,id+" actual localized shape change")
		print("DENTS_MODEL ",id," meshes=",changed," max_displacement=",displacement," rebuild_us=",car.body_dents.rebuild_usec)
		var record:=FLEET.capture(car,"harbor")
		check(FLEET.validate(record),id+" fleet validates dents")
		var snapshot: Array=car.body_dents.snapshot()
		car.repair()
		for part in originals: check(part.mesh==originals[part],id+" repair restores exact mesh")
		check(car.body_dents.dents.is_empty() and not car.body_dents.is_processing(),id+" repair clears state/recoil")
		var path:="user://dents-test-"+str(OS.get_process_id())+".json"
		var file:=FileAccess.open(path,FileAccess.WRITE)
		file.store_string(JSON.stringify(record)); file.close()
		var loaded: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
		DirAccess.remove_absolute(path)
		car.restore_body_dents(loaded.body_dents)
		check(car.body_dents.dents.size()==snapshot.size() and absf(car.body_dents.dents[0].depth-snapshot[0].depth)<.000001,id+" disk round trip")
		for i in 20: car.receive_impact(2,Vector3(car.half_width*.65,.6,-car.half_length))
		check(car.body_dents.dents.size()==1 and car.body_dents.dents[0].depth<=DENTS.MAX_DEPTH,id+" repeated contact stays bounded")
		var before: Array=car.body_dents.snapshot()
		car.receive_impact(INF,Vector3.ZERO)
		car.receive_impact(10,Vector3(NAN,0,0))
		check(car.body_dents.snapshot()==before,id+" invalid impact ignored")
		car.set_meta("invulnerable",true)
		# DamageProtection recognizes group/ancestor metadata; use its public contract.
		car.add_to_group("damage_protected")
		car.receive_impact(10,Vector3(car.half_width,.5,0))
		check(car.body_dents.snapshot()==before,id+" protected vehicle unchanged")
		car.remove_meta("invulnerable")
		car.controlled=true
		car.receive_impact(10,Vector3(car.half_width,.5,0))
		await process_frame
		await process_frame
		car.repair()
		check(car.visual.position==Vector3.ZERO and car.visual.rotation.x==0 and car.visual.rotation.z==0,id+" repair during recoil stays upright")
		# Damaged NPC -> prepare doors -> another collision -> repair. Door cuts
		# must survive both rebuild and repair without duplicated closed panels.
		car.controlled=false
		car.receive_impact(18,Vector3(car.half_width,.55,0))
		car.finish_doors()
		check(car.door_presentation.ready_for_boarding,id+" damaged car prepares doors")
		var topology: Dictionary={}
		for entry in car.body_dents.parts: topology[entry.node]=entry.mesh
		car.receive_impact(10,Vector3(.6,.6,-car.half_length))
		car.repair()
		for part in topology: check(part.mesh==topology[part],id+" repair preserves door topology")
		car.queue_free()
		await process_frame
	check(not DENTS.valid_records([{"point":[0,0,0],"direction":[0,0,0],"radius":1,"depth":.1}]),"invalid direction rejected")
	check(DENTS.valid_records([]),"legacy saves have no dents")
	print("BODY_DENTS failures=",failures)
	quit(0 if failures.is_empty() else 1)
