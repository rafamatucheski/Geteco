extends SceneTree
## Testes puros de autoridade/migração; a integração real e o benchmark renderizado
## são scripts separados. Este teste ainda usa o runner Godot .NET do projeto.
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const POLICY := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const CAMPAIGN := preload("res://systems/campaign/CampaignRuntime.gd")
const MISSIONS := preload("res://data/campaign/HarborMissions.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("NORTH_GATEWAY_PROGRESS ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func run() -> void:
	for count in MISSIONS.ORDER.size():
		var checkpoint: Dictionary = FIXTURE.prefix(count)
		check(CAMPAIGN.validate_snapshot(checkpoint),"valid current campaign prefix %d"%count)
		check(not POLICY.campaign_completed(checkpoint),"bridge closed before final mission, prefix %d"%count)
	var runtime = CAMPAIGN.new()
	var won_race: Dictionary = FIXTURE.before_document()
	won_race.step = 6
	check(runtime.restore_snapshot(won_race),"fixture represents won finale race before entering leader house")
	check(not POLICY.campaign_completed(runtime.snapshot()),"winning the race alone does not finish construction")
	var entered: Dictionary = runtime.apply_event("leader_house_entered",{"target_id":"cobra_leader_house","on_foot":true,"place_id":"cobra_leader_house"})
	check(entered.ok and runtime.step==7,"real house event advances final mission")
	check(not POLICY.campaign_completed(runtime.snapshot()),"entering leader house alone keeps bridge closed")
	var wrong: Dictionary = runtime.apply_event("transfer_document_collected",{"target_id":"transfer_document","on_foot":true,"place_id":"harbor_street"})
	check(not wrong.ok and not POLICY.campaign_completed(runtime.snapshot()),"document from wrong place cannot unlock bridge")
	var result: Dictionary = FIXTURE.final_event(runtime)
	check(result.ok and result.completed==str(MISSIONS.ORDER.back()),"actual final mission event completes ledger")
	var complete: Dictionary = runtime.snapshot()
	var before: Dictionary = complete.duplicate(true)
	check(POLICY.campaign_completed(complete),"bridge opens with final reward still pending")
	check(complete==before,"policy leaves campaign snapshot unchanged")
	check(not complete.get("aftermath",{}).get("call_complete",false),"fixture has not completed act-two call")
	check(POLICY.campaign_completed(JSON.parse_string(JSON.stringify(complete))),"JSON round-trip preserves unlock")
	var legacy: Dictionary = FIXTURE.prefix(MISSIONS.LEGACY_ORDER.size(),true)
	check(POLICY.campaign_completed(legacy),"completed version-1 save opens bridge before migration")
	var migrated = CAMPAIGN.new()
	check(migrated.restore_snapshot(JSON.parse_string(JSON.stringify(legacy))),"old completed save migrates through real campaign")
	check(POLICY.campaign_completed(migrated.snapshot()),"migration keeps old legitimate completion unlocked")
	check(migrated.snapshot().legacy_skipped==["jessica_bank"],"old completion does not invent Jessica mission completion")
	var old_active: Dictionary = FIXTURE.prefix(MISSIONS.LEGACY_ORDER.size()-1,true)
	old_active.active_id = str(MISSIONS.ORDER.back())
	old_active.step = 2
	check(migrated.restore_snapshot(old_active),"unfinished legacy finale is accepted for safe restart")
	check(migrated.step==0 and not POLICY.campaign_completed(migrated.snapshot()),"unfinished old finale remains locked after restart")
	for invalid in [null,[],true,"cobra_finale",{}, {"completed":["cobra_finale"]}]:
		check(not POLICY.campaign_completed(invalid),"malformed or non-campaign value denied: "+str(invalid))
	var forged: Dictionary = FIXTURE.prefix(0)
	forged.flags.cobra_defeated = true
	check(not POLICY.campaign_completed(forged),"standalone victory flag cannot unlock bridge")
	forged = complete.duplicate(true)
	forged.completed = [str(MISSIONS.ORDER.back())]
	check(not POLICY.campaign_completed(forged),"final id without ordered prerequisites denied")
	forged = complete.duplicate(true)
	forged.pending_rewards.clear()
	check(not POLICY.campaign_completed(forged),"corrupt reward ledger cannot unlock bridge")
	forged = complete.duplicate(true)
	forged.completed = null
	forged.legacy_skipped = ["jessica_bank"]
	check(not POLICY.campaign_completed(forged),"wrong completed type denied safely even in legacy migration data")
	print("NORTH_GATEWAY_PROGRESS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
