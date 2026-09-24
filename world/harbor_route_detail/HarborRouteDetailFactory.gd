extends RefCounted
class_name HarborRouteDetailFactory

## Factory class for creating and mounting the Harbor Route Detail component and its modular zones.
## Integrates seamlessly into the NativeRegion chunk streaming and regional loading lifecycle.

## Instantiates a new HarborRouteDetail3D composite node containing all zones.
static func create_route_detail() -> HarborRouteDetail3D:
	var route := HarborRouteDetail3D.new()
	route.name = "HarborRouteDetail3D"
	route.mount_all()
	return route

## Instantiates and mounts HarborRouteDetail3D into the designated parent node with all zones active.
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

## Mounts an isolated single zone directly into the designated parent (e.g. a streaming chunk).
## Returns the mounted zone Node3D, which is now a direct child of parent.
static func mount_zone(parent: Node3D, zone_id: String) -> Node3D:
	if parent == null:
		push_error("HarborRouteDetailFactory: Cannot mount zone into null parent.")
		return null
	var zone := create_zone(zone_id)
	if zone != null:
		parent.add_child(zone)
	return zone

## Returns zone spatial definitions for NativeRegion streaming registration in _prepare().
static func get_zone_records() -> Array[Dictionary]:
	return [
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_RODOVIARIA, "position": Vector3(106.25, 0.0, 70.625)},
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_CONNECTING_STREETS, "position": Vector3(86.8, 0.0, 94.0)},
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_DELEGACIA, "position": Vector3(67.5, 0.0, 132.5)},
		{"kind": "harbor_route_zone", "zone_id": HarborRouteDetail3D.ZONE_MACIOTA, "position": Vector3(46.875, 0.0, 101.7375)},
	]

## Populates a single zone into a streaming chunk when the chunk enters proximity focus.
static func populate_zone_chunk(chunk: Node3D, zone_id: String) -> Node3D:
	if chunk == null:
		return null
	return mount_zone(chunk, zone_id)
