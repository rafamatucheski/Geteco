extends SceneTree
## Regional variety, retained resources and a real isolated save round trip.
## Resource contracts only; rendered driving and timing are validated separately.
const FLEET := preload("res://runtime/FleetCatalog.gd")
const FLEET_STATE := preload("res://runtime/FleetState.gd")
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const NEW_IDS := ["besouro_1300", "mare_microvan", "toco_minitruck"]
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	var roster = load("res://runtime/TrafficFleetRoster.gd")
	if roster == null:
		check(false, "regional civilian roster loads")
		finish()
		return
	var contexts := [
		["harbor", "market_street", "city"],
		["harbor", "road/dock_street", "work"],
		["harbor", "warehouse_way", "work"],
		["harbor", "island_esplanade", "executive"],
		["harbor", "northbank_civic_avenue", "executive"],
		["mountain", "mountain_pass", "mountain"],
		["desert", "desert_town_main", "desert"],
	]
	var all_ids: Array = roster.all_car_types()
	check(all_ids.size() > 7, "active civilian roster expands beyond seven cars")
	for context in contexts:
		var key: String = roster.profile(context[0], context[1])
		check(key == context[2], "authored street context: " + str(context))
		var pool: Array = roster.POOLS[key]
		check(not pool.is_empty(), key + " has civilian choices")
		for id: String in pool:
			check(id in all_ids and not FLEET.spec(id).is_empty(), key + ": retained catalog choice " + id)
	for id in ["supra_a80", "monaliza", "porto_rosso", "cobra_v8", "jessica_jetta_gli", "digo_gol_1993", "digo_amarok_2014", "vertice_midengine"]:
		check(id not in all_ids, "narrative/special model excluded from ordinary traffic: " + id)
	check("toco_minitruck" in roster.POOLS.work and "mare_microvan" in roster.POOLS.work, "working streets gain compact commercial silhouettes")
	check("besouro_1300" in roster.POOLS.city, "popular streets gain rounded compact silhouette")
	check("aurora_executive" in roster.POOLS.executive, "executive streets use existing luxury sedan")
	var parking = load("res://runtime/RoadsideParking.gd")
	for id: String in NEW_IDS:
		check(id in FLEET.all(), "new model is included in the catalog: " + id)
		check(id in parking.CITY_MODELS, "new model supports ordinary parking: " + id)
		var spec: Dictionary = FLEET.spec(id)
		check(not spec.is_empty() and ResourceLoader.exists(str(spec.get("scene", ""))), "packed scene exists: " + id)
		var state = STATE.new()
		var stage := Node3D.new()
		root.add_child(stage)
		var car := VEHICLE.new()
		car.archetype = id
		car.vehicle_id = "roster_test_" + id
		car.paint_color = Color("758b62")
		car.position = Vector3(10, .12, 50)
		stage.add_child(car)
		car.process_mode = Node.PROCESS_MODE_DISABLED
		var record: Dictionary = FLEET_STATE.capture(car, "harbor")
		check(FLEET_STATE.validate(record), "native vehicle snapshot is accepted: " + id)
		state.world_state.vehicles = [record]
		var store = STORE.new()
		store.path = "user://civilian-roster-tests-%d/%s.json" % [Time.get_ticks_usec(), id]
		check(store.save(state) == OK, "isolated disk save succeeds: " + id)
		var loaded = STATE.new()
		check(store.load_into(loaded).get("ok", false), "isolated disk reload succeeds: " + id)
		var records: Array = loaded.world_state.get("vehicles", [])
		check(records.size() == 1 and records[0].archetype == id and records[0].paint == record.paint, "model identity and paint survive disk round trip: " + id)
		stage.free()
	finish()

func finish() -> void:
	print("CIVILIAN_FLEET_ROSTER ", JSON.stringify({"checks":checks,"failures":failures,"performance_certified":false}))
	quit(0 if failures.is_empty() else 1)
