extends RefCounted
class_name HarborRouteDetailFactory

## Classe fábrica que cria e monta o componente Harbor Route Detail e as zonas modulares.
## Integra-se sem emendas ao streaming de chunks do NativeRegion e ao ciclo de carregamento regional.

## Instantiates a new HarborRouteDetail3D composite node containing all zones.
static func create_route_detail() -> HarborRouteDetail3D:
	var route := HarborRouteDetail3D.new()
	route.name = "HarborRouteDetail3D"
	route.mount_all()
	return route

## Instancia e monta HarborRouteDetail3D no nó pai indicado com todas as zonas ativas.
static func mount_route_detail(parent: Node3D) -> HarborRouteDetail3D:
	if parent == null:
		push_error("HarborRouteDetailFactory: Cannot mount into null parent.")
		return null
	var route := create_route_detail()
	parent.add_child(route)
	return route

## Instantiates a standalone, unparented single zone Node3D.
## Does NOT instantiate a HarborRouteDetail3D container, preventing orphan nodes.
static func create_zone(zone_id: String) -> Node3D:
	return HarborRouteDetail3D.build_zone(zone_id)

static func begin_zone(zone_id: String) -> Dictionary:
	return HarborRouteDetail3D.begin_zone(zone_id)

static func step_zone(job: Dictionary, budget_usec: float = 1500.0) -> bool:
	return HarborRouteDetail3D.step_zone(job, budget_usec)

static func cancel_zone(job: Dictionary) -> void:
	HarborRouteDetail3D.cancel_zone(job)

## Monta uma zona isolada direto no pai indicado (por exemplo, um chunk em streaming).
## Devolve o Node3D da zona montada, que agora é filho direto de parent.
static func mount_zone(parent: Node3D, zone_id: String) -> Node3D:
	if parent == null:
		push_error("HarborRouteDetailFactory: Cannot mount zone into null parent.")
		return null
	var zone := create_zone(zone_id)
	if zone != null:
		parent.add_child(zone)
	return zone

## Devolve as definições espaciais das zonas para o registro de streaming do NativeRegion em _prepare().
static func get_zone_records() -> Array[Dictionary]:
	return [
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_RODOVIARIA, "position": Vector3(106.25, 0.0, 70.625)},
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_CONNECTING_STREETS, "position": Vector3(86.8, 0.0, 94.0)},
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_DELEGACIA, "position": Vector3(67.5, 0.0, 132.5)},
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_MACIOTA, "position": Vector3(166.0, 0.0, 109.8)},
	]

## Populates a single zone into a streaming chunk when the chunk enters proximity focus.
static func populate_zone_chunk(chunk: Node3D, zone_id: String, prepared_zone: Node3D = null) -> Node3D:
	if chunk == null:
		return null
	if is_instance_valid(prepared_zone) and prepared_zone.get_parent() == null:
		chunk.add_child(prepared_zone)
		return prepared_zone
	return mount_zone(chunk, zone_id)
