extends Node
## Session-owned adapter for productive Harbor behaviors that do not belong to
## NativeRegion geometry, the place catalog, Actor, combat or shared models.

var session
var port
var cemetery
var security
var cargo_handling
var secret_car

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
	return cemetery.nearest_action() if is_instance_valid(cemetery) else {}

func perform(target: String) -> bool:
	if target == "south_port_checkpoint": return is_instance_valid(security) and security.perform(target)
	return is_instance_valid(cemetery) and cemetery.perform(target)

func snapshot() -> Dictionary:
	return {
		"version":1,
		"port":port.snapshot() if is_instance_valid(port) else {},
		"cemetery":cemetery.snapshot() if is_instance_valid(cemetery) else {},
	}

func restore_snapshot(data: Dictionary) -> bool:
	if not is_instance_valid(port) or not is_instance_valid(cemetery) or not validate_snapshot(data): return false
	return port.restore_snapshot(data.port) and cemetery.restore_snapshot(data.cemetery)

static func validate_snapshot(data: Dictionary) -> bool:
	return data.get("version") == 1 and data.get("port") is Dictionary and data.get("cemetery") is Dictionary \
		and preload("res://gameplay/urban_v1/PortOperations.gd").validate_snapshot(data.port) \
		and preload("res://gameplay/urban_v1/CemeteryOperations.gd").validate_snapshot(data.cemetery)
