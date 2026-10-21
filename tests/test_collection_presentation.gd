extends SceneTree
const VIEW = preload("res://ui/CollectionPresentation.gd")
const CATALOG = preload("res://data/catalogs/AchievementCatalog.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	assert(VIEW.progress(CATALOG.ACHIEVEMENTS.secret_lead,{"collectibles":2},false) == Vector2(2,3))
	assert(VIEW.progress(CATALOG.ACHIEVEMENTS.shark,{"money":0},true) == Vector2(10000,10000))
	assert(VIEW.progress(CATALOG.ACHIEVEMENTS.first_lead,{"collectibles":12},false) == Vector2(1,1))
	assert(VIEW.icon_name("first_race",CATALOG.ACHIEVEMENTS.first_race,true) == "flag-check")
	assert(VIEW.icon_name("personal_best",CATALOG.ACHIEVEMENTS.personal_best,true) == "stopwatch")
	for id in CATALOG.ACHIEVEMENTS:
		var row = VIEW.row(id,CATALOG.ACHIEVEMENTS[id],false,true,{})
		assert(row.find_child("Progress",true,false).value == 0)
		row.free()
	var legacy = VIEW.row("old_unknown_id",{},true,false,{})
	assert(legacy.get_meta("completed") and legacy.find_child("Progress",true,false).value == 1)
	legacy.free()
	print("COLLECTION_PRESENTATION PASS: partial progress, permanent unlocks, clamping, semantic icons, all 19 rows, legacy collectible")
	quit()
