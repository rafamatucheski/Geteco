extends RefCounted
## Persisted gameplay time; pausing or returning to the menu cannot refill stock.
const DAILY_LIMIT := 6
const DAY_SECONDS := 600.0 # Same ten-minute playable day as the Harbor campaign.
var data: Dictionary

func _init(saved: Dictionary = {}) -> void:
	data = saved
	for key in {"day":1, "clock":0.0, "delivered":0, "jobs_taken":0, "completed":0, "contract":{}, "last_result":""}:
		if not data.has(key):
			data[key] = {"day":1, "clock":0.0, "delivered":0, "jobs_taken":0, "completed":0, "contract":{}, "last_result":""}[key]

func advance(delta: float, campaign_day: int = 0) -> void:
	if campaign_day>0:
		if campaign_day>int(data.day):
			data.day=campaign_day
			data.delivered=0
			data.jobs_taken=0
	else:
		data.clock = float(data.clock) + maxf(0.0, delta)
		while float(data.clock) >= DAY_SECONDS:
			data.clock -= DAY_SECONDS
			data.day = int(data.day) + 1
			data.delivered = 0
			data.jobs_taken = 0
	if not data.contract.is_empty():
		data.contract.remaining = maxf(0.0, float(data.contract.remaining) - delta)
		if float(data.contract.remaining) <= 0.0:
			fail_contract("expired")

func available() -> int:
	return maxi(0, DAILY_LIMIT - int(data.delivered))

func accept(spec: Dictionary) -> bool:
	if available() == 0 or not data.contract.is_empty() or int(data.jobs_taken) >= 3:
		return false
	data.jobs_taken = int(data.jobs_taken) + 1
	data.contract = spec.duplicate(true)
	data.contract.token = "salvage_%d_%d" % [data.day, data.jobs_taken]
	data.contract.remaining = float(spec.get("duration", 150.0))
	data.last_result = "accepted"
	return true

func fail_contract(reason: String) -> void:
	data.contract = {}
	data.last_result = reason

func settle(token: String, base_reward: int) -> int:
	if available() == 0: return 0
	var reward := base_reward
	if not data.contract.is_empty() and token == String(data.contract.token):
		if bool(data.contract.get("tow_required",false)) and not bool(data.contract.get("tow_loaded",false)): return 0
		reward = int(data.contract.reward)
		if bool(data.contract.get("tow_required",false)):
			data["tow_completed"] = int(data.get("tow_completed",0)) + 1
		data.completed = int(data.completed) + 1
		data.contract = {}
		data.last_result = "completed"
	data.delivered = int(data.delivered) + 1
	return reward
