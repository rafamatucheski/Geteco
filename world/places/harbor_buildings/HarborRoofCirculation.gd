extends RefCounted
## Shared physical clearance for the roof stair, cache and guarded jump bay.
## Dressing keeps its detail budget, placing props around these walking lanes.
## Casinha da escada: centro em relação ao patamar e tamanho da que se monta ao subir
## (a do enfeite, BuildingLifeKit._roof_shed, tem 2,0 × 2,0 × 1,6 e cabe dentro dela).
const HOUSE_OFFSET := Vector3(0,0,-1.65)
const HOUSE_SIZE := Vector3(2.08,2.08,1.68)

## Definição do telhado caminhável do prédio (interior do catálogo ou telhado de serviço).
static func definition_for(building: Node3D) -> Dictionary:
	var access := building.get_node_or_null("BuildingAccess")
	var definition: Dictionary = access.definition if access!=null else {}
	if definition.is_empty() and building is UrbanBuildingBase:
		definition = load("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd").for_source(building.building_id)
	return definition

## Patamar da saída do telhado, no espaço do telhado (centro do prédio, frente em +Z).
## O canto oeste é o padrão; o quartel põe a saída no topo da escada pintada.
static func stair(definition: Dictionary) -> Vector3:
	var size: Vector2 = definition.size
	var point: Vector3 = definition.get("stair",Vector3(-size.x*.5+1.45,0,1.45))
	point.y = 0.0
	return point

## Casinha da escada no espaço local do prédio (porta para +Z, olhando o patamar), ou
## null sem telhado caminhável. O CityChunkDressing põe ali a ÚNICA casinha/alçapão do
## telhado; HarborBuildingRooftop monta a mesma casinha (um pouco maior) quando se sobe.
static func stair_house(building: Node3D) -> Variant:
	var definition := definition_for(building)
	if definition.is_empty(): return null
	var local_to_building: Transform3D = building.global_transform.affine_inverse()*Transform3D(Basis(Vector3.UP,float(definition.exterior_rotation)),definition.exterior_position)
	return local_to_building*Transform3D(Basis.IDENTITY,stair(definition)+HOUSE_OFFSET)

static func occupied(building: Node3D) -> Array:
	var definition := definition_for(building)
	if definition.is_empty(): return []
	var size: Vector2 = definition.size
	var landing := stair(definition)
	var cache: Vector3 = definition.get("roof_cache_position",Vector3(size.x*.26,0,size.y*.22))
	cache.y = 0.0
	var jump := Vector3(float(definition.get("jump_x",maxf(.7,size.x*.5-2.0))),0,size.y*.5-.88)
	var local_to_building: Transform3D = building.global_transform.affine_inverse()*Transform3D(Basis(Vector3.UP,float(definition.exterior_rotation)),definition.exterior_position)
	var paths := [
		[landing,Vector3(jump.x,0,landing.z)],
		[Vector3(cache.x,0,landing.z),cache],
		[Vector3(jump.x,0,landing.z),jump],
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
	var bulkhead: Vector3 = local_to_building*(landing+Vector3(0,0,-1.25))
	result.append({"point":Vector2(bulkhead.x,bulkhead.z),"radius":1.45})
	return result
