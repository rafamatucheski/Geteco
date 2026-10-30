extends RefCounted
## Shared physical clearance for the roof stair, cache and guarded jump bay.
## Dressing keeps its detail budget, placing props around these walking lanes.
## Casinha da escada: centro em relação ao patamar e tamanho da que se monta ao subir
## (a do enfeite, BuildingLifeKit._roof_shed, tem 2,0 × 2,0 × 1,6 e cabe dentro dela).
const HOUSE_OFFSET := Vector3(0,0,-1.65)
const HOUSE_SIZE := Vector3(2.08,2.08,1.68)
## Prédio com laje abaixo disto é térreo: sai por alçapão no lugar da casinha (playtest
## 30/10: casinha de escada em casa de um andar só lia como andar que não existe).
const HATCH_MAX_ROOF_HEIGHT := 5.5
## Moldura do alçapão aberto que se monta ao subir; cobre o alçapão fechado do enfeite
## (CityPropKit roof_hatch, 1,0 × 0,46 × 1,0).
const HATCH_SIZE := Vector3(1.12,.5,1.12)

static func uses_hatch(definition: Dictionary) -> bool:
	return float(definition.get("roof_height",INF)) < HATCH_MAX_ROOF_HEIGHT

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

## Casinha da escada vista da rua: as mesmas peças e materiais com textura (pedra, metal, madeira de
## HarborBuildingMaterials) da que se monta ao subir no telhado (HarborBuildingRooftop). Era a caixa lisa
## de cor por vértice do kit de adereços (30/10: "melhorar com texturas já prontas para ficar condizente").
## `at` = centro da base, no espaço de `parent`; porta para +Z.
static func build_house(parent: Node3D, at: Transform3D) -> Node3D:
	var materials := preload("res://world/places/harbor_buildings/HarborBuildingMaterials.gd")
	var house := Node3D.new()
	house.name = "RoofStairHouse"
	house.transform = at
	parent.add_child(house)
	for spec in [
		["Walls", Vector3(0, HOUSE_SIZE.y * .5, 0), HOUSE_SIZE, "stone", "a39b8c"],
		["Cap", Vector3(0, HOUSE_SIZE.y + .08, .05), Vector3(HOUSE_SIZE.x + .2, .16, HOUSE_SIZE.z + .2), "metal", "6e7577"],
		["Door", Vector3(.4, .87, HOUSE_SIZE.z * .5 + .012), Vector3(.82, 1.74, .02), "wood", "5a4a3c"],
		["Window", Vector3(-.55, 1.4, HOUSE_SIZE.z * .5 + .012), Vector3(.52, .42, .02), "metal", "2e3a40"],
	]:
		var piece := MeshInstance3D.new()
		piece.name = spec[0]
		var box := BoxMesh.new()
		box.size = spec[2]
		piece.mesh = box
		piece.position = spec[1]
		piece.material_override = materials.material(spec[3], Color(spec[4]))
		house.add_child(piece)
	return house

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
