extends RefCounted
## Event state machine; adapters must derive events from actual world actions.
const Missions := preload("res://data/campaign/HarborMissions.gd")
const Race := preload("res://systems/campaign/CobraRaceProgress.gd")
const RACE_IDS := ["cobra_race","cobra_finale"]
var _data := {"version": 2, "active_id": "", "step": 0, "completed": [], "flags": {}, "legacy_skipped":[],
	"pending_rewards": {}, "claimed_rewards": [], "race_elapsed": 0.0, "race_outside":0.0, "race_run":{}, "failure": ""}
var active_id: String:
	get: return _data.active_id
var step: int:
	get: return int(_data.step)

func snapshot() -> Dictionary:
	return _data.duplicate(true)

func race_elapsed() -> float:
	return float(_data.race_elapsed)

func race_status() -> Dictionary:
	var result: Dictionary=_data.get("race_run",{}).duplicate(true)
	if not result.is_empty():
		result.merge({"elapsed":float(_data.race_elapsed),"outside":float(_data.race_outside),"time_left":maxf(0,100.0-float(_data.race_elapsed)),"return_seconds":maxf(0,4.0-float(_data.race_outside))})
		if result.get("course_version",0)==2:
			result.time_left=maxf(0,180.0-float(_data.race_elapsed))
			result.return_seconds=maxf(0,20.0-float(_data.race_outside))
	return result

func set_street_race_place(value: int) -> void:
	if active_id in RACE_IDS and _data.race_run.get("course_version",0)==2:
		_data.race_run.place=clampi(value,1,6)

func tick_race(delta: float, point: Vector2, vehicle_id: String, alive: bool) -> Dictionary:
	if not race_stage_active() or step==0 or not is_finite(delta) or delta<=0 or not point.is_finite(): return {}
	if _data.get("race_run",{}).is_empty(): return {}
	var result: Dictionary=Race.tick(_data.race_run,delta,point,vehicle_id,alive,float(_data.race_elapsed),float(_data.race_outside))
	if not str(result.failure).is_empty():
		cancel(result.failure)
		return result
	_data.race_elapsed=result.elapsed
	_data.race_outside=result.outside
	return result

func advance_race(delta: float, on_track: bool, inner_cut := false) -> String:
	if not race_stage_active() or step==0 or not is_finite(delta) or delta<=0: return ""
	_data.race_elapsed=float(_data.race_elapsed)+delta
	_data.race_outside=0.0 if on_track else float(_data.get("race_outside",0.0))+delta
	var failure := ""
	if inner_cut or _data.race_outside>=4.0: failure="race_offtrack"
	elif _data.race_elapsed>=100.0: failure="race_timeout"
	if not failure.is_empty(): cancel(failure)
	return failure

func race_stage_active() -> bool:
	return active_id in RACE_IDS and step < 6

func has_progress(id: String) -> bool:
	return _data.completed.has(id) or _data.get("legacy_skipped",[]).has(id)

func available_missions() -> Array:
	var result := []
	if active_id != "": return result
	for id in Missions.ORDER:
		var required: String = Missions.MISSIONS[id].requires
		if not has_progress(id) and (required == "" or has_progress(required)):
			result.append(id)
	return result

func begin(id: String) -> bool:
	if not available_missions().has(id): return false
	_data.active_id = id
	_data.step = 0
	_data.race_elapsed = 0.0
	_data.race_outside = 0.0
	_data.race_run = {}
	_data.failure = ""
	return true

func current_step() -> Dictionary:
	if active_id == "": return {}
	return Missions.MISSIONS[active_id].steps[step].duplicate(true)

func objective() -> String:
	if is_suspended(): return "Missão interrompida. Libere espaço atrás do guincho para encerrar a tentativa."
	if race_stage_active() and not _data.get("race_run",{}).is_empty():
		if _data.race_run.countdown>0: return String(TranslationServer.translate("Fique parado · %d"))%ceili(float(_data.race_run.countdown))
		if _data.race_run.get("course_version",0)==2:
			if _data.race_outside>0: return String(TranslationServer.translate("Volte à rota · %d s"))%ceili(20.0-float(_data.race_outside))
			return String(TranslationServer.translate("Checkpoint azul %d/4 · Chegue em primeiro às docas."))%mini(int(_data.race_run.checkpoint)+1,4)
		if _data.race_outside>0: return String(TranslationServer.translate("Volte à pista pelo mesmo lugar · %d s"))%ceili(4.0-float(_data.race_outside))
		return String(TranslationServer.translate("Portão %d/4 · Restam %d s · Siga a faixa externa."))%[mini(int(_data.race_run.checkpoint)+1,4),ceili(100.0-float(_data.race_elapsed))]
	return str(current_step().get("objective", "Consulte o quadro da garagem."))

func target_id() -> String:
	return str(current_step().get("target", ""))

func legacy_flags() -> Dictionary:
	# Flags originais do Harbor projetadas a partir do checkpoint; sem acoplamento por coordenada.
	var result := {}
	if active_id == "primeiro_giro" or _data.completed.has("primeiro_giro"):
		result.harbor_delivery_started = true
		result.harbor_first_favors_v3 = true
	if (active_id == "primeiro_giro" and step >= 1) or _data.completed.has("primeiro_giro"):
		result.harbor_delivery_receipt = true
	if (active_id == "primeiro_giro" and step >= 2) or _data.completed.has("primeiro_giro"):
		result.harbor_delivery_picked_up = true
	if _data.completed.has("primeiro_giro"): result.harbor_delivery_complete = true
	return result

func cobra_status() -> Dictionary:
	var result := {"civilian_reputation": 0, "cobra_access": 0, "defeated": _data.completed.has("cobra_finale")}
	for id in _data.completed:
		if id in ["cobra_contact", "cobra_race"]: result.cobra_access += 1
		elif id in ["cobra_collection", "cobra_supply", "cobra_finale"]:
			result.civilian_reputation += 1
			result.cobra_access = 0
	return result

func cancel(reason: String = "cancelled") -> bool:
	if active_id == "": return false
	_data.active_id = ""
	_data.step = 0
	_data.race_elapsed = 0.0
	_data.race_outside = 0.0
	_data.race_run = {}
	_data.failure = reason.left(256)
	return true

func is_suspended() -> bool:
	return active_id != "" and str(_data.failure).begins_with("pending:")

func suspend_attempt(reason: String) -> void:
	if active_id != "": _data.failure = "pending:"+reason.left(240)

func aftermath_pending() -> bool:
	return _data.completed.has("cobra_finale") and not _data.get("aftermath",{}).get("call_complete",false)

func complete_aftermath_call() -> bool:
	if not aftermath_pending(): return false
	_data.aftermath = {"call_complete":true}
	return true

func apply_event(event_id: String, payload: Dictionary = {}) -> Dictionary:
	if active_id == "": return _reply(false, false, "no_active_mission")
	if is_suspended(): return _reply(false, false, "attempt_interrupted")
	var expected := current_step()
	if event_id != expected.event or payload.get("target_id", "") != expected.target:
		return _reply(false, false, "unexpected_event")
	if expected.get("on_foot", false) and payload.get("on_foot") != true: return _reply(false, false, "on_foot_required")
	if expected.get("in_vehicle", false) and payload.get("in_vehicle") != true: return _reply(false, false, "vehicle_required")
	if expected.get("unarmed", false) and payload.get("unarmed") != true: return _reply(false, false, "holster_required")
	if expected.get("no_wanted", false) and payload.get("wanted_level", -1) != 0: return _reply(false, false, "lose_police")
	if expected.get("encounter", false) and payload.get("encounter_cleared") != true: return _reply(false, false, "encounter_required")
	if active_id == "cobra_contact" and event_id == "neco_repair_received" and payload.get("tow_delivery_ready") != true:
		return _reply(false, false, "tow_delivery_required")
	if expected.get("vehicle_action", false) and (payload.get("story_vehicle_alive") != true or payload.get("correct_vehicle") != true):
		return _reply(false, false, "story_vehicle_required")
	if expected.has("checkpoint") and payload.get("checkpoint", -1) != expected.checkpoint:
		return _reply(false, false, "wrong_checkpoint")
	if active_id == "jessica_bank":
		if event_id == "jessica_bank_haul_escaped":
			if payload.get("bank_receipt_paid") != true or not _integer(payload.get("bank_cycle"),0,10000000) or not _integer(payload.get("bank_haul_mask"),1,7): return _reply(false,false,"real_bank_haul_required")
			if payload.get("bank_haul_receipt") != "bank_haul:%d:%d" % [int(payload.bank_cycle),int(payload.bank_haul_mask)]: return _reply(false,false,"bank_receipt_required")
		elif event_id == "jessica_getaway_boarded":
			if payload.get("passenger") != true or payload.get("correct_vehicle") != true or payload.get("door_clear") != true: return _reply(false,false,"jessica_passenger_required")
		elif event_id == "jessica_safe_return":
			if payload.get("route_finished") != true or payload.get("safe_exit") != true or payload.get("correct_vehicle") != true: return _reply(false,false,"physical_getaway_required")
			var travelled: Variant = payload.get("travelled",0)
			if typeof(travelled) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(travelled)) or float(travelled)<25: return _reply(false,false,"physical_getaway_required")
	if event_id == "leader_house_entered" and payload.get("place_id") != "cobra_leader_house": return _reply(false,false,"leader_house_required")
	if active_id == "cobra_finale" and event_id == "transfer_document_collected" and payload.get("place_id") != "cobra_leader_house": return _reply(false,false,"leader_house_required")
	if active_id in RACE_IDS and event_id in ["race_started","race_checkpoint","race_finished"]:
		if event_id=="race_started":
			var vehicle_id: String=str(payload.get("race_vehicle_id",""))
			var point: Variant=payload.get("race_position")
			if vehicle_id.is_empty() or vehicle_id.length()>128 or not point is Vector2 or not point.is_finite(): return _reply(false,false,"race_vehicle_required")
		else:
			var run: Dictionary=_data.get("race_run",{})
			if run.is_empty() or run.countdown>0: return _reply(false,false,"race_not_started")
			if event_id=="race_checkpoint" and int(run.checkpoint)<=int(expected.checkpoint): return _reply(false,false,"race_crossing_required")
			if event_id=="race_finished" and (int(run.checkpoint)!=4 or float(run.progress)<TAU): return _reply(false,false,"race_lap_required")
			if event_id=="race_finished" and run.get("course_version",0)==2 and int(run.place)!=1: return _reply(false,false,"race_win_required")
		var elapsed: Variant = payload.get("elapsed", -1)
		if typeof(elapsed) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(elapsed)) or float(elapsed) < float(_data.race_elapsed):
			return _reply(false, false, "invalid_elapsed")
		if float(elapsed) >= (180.0 if _data.race_run.get("course_version",0)==2 else 100.0):
			cancel("race_timeout")
			return _reply(false, true, "race_timeout")
		_data.race_elapsed = float(elapsed)
		if event_id=="race_started":
			_data.race_run=preload("res://systems/campaign/CobraStreetProgress.gd").start(str(payload.race_vehicle_id),payload.race_position) if payload.get("race_course",0)==2 else Race.start(str(payload.race_vehicle_id),payload.race_position)
			_data.failure=""
		if event_id == "race_finished" and active_id == "cobra_finale":
			_data.race_run = {}
			_data.race_elapsed = 0.0
			_data.race_outside = 0.0
	_data.step += 1
	if step < Missions.MISSIONS[active_id].steps.size(): return _reply(true, true, "advanced")
	var completed_id := active_id
	var definition: Dictionary = Missions.MISSIONS[completed_id]
	_data.completed.append(completed_id)
	_data.pending_rewards[completed_id] = int(definition.reward)
	for flag in definition.sets_flags: _data.flags[flag] = true
	_data.active_id = ""
	_data.step = 0
	_data.race_elapsed = 0.0
	_data.race_outside = 0.0
	_data.race_run = {}
	var response := _reply(true, true, "completed")
	response.completed = completed_id
	response.reward = int(definition.reward)
	return response

func claim_reward(economy: RefCounted, id: String = "") -> bool:
	if id == "":
		if _data.pending_rewards.is_empty(): return false
		id = str(_data.pending_rewards.keys()[0])
	if not _data.pending_rewards.has(id): return false
	# O recibo da carteira cuida da idempotência. Salve os dois módulos no mesmo snapshot.
	var receipt := "campaign:" + id
	var paid := bool(economy.grant_reward(receipt, int(_data.pending_rewards[id]), String(TranslationServer.translate(str(Missions.MISSIONS.get(id, {}).get("title", ""))))))
	if not paid:
		var wallet: Dictionary = economy.snapshot()
		var entry: Dictionary = wallet.get("transactions", {}).get("reward:" + receipt, {})
		if entry.get("amount", -1) != _data.pending_rewards[id] or entry.get("kind", "") != "reward": return false
	_data.pending_rewards.erase(id)
	if not _data.claimed_rewards.has(id): _data.claimed_rewards.append(id)
	return true

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data): return false
	_data = data.duplicate(true)
	_data.version = 2
	_data.legacy_skipped = _data.get("legacy_skipped",[]).duplicate()
	if int(data.version) == 1:
		if data.completed.has("cobra_supply") or data.completed.has("cobra_finale") or data.active_id in ["cobra_supply","cobra_finale"]:
			_data.legacy_skipped = ["jessica_bank"]
		if data.active_id == "cobra_finale":
			_data.step = 0
			_data.race_run = {}
			_data.race_elapsed = 0.0
			_data.race_outside = 0.0
			_data.failure = "leader_race_restart_required"
	_data.step = int(_data.step)
	_data.race_elapsed = float(_data.race_elapsed)
	_data.race_outside = float(_data.get("race_outside",0.0))
	_data.race_run = _data.get("race_run",{}).duplicate(true)
	if _data.race_run.get("course_version",0)==2:
		# Rivais são corpos transitórios. Reabrir um save reinicia a largada,
		# nunca restaura o jogador adiante enquanto os adversários voltam ao início.
		_data.step=0
		_data.race_run={}
		_data.race_elapsed=0.0
		_data.race_outside=0.0
		_data.failure="race_restart_required"
	if race_stage_active() and _data.step>0 and _data.race_run.is_empty():
		# Pre-angular saves lack a trustworthy car/start/trajectory. Keep mission/unlocks,
		# but require a new physical start instead of inventing a completed lap.
		_data.step=0
		_data.race_elapsed=0.0
		_data.race_outside=0.0
		_data.failure="race_restart_required"
	for id in _data.pending_rewards: _data.pending_rewards[id] = int(_data.pending_rewards[id])
	return true

static func validate_snapshot(data: Dictionary) -> bool:
	var aftermath: Variant = data.get("aftermath",{})
	if not aftermath is Dictionary or not aftermath.get("call_complete",false) is bool: return false
	if aftermath.get("call_complete",false) and (not data.get("completed") is Array or not data.completed.has("cobra_finale")): return false
	for key in ["version", "active_id", "step", "completed", "flags", "pending_rewards", "claimed_rewards", "race_elapsed", "failure"]:
		if not data.has(key): return false
	if not _integer(data.version, 1, 2) or not _integer(data.step, 0, 99): return false
	var legacy: bool = int(data.version) == 1
	var skipped: Variant = data.get("legacy_skipped",[])
	if not skipped is Array or (not skipped.is_empty() and skipped != ["jessica_bank"]): return false
	if not skipped.is_empty() and not (data.get("completed",[]).has("cobra_supply") or data.get("completed",[]).has("cobra_finale") or data.get("active_id","") in ["cobra_supply","cobra_finale"]): return false
	if not data.active_id is String or not data.failure is String or data.failure.length() > 256: return false
	for key in ["completed", "claimed_rewards"]:
		if not data[key] is Array: return false
		var seen := {}
		for id in data[key]:
			if not id is String or not Missions.ORDER.has(id) or seen.has(id): return false
			seen[id] = true
	for key in ["flags", "pending_rewards"]:
		if not data[key] is Dictionary: return false
	var order: Array = Missions.LEGACY_ORDER if legacy else Missions.ORDER.filter(func(id): return not skipped.has(id))
	if data.completed.size() > order.size(): return false
	for i in data.completed.size():
		if data.completed[i] != order[i]: return false
	for id in data.pending_rewards:
		if not data.completed.has(id) or data.claimed_rewards.has(id) or not _integer(data.pending_rewards[id], int(Missions.MISSIONS[id].reward), int(Missions.MISSIONS[id].reward)): return false
	for id in data.claimed_rewards:
		if not data.completed.has(id): return false
	for id in data.completed:
		if not data.pending_rewards.has(id) and not data.claimed_rewards.has(id): return false
		for flag in Missions.MISSIONS[id].sets_flags:
			if data.flags.get(flag) != true: return false
	for flag in data.flags:
		var valid := false
		for id in data.completed:
			if Missions.MISSIONS[id].sets_flags.has(flag) and data.flags[flag] == true: valid = true
		if not valid: return false
	if data.active_id != "":
		if not Missions.ORDER.has(data.active_id) or data.completed.has(data.active_id): return false
		var required: String = Missions.MISSIONS[data.active_id].requires
		if legacy and data.active_id == "cobra_supply": required = "cobra_collection"
		if required != "" and not data.completed.has(required) and not skipped.has(required): return false
		var steps: int = 3 if legacy and data.active_id == "cobra_finale" else Missions.MISSIONS[data.active_id].steps.size()
		if int(data.step) >= steps: return false
	elif int(data.step) != 0: return false
	var street: bool=data.get("race_run",{}) is Dictionary and data.get("race_run",{}).get("course_version",0)==2
	if typeof(data.race_elapsed) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(data.race_elapsed)) or float(data.race_elapsed) < 0.0 or float(data.race_elapsed) > (180.0 if street else 100.0): return false
	var race_active: bool = data.active_id in RACE_IDS and int(data.step) < 6 and not (legacy and data.active_id == "cobra_finale")
	if not race_active and float(data.race_elapsed) != 0.0: return false
	var outside: Variant=data.get("race_outside",0.0)
	if typeof(outside) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(outside)) or outside<0 or outside>=(20.0 if street else 4.0): return false
	if (not race_active or data.step==0) and outside!=0: return false
	var run: Variant=data.get("race_run",{})
	if not Race.validate(run): return false
	if not run.is_empty():
		if not race_active or data.step==0: return false
		if int(run.checkpoint)!=int(data.step)-1: return false
		if run.checkpoint>0 and (run.countdown!=0 or not run.initialized): return false
		if run.checkpoint==4 and run.progress<TAU: return false
		if run.countdown==0 and not run.initialized: return false
		if run.countdown>0 and (data.step!=1 or data.race_elapsed!=0 or run.initialized): return false
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

static func _reply(ok: bool, changed: bool, reason: String) -> Dictionary:
	return {"ok": ok, "changed": changed, "reason": reason, "completed": "", "reward": 0}
