class_name DistrictRestrictionManager
extends Node

## Enforces the Bairro 1 ankle-monitor boundary without owning campaign, HUD,
## audio or police presentation.  Those systems consume the signals below.

signal boundary_warning_requested(message: String, exit_anchor: Node2D, tracked_actor: Node2D, distance: float)
signal boundary_breached(exit_anchor: Node2D, tracked_actor: Node2D, destination_district: int)
signal lethal_pursuit_requested(minimum_stars: int, exit_anchor: Node2D, tracked_actor: Node2D)
signal restriction_event_reset()

@export var ankle_monitor_flag: StringName = &"ankle_monitor_active"
@export var monitored_from_district: int = 1
@export_range(1.0, 2000.0, 1.0) var warning_distance: float = 360.0
@export_range(1.0, 1000.0, 1.0) var breach_distance: float = 100.0
@export_range(1, 6, 1) var minimum_lethal_stars: int = 4
@export_range(0.01, 2.0, 0.01) var scan_interval: float = 0.10
@export var warning_message: String = "TORNOZELEIRA: LIMITE DO BAIRRO. RETORNE AGORA."
@export var campaign_state_path: NodePath = NodePath("/root/CampaignState")
@export var wanted_manager_path: NodePath = NodePath("/root/WantedManager")

const WANTED_POINT_THRESHOLDS := [0, 1, 15, 35, 70, 120, 200]

var _scan_remaining: float = 0.0
var _warned_exit_ids: Dictionary = {}
var _breach_triggered: bool = false
var _saw_recovery_since_breach: bool = false
var _campaign_state_override: Node = null
var _wanted_manager_override: Node = null


func _ready() -> void:
	add_to_group("district_restriction_manager")


func _process(delta: float) -> void:
	_observe_player_respawn()
	_scan_remaining -= delta
	if _scan_remaining > 0.0:
		return
	_scan_remaining = scan_interval
	evaluate_restrictions()


## Dependency injection keeps this component testable and usable before it is
## registered as an autoload. Passing null restores the normal root lookups.
func configure_dependencies(campaign_state: Node, wanted_manager: Node) -> void:
	_campaign_state_override = campaign_state
	_wanted_manager_override = wanted_manager


## Public deterministic tick used by tests and by scene adapters that do not
## want this node to process continuously.
func evaluate_restrictions() -> void:
	_observe_player_respawn()
	if _breach_triggered or not _is_ankle_monitor_active():
		return
	var actor := _get_tracked_actor()
	if actor == null:
		return
	var effective_warning_distance := maxf(warning_distance, breach_distance)
	for exit_anchor in _get_blocked_bairro_one_exits():
		var distance := actor.global_position.distance_to(exit_anchor.global_position)
		var exit_id := _get_exit_id(exit_anchor)
		if distance <= effective_warning_distance and not _warned_exit_ids.has(exit_id):
			_warned_exit_ids[exit_id] = true
			boundary_warning_requested.emit(warning_message, exit_anchor, actor, distance)
		if distance <= breach_distance:
			_trigger_boundary_breach(exit_anchor, actor)
			return


## Called automatically after the Player completes its recovery cycle.  A
## future explicit respawn signal may call this same API.  It deliberately does
## not clear CampaignState's ankle_monitor_active flag.
func reset_event_after_respawn() -> void:
	if not _breach_triggered and _warned_exit_ids.is_empty():
		return
	_breach_triggered = false
	_saw_recovery_since_breach = false
	_warned_exit_ids.clear()
	restriction_event_reset.emit()


func is_breach_latched() -> bool:
	return _breach_triggered


func _trigger_boundary_breach(exit_anchor: Node2D, actor: Node2D) -> void:
	if _breach_triggered:
		return
	_breach_triggered = true
	_saw_recovery_since_breach = false
	var destination := int(exit_anchor.get_meta("to_district", -1))
	boundary_breached.emit(exit_anchor, actor, destination)
	_ensure_minimum_wanted_level()
	lethal_pursuit_requested.emit(minimum_lethal_stars, exit_anchor, actor)


func _ensure_minimum_wanted_level() -> void:
	var wanted := _get_wanted_manager()
	if wanted == null:
		return
	if wanted.has_method("ensure_minimum_wanted_level"):
		wanted.call("ensure_minimum_wanted_level", minimum_lethal_stars)
		return
	if not wanted.has_method("report_crime"):
		return
	var current_stars := int(wanted.get("current_stars"))
	var current_points := maxi(0, int(wanted.get("crime_points")))
	var target_index := clampi(minimum_lethal_stars, 0, WANTED_POINT_THRESHOLDS.size() - 1)
	var target_points := int(WANTED_POINT_THRESHOLDS[target_index])
	var required_severity := maxi(0, target_points - current_points)
	# report_crime(0) is intentional when already above the threshold: it resets
	# the public pursuit timer without lowering the current wanted level.
	if current_stars >= minimum_lethal_stars:
		required_severity = 0
	wanted.call("report_crime", required_severity)


func _observe_player_respawn() -> void:
	if not _breach_triggered:
		return
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	var is_recovering := bool(player.get("is_dead")) or bool(player.get("is_arrested")) or bool(player.get("is_recovering"))
	if is_recovering:
		_saw_recovery_since_breach = true
	elif _saw_recovery_since_breach:
		reset_event_after_respawn()


func _is_ankle_monitor_active() -> bool:
	var campaign := _get_campaign_state()
	return campaign != null and campaign.has_method("has_campaign_flag") and bool(campaign.call("has_campaign_flag", ankle_monitor_flag))


func _get_campaign_state() -> Node:
	if is_instance_valid(_campaign_state_override):
		return _campaign_state_override
	return get_node_or_null(campaign_state_path)


func _get_wanted_manager() -> Node:
	if is_instance_valid(_wanted_manager_override):
		return _wanted_manager_override
	return get_node_or_null(wanted_manager_path)


func _get_tracked_actor() -> Node2D:
	for vehicle in get_tree().get_nodes_in_group("vehicle"):
		if is_instance_valid(vehicle) and vehicle is Node2D and vehicle.get("is_driven_by_player") == true:
			return vehicle as Node2D
	var player := get_tree().get_first_node_in_group("player")
	return player as Node2D if is_instance_valid(player) and player is Node2D else null


func _get_blocked_bairro_one_exits() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group("district_connection"):
		if not node is Node2D:
			continue
		if int(node.get_meta("from_district", -1)) != monitored_from_district:
			continue
		if not bool(node.get_meta("temporary_blocked", false)):
			continue
		result.append(node as Node2D)
	return result


func _get_exit_id(exit_anchor: Node2D) -> StringName:
	var configured := StringName(exit_anchor.get_meta("restriction_id", &""))
	if not configured.is_empty():
		return configured
	return StringName("district_%d_to_%d" % [
		int(exit_anchor.get_meta("from_district", -1)),
		int(exit_anchor.get_meta("to_district", -1)),
	])
