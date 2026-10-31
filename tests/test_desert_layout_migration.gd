extends SceneTree
## A migração de coordenadas legadas precisa ser única, cópia-na-leitura e local ao
## exterior do deserto. Quem chama ainda é dono da validação completa do esquema do save.
const MIGRATION := preload("res://runtime/desert/DesertLayoutMigration.gd")
const STATE := preload("res://runtime/GameState.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
const YARD_STATE := preload("res://gameplay/mining/jobs/MiningYardJobState.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const CANYON_LAYOUT := preload("res://world/desert/canyon/DesertSmugglerLayout.gd")
const CANYON_TERRAIN := preload("res://world/desert/canyon/DesertSmugglerTerrain.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func point(record: Dictionary) -> Vector3:
	return Vector3(record.position[0], record.position[1], record.position[2])

func run() -> void:
	var old := {
		"region_id": "desert", "place_id": "",
		"economy": {"balance": 12345, "inventory": {"water": 2}},
		"campaign": {"completed": ["preserve_this_mission"]},
		"world": {
			"pedestrian": {"region": "desert", "position": [-180, .08, -900]},
			"vehicles": [
				{"region": "desert", "position": [-900, .1, -1320], "vehicle_id": "same_drag_car"},
				{"region": "harbor", "position": [-180, .1, -900], "vehicle_id": "same_harbor_car"}],
			"mining_equipment": {"mineradora_haul_pit": {"region": "desert", "position": [-180, -28, -1760]}},
			"garage_rewards": {"vehicles": {
				"outside": {"region_id": "desert", "place_id": "", "position": [-180, .04, -900]},
				"inside": {"region_id": "desert", "place_id": "desert_digo", "position": [0, .04, 0]}}},
			"desert_discoveries": {"preserve": true},
			"desert_smuggler_canyon": {"version":1,"defeated_mask":37,"cache_mask":0}
		}
	}
	var original := old.duplicate(true)
	var migrated: Dictionary = MIGRATION.migrate_snapshot(old)
	check(old == original, "Migration does not mutate the input snapshot")
	check(migrated.world.get("desert_layout_version") == 2, "Migrated snapshot records compact-layout version 2")
	check(point(migrated.world.pedestrian).is_equal_approx(Vector3(-180, .08, -560)), "Town pedestrian relocates rigidly by 340m")
	check(point(migrated.world.vehicles[0]).is_equal_approx(Vector3(-760, .1, -800)), "Saved drag car follows the intact 800m strip")
	check(migrated.world.vehicles[1] == original.world.vehicles[1], "Fleet record in Harbor remains byte-equivalent")
	check(point(migrated.world.mining_equipment.mineradora_haul_pit).is_equal_approx(Vector3(-180, -28, -1080)), "Saved mining equipment keeps excavation depth")
	check(point(migrated.world.garage_rewards.vehicles.outside).is_equal_approx(Vector3(-180, .04, -560)), "Garage fleet outdoors follows its desert position")
	check(migrated.world.garage_rewards.vehicles.inside == original.world.garage_rewards.vehicles.inside, "Garage fleet indoors keeps room-local coordinates")
	check(migrated.economy == original.economy and migrated.campaign == original.campaign and migrated.world.desert_discoveries == original.world.desert_discoveries, "Inventory, money, campaign and discovery progress survive migration unchanged")
	check(migrated.world.desert_smuggler_canyon==original.world.desert_smuggler_canyon, "Shortening the canyon preserves defeated defenders and armory progress")
	check(MIGRATION.migrate_snapshot(migrated) == migrated, "Loading a migrated snapshot twice never moves it again")
	for relocation in [
		{"id":"natural arch", "old":Vector3(-790,.08,-690), "expected":Vector3(-650,.08,-690)},
		{"id":"wind dunes", "old":Vector3(-25,.08,-622), "expected":Vector3(-25,.08,-460)},
		{"id":"salt pan", "old":Vector3(-790,.08,-1420), "expected":Vector3(150,.08,-680)},
		{"id":"dry wash", "old":Vector3(-650,.08,-1080), "expected":Vector3(149,.08,-1090)},
		{"id":"drag return beside old salt pan", "old":Vector3(-790,.1,-1350), "expected":Vector3(-650,.1,-830)},
		{"id":"straightened mining access gate approach", "old":Vector3(-167,.08,-1611), "expected":Vector3(-180,.08,-939)},
		{"id":"mining access highway junction", "old":Vector3(-180,.08,-1540), "expected":Vector3(-180,.08,-900)},
		{"id":"mining approach with preserved lateral offset", "old":Vector3(-164,.08,-1605), "expected":Vector3(-177,.08,-933.9230769)},
		{"id":"Tiao camp keeps its authored offset ahead of access mapping", "old":Vector3(-212,.08,-1572), "expected":Vector3(-212,.08,-932)},
		{"id":"shortened canyon bridge entrance", "old":Vector3(-1344,.12,-775), "expected":Vector3(-1204,.12,-603.5)},
		{"id":"shortened canyon bridge preserves lateral walking offset", "old":Vector3(-1343.275,.12,-655), "expected":Vector3(-1203.275,.12,-567.5)},
		{"id":"shortened canyon bridge camp-side endpoint", "old":Vector3(-1344,.12,-530), "expected":Vector3(-1204,.12,-530)},
		{"id":"canyon camp stays rigidly positioned beside shorter bridge", "old":Vector3(-1344,.08,-492), "expected":Vector3(-1204,.08,-492)},
		{"id":"canyon armory keeps its original camp-local position", "old":Vector3(-1360,.08,-481), "expected":Vector3(-1220,.08,-481)},
	]:
		var landmark_save := original.duplicate(true)
		landmark_save.world.pedestrian.position = [relocation.old.x,relocation.old.y,relocation.old.z]
		var landmark_result: Dictionary = MIGRATION.migrate_snapshot(landmark_save)
		check(point(landmark_result.world.pedestrian).is_equal_approx(relocation.expected), "Legacy exterior save follows " + str(relocation.id))
	var interior := original.duplicate(true)
	interior.place_id = "desert_digo"
	interior.world.pedestrian.position = [0, .04, -2400]
	var indoor: Dictionary = MIGRATION.migrate_snapshot(interior)
	check(indoor.world.pedestrian == interior.world.pedestrian, "Pedestrian in a room at z=-2400 keeps interior coordinates")
	var harbor := original.duplicate(true)
	harbor.region_id = "harbor"
	harbor.world.pedestrian.region = "harbor"
	var other: Dictionary = MIGRATION.migrate_snapshot(harbor)
	check(other.world.pedestrian == harbor.world.pedestrian, "Harbor pedestrian is unaffected by desert migration")
	check(MIGRATION.valid_version({}) and MIGRATION.valid_version({"desert_layout_version": 2}), "Missing legacy marker and current marker are accepted")
	check(not MIGRATION.valid_version({"desert_layout_version": "2"}) and not MIGRATION.valid_version({"desert_layout_version": 3}), "Corrupt and future coordinate versions cannot silently remigrate")
	var real := FIXTURE.full_snapshot(Vector3(-180, .08, -900), true)
	real.region_id = "desert"
	real.world.pedestrian = {"region": "desert", "position": [-180, .08, -900]}
	real.world.erase("desert_layout_version")
	var state := STATE.new()
	check(state.restore_snapshot(real), "Real GameState restores a valid legacy desert save")
	var saved: Dictionary = state.snapshot()
	check(point(saved.world.pedestrian).is_equal_approx(Vector3(-180, .08, -560)) and saved.world.desert_layout_version == 2, "GameState persists migrated coordinates with their version")
	check(STATE.new().restore_snapshot(saved), "Migrated full snapshot remains schema-valid on the next load")
	canyon_floor_migration_contract(original)
	yard_migration_contract()
	for failure in failures: push_error(failure)
	print("DESERT_LAYOUT_MIGRATION ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func canyon_floor_migration_contract(original: Dictionary) -> void:
	for old: Vector3 in [Vector3(-1344,-72,-655),Vector3(-1324,-35,-655)]:
		var legacy := original.duplicate(true)
		legacy.world.pedestrian.position=[old.x,old.y,old.z]
		var migrated: Dictionary=MIGRATION.migrate_snapshot(legacy)
		var mapped := point(migrated.world.pedestrian)
		var ground := CANYON_TERRAIN.surface_height(Vector2(mapped.x,mapped.z))
		check(CANYON_LAYOUT.BOUNDS.has_point(Vector2(mapped.x,mapped.z)) and is_equal_approx(mapped.x,-1204.0+(old.x+1344.0)*.6) and is_equal_approx(mapped.z,-567.5), "Legacy canyon wall/floor save follows the smaller formation: " + str(old))
		check(mapped.y>=ground+.09, "Legacy canyon wall/floor save cannot restore below the current physical surface: " + str(old))
		check(MIGRATION.migrate_snapshot(migrated)==migrated and migrated.world.desert_smuggler_canyon==original.world.desert_smuggler_canyon, "Canyon floor migration remains one-shot and preserves encounter progress")

func yard_migration_contract() -> void:
	for status: String in ["active","complete"]:
		var legacy := FIXTURE.full_snapshot(Vector3(0,.08,0),true)
		legacy.world.erase("desert_layout_version")
		var delivered: Dictionary = {}
		for index in 3:
			delivered[str(index)]={"position":[-195.0+float(index)*2.0,-27.42,-1751.5],"rotation":[0.0,float(index)*.1,0.0]}
		legacy.world[YARD_STATE.KEY]={"version":1,"status":status,"delivered":delivered}
		var wallet := ECONOMY.new()
		check(wallet.restore_snapshot(legacy.economy), "Mining migration fixture restores its real wallet: " + status)
		if status == "complete":
			check(wallet.grant_world_reward({"id":YARD_STATE.RECEIPT,"kind":"cash","amount":YARD_STATE.REWARD}).get("ok",false), "Completed old mining work has its genuine payment receipt")
		legacy.economy=wallet.snapshot()
		var original := legacy.duplicate(true)
		var migrated: Dictionary=MIGRATION.migrate_snapshot(legacy)
		check(legacy==original, "Old mining checkpoint remains untouched: " + status)
		var poses_preserved := true
		for identity in delivered:
			var old_record: Dictionary=delivered[identity]
			var new_record: Dictionary=migrated.world[YARD_STATE.KEY].delivered[identity]
			poses_preserved=poses_preserved and point(new_record).is_equal_approx(point(old_record)+Vector3(0,0,680)) and new_record.rotation==old_record.rotation
		check(poses_preserved and migrated.world[YARD_STATE.KEY].status==status, "Three delivered rocks move680m with IDs, rotations and job status preserved: " + status)
		check(YARD_STATE.valid(migrated.world[YARD_STATE.KEY]) and YARD_STATE.validate_wallet(migrated.world,migrated.economy), "Migrated mining positions and receipts satisfy current contracts: " + status)
		check(migrated.economy==original.economy and migrated.campaign==original.campaign, "Mining migration preserves payment and campaign exactly: " + status)
		check(MIGRATION.migrate_snapshot(migrated)==migrated, "Delivered mining rocks never migrate twice: " + status)
		var state := STATE.new()
		check(state.restore_snapshot(legacy) and YARD_STATE.valid(state.world_state[YARD_STATE.KEY]), "Real GameState accepts an old checkpoint with delivered mining rocks: " + status)
		if status == "complete":
			check(not YARD_STATE.claim(migrated.world,wallet).get("ok",false) and wallet.snapshot()==original.economy, "Migrated completed work cannot pay its receipt again")
