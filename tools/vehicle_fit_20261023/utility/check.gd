extends SceneTree
const OUT="res://artifacts/vehicle-fit-20261023/utility"
const IDS=["ranch_pickup","ranch_single","boxrunner","toco_minitruck"]
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func hits(model:Node3D,origin:Vector3,direction:Vector3)->bool:
	var body:MeshInstance3D=model.get_node("Body")
	var faces:=body.mesh.get_faces()
	for i in range(0,faces.size(),3):
		var hit:Variant=Geometry3D.ray_intersects_triangle(origin,direction,faces[i],faces[i+1],faces[i+2])
		if hit!=null and (hit as Vector3).distance_to(origin)<.3:return true
	return false
func run()->void:
	for id:String in IDS:
		var before:Node3D=(load(OUT+"/originals/"+id+".scn") as PackedScene).instantiate()
		var after:Node3D=(load(OUT+"/candidates/"+id+".scn") as PackedScene).instantiate()
		check(before.get_child_count()==after.get_child_count(),id+" no additional runtime nodes")
		for key:StringName in before.get_meta_list():check(after.get_meta(key)==before.get_meta(key),id+" retains root metadata "+str(key))
		for source:MeshInstance3D in before.find_children("*","MeshInstance3D",true,false):
			var target:MeshInstance3D=after.get_node(str(source.name))
			check(target!=null,id+" retains "+str(source.name))
			check(target.transform.is_equal_approx(source.transform),id+" transforms "+str(source.name))
			check(target.mesh.get_surface_count()==source.mesh.get_surface_count(),id+" draw surface budget "+str(source.name))
			for key:StringName in source.get_meta_list():check(target.get_meta(key)==source.get_meta(key),id+" retains part metadata "+str(key))
			for s in source.mesh.get_surface_count():
				check(ROLES.key(source,s)==ROLES.key(target,s),id+" semantic material "+str(s))
				var a:Material=source.get_active_material(s);var b:Material=target.get_active_material(s)
				if a is StandardMaterial3D and b is StandardMaterial3D:
					check(a.albedo_color.is_equal_approx(b.albedo_color) and a.emission_enabled==b.emission_enabled,id+" keeps paint/lens state")
			if source.has_meta("wheel_center"):
				var a:=source.mesh.get_faces();var b:=target.mesh.get_faces()
				var same:=a.size()==b.size()
				if same:
					for i in a.size():
						if not a[i].is_equal_approx(b[i]):same=false;break
				check(same,id+" wheel geometry/contact/steering clearance "+str(source.name))
		if id in ["ranch_pickup","ranch_single"]:
			check(not hits(before,Vector3(0,.985,.50),Vector3.FORWARD),id+" baseline reproduces gap beneath rear window")
			check(hits(after,Vector3(0,.985,.50),Vector3.FORWARD),id+" closed rear cabin beneath window")
		elif id=="toco_minitruck":
			check(hits(after,Vector3(0,.95,-.30),Vector3.FORWARD),id+" closed rear cabin")
		elif id=="boxrunner":
			var body:MeshInstance3D=after.get_node("Body")
			var arrays:=body.mesh.surface_get_arrays(1)
			check((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()==18,"Boxrunner glass is three panes, not overlapping boxes")
		before.free();after.free()
	print("UTILITY_FIT_CHECKS checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
