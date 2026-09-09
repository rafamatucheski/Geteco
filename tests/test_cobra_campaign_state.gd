extends SceneTree

const LEDGER = preload("res://world/harbor/campaign/CobraCampaignState.gd")
const CAMPAIGN = preload("res://CampaignState.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _run() -> void:
	var campaign := CAMPAIGN.new()
	root.add_child(campaign)
	var state := LEDGER.new()
	state.bind(campaign)
	_check(not state.begin("cobra_contact"), "Contact requires existing delivery")
	campaign.set_campaign_flag(&"harbor_delivery_complete", true)
	_check(state.get_status("cobra_contact").available, "Delivery unlocks contact immediately")
	_check(state.rest_until_next_day(), "Safe resting advances arrival day")
	_check(state.begin("cobra_contact"), "Legacy delivery bridges contact")
	_check(not state.rest_until_next_day(), "No rest during active mission")
	state.set_stage(2)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	_check(campaign.restore_from_save(saved), "Campaign save roundtrip")
	_check(state.data.stage == 2, "Stage was serialized")
	state.sync_legacy()
	_check(state.data.stage == 2 and state.data.active_id == "cobra_contact", "Live ledger reattaches after restore")
	state.fail()
	_check(state.begin("cobra_contact") and state.data.stage == 0, "Retry resets checkpoints")
	_check(state.complete_mission("cobra_contact"), "Contact completes")
	_check(not state.complete_mission("cobra_contact"), "Cannot complete twice")
	_check(state.claim_reward("cobra_contact").get("cash", 0) == 120, "Reward token generated")
	_check(state.claim_reward("cobra_contact").is_empty(), "No duplicate reward")
	saved = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	_check(campaign.restore_from_save(saved), "Reward save roundtrip")
	_check(state.claim_reward("cobra_contact").is_empty(), "No duplicate after reload")
	_check(state.get_status("cobra_race").available, "Next mission available same day")
	_check(state.data.active_id == "", "No automatic start after completion")
	_check(not state.rest_until_next_day(true), "Combat prohibits resting")
	state.tick(LEDGER.DAY_SECONDS - 1)
	state.data.unlock_days["cobra_race"] = 99
	_check(state.get_status("cobra_race").available, "Old save day gates no longer block jobs")
	state.tick(1)
	_check(state.begin("cobra_race"), "Race can start without a day requirement")
	_check(state.complete(), "Race completes")
	_check(state.data.cobra_access == 2 and state.data.civilian_reputation == 0, "Access is not civilian reputation")
	for id in ["cobra_collection", "cobra_supply", "cobra_finale"]:
		_check(state.rest_until_next_day(), "Safe rest skips wait")
		_check(state.begin(id), "Fixed prerequisite chain: " + id)
		_check(state.complete(), "Complete " + id)
	_check(state.data.defeated and state.data.cobra_access == 0 and state.data.civilian_reputation == 3, "Finale defeats gang, restores civilians")
	state.data.secret_owned["ashbend_coupe"] = true
	state.data.optional_flags["resident_helped"] = true
	saved = JSON.parse_string(JSON.stringify(campaign.to_save_data()))
	campaign.restore_from_save(saved)
	state.sync_legacy()
	_check(state.data.secret_owned.get("ashbend_coupe", false), "Secret ownership persists")
	_check(state.data.optional_flags.get("resident_helped", false), "Optional discovery persists")
	campaign.reset_campaign()
	state.sync_legacy()
	_check(not state.data.defeated and state.data.completed.is_empty(), "New game clears isolated namespace")
	campaign.queue_free()
	print("COBRA CAMPAIGN STATE: %d failure(s)" % failures)
	quit(1 if failures else 0)
