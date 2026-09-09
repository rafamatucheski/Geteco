extends RefCounted

## A save-backed ledger; never moves actors, pays wallets, or starts missions.
const DAY_SECONDS := 600.0
const MISSION_IDS := ["cobra_contact", "cobra_race", "cobra_collection", "cobra_supply", "cobra_finale"]
const REWARDS := [120, 200, 250, 350, 600]
const TITLES_PT := ["Dentro do território", "Prova de rua", "A conta chega", "Cortar o abastecimento", "A última cobrança"]
const TITLES_EN := ["Inside Their Turf", "Street Trial", "The Bill Comes Due", "Cut the Supply", "The Last Collection"]
var _campaign: Node
var _local_data: Dictionary = {}
var data: Dictionary:
	get:
		if is_instance_valid(_campaign):
			return _campaign.get("cobra_campaign")
		return _local_data
	set(value):
		_local_data = value

func bind(campaign: Node) -> void:
	_campaign = campaign
	_attach()
	sync_legacy()

func _defaults() -> Dictionary:
	return {"version": 1, "active_id": "", "stage": 0, "day": 1,
		"day_elapsed": 0.0, "completed": {}, "reward_claimed": {},
		"unlock_days": {}, "civilian_reputation": 0, "cobra_access": 0,
		"defeated": false, "optional_flags": {}, "secret_owned": {}, "boss_owned": {}}

func _attach() -> void:
	var defaults := _defaults()
	if data.is_empty():
		data.merge(defaults)
	for key in defaults:
		if not data.has(key):
			data[key] = defaults[key]
	for key in ["completed", "reward_claimed", "unlock_days", "optional_flags", "secret_owned", "boss_owned"]:
		if not data[key] is Dictionary:
			data[key] = {}
	data.day = maxi(1, int(data.day))
	data.day_elapsed = maxf(0.0, float(data.day_elapsed))
	if not str(data.active_id).is_empty() and not MISSION_IDS.has(str(data.active_id)):
		data.active_id = ""
		data.stage = 0

func sync_legacy() -> void:
	_attach()
	if not is_instance_valid(_campaign):
		return
	if _campaign.call("has_campaign_flag", &"harbor_arrival_call_complete"):
		data.completed["arrival"] = true
	if _campaign.call("has_campaign_flag", &"harbor_delivery_complete"):
		if not bool(data.completed.get("primeiro_giro", false)):
			data.unlock_days["cobra_contact"] = int(data.day)
		data.completed["primeiro_giro"] = true

func tick(delta: float) -> void:
	_attach()
	if delta <= 0.0 or not is_finite(delta):
		return
	data.day_elapsed = float(data.day_elapsed) + delta
	while float(data.day_elapsed) >= DAY_SECONDS:
		data.day_elapsed = float(data.day_elapsed) - DAY_SECONDS
		data.day = int(data.day) + 1

func get_status(id: String) -> Dictionary:
	sync_legacy()
	var index := MISSION_IDS.find(id)
	var reason := ""
	var unlock_day := int(data.unlock_days.get(id, 1))
	if index < 0:
		reason = "unknown"
	elif bool(data.completed.get(id, false)):
		reason = "completed"
	elif not str(data.active_id).is_empty():
		reason = "active"
	elif not bool(data.completed.get("primeiro_giro" if index == 0 else MISSION_IDS[index - 1], false)):
		reason = "prerequisite"
	return {"available": reason.is_empty(), "reason": reason, "unlock_day": unlock_day}

func begin(id: String) -> bool:
	if not bool(get_status(id).available):
		return false
	data.active_id = id
	data.stage = 0
	return true

func start_mission(id: String) -> bool:
	return begin(id)

func set_stage(stage: int) -> void:
	_attach()
	if not str(data.active_id).is_empty():
		data.stage = maxi(0, stage)

func fail() -> void:
	_attach()
	data.active_id = ""
	data.stage = 0

func fail_mission(id: String) -> void:
	_attach()
	if str(data.active_id) == id:
		fail()

func complete() -> bool:
	_attach()
	var id := str(data.active_id)
	var index := MISSION_IDS.find(id)
	if index < 0 or bool(data.completed.get(id, false)):
		return false
	data.completed[id] = true
	data.active_id = ""
	data.stage = 0
	if index + 1 < MISSION_IDS.size():
		data.unlock_days[MISSION_IDS[index + 1]] = int(data.day)
	if index <= 1:
		data.cobra_access = int(data.cobra_access) + 1
	else:
		data.civilian_reputation = int(data.civilian_reputation) + 1
		data.cobra_access = 0
	if id == "cobra_finale":
		data.defeated = true
	return true

func complete_mission(id: String) -> bool:
	_attach()
	return complete() if str(data.active_id) == id else false

## Caller pays immediately after receiving this token, then saves both states.
func claim_reward(id: String) -> Dictionary:
	_attach()
	var index := MISSION_IDS.find(id)
	if index < 0 or not bool(data.completed.get(id, false)) or bool(data.reward_claimed.get(id, false)):
		return {}
	data.reward_claimed[id] = true
	return {"mission_id": id, "cash": REWARDS[index]}

## Runtime must also verify the player is physically at a safe rest location.
func rest_until_next_day(in_combat: bool = false) -> bool:
	_attach()
	if in_combat or not str(data.active_id).is_empty():
		return false
	data.day = int(data.day) + 1
	data.day_elapsed = 0.0
	return true
