extends SceneTree

const CONVERTER := preload("res://migration/v1/V1SaveConverter.gd")
const FIXTURES := preload("res://tests/migration_v1/V1Fixtures.gd")
const GAME_STATE := preload("res://runtime/GameState.gd")

var failures: Array[String] = []
var checks := 0

func _init() -> void:
	_test_start()
	_test_intermediate()
	_test_interior()
	_test_vehicle()
	_test_reward_received()
	_test_invalid()
	_test_unknown_fields()
	_test_determinism_and_immutability()
	if checks == 0: failures.append("test body did not execute")
	if failures.is_empty():
		print("MIGRATION_V1 PASS (%d checks, 7 synthetic scenarios)" % checks)
		quit(0)
	else:
		for failure in failures: push_error(failure)
		print("MIGRATION_V1 FAIL (%d failures / %d checks)" % [failures.size(),checks])
		quit(1)

func _test_start() -> void:
	var converted := CONVERTER.convert(FIXTURES.start())
	_expect(converted.ok,"start converts")
	_expect(converted.ready_for_publication,"start is publication-ready")
	_expect(converted.proposal.economy.balance == 3000,"start preserves money")
	_expect(converted.proposal.world.pedestrian.position == [49.375,0.0,93.4375],"start converts XY pixels to XZ metres")
	_expect(_accepts(converted.proposal),"start passes the unmodified V2 validator")

func _test_intermediate() -> void:
	var converted := CONVERTER.convert(FIXTURES.intermediate())
	_expect(converted.ok,"intermediate proposal validates")
	_expect(not converted.ready_for_publication,"intermediate exposes missing personal-car decision")
	_expect(converted.proposal.economy.balance == 4120,"intermediate balance is exact")
	_expect(converted.proposal.economy.weapons.pistol == {"magazine":7,"reserve":31},"intermediate ammo is exact")
	_expect(converted.proposal.campaign.completed == ["primeiro_giro","cobra_contact"],"mission prefix is mapped")
	_expect(converted.proposal.campaign.claimed_rewards == ["primeiro_giro","cobra_contact"],"claimed rewards remain claimed")
	_expect(converted.proposal.economy.transactions["reward:campaign:primeiro_giro"].amount == 150,"first reward receipt is historical")
	_expect(converted.proposal.economy.transactions["reward:campaign:cobra_contact"].amount == 120,"cobra reward receipt is historical")
	_expect(_accepts(converted.proposal),"intermediate passes the unmodified V2 validator")

func _test_interior() -> void:
	var converted := CONVERTER.convert(FIXTURES.interior())
	_expect(converted.ok,"interior proposal validates")
	_expect(converted.proposal.place_id == "mountain_cabin","interior ID is preserved")
	_expect(not converted.proposal.world.has("pedestrian"),"interior does not publish a false exterior pedestrian point")
	_expect(_has_decision(converted,"interior_return"),"interior return requires an explicit decision")
	_expect(converted.proposal.world.cold.temperature == 72.5,"cold temperature is preserved")
	_expect(_accepts(converted.proposal),"interior passes the unmodified V2 validator")

func _test_vehicle() -> void:
	var converted := CONVERTER.convert(FIXTURES.vehicle())
	_expect(converted.ok,"vehicle proposal validates")
	_expect(converted.proposal.world.vehicles.size() == 1,"vehicle is proposed once")
	if converted.proposal.world.vehicles.is_empty(): return
	var vehicle: Dictionary = converted.proposal.world.vehicles[0]
	_expect(vehicle.position == [100.0,0.0,50.0],"vehicle coordinates preserve unit conversion")
	_expect(is_equal_approx(vehicle.yaw,-0.25-PI/2.0),"vehicle yaw uses documented axis transform")
	_expect(vehicle.health == 70.0 and vehicle.paint == "336699ff","vehicle health and paint are preserved")
	_expect(_accepts(converted.proposal),"vehicle passes the unmodified V2 validator")

func _test_reward_received() -> void:
	var converted := CONVERTER.convert(FIXTURES.reward_received())
	_expect(converted.ok,"already-received reward proposal validates")
	_expect(converted.proposal.economy.balance == 7777,"historical reward never changes the saved balance")
	_expect(converted.proposal.economy.transactions["reward:mountain_bunker_cash_01"].amount == 1500,"world reward gets exact receipt")
	_expect(converted.proposal.world.rewards.has("mountain_bunker_cash_01"),"world reward marker is preserved")
	_expect(_accepts(converted.proposal),"reward proposal passes the unmodified V2 validator")

func _test_invalid() -> void:
	var converted := CONVERTER.convert(FIXTURES.invalid_format())
	_expect(not converted.source_valid,"invalid version is rejected as source")
	_expect(not converted.ok and not converted.ready_for_publication,"invalid format cannot publish")
	_expect(not converted.incompatibilities.is_empty(),"invalid format explains incompatibility")

func _test_unknown_fields() -> void:
	var converted := CONVERTER.convert(FIXTURES.unknown_fields())
	_expect(converted.ok,"unknown fields do not corrupt the safe proposal")
	_expect(not converted.ready_for_publication,"unknown fields block automatic publication")
	_expect(_has_unconverted(converted,"future_top_level"),"unknown top-level field is returned")
	_expect(_has_unconverted(converted,"player.future_player_field"),"unknown player field is returned")
	_expect(_has_unconverted(converted,"world.future_world_field"),"unknown world field is returned")
	_expect(_accepts(converted.proposal),"proposal with reported unknown fields passes V2 validator")

func _test_determinism_and_immutability() -> void:
	var source := FIXTURES.vehicle()
	var before := source.duplicate(true)
	var first := CONVERTER.convert(source)
	var second := CONVERTER.convert(source)
	_expect(source == before,"converter does not mutate source dictionary")
	_expect(first == second,"repeated calls produce identical results")

func _accepts(snapshot: Dictionary) -> bool:
	return GAME_STATE.new().restore_snapshot(snapshot)

func _has_decision(result: Dictionary, code: String) -> bool:
	for row in result.decisions_required:
		if row.code == code: return true
	return false

func _has_unconverted(result: Dictionary, path: String) -> bool:
	for row in result.unconverted_fields:
		if row.path == path: return true
	return false

func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
