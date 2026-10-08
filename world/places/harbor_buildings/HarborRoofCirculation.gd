extends RefCounted
## Shared physical clearance for the roof stair, cache and guarded jump bay.
## Dressing keeps its detail budget, placing props around these walking lanes.
static func occupied(building: Node3D) -> Array:
	var access := building.get_node_or_null("BuildingAccess")
	var definition: Dictionary = access.definition if access!=null else {}
	if definition.is_empty() and building is UrbanBuildingBase:
		definition = load("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd").for_source(building.building_id)
	if definition.is_empty(): return []
	var size: Vector2 = definition.size
	var stair := Vector3(-size.x*.5+1.45,0,1.45)
	var cache: Vector3 = definition.get("roof_cache_position",Vector3(size.x*.26,0,size.y*.22))
	cache.y = 0.0
	var jump := Vector3(float(definition.get("jump_x",maxf(.7,size.x*.5-2.0))),0,size.y*.5-.88)
	var local_to_building: Transform3D = building.global_transform.affine_inverse()*Transform3D(Basis(Vector3.UP,float(definition.exterior_rotation)),definition.exterior_position)
	var paths := [
		[stair,Vector3(jump.x,0,stair.z)],
		[Vector3(cache.x,0,stair.z),cache],
		[Vector3(jump.x,0,stair.z),jump],
	]
	var result := []
	for path in paths:
		var a: Vector3 = path[0]
		var b: Vector3 = path[1]
		var steps := maxi(1,ceili(a.distance_to(b)/.8))
		for index in steps+1:
			var point: Vector3 = local_to_building*a.lerp(b,float(index)/steps)
			result.append({"point":Vector2(point.x,point.z),"radius":.65})
	# The stair bulkhead and its landing are authored architecture on the roof.
	var bulkhead: Vector3 = local_to_building*(stair+Vector3(0,0,-1.25))
	result.append({"point":Vector2(bulkhead.x,bulkhead.z),"radius":1.45})
	return result
