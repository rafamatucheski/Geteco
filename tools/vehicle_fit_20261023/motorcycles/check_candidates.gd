extends SceneTree
const OUT="res://artifacts/vehicle-fit-20261023/motorcycles/"
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func anchors(model: Node3D) -> Array:
	var result:=[]
	for part in model.get_children():
		if part.has_meta("wheel_center") and bool(part.get_meta("wheel_spins",false)): result.append(part.get_meta("wheel_center"))
	result.sort_custom(func(a,b): return a.z<b.z)
	return result
func lenses(model: Node3D) -> Dictionary:
	var result:={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		for i in part.mesh.get_surface_count():
			var role:=ROLES.key(part,i)
			if not (ROLES.is_headlight_lens(role) or ROLES.is_tail_lens(role) or role=="lens"): continue
			var mat:=part.get_active_material(i) as StandardMaterial3D
			var arrays:=part.mesh.surface_get_arrays(i)
			result[role+str((part.transform*surface_bounds(arrays)).get_center())]={"bounds":str(part.transform*surface_bounds(arrays)),"vertices":arrays[Mesh.ARRAY_VERTEX].size(),"emission":mat.emission_enabled,"energy":mat.emission_energy_multiplier,"albedo":mat.albedo_color.to_html()}
	return result
func surface_bounds(arrays: Array) -> AABB:
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var box:=AABB(points[0],Vector3.ZERO)
	for p: Vector3 in points: box=box.expand(p)
	return box
func run() -> void:
	for id: String in ["bike_sport","bike_cruiser","bike_urban"]:
		var before: Node3D=(load(OUT+"originals/"+id+".scn") as PackedScene).instantiate()
		var after: Node3D=(load(OUT+id+".scn") as PackedScene).instantiate()
		check(anchors(before)==anchors(after),id+" exact rolling wheel pivots")
		check(before.get_meta("motorcycle_seat")==after.get_meta("motorcycle_seat"),id+" exact rider seat")
		check(lenses(before)==lenses(after),id+" exact lens bounds, vertices, emission and colour")
		var bc:=MESH.counts(before); var ac:=MESH.counts(after)
		check(ac.meshes<bc.meshes and ac.triangles<bc.triangles,id+" reduced meshes and triangles")
		for side: String in ["Left","Right"]:
			var old: MeshInstance3D=before.get_node("MotorcycleGrip"+side)
			var fresh: MeshInstance3D=after.get_node("MotorcycleGrip"+side)
			check(old.get_aabb()==fresh.get_aabb() and old.get_meta("wheel_center")==fresh.get_meta("wheel_center"),id+" exact "+side+" grip and steering pivot")
		var body:=after.get_node("Body") as MeshInstance3D
		check(body.get_aabb().position.y>.20 and after.get_meta("motorcycle_stand_stowed",false),id+" stand stowed above ground against frame")
		if id=="bike_sport":
			var shell_height: float=-INF
			for surface in body.mesh.get_surface_count():
				if ROLES.key(body,surface)!="paint": continue
				var isolated:=ArrayMesh.new(); isolated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,body.mesh.surface_get_arrays(surface))
				var faces:=isolated.get_faces()
				for first in range(0,faces.size(),3):
					var hit=Geometry3D.ray_intersects_triangle(Vector3(0,1.3,-.16),Vector3.DOWN,faces[first],faces[first+1],faces[first+2])
					if hit!=null: shell_height=maxf(shell_height,hit.y)
			check(shell_height>1.052 and shell_height<1.073,"sport filler cap cylinder intersects actual tank skin (skin y="+str(shell_height)+", cap base1.052/top1.073)")

		for i in body.mesh.get_surface_count():
			var arrays:=body.mesh.surface_get_arrays(i)
			for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				if not p.is_finite(): check(false,id+" finite geometry"); break
		before.free(); after.free()
	print("MOTORCYCLE_FIT_CONTRACTS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
