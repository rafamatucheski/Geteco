extends SceneTree
## Pure side-quest, malformed save and isolated disk persistence contracts.
const PROGRESS := preload("res://systems/campaign/MountainStoryProgress.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var world := {"rewards":["mountain_cargo_plane_treasure_01","mountain_cargo_plane_smg_01"],
		"mountain_progression":{"version":1,"shadow_announced":true},"unrelated":{"keep":true}}
	var old := world.duplicate(true)
	check(PROGRESS.validate_snapshot(PROGRESS.data(world)),"old saves get an independent empty ledger")
	check(world == old,"reading migration defaults leaves old saves and cargo receipts untouched")
	check(not PROGRESS.record(world,"vicente_note",proof("vicente_note")),"cave conclusion requires the actual preceding investigation")
	for event in PROGRESS.EVENTS:
		var before := world.duplicate(true)
		for field in ["alive","on_foot","reachable","dialogue_complete"]:
			var rejected := proof(event)
			rejected[field] = false
			check(not PROGRESS.record(world,event,rejected),event+" rejects "+field+"=false")
		for distance in [-.1,PROGRESS.INTERACTION_RANGE+.001,INF,NAN,"1",true,null]:
			var rejected := proof(event)
			rejected.distance = distance
			check(not PROGRESS.record(world,event,rejected),event+" rejects invalid or distant position "+str(distance))
		for scope in [{"region":"harbor"},{"place":"harbor_bank"},{"anchor":"mountain_cabin"}]:
			var rejected := proof(event)
			rejected.merge(scope,true)
			check(not PROGRESS.record(world,event,rejected),event+" rejects another location or anchor")
		check(world == before,"all rejected "+event+" proofs are atomic")
		check(PROGRESS.record(world,event,proof(event)),event+" accepts living pedestrian reading at the correct physical evidence")
		check(not PROGRESS.record(world,event,proof(event)),event+" has exactly one narrative receipt")
		check(PROGRESS.validate_snapshot(JSON.parse_string(JSON.stringify(PROGRESS.data(world)))),event+" survives JSON round trip")
		if event == "cargo_identified": check(PROGRESS.data(world).completed.is_empty(),"seeing the plane alone does not complete the cargo quest")
		if event == "cargo_manifest": check(PROGRESS.data(world).completed == ["cobra_cargo"],"manifest finishes the first quest and opens Vicente's trail")
		if event == "cave_shelter": check(PROGRESS.data(world).completed == ["cobra_cargo"],"the old expedition map alone cannot stand in for Vicente's note")
	check(PROGRESS.data(world).completed == ["cobra_cargo","vicente_trail"],"two authored side quests finish in the mountain")
	check(PROGRESS.next_event(PROGRESS.data(world)).is_empty(),"finished discoveries cannot restart or repay")
	var untouched := world.duplicate(true)
	untouched.erase("mountain_story")
	check(untouched == old,"story never changes loot receipts, skiing or unrelated world state")
	var complete := PROGRESS.data(world)
	for version in [null,"1",true,0,2,1.5,NAN,INF]:
		var corrupt := complete.duplicate(true)
		corrupt.version = version
		check(not PROGRESS.validate_snapshot(corrupt),"bad schema rejected: "+str(version))
	for key in ["events","receipts","completed"]:
		var corrupt := complete.duplicate(true)
		corrupt[key] = null
		check(not PROGRESS.validate_snapshot(corrupt),"required ledger array: "+key)
	var corrupt := complete.duplicate(true)
	corrupt.events[1] = "vicente_note"
	check(not PROGRESS.validate_snapshot(corrupt),"out-of-order discoveries rejected")
	corrupt = complete.duplicate(true)
	corrupt.receipts[1] = "mountain_cargo_plane_treasure_01"
	check(not PROGRESS.validate_snapshot(corrupt),"ordinary loot receipt cannot impersonate a story discovery")
	corrupt = complete.duplicate(true)
	corrupt.completed.append("vicente_trail")
	check(not PROGRESS.validate_snapshot(corrupt),"duplicate completion rejected")
	corrupt = complete.duplicate(true)
	corrupt.events.pop_back()
	corrupt.receipts.pop_back()
	check(not PROGRESS.validate_snapshot(corrupt),"completion without the final read receipt rejected")
	var invalid := {"mountain_story":corrupt}
	var invalid_before := invalid.duplicate(true)
	check(not PROGRESS.record(invalid,"cargo_identified",proof("cargo_identified")) and invalid == invalid_before,"bad saved state is preserved instead of resetting and regranting progress")
	check(not PROGRESS.validate_snapshot(null) and not PROGRESS.validate_snapshot([]),"malformed top-level values rejected safely")
	var folder := "res://evidence/mountain-story-progress-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var file := FileAccess.open(folder.path_join("story.json"),FileAccess.WRITE)
	check(file != null,"isolated persistence file opens")
	if file != null:
		file.store_string(JSON.stringify(world))
		file.close()
		var restored: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("story.json")))
		check(restored is Dictionary and PROGRESS.validate_snapshot(restored.get("mountain_story")),"isolated disk load validates the completed ledger")
		# O JSON devolve inteiros como decimais; compara os dois lados depois do mesmo ciclo.
		check(JSON.stringify(restored) == JSON.stringify(JSON.parse_string(JSON.stringify(world))),"disk save preserves story, old loot and unrelated data")
		check(not PROGRESS.record(restored,"vicente_note",proof("vicente_note")),"reloading cannot duplicate the final discovery")
	var dialogue: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/mountain-story-dialogue.json"))
	for event in PROGRESS.EVENTS:
		check(dialogue is Dictionary and dialogue.get(event,[]).size() >= 2,"authored conversation exists for "+event)
		for line in dialogue.get(event,[]):
			check(not str(line.get("pt","")).is_empty() and not str(line.get("en","")).is_empty(),"both supported dialogue languages: "+event)
	print("MOUNTAIN_STORY_PROGRESS_RESULT checks=%d failures=%d evidence=%s" % [checks,failures.size(),folder])
	quit(0 if failures.is_empty() else 1)

func proof(event: String) -> Dictionary:
	return {"region":"mountain", "place":PROGRESS.place_for(event),
		"anchor":PROGRESS.CAVE if PROGRESS.place_for(event) == PROGRESS.CAVE else "cargo_plane",
		"alive":true,"on_foot":true,"reachable":true,"distance":PROGRESS.INTERACTION_RANGE,"dialogue_complete":true}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
