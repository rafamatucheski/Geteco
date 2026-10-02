extends SceneTree
## Roof closure protects the demonstrated split-roof regression.
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func run() -> void:
	for id in ["PorchHouse","Duplex","ShingleHouse","CobraWorkshop","CourtyardHouse","BrickDuplex","TinRoofHouse","CornerBungalow"]:
		var house := preload("res://world/urban_detail/UrbanCobraHouse.gd").new()
		house.setup({"id":id,"kind":"cobra_house","size":Vector2(14,12),"color":"72594b"})
		root.add_child(house)
		var front := house.find_child("RoofFrontSlope",true,false) as MeshInstance3D
		var rear := house.find_child("RoofRearSlope",true,false) as MeshInstance3D
		var front_peak := front.to_global(Vector3(0,0,-front.mesh.size.z*.5))
		var rear_peak := rear.to_global(Vector3(0,0,rear.mesh.size.z*.5))
		check(front_peak.distance_to(rear_peak)<.01,id+": both slopes meet at the ridge")
		check(front_peak.y>front.global_position.y and rear_peak.y>rear.global_position.y,id+": roof drains toward both eaves")
		check(front.material_override.albedo_texture!=null and rear.material_override.albedo_texture!=null,id+": textured roof surfaces")
		check(preload("res://world/city_look/CityChunkDressing.gd")._roof_slabs(house).is_empty(),id+": no generic flat slab through pitched roof")
		house.free()
	print("COBRA_ROOF checks=32 failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
