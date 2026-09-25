extends SceneTree
const Economy := preload("res://systems/economy/Economy.gd")
const Campaign := preload("res://systems/campaign/CampaignRuntime.gd")
const Canonical := preload("res://systems/campaign/CanonicalCampaign.gd")
const Vehicles := preload("res://data/catalogs/VehicleCatalog.gd")
const Races := preload("res://data/catalogs/RaceCatalog.gd")
const Drift := preload("res://data/catalogs/DriftZoneCatalog.gd")
const Dialogue := preload("res://systems/campaign/OriginalDialogue.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_economy()
	_campaign()
	_canonical()
	_services()
	print("CATALOGS weapons=%d outfits=%d vehicles=%d races=%d drift=%d collectibles=%d achievements=%d" % [Economy.Weapons.WEAPONS.size(), Economy.Outfits.OUTFITS.size(), Vehicles.VEHICLES.size(), Races.RACES.size(), Drift.ZONES.size(), Economy.Collectibles.ENTRIES.size(), Economy.Achievements.ACHIEVEMENTS.size()])
	for failure in failures: push_error(failure)
	print("%s campaign/economy: %d checks" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

func _services() -> void:
	var economy := Economy.new()
	economy.grant_reward("service_test", 1000)
	var armor_economy := Economy.new()
	armor_economy.grant_reward("armor_funds",1000)
	var armor: Dictionary = armor_economy.purchase_body_armor(35,100,"armor:1")
	_check(armor.ok and armor.armor == 100 and armor_economy.balance == 500,"Body armor debit returns protection only after success")
	var armor_balance := armor_economy.balance
	_check(not armor_economy.purchase_body_armor(100,100,"armor:2").ok and armor_economy.balance == armor_balance,"Full body armor cannot be charged")
	_check(economy.grant_weapon("pistol"), "Pickup grants original weapon")
	_check(not economy.grant_weapon("pistol"), "Pickup duplicate preserves ammo")
	_check(economy.spend(100, "repair:1") and economy.balance == 900, "Service debits exact original price")
	_check(economy.spend(100, "repair:1") and economy.balance == 900, "Service retry does not charge twice")
	_check(not economy.spend(150, "repair:1"), "Service receipt amount cannot change")
	_check(not economy.spend(-1, "bad"), "Negative service charge blocked")
	_check(economy.buy_ammo("pistol", 12, "ammo:1") and economy.balance == 860, "Original ammunition minimum price 40")
	_check(economy.buy_ammo("pistol", 12, "ammo:1") and economy.get_ammo("pistol").reserve == 72, "Ammunition retry does not duplicate rounds")
	_check(not economy.buy_ammo("pistol", 13, "ammo:1"), "Ammunition receipt quantity immutable")
	var restored := Economy.new()
	_check(restored.restore_snapshot(_roundtrip(economy.snapshot())) and restored.snapshot() == economy.snapshot(), "Service/loot/ammunition snapshot roundtrip")
	var dialogue := Dialogue.new()
	_check(dialogue.lines("primeiro_giro_begin").size() == 4, "All original briefing lines")
	_check(dialogue.lines("bank_receipt").size() == 4 and dialogue.lines("bank_receipt")[0].speaker == "HELENA", "Bank dialogue excludes fallback branch")
	_check(dialogue.lines("bank_unavailable").size() == 2, "Original unavailable-bank fallback preserved")
	_check(dialogue.lines("primeiro_giro_finish").size() == 3, "Original return dialogue preserved")
	var extended := Economy.new()
	extended.grant_weapon("pistol")
	_check(extended.reload_weapon("pistol", 18), "Original extended pistol magazine accepted")
	_check(extended.get_ammo("pistol") == {"magazine": 18, "reserve": 54}, "Extended reload conserves ammo")
	_check(not extended.reload_weapon("pistol", 19), "Capacity beyond original customization refused")
	_check(restored.restore_snapshot(_roundtrip(extended.snapshot())), "Extended magazine survives restore")
	var collection := Economy.new()
	for id in Economy.Collectibles.ENTRIES:
		_check(collection.collect(id), "Original collectible pays once")
	_check(collection.balance == 1300, "Original 10 finds plus milestones total 1300")
	_check(not economy.purchase("outfit", "dante_ski", "ski").ok, "Ski outfit absent from original shop ORDER is not sold for free")
	_check(economy.grant_outfit("dante_ski") and economy.equip_outfit("dante_ski"), "Original ski service can grant special outfit")
	var pickup := Economy.new()
	var cash: Dictionary = pickup.grant_world_reward({"id":"test_cash","kind":"cash","amount":250})
	_check(cash.ok and cash.changed and pickup.balance==250,"World cash is granted atomically")
	var cash_retry: Dictionary = pickup.grant_world_reward({"id":"test_cash","kind":"cash","amount":250})
	_check(cash_retry.ok and not cash_retry.changed and pickup.balance==250,"World cash receipt reconciles without duplicate")
	var weapon: Dictionary = pickup.grant_world_reward({"id":"test_smg","kind":"weapon","item":"smg","amount":1,"ammo":20})
	var smg_ammo: Dictionary = pickup.get_ammo("smg")
	_check(weapon.ok and weapon.changed and pickup.owns_weapon("smg") and smg_ammo.reserve==int(Economy.Weapons.WEAPONS.smg.starting_reserve)+20,"Weapon and ammunition grant as one reward")
	var pickup_restored := Economy.new()
	_check(pickup_restored.restore_snapshot(_roundtrip(pickup.snapshot())),"World reward receipt survives snapshot")
	var reserve_before := int(pickup_restored.get_ammo("smg").reserve)
	var weapon_retry: Dictionary = pickup_restored.grant_world_reward({"id":"test_smg","kind":"weapon","item":"smg","amount":1,"ammo":20})
	_check(weapon_retry.ok and not weapon_retry.changed and pickup_restored.get_ammo("smg").reserve==reserve_before,"Loaded weapon reward cannot duplicate ammunition")
	var full_wallet := Economy.new()
	full_wallet.grant_reward("fill",Economy.LIMIT)
	var full_before: Dictionary = full_wallet.snapshot()
	_check(not full_wallet.grant_world_reward({"id":"blocked_cash","kind":"cash","amount":1}).ok and full_wallet.snapshot()==full_before,"Full wallet leaves reward and receipt untouched")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _roundtrip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))

func _economy() -> void:
	var economy := Economy.new()
	_check(economy.balance == 0 and economy.owns_weapon("fists"), "Default wallet and fists")
	_check(not economy.purchase("weapon", "magnum", "test").ok, "Insufficient funds rejected")
	_check(economy.grant_reward("test_start", 10000), "Reward granted")
	_check(not economy.grant_reward("test_start", 10000) and economy.balance == 10000, "Reward receipt idempotent")
	_check(economy.purchase("weapon", "magnum", "test").ok, "Weapon purchase succeeds")
	_check(economy.balance == 9200, "Original Magnum price 800")
	_check(economy.purchase("weapon", "magnum", "test").ok and economy.balance == 9200, "Purchase retry does not charge twice")
	_check(not economy.purchase("outfit", "dante_suit", "test").ok, "Transaction ID cannot be repurposed")
	_check(not economy.purchase("weapon", "smg", "locked").ok, "Discovery lock respected")
	_check(economy.discover("mountain_cargo_plane_smg_01"), "Original discovery unlock ID accepted")
	_check(economy.purchase("weapon", "smg", "locked").ok, "Discovery allows purchase")
	_check(economy.equip_weapon("magnum"), "Owned weapon equipped")
	_check(economy.get_ammo("magnum") == {"magazine": 6, "reserve": 36}, "Original initial ammo")
	_check(economy.consume_ammo("magnum", 6), "Magazine consumed")
	_check(not economy.consume_ammo("magnum", 1), "Empty magazine blocks shot")
	_check(economy.reload_weapon("magnum"), "Reload transfers reserve")
	_check(economy.get_ammo("magnum") == {"magazine": 6, "reserve": 30}, "Ammo conserved")
	_check(not economy.consume_ammo("magnum", -2), "Negative consume cannot create ammo")
	_check(not economy.add_ammo("magnum", -2), "Negative ammo grant refused")
	_check(economy.consume_ammo("fists") and not economy.reload_weapon("fists"), "Melee sentinel supported")
	_check(economy.purchase("outfit", "dante_suit", "suit").ok, "Original outfit purchase")
	_check(economy.equip_outfit("dante_suit"), "Owned outfit equipped")
	_check(not economy.equip_outfit("dante_arctic"), "Unowned outfit refused")
	_check(economy.grant_item("receipt", 1) and economy.consume_item("receipt"), "Quest item use")
	_check(not economy.consume_item("receipt"), "Cannot consume missing item")
	_check(economy.collect("harbor_memorial_letter"), "Original collectible registered")
	_check(not economy.collect("harbor_memorial_letter"), "Collectible idempotent")
	var previous := economy.balance
	_check(economy.evaluate_achievements({"collectibles": 1}) == ["first_lead"], "Original achievement criterion")
	_check(economy.balance == previous + 50, "Original achievement reward")
	_check(economy.evaluate_achievements({"collectibles": 1}).is_empty(), "Achievement idempotent")
	var restored := Economy.new()
	_check(restored.restore_snapshot(_roundtrip(economy.snapshot())), "Economy JSON restore")
	_check(restored.snapshot() == economy.snapshot(), "Economy full roundtrip")
	var original := restored.snapshot()
	for patch in [{"balance": -1}, {"balance": 1.5}, {"version": true}, {"equipped_weapon": "unknown"}, {"outfits": ["unknown"]}, {"inventory": {"x": -1}}, {"discoveries": ["invented"]}, {"weapons": {"fists": {"magazine": 10, "reserve": 0}}}]:
		var corrupt := original.duplicate(true)
		corrupt.merge(patch, true)
		_check(not restored.restore_snapshot(corrupt) and restored.snapshot() == original, "Invalid economy restore rejected transactionally: " + str(patch))

func _campaign() -> void:
	var campaign := Campaign.new()
	var economy := Economy.new()
	_check(not campaign.begin("cobra_finale"), "Cannot skip mission prerequisites")
	_check(campaign.begin("primeiro_giro"), "First original Harbor mission available")
	_check(not campaign.apply_event("bank_receipt_received", {"target_id": "helena", "on_foot": true}).ok, "Bank requires holstered weapon")
	_check(not campaign.apply_event("maciota_delivery_received", {"target_id": "maciota", "on_foot": true}).ok, "Cannot skip bank/parcel")
	for id in Campaign.Missions.ORDER:
		if campaign.active_id == "": _check(campaign.begin(id), "Next mission opens in original order")
		var elapsed := 0.0
		while campaign.active_id != "":
			var step := campaign.current_step()
			var payload := {"target_id": step.target, "on_foot": true, "unarmed": true, "in_vehicle": true, "wanted_level": 0,
				"encounter_cleared": true, "story_vehicle_alive": true, "correct_vehicle": true, "elapsed": elapsed,
				"tow_delivery_ready": true, "race_vehicle_id": RACE_CAR}
			if step.has("checkpoint"): payload.checkpoint = step.checkpoint
			if step.event == "race_started": payload.race_position = RACE_START
			var result: Dictionary = campaign.apply_event(step.event, payload)
			if result.ok and step.event == "race_started":
				_check(_drive_lap(campaign), "Physical lap completes the original race")
				break
			_check(result.ok, "Original required action advances: %s %s" % [step.event, result])
			# Sem progresso a etapa nunca termina: falha registrada em vez de laço infinito.
			if not result.ok: break
			elapsed += 10.0
		if campaign.active_id != "": break
		_check(campaign.claim_reward(economy, id), "Reward claimed once: " + id)
		_check(not campaign.claim_reward(economy, id), "Reward cannot duplicate: " + id)
	_check(economy.balance == 1670, "Six original Harbor rewards total 1670")
	_check(campaign.available_missions().is_empty(), "Completed missions not reoffered")
	var restored := Campaign.new()
	_check(restored.restore_snapshot(_roundtrip(campaign.snapshot())), "Campaign JSON roundtrip")
	_check(restored.snapshot() == campaign.snapshot(), "Campaign restoration exact")
	var invalid := restored.snapshot()
	invalid.completed.reverse()
	_check(not restored.restore_snapshot(invalid), "Reordered completion cannot bypass sequence")
	var race := Campaign.new()
	var race_state := campaign.snapshot()
	race_state.completed = ["primeiro_giro", "cobra_contact"]
	race_state.claimed_rewards = race_state.completed.duplicate()
	race_state.flags = {"harbor_delivery_complete": true, "cobra_contact_complete": true}
	_check(race.restore_snapshot(race_state), "Valid pre-race checkpoint restored")
	race.begin("cobra_race")
	_check(race.apply_event("race_started", {"target_id": "ashbend_start", "in_vehicle": true, "elapsed": 0}).reason == "race_vehicle_required", "Race start without a vehicle is refused")
	_check(race.apply_event("race_started", {"target_id": "ashbend_start", "in_vehicle": true, "elapsed": 0, "race_vehicle_id": RACE_CAR, "race_position": RACE_START}).ok, "Race requires real vehicle")
	_check(not race.apply_event("race_checkpoint", {"target_id": "ashbend_gate_0", "in_vehicle": true, "checkpoint": 1, "elapsed": 3}).ok, "Out-of-order gate rejected")
	_check(_lap_times_out(race), "Original 100-second limit enforced")
	_check(race.active_id == "" and race.begin("cobra_race"), "Failed race retries without payment")
	race.apply_event("race_started",{"target_id":"ashbend_start","in_vehicle":true,"elapsed":0, "race_vehicle_id": RACE_CAR, "race_position": RACE_START})
	# O relógio só corre depois da contagem parada na largada (save com contagem e
	# relógio andando é estado impossível e é recusado na restauração).
	_wait_countdown(race)
	_check(race.advance_race(61.5,true).is_empty() and race.race_elapsed()==61.5,"Clock advances between physical gates")
	var resumed := Campaign.new()
	_check(resumed.restore_snapshot(_roundtrip(race.snapshot())) and resumed.race_elapsed()==61.5,"Mid-race reload preserves elapsed seconds")
	_check(resumed.advance_race(38.5,true)=="race_timeout" and resumed.snapshot().failure=="race_timeout","Restored race expires at original 100 seconds")
	_check(resumed.snapshot().pending_rewards.is_empty(),"Timeout grants no reward")
	race.advance_race(2.5,false)
	_check(resumed.restore_snapshot(_roundtrip(race.snapshot())),"Off-track grace counter survives save")
	_check(resumed.advance_race(1.5,false)=="race_offtrack","Reload does not reset four-second abandonment grace")
	_check(race.advance_race(.1,true).is_empty() and race.snapshot().race_outside==0,"Rejoining road resets abandonment timer")
	_check(race.advance_race(.1,false,true)=="race_offtrack","Crossing inner garden fails immediately")

# A corrida é física (CobraRaceProgress): contagem parada na largada, progresso pelo
# ângulo percorrido na faixa e portões a cada quarto de volta. O teste faz a volta.
const RACE := preload("res://systems/campaign/CobraRaceProgress.gd")
const RACE_CAR := "test_race_car"
var RACE_START: Vector2 = RACE.CENTER + Vector2.from_angle(PI) * RACE.LANE_RADIUS

func _race_point(angle: float) -> Vector2:
	return RACE.CENTER + Vector2.from_angle(angle) * RACE.LANE_RADIUS

func _wait_countdown(campaign) -> void:
	# Para exatamente no fim da contagem: passos extras já contariam como corrida.
	for i in 60:
		if float(campaign.race_status().get("countdown", 0.0)) <= 0.0: return
		campaign.tick_race(.1, RACE_START, RACE_CAR, true)

## Volta completa: envia cada portão quando a própria corrida o registra e a chegada.
func _drive_lap(campaign) -> bool:
	_wait_countdown(campaign)
	var angle := PI
	for tick in 600:
		angle += .08
		var result: Dictionary = campaign.tick_race(.1, _race_point(angle), RACE_CAR, true)
		if not str(result.get("failure", "")).is_empty(): return false
		if int(result.get("crossed", -1)) >= 0:
			var step: Dictionary = campaign.current_step()
			if not campaign.apply_event(step.event, {"target_id": step.target, "in_vehicle": true, "checkpoint": step.get("checkpoint", -1), "elapsed": campaign.race_elapsed()}).ok: return false
		var status: Dictionary = campaign.race_status()
		if int(status.get("checkpoint", 0)) == 4 and float(status.get("progress", 0.0)) >= TAU:
			var finish: Dictionary = campaign.current_step()
			return campaign.apply_event(finish.event, {"target_id": finish.target, "in_vehicle": true, "elapsed": campaign.race_elapsed()}).ok
	return false

## Volta lenta demais: a corrida expira aos 100 s sem pagar nada.
func _lap_times_out(campaign) -> bool:
	_wait_countdown(campaign)
	var angle := PI
	for tick in 200:
		angle += .005
		var result: Dictionary = campaign.tick_race(1.0, _race_point(angle), RACE_CAR, true)
		if str(result.get("failure", "")) == "race_timeout": return campaign.active_id == ""
		if not str(result.get("failure", "")).is_empty(): return false
	return false

func _canonical() -> void:
	var campaign := Canonical.new()
	var economy := Economy.new()
	_check(campaign.catalog.beats.size() == 9 and campaign.catalog.district_one_contracts.size() == 4, "Canonical source fully present")
	_check(not campaign.complete_beat("final_race_completed"), "Canonical order enforced")
	for beat in campaign.catalog.beats:
		if beat.id == "contracts_arc":
			_check(not campaign.complete_beat("contracts_arc_completed"), "Canonical contract gate requires all authored contracts")
			for contract in campaign.catalog.district_one_contracts:
				_check(campaign.complete_contract(contract.id, economy), "Original contract receipt accepted")
				_check(not campaign.complete_contract(contract.id, economy), "Contract cannot pay twice")
		_check(campaign.complete_beat(str(beat.id) + "_completed"), "Canonical beat completion: " + str(beat.id))
	_check(economy.balance == 8300, "Original four contract rewards preserved")
	_check(campaign.snapshot().flags.ankle_monitor_active == false, "Canonical aftermath removes monitor")
	_check(campaign.snapshot().regions.has("coastal_frontier"), "Canonical region unlock preserved")
	var restored := Canonical.new()
	_check(restored.restore_snapshot(_roundtrip(campaign.snapshot())), "Canonical JSON roundtrip")
	var corrupt := campaign.snapshot()
	corrupt.flags.boss_one_defeated = false
	_check(not restored.restore_snapshot(corrupt), "Derived canonical flags checked")
