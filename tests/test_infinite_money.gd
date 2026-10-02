extends SceneTree
const ECONOMY := preload("res://systems/economy/Economy.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func _wallet() -> void:
	var wallet := ECONOMY.new()
	wallet.grant_reward("initial",125)
	wallet.cheat_infinite_money = true
	check(wallet.balance == ECONOMY.LIMIT,"Cheat exposes funds to existing shop eligibility checks")
	for index in 3:
		check(wallet.spend(ECONOMY.LIMIT,"service_%d" % index),"Repeated maximum charges remain affordable")
	check(wallet.snapshot().balance == 125,"Unlimited spending preserves actual wallet")
	check(wallet.spend(ECONOMY.LIMIT,"service_0"),"Service retry remains idempotent")
	check(not wallet.spend(1,"service_0"),"Cheat preserves receipt conflict protection")
	check(not wallet.spend(-1,"negative"),"Cheat rejects negative charges")
	check(wallet.purchase("weapon","pistol","pistol").ok,"Weapon purchase works without sufficient actual funds")
	check(wallet.purchase("weapon","pistol","pistol").ok,"Purchase retry remains idempotent")
	check(not wallet.purchase("weapon","smg","locked").ok,"Cheat preserves discovery requirements")
	check(wallet.purchase("supply","lockpick","supply").ok,"Supplies can be purchased")
	check(wallet.buy_ammo("pistol",12,"ammo"),"Ammunition can be purchased")
	var ammo := wallet.get_ammo("pistol")
	check(wallet.buy_ammo("pistol",12,"ammo") and wallet.get_ammo("pistol") == ammo,"Ammunition retry does not duplicate rounds")
	check(wallet.purchase_body_armor(0,100,"armor").ok,"Armor can be purchased")
	check(not wallet.purchase_body_armor(100,100,"full").ok,"Full armor remains rejected")
	check(wallet.snapshot().balance == 125,"All purchase paths preserve actual funds")
	check(wallet.grant_world_reward({"id":"pickup","kind":"cash","amount":250}).ok,"Cash pickup works while cheat is active")
	check(wallet.grant_world_reward({"id":"pickup","kind":"cash","amount":250}).ok and wallet.snapshot().balance == 375,"Reward receipts remain idempotent")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(wallet.snapshot()))
	check(not saved.has("cheat_infinite_money") and ECONOMY.validate_snapshot(saved),"Save stays valid and excludes temporary cheat")
	wallet.cheat_infinite_money = false
	check(wallet.balance == 375,"Disabling restores actual funds including rewards")
	check(not wallet.spend(500,"too_expensive"),"Normal insufficient funds protection returns")
	wallet.cheat_infinite_money = true
	var invalid := saved.duplicate(true)
	invalid.balance = -1
	check(not wallet.restore_snapshot(invalid) and wallet.cheat_infinite_money,"Invalid restore does not mutate cheat state")
	check(wallet.restore_snapshot(saved) and not wallet.cheat_infinite_money and wallet.balance == 375,"Loading valid save clears cheat and restores wallet")
	wallet.cheat_infinite_money = true
	wallet.enable_grid_inventory()
	check(wallet.purchase("supply","lockpick","grid_supply").ok,"Cheat works with production grid inventory")
	check(wallet.snapshot().balance == 375,"Grid purchases preserve actual funds")

func _type(code: String) -> void:
	for letter in code:
		var key := InputEventKey.new()
		key.keycode = letter.to_upper().unicode_at(0)
		key.physical_keycode = key.keycode
		key.unicode = letter.unicode_at(0)
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		key = key.duplicate()
		key.pressed = false
		Input.parse_input_event(key)
		await process_frame

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Requires --no-save to protect personal saves")
		quit(2)
		return
	_wallet()
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	world.set_meta("skip_dispatch",true)
	root.add_child(world)
	current_scene = world
	for frame in 1800:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"Production session ready")
	if world.session != null and world.session.ready_for_play:
		var wallet = world.session.state.economy
		await _type("grana")
		check(wallet.cheat_infinite_money,"Real keyboard input activates money cheat")
		await create_timer(.12).timeout
		var hud = world.find_child("MoneyHUD",true,false)
		check(hud != null and hud.amount.text == "$ ∞","Production HUD displays infinity")
		var actual: int = wallet.snapshot().balance
		check(wallet.spend(ECONOMY.LIMIT,"production_service"),"Production wallet supports unlimited charge")
		check(wallet.snapshot().balance == actual,"Production service preserves actual funds")
		await _type("grana")
		await create_timer(.12).timeout
		check(not wallet.cheat_infinite_money and wallet.balance == actual,"Typing again disables cheat without consuming actual funds")
		check(hud != null and not hud.amount.text.contains("∞"),"HUD restores numeric wallet")
		paused = true
		await _type("grana")
		check(not wallet.cheat_infinite_money,"Pause blocks cheat input")
		paused = false
		await _type("godmode")
		check(world.gameplay.god_mode,"Existing godmode cheat still works after shared prefix")
		await _type("grana")
		check(wallet.cheat_infinite_money,"Money cheat works after godmode")
	world.queue_free()
	for frame in 3: await process_frame
	print("%s infinite money: %d checks" % ["PASS" if failures.is_empty() else "FAIL",checks])
	quit(0 if failures.is_empty() else 1)
