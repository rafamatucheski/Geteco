extends SceneTree
const FLEET=preload("res://runtime/FleetCatalog.gd")
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
const IDS=["porto_rosso","beach_cabriolet","orbita_micro","vale_crossover"]
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var report:={}
	for id: String in IDS:
		var model:=FLEET.create(id)
		var parts:=[]
		var meta:={}
		for key in model.get_meta_list(): meta[str(key)]=str(model.get_meta(key))
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var surfaces:=[]
			for s in part.mesh.get_surface_count():
				var arrays:=part.mesh.surface_get_arrays(s)
				var points:=[]
				for p: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					var v:=part.transform*p
					points.append([v.x,v.y,v.z])
				var indices:Array=Array(arrays[Mesh.ARRAY_INDEX]) if arrays[Mesh.ARRAY_INDEX]!=null else []
				var m:=part.get_active_material(s) as StandardMaterial3D
				surfaces.append({"role":ROLES.key(part,s),"points":points,"indices":indices,"material":m.resource_name if m else "","cull":m.cull_mode if m else -1})
			var pm:={}
			for key in part.get_meta_list(): pm[str(key)]=str(part.get_meta(key))
			parts.append({"name":str(part.name),"metadata":pm,"surfaces":surfaces})
		report[id]={"metadata":meta,"parts":parts}
		model.free()
	var folder:="res://artifacts/vehicle-fit-20261023/passenger"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder+"/geometry.json",FileAccess.WRITE).store_string(JSON.stringify(report))
	quit()
