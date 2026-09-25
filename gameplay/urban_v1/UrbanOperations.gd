extends Node
## Session-owned adapter for productive Harbor behaviors that do not belong to
## NativeRegion geometry, the place catalog, Actor, combat or shared models.

var session
var port
var cemetery
var security
var cargo_handling
var secret_car
var freight

func configure(owner_session) -> void:
	session = owner_session
	name = "V1UrbanOperations"
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _ready() -> void:
	port = preload("res://gameplay/urban_v1/PortOperations.gd").new()
	port.configure(session)
	add_child(port)
	cemetery = preload("res://gameplay/urban_v1/CemeteryOperations.gd").new()
	cemetery.configure(session)
	add_child(cemetery)
	security = preload("res://gameplay/urban_v1/HarborPortSecurity.gd").new()
	security.configure(session)
	add_child(security)
	cargo_handling = preload("res://gameplay/urban_v1/PortCargoOperations.gd").new()
	cargo_handling.configure(session)
	add_child(cargo_handling)
	freight = preload("res://gameplay/urban_v1/PortFreightDelivery.gd").new()
	freight.configure(session, cargo_handling, security)
	add_child(freight)
	secret_car = preload("res://gameplay/urban_v1/CobraSecretCar3D.gd").new()
	secret_car.configure(session)
	add_child(secret_car)

func refresh_context() -> void:
	if is_instance_valid(port): port.refresh_context()
	if is_instance_valid(cemetery): cemetery.refresh_context()
	if is_instance_valid(cargo_handling): cargo_handling.refresh_context()

func nearest_action() -> Dictionary:
	var checkpoint: Dictionary = security.nearest_action() if is_instance_valid(security) else {}
	if not checkpoint.is_empty(): return checkpoint
	var delivery: Dictionary = freight.nearest_action() if is_instance_valid(freight) else {}
	if not delivery.is_empty(): return delivery
	return cemetery.nearest_action() if is_instance_valid(cemetery) else {}

func freight_status() -> Dictionary:
	return freight.freight_status() if is_instance_valid(freight) else {"active":false}

func perform(target: String) -> bool:
	if target == "south_port_checkpoint": return is_instance_valid(security) and security.perform(target)
	if target.begins_with("south_port_freight_"): return is_instance_valid(freight) and freight.perform(target)
	return is_instance_valid(cemetery) and cemetery.perform(target)

func snapshot() -> Dictionary:
	return {
		"version":1,
		"port":port.snapshot() if is_instance_valid(port) else {},
		"cemetery":cemetery.snapshot() if is_instance_valid(cemetery) else {},
		"security":security.snapshot() if is_instance_valid(security) else {},
		"freight":freight.snapshot() if is_instance_valid(freight) else {},
	}

func restore_snapshot(data: Dictionary) -> bool:
	if not is_instance_valid(port) or not is_instance_valid(cemetery) or not is_instance_valid(security) or not is_instance_valid(freight) or not validate_snapshot(data): return false
	var checkpoint: Dictionary = data.get("security", {"version":1,"authorized_entry":false,"authorized_visit":false,"exiting_port":false})
	var delivery: Dictionary = data.get("freight", {"version":1,"jobs":[0,0,0],"active_bay":-1,"truck":{}})
	return port.restore_snapshot(data.port) and cemetery.restore_snapshot(data.cemetery) and security.restore_snapshot(checkpoint) and freight.restore_snapshot(delivery)

static func validate_snapshot(data: Dictionary) -> bool:
	return data.get("version") == 1 and data.get("port") is Dictionary and data.get("cemetery") is Dictionary \
		and preload("res://gameplay/urban_v1/PortOperations.gd").validate_snapshot(data.port) \
		and preload("res://gameplay/urban_v1/CemeteryOperations.gd").validate_snapshot(data.cemetery) \
		and (not data.has("security") or (data.security is Dictionary \
			and preload("res://gameplay/urban_v1/HarborPortSecurity.gd").validate_snapshot(data.security))) \
		and (not data.has("freight") or (data.freight is Dictionary \
			and preload("res://gameplay/urban_v1/PortFreightDelivery.gd").validate_snapshot(data.freight)))
