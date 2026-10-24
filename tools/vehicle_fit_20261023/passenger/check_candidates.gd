extends SceneTree
## Scoped regression probe: front-face-aware rays test the formerly transparent
## exterior quarter, open roof crowns and wheel-well daylight paths.
const ROOT:="res://artifacts/vehicle-fit-20261023/passenger"
const ROLES:=preload("res://runtime/VehicleSurfaceRoles.gd")
const IDS:=["porto_rosso","beach_cabriolet","orbita_micro","vale_crossover"]
var failures: Array[String]=[]
var checks:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label); push_error(label)
func hit(model: Node3D,at: Vector3,dir: Vector3,role_filter:="") -> Dictionary:
	var nearest:=INF
	var result:={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or part.has_meta("wheel_center"): continue
		for surface in part.mesh.get_surface_count():
			var role:=ROLES.key(part,surface)
			if not role_filter.is_empty() and role!=role_filter: continue
			var arrays:=part.mesh.surface_get_arrays(surface)
			var p: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var n:=ix.size() if not ix.is_empty() else p.size()
			for first in range(0,n,3):
				var a:=part.transform*p[ix[first] if not ix.is_empty() else first]
				var b:=part.transform*p[ix[first+1] if not ix.is_empty() else first+1]
				var c:=part.transform*p[ix[first+2] if not ix.is_empty() else first+2]
				# Godot front faces use clockwise winding.
				if (b-a).cross(c-a).dot(dir)<=.0000001: continue
				var v=Geometry3D.ray_intersects_triangle(at,dir,a,b,c)
				if v==null or at.distance_to(v)>=nearest: continue
				nearest=at.distance_to(v)
				result={"point":v,"role":role}
	return result
func run() -> void:
	var report:={}
	var baseline:="--baseline" in OS.get_cmdline_user_args()
	for id: String in IDS:
		var path:="res://artifacts/vehicle-fit-20261023/baseline/assets/"+id+".scn" if baseline else ROOT+"/candidates/"+id+".scn"
		var model: Node3D=(load(path) as PackedScene).instantiate()
		var before:=checks
		var origins:=[]
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			if part.has_meta("wheel_center") and part.get_meta("wheel_spins",true):
				var center: Vector3=part.get_meta("wheel_center")
				var box: AABB=part.transform*part.mesh.get_aabb()
				var radius:=maxf(box.size.y,box.size.z)*.5
				origins.append({"center":center,"radius":radius})
		check(origins.size()==4,id+" retains four rolling wheel assemblies")
		for wheel: Dictionary in origins:
			var center: Vector3=wheel.center
			var side:=signf(center.x)
			var ray:=hit(model,Vector3(side*3,center.y+wheel.radius+.035,center.z),Vector3(-side,0,0))
			check(not ray.is_empty(),id+" wheel crown is backed by a front-facing solid: "+str(center))
		if id=="porto_rosso":
			for side: float in [-1.0,1.0]:
				for probe: Vector2 in [Vector2(.90,.65),Vector2(1.88,.43)]:
					var ray:=hit(model,Vector3(side*3,probe.y,probe.x),Vector3(-side,0,0),"paint")
					check(not ray.is_empty() and ray.point.x*side>.70,id+" rear quarter is visible on the approached side: "+str(Vector2(side,probe.x)))
		if id in ["orbita_micro","vale_crossover"]:
			var height:=1.48 if id=="orbita_micro" else 1.70
			var front:=-.56 if id=="orbita_micro" else -.66
			var rear:=1.04 if id=="orbita_micro" else 1.36
			for x: float in [-.32,0,.32]:
				for z: float in [front,rear]:
					var direction:=Vector3.BACK if z==front else Vector3.FORWARD
					var ray:=hit(model,Vector3(x,height+.025,z)-direction*.2,direction,"paint")
					check(not ray.is_empty() and absf(ray.point.z-z)<.02,id+" roof crown has an end closure: "+str(Vector2(x,z)))
		report[id]={"checks":checks-before}
		model.free()
	FileAccess.open(ROOT+("/baseline-checks.json" if baseline else "/candidate-checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"models":report},"\t"))
	print("PASSENGER_CANDIDATE_CHECKS ",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
