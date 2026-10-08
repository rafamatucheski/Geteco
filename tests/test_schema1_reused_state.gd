extends SceneTree
## Exercise the real SaveStore migration boundary against an already populated
## GameState. All files are inside a newly created, unique temporary directory.
const STATE := preload("res://runtime/GameState.gd")
const INTRO := preload("res://systems/Progression.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20).timeout.connect(func(): push_error("SCHEMA1_REUSED_STATE timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var directory := OS.get_temp_dir().path_join("geteco-schema1-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: quit(2); return
	var intro := INTRO.new()
	intro.set_location("harbor_garage")
	intro.interact("maciota")
	intro.interact("mechanic")
	intro.interact("workbench")
	var legacy: Dictionary = intro.snapshot()
	legacy.inventory["pistol"] = 1
	check(INTRO.validate_snapshot(legacy),"authored schema-1 garage progress is valid")
	var expected := STATE.new()
	check(expected.restore_snapshot(legacy),"schema-1 migration into fresh state succeeds")
	var live := STATE.new()
	var reward: Dictionary = STATE.CARGO_REWARDS[0]
	check(live.economy.grant_world_reward(reward).ok,"existing world reward is granted legitimately")
	live.world_state.rewards.append(reward.id)
	live.world_state.time = .83
	live.world_state.weather = 2
	live.combat_state = {"health":60.0,"armor":40.0,"crime_points":0,"hidden_time":0.0,"customization":{}}
	check(STATE.new().restore_snapshot(live.snapshot()),"previous modern state and reward receipt are consistent")
	var before: Dictionary = live.snapshot()
	var invalid: Dictionary = legacy.duplicate(true)
	invalid.phase = "unknown"
	check(not live.restore_snapshot(invalid) and live.snapshot()==before,"invalid legacy input does not partially reset live state")
	var store := STORE.new()
	store.path = directory.path_join("legacy.json")
	var file := FileAccess.open(store.path,FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify(legacy))
	file.close()
	var result: Dictionary = store.load_into(live)
	check(result.get("ok",false) and result.get("migrated",false),"real SaveStore loads schema-1 into a reused state")
	check(live.world_state==expected.world_state,"migration replaces old world rewards, weather and time with fresh defaults")
	check(live.combat_state==expected.combat_state,"migration does not inherit old health or armor")
	check(live.snapshot()==expected.snapshot(),"migration result is independent of the previous session")
	check(live.owns_weapon("pistol") and live.economy.snapshot().inventory.get("garage_part",0)==1,"legacy weapon and carried garage part survive migration")
	check(live.place_id=="maciota" and not live.weapons_allowed(),"legacy garage location keeps weapon restrictions")
	check(STATE.new().restore_snapshot(live.snapshot()),"migrated modern snapshot has no orphaned world reward")
	store.path = directory.path_join("upgraded.json")
	check(store.save(live)==OK,"migrated reused state can immediately publish a valid modern save")
	var reloaded := STATE.new()
	var reload_result := store.load_into(reloaded)
	# JSON represents integer world weather as float; compare both disk-shaped values.
	check(reload_result.get("ok",false) and JSON.parse_string(JSON.stringify(reloaded.snapshot()))==JSON.parse_string(JSON.stringify(expected.snapshot())),"published migration survives a cold disk reload")
	print("SCHEMA1_REUSED_STATE checks=",checks," failures=",failures," isolated=",directory)
	quit(0 if failures==0 else 1)
