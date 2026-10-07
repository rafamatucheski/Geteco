extends Node
var session
var community: Node3D
var wash: Node3D
var mining_job: Node3D
var travel: Node3D
var north_pass: Node3D
func configure(owner_session) -> void:
	session=owner_session
	community=preload("res://runtime/desert/community/DesertCommunityRuntime.gd").new()
	wash=preload("res://activities/desert_wash/DesertWash.gd").new()
	mining_job=preload("res://gameplay/mining/jobs/MiningYardJob.gd").new()
	travel=preload("res://runtime/secret_travel/SecretTravel.gd").new()
	north_pass=preload("res://runtime/desert/north_pass/DesertNorthPass.gd").new()
	for component in [community,wash,mining_job,travel,north_pass]:
		add_child(component)
		component.configure(session)
func busy() -> bool: return is_instance_valid(wash) and wash.active
func controls_locked() -> bool: return is_instance_valid(wash) and wash.controls_locked()
func map_markers() -> Array[Dictionary]:
	var result: Array[Dictionary]=[{"point":preload("res://activities/desert_wash/DesertWashCourse.gd").gate(0),"title":"Leito seco"}]
	if preload("res://runtime/desert/community/DesertCommunityState.gd").data(session.state.world_state).step<5:
		result.append({"point":preload("res://world/desert/community/DesertCommunitySite.gd").RADIO,"title":"Água para Santa Lua"})
	if preload("res://gameplay/mining/jobs/MiningYardJobState.gd").data(session.state.world_state).status!="complete":
		result.append({"point":preload("res://gameplay/mining/jobs/MiningYardJob.gd").CONTACT,"title":"Limpeza da cava"})
	return result
func nearest_action() -> Dictionary:
	if busy(): return {"id":"desert","target":"wash:cancel","label":"Abandonar prova do leito seco"}
	for component in [travel,community,mining_job,wash]:
		var action: Dictionary=component.nearest_action()
		if action.is_empty(): continue
		if component==wash:
			action.id="desert"
			action.target="wash:"+str(action.target)
		return action
	return {}
func perform(action: Dictionary) -> bool:
	var target:=str(action.get("target",""))
	if target.begins_with("wash:"): return wash.perform(target.trim_prefix("wash:"))
	if target=="secret_fast_travel": return travel.perform()
	if target=="yard_job": return mining_job.perform(action)
	return community.perform(action)
func handles(action: Dictionary) -> bool:
	var target:=str(action.get("target",""))
	return target.begins_with("wash:") or target=="secret_fast_travel" or target=="yard_job" or target.begins_with("community:")
func objective() -> String:
	for component in [wash,mining_job,community]:
		var text: String=component.objective()
		if not text.is_empty(): return text
	return ""
func target_position() -> Vector3:
	for component in [wash,mining_job,community]:
		if not component.objective().is_empty(): return component.target_position()
	return Vector3.ZERO
func save_block_reason() -> String:
	for component in [wash,mining_job,community]:
		var reason: String=component.save_block_reason()
		if not reason.is_empty(): return reason
	return ""
func cancel_attempt() -> void:
	for component in [wash,mining_job,community,travel,north_pass]: component.cancel_attempt()

func stop_tracking() -> void:
	preload("res://runtime/desert/community/DesertCommunityState.gd").track(session.state.world_state,false)
	mining_job.suspend()

func append_tracking_buttons() -> void:
	var state:=preload("res://runtime/desert/community/DesertCommunityState.gd").data(session.state.world_state)
	if state.step>0 and state.step<5 and not state.active:
		session._button("Acompanhar: Água para Santa Lua",_track_water)
	if not objective().is_empty():
		session._button("Acompanhar história principal",_track_story)

func _track_water() -> void:
	session.close_menu()
	if session.state.region_id!="desert" or session.is_transition_blocked() or busy(): return
	mining_job.suspend()
	preload("res://runtime/desert/DesertContractState.gd").track(session.state.world_state,"")
	preload("res://runtime/desert/community/DesertCommunityState.gd").track(session.state.world_state,true)
	session.save_game()

func _track_story() -> void:
	session.close_menu()
	if session.state.region_id!="desert" or session.is_transition_blocked() or busy(): return
	stop_tracking()
	preload("res://runtime/desert/DesertContractState.gd").track(session.state.world_state,"")
	session.save_game()
