## Small state container used by a Player/WeaponController.
## It contains no input, UI, scene, or texture dependencies.
class_name WeaponRuntime
extends RefCounted

signal weapon_changed(weapon_id: StringName)
signal ammo_changed(weapon_id: StringName, magazine: int, reserve: int)
signal reload_started(weapon_id: StringName)
signal reload_finished(weapon_id: StringName)

var catalog: Dictionary = {}
var owned: Dictionary = {}
var active_weapon_id: StringName = &""
var is_reloading := false
var reload_remaining := 0.0


func configure(weapon_catalog: Dictionary, initial_owned: Dictionary, initial_weapon: StringName) -> void:
	catalog = weapon_catalog.duplicate(true)
	owned = initial_owned.duplicate(true)
	active_weapon_id = initial_weapon
	_ensure_weapon_state(active_weapon_id)


func tick(delta: float) -> bool:
	if not is_reloading:
		return false
	reload_remaining = maxf(0.0, reload_remaining - delta)
	if reload_remaining > 0.0:
		return false
	_finish_reload()
	return true


func active_data() -> Dictionary:
	return get_data(active_weapon_id)


func get_data(weapon_id: StringName) -> Dictionary:
	var data: Variant = catalog.get(weapon_id, {})
	return data as Dictionary


func owns(weapon_id: StringName) -> bool:
	return owned.has(weapon_id)


func unlock(weapon_id: StringName, reserve_bonus: int = -1) -> bool:
	if not catalog.has(weapon_id):
		return false
	_ensure_weapon_state(weapon_id)
	if reserve_bonus >= 0:
		var state: Dictionary = owned[weapon_id]
		state["reserve"] = int(state.get("reserve", 0)) + reserve_bonus
		owned[weapon_id] = state
		_emit_ammo(weapon_id)
	return true


func equip(weapon_id: StringName) -> bool:
	if not owns(weapon_id):
		return false
	active_weapon_id = weapon_id
	is_reloading = false
	reload_remaining = 0.0
	weapon_changed.emit(active_weapon_id)
	_emit_ammo(active_weapon_id)
	return true


func can_fire() -> bool:
	if is_reloading or active_weapon_id.is_empty() or not owns(active_weapon_id):
		return false
	var state: Dictionary = owned[active_weapon_id]
	return int(state.get("magazine", 0)) > 0


func consume_round() -> bool:
	if not can_fire():
		return false
	var state: Dictionary = owned[active_weapon_id]
	state["magazine"] = maxi(0, int(state.get("magazine", 0)) - 1)
	owned[active_weapon_id] = state
	_emit_ammo(active_weapon_id)
	return true


func request_reload() -> bool:
	if is_reloading or active_weapon_id.is_empty() or not owns(active_weapon_id):
		return false
	var state: Dictionary = owned[active_weapon_id]
	var data := active_data()
	if int(state.get("reserve", 0)) <= 0 or int(state.get("magazine", 0)) >= int(data.get("magazine_size", 0)):
		return false
	is_reloading = true
	reload_remaining = maxf(0.05, float(data.get("reload_time", 1.0)))
	reload_started.emit(active_weapon_id)
	return true


func add_ammo(weapon_id: StringName, amount: int) -> bool:
	if amount <= 0 or not catalog.has(weapon_id):
		return false
	_ensure_weapon_state(weapon_id)
	var state: Dictionary = owned[weapon_id]
	state["reserve"] = int(state.get("reserve", 0)) + amount
	owned[weapon_id] = state
	_emit_ammo(weapon_id)
	return true


func ammo(weapon_id: StringName = &"") -> Dictionary:
	var id := active_weapon_id if weapon_id.is_empty() else weapon_id
	if not owned.has(id):
		return {"magazine": 0, "reserve": 0}
	return (owned[id] as Dictionary).duplicate()


func _finish_reload() -> void:
	var state: Dictionary = owned[active_weapon_id]
	var capacity := int(active_data().get("magazine_size", 0))
	var needed := maxi(0, capacity - int(state.get("magazine", 0)))
	var transfer := mini(needed, int(state.get("reserve", 0)))
	state["magazine"] = int(state.get("magazine", 0)) + transfer
	state["reserve"] = int(state.get("reserve", 0)) - transfer
	owned[active_weapon_id] = state
	is_reloading = false
	reload_finished.emit(active_weapon_id)
	_emit_ammo(active_weapon_id)


func _ensure_weapon_state(weapon_id: StringName) -> void:
	if owned.has(weapon_id):
		return
	var data := get_data(weapon_id)
	owned[weapon_id] = {
		"magazine": int(data.get("magazine_size", 0)),
		"reserve": int(data.get("starting_reserve", 0)),
	}


func _emit_ammo(weapon_id: StringName) -> void:
	var state := ammo(weapon_id)
	ammo_changed.emit(weapon_id, int(state["magazine"]), int(state["reserve"]))
