extends SceneTree
const NIGHT := preload("res://activities/desert_drag/DragNightProgress.gd")
const CATALOG := preload("res://activities/desert_drag/DragNightCatalog.gd")
const RACE := preload("res://activities/desert_drag/DesertDrag.gd")
const TUNING := preload("res://gameplay/desert_cars/DesertTuning.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks+=1
	print("NIGHT_CATEGORY ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)

func _initialize() -> void:
	var parts := {"engine":"street_cam","tires":"drag_tires"}
	var over := {"engine":"race_cam","turbo":"turbo_large"}
	check(CATALOG.preparation_value(parts)==4600,"budget counts the value of installed mechanical parts")
	check(CATALOG.preparation_value({"ecu":"rival_digo_ecu"})==1800,"free rival gift has a nonzero reference value")
	check(CATALOG.preparation_value({"paint":"paint_pearl","neon":"neon_amber"})==0,"cosmetics never consume the mechanical budget")
	check(CATALOG.fits_category(parts,"street") and not CATALOG.fits_category(over,"street") and not CATALOG.fits_category(over,"prepared"),"both authored caps reject over-budget builds")
	check(CATALOG.fits_category(over,"livre") and not CATALOG.fits_category({},"unknown"),"Livre stays unrestricted and unknown categories are rejected")
	for rival in RACE.RIVALS:
		for category in ["street","prepared"]:
			var authored := RACE.rival_parts(rival)
			var limited := CATALOG.rival_preparation(authored,category)
			check(CATALOG.fits_category(limited,category),"rival obeys player cap: "+rival+" / "+category)
			var subset := true
			for slot in limited: subset=subset and authored.get(slot,"")==limited[slot]
			check(subset,"budget filtering keeps the rival's authored parts: "+rival+" / "+category)
	var signatures := []
	for category in CATALOG.CATEGORIES:
		var world := {}
		check(NIGHT.begin(world,"digo","night_budget_car","desert_faisca","desert_faisca",category).ok,"category can begin: "+category)
		check(NIGHT.next_pass(world).category==category,"episode persists selected category")
		var before := world.duplicate(true)
		if category!="livre": check(NIGHT.record_finish(world,1,0,"night_budget_car","desert_faisca",over,10,11,201).is_empty() and world==before,"finish cannot award an over-budget preparation")
		for i in 4:
			var result := NIGHT.record_finish(world,1,i,"night_budget_car","desert_faisca",parts,10+i,11+i,NIGHT.DISTANCES[i])
			check(result.get("finished",false),"within-cap physical result accepted: "+category+" / "+str(i))
		check(NIGHT.validate_snapshot(JSON.parse_string(JSON.stringify(NIGHT.data(world)))),"category and record namespace survive JSON")
		signatures.append(NIGHT.record_key("desert_faisca",parts,201,category))
	check(signatures[0]!=signatures[1] and signatures[1]!=signatures[2] and signatures[0]!=signatures[2],"identical cars in three categories have separate records")
	var legacy := {}
	NIGHT.begin(legacy,"digo","legacy_car","desert_faisca","desert_faisca")
	legacy[NIGHT.KEY].current.erase("category")
	check(NIGHT.validate_snapshot(NIGHT.data(legacy)) and NIGHT.next_pass(legacy).category=="livre","pre-category episodes load as Livre without migration")
	var expected := ("rules1|desert_faisca|201|"+JSON.stringify(NIGHT.mechanical_parts(parts))).sha256_text()
	check(NIGHT.record_key("desert_faisca",parts,201,"livre")==expected,"legacy Livre record hash is byte-for-byte preserved")
	legacy[NIGHT.KEY].current.category="unknown"
	check(not NIGHT.validate_snapshot(NIGHT.data(legacy)),"unknown saved category is rejected")
	print("NIGHT_CATEGORIES_DONE checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
