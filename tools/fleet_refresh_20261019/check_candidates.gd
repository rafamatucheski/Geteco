extends SceneTree
## Offline candidate audit, complementary to production door/driver/gameplay tests.
const BUILD=preload("res://tools/fleet_refresh_20261019/build_current.gd")
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
var failures: Array[String]=[]
var checks:=0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)

func wheels(model: Node3D) -> Dictionary:
	var result:={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if not part.has_meta("wheel_center") or not bool(part.get_meta("wheel_spins",true)): continue
		var center: Vector3=part.get_meta("wheel_center")
		var box: AABB=part.transform*part.mesh.get_aabb()
		result[center]=box if not result.has(center) else (result[center] as AABB).merge(box)
	return result

func glass(model: Node3D) -> AABB:
	var bounds:=AABB()
	var initialized:=false
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null: continue
		for surface in part.mesh.get_surface_count():
			if ROLES.key(part,surface) not in ["glass","tinted_glass","windshield","window"]: continue
			for p: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var v:=part.transform*p
				bounds=bounds.expand(v) if initialized else AABB(v,Vector3.ZERO)
				initialized=true
	return bounds

func semantic_counts(model: Node3D) -> Dictionary:
	var result:={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or part.has_meta("wheel_center"): continue
		for surface in part.mesh.get_surface_count():
			var role: String=ROLES.key(part,surface)
			var semantic:=role=="paint" or "glass" in role or ROLES.is_tail_lens(role) or ROLES.is_headlight_lens(role)
			if not semantic: continue
			var arrays:=part.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count: int=indices.size() if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()
			result[role]=int(result.get(role,0))+count/3
	return result

func run() -> void:
	var report:={}
	var ids: Array=BUILD.FAMILIES.keys()
	var label:="current-checks"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="): ids=Array(arg.trim_prefix("--ids=").split(","))
		if arg.begins_with("--label="): label=arg.trim_prefix("--label=").validate_filename()
	for id: String in ids:
		var before: Node3D=(load(BUILD.ORIGINALS+"/"+id+".scn") as PackedScene).instantiate()
		var after: Node3D=(load(BUILD.OUT+"/"+id+".scn") as PackedScene).instantiate()
		var original: Dictionary=MESH.counts(before)
		var candidate: Dictionary=MESH.counts(after)
		check(candidate.triangles<original.triangles,id+": triangles must decrease")
		check(candidate.meshes<=original.meshes,id+": mesh budget")
		check(candidate.surfaces<=original.surfaces,id+": surface budget")
		for part: MeshInstance3D in after.find_children("*","MeshInstance3D",true,false):
			if part.mesh==null: continue
			var canonical: Array=part.get_meta("batch_surface_material_keys",[])
			for key in part.get_meta_list():
				if str(key).ends_with("surface_material_keys") or str(key).ends_with("surface_material_roles"):
					check(part.get_meta(key).size()==part.mesh.get_surface_count(),id+": every material role array covers all surfaces")
					check(part.get_meta(key)==canonical,id+": material role aliases use the final surface order")
		var old_wheels:=wheels(before)
		var new_wheels:=wheels(after)
		check(old_wheels.size()==4 and new_wheels.size()==4,id+": four independent wheels")
		for center: Vector3 in old_wheels:
			check(new_wheels.has(center),id+": unchanged wheel pivot "+str(center))
			if not new_wheels.has(center): continue
			var old: AABB=old_wheels[center]
			var fresh: AABB=new_wheels[center]
			check(absf(old.position.y-fresh.position.y)<.0002,id+": tire ground contact")
			check(absf(old.size.y-fresh.size.y)<.0002 and absf(old.size.z-fresh.size.z)<.0002,id+": tire radius")
		check(semantic_counts(before)==semantic_counts(after),id+": preserve body/door/glass/lens topology")
		check(after.find_children("*","Light3D",true,false).size()==before.find_children("*","Light3D",true,false).size(),id+": no new lights")
		var old_glass:=glass(before)
		var new_glass:=glass(after)
		if id=="sedan_classic": check(new_glass.end.y>old_glass.end.y+.05,id+": taller popular cabin")
		if id=="aurora_executive": check(new_glass.end.y<old_glass.end.y-.05,id+": lower executive cabin")
		if id in ["desert_faisca","desert_faisca_rally"]: check(new_glass.end.y<old_glass.end.y-.04,id+": sport hatch roof")
		var cabin: Dictionary=after.get_meta("vehicle_interior_spec",{})
		if cabin.has("roof"):
			check(float(cabin.roof)<=new_glass.end.y+.05,id+": driver cabin roof follows glazing")
			check(float(cabin.rear_top)<=float(cabin.rear),id+": rear cabin taper")
		report[id]={"before":original,"after":candidate,"glass_before":str(old_glass),"glass_after":str(new_glass)}
		before.free()
		after.free()
	var result:={"checks":checks,"failures":failures,"models":report}
	var file:=FileAccess.open(BUILD.OUT+"/"+label+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("FLEET_REFRESH_CANDIDATES ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
