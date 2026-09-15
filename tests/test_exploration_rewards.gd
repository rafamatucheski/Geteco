extends SceneTree
## Real player progression/save code; omit only presentation-heavy character art.
class TestPlayer extends "res://Player.gd":
	func _build_dante_3d_viewport() -> void: pass
	func _rebuild_dante_costume() -> void: pass
	func _update_equipped_weapon_3d_mesh() -> void: pass
	func _physics_process(_delta: float) -> void: pass

var failures: Array[String] = []
const CATALOG := preload("res://CollectibleCatalog.gd")
const BANK := preload("res://audio/rewards/RewardAudioBank.gd")
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for i in count: await process_frame
func run() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	root.get_node("SaveManager").clear_pending_save()
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	var hud = load("res://HUD.tscn").instantiate()
	world.add_child(hud)
	var player := TestPlayer.new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	world.add_child(player)
	await frames()
	player.restore({"money":0,"collectibles_found":[],"unlocked_achievements":[]})
	await frames()
	check(player.money == 0 and not hud._achievement_presenting, "Restoration neither pays nor celebrates")
	var ids := CATALOG.get_all_ids()
	# Actual physical pickup callback, not an isolated money helper.
	var item := Collectible.new()
	item.collectible_id = ids[0]
	world.add_child(item)
	item._on_body_entered(player)
	check(item._is_collected and player.money == 100, "First physical discovery pays $50 plus $50 achievement")
	check(hud.achievement_desc_label.text.contains("+$50"), "Achievement announces its actual reward")
	check(not hud._achievement_audio.playing, "Discovery sound gets room before achievement sound")
	check(world.has_node("RewardAudioVoices"), "Physical discovery routes to reward bank")
	var earned := player.money
	item._on_body_entered(player)
	check(player.money == earned, "Same ground item cannot pay twice")
	for i in range(1,5): player.add_collectible(ids[i], "Achado")
	check(player.money == 850, "Five finds pay base rewards, 3/5 bonuses and earned badges")
	check(hud._achievement_queue.size() == 2, "Simultaneous milestones queue instead of replacing each other")
	check(not player.add_collectible(ids[4]) and player.money == 850, "Duplicate ID cannot claim any reward")
	check(player.add_collectible("legacy_unknown") and player.money == 850, "Unknown legacy ID preserved without inflating rewards")
	check(CATALOG.known_count(player.collectibles_found) == 5, "Legacy IDs do not count toward current collection")
	var save := player.serialize()
	player.restore(save)
	await frames()
	player._refresh_weapon_ui()
	check(player.money == 850, "Save roundtrip never pays again")
	player._unlock_achievement("lead_hunter")
	check(player.money == 850, "Direct repeated achievement is idempotent")
	for i in range(5,10): player.add_collectible(ids[i], "Achado")
	player._refresh_weapon_ui()
	check(player.money == 2250, "Complete collection pays all authored bonuses and badges")
	check(player.secret_car_leads == 0, "No fictitious secret-car lead is granted")
	var completed := player.serialize()
	player.restore(completed)
	await frames()
	check(player.money == 2250, "Completed collection remains paid after reload")
	player.armor = 0
	check(player.buy_armor_amount(25, 50) == "COLETE EQUIPADO" and player.armor == 25 and player.money == 2200, "Exploration money buys usable equipment through the real purchase path")
	for kind in ["collectible", "achievement"]:
		var file := AudioStreamWAV.load_from_file(ProjectSettings.globalize_path("res://audio/rewards/" + kind + ".wav"))
		check(file.data == BANK.sound(kind).data, kind + " imports the new authored cue")
	check(is_equal_approx(BANK.sound("collectible").get_length(), 1.15), "Discovery cue lasts 1.15 s")
	check(is_equal_approx(BANK.sound("achievement").get_length(), 2.4), "Achievement cue lasts 2.4 s")
	await create_timer(1.3).timeout
	check(hud._achievement_audio.playing, "Achievement answers after the discovery")
	check(not hud.achievement_panel.get_global_rect().intersects(hud.notice_label.get_global_rect()), "Discovery receipt clears the achievement banner")
	await hud._achievement_tween.finished
	check(hud.achievement_title_label.text == "NA TRILHA", "Queued badge receives its own presentation")
	print("EXPLORATION_REWARDS failures=", failures)
	world.queue_free()
	await frames()
	quit(0 if failures.is_empty() else 1)
