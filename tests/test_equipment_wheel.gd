extends SceneTree
## Production input/inventory/lifecycle integration. Run with --no-save --skip-arrival.
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
var world
var checks := 0
var failures: Array[String] = []
var out := "res://artifacts/equipment-wheel-20261026/functional"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("EQUIPMENT_WHEEL: "+label)
func frames(count := 2) -> void:
	for i in count: await process_frame
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()
func point_to(index: int) -> void:
	var wheel = world.session.equipment_wheel
	var event := InputEventMouseMotion.new()
	event.position = wheel.view.size*.5 + Vector2.from_angle(-PI*.5+TAU*float(index)/8.0)*minf(wheel.view.size.x,wheel.view.size.y)*.25
	Input.parse_input_event(event)
	await frames()
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"/"+label+".png")
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	current_scene = world
	check(await STARTUP.wait_for_startup(world),"real session starts after streaming and curtain")
	if not failures.is_empty(): world.free(); quit(1); return
	var session = world.session
	var wheel = session.equipment_wheel
	var economy = session.state.economy
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	check(world.production.no_save and wheel != null,"wheel installed without touching personal saves")
	controls.import_bindings({"weapon_next":[{"key":KEY_Q},{"mouse":MOUSE_BUTTON_WHEEL_UP}]})
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.keycode = KEY_Q
	check(q.is_action("weapon_wheel") and not q.is_action("weapon_next"),"legacy Q migrates to wheel without instant weapon cycling")
	controls.reset_bindings()
	check(economy.grid_equip_bag("backpack"),"fixture equips backpack")
	check(economy.grant_weapon("pistol"),"fixture grants pistol")
	check(economy.grant_weapon("hunting_rifle"),"fixture grants rifle")
	check(economy.grant_item("apple",3) and economy.grant_item("water",2),"fixture stores consumables")
	session.state.equip_weapon("fists")
	world.gameplay.health = 60
	await key(KEY_Q,true)
	check(wheel.active and wheel.view.visible and is_equal_approx(Engine.time_scale,.2),"hold Q opens and slows actual world")
	check(not paused and not session.modal and world.player.input_locked,"wheel locks controls while world continues")
	await point_to(1)
	check(wheel.entries[wheel.selected].id == "pistol","mouse selects actual pistol sector")
	check(session.state.equipped_weapon == "fists","hover does not equip early")
	var ammo_before: Dictionary = session.state.get_ammo("pistol").duplicate(true)
	var fire := InputEventMouseButton.new()
	fire.button_index = MOUSE_BUTTON_LEFT
	fire.pressed = true
	Input.parse_input_event(fire)
	await frames(3)
	check(not session.state.can_attack() and session.state.get_ammo("pistol") == ammo_before,"held attack cannot fire through wheel")
	fire.pressed = false
	Input.parse_input_event(fire)
	await shot("weapons-1280")
	await key(KEY_Q,false)
	check(not wheel.active and session.state.equipped_weapon == "pistol","release Q commits selected weapon")
	check(is_equal_approx(Engine.time_scale,1) and not world.player.input_locked,"release restores world speed and controls")
	await key(KEY_Q,true)
	await key(KEY_E,true)
	await key(KEY_E,false)
	check(wheel.active and wheel.page == 1,"E switches to consumables while Q remains held")
	await point_to(2)
	check(wheel.entries[wheel.selected].id == "apple","apple sector comes from carried inventory")
	var apples_before := int(economy.inventory.get("apple",0))
	var health_before: float = world.gameplay.health
	await shot("consumables-1280")
	await key(KEY_Q,false)
	check(is_equal_approx(world.gameplay.health,health_before+8) and int(economy.inventory.get("apple",0)) == apples_before-1,"release consumes exactly one selected apple and heals")
	await key(KEY_Q,false)
	check(int(economy.inventory.get("apple",0)) == apples_before-1,"duplicate release cannot double-consume")
	world.gameplay.health = 100
	await key(KEY_Q,true)
	await key(KEY_E,true)
	await key(KEY_E,false)
	await point_to(2)
	check(not wheel.entries[wheel.selected].enabled,"full health disables food")
	await key(KEY_Q,false)
	check(int(economy.inventory.get("apple",0)) == apples_before-1,"full health preserves consumable")
	await key(KEY_Q,true)
	await point_to(0)
	await key(KEY_ESCAPE,true)
	await key(KEY_ESCAPE,false)
	await key(KEY_Q,false)
	check(not wheel.active and not paused and session.state.equipped_weapon == "pistol" and is_equal_approx(Engine.time_scale,1),"Esc cancels selection without pausing or changing weapon")
	check(economy.grid_store_weapon("hunting_rifle","trunk"),"fixture stores rifle in trunk")
	await key(KEY_Q,true)
	check(not wheel.entries[5].enabled,"remote trunk rifle cannot be selected")
	await key(KEY_Q,false)
	await key(KEY_Q,true)
	session.show_inventory()
	check(not wheel.active and session.modal and world.player.input_locked and is_equal_approx(Engine.time_scale,1),"another menu cancels wheel and owns input lock")
	await key(KEY_Q,false)
	session.close_menu()
	await frames()
	check(not world.player.input_locked,"closing replacement menu restores control")
	await key(KEY_Q,true)
	world._toggle_pause()
	await frames()
	check(paused and not wheel.active and is_equal_approx(Engine.time_scale,1),"external pause cancels slow motion")
	world._toggle_pause()
	await key(KEY_Q,false)
	await key(KEY_Q,true)
	world.gameplay.health -= 1
	await frames(3)
	check(not wheel.active and is_equal_approx(Engine.time_scale,1) and not world.player.input_locked,"damage cancels wheel without leaving slow motion")
	await key(KEY_Q,false)
	await key(KEY_Q,true)
	var transition: int = session._begin_transition("equipment_wheel_test")
	check(transition > 0 and not wheel.active and is_equal_approx(Engine.time_scale,1),"transition cancels before acquiring lifecycle ownership")
	session._finish_transition(transition)
	world.player.input_locked = false
	await key(KEY_Q,false)
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	Input.parse_input_event(middle)
	await frames()
	check(world.camera.mouse_orbit_active(),"fixture starts actual middle-button camera orbit")
	await key(KEY_Q,true)
	check(wheel.active and not world.camera.mouse_orbit_active() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,"opening wheel releases camera capture for pointer selection")
	middle.pressed = false
	Input.parse_input_event(middle)
	await key(KEY_Q,false)
	check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED,"closing wheel cannot restore stale camera capture")
	var honor := preload("res://runtime/TakeshiHonor.gd")
	honor.record_finish(session.state.world_state,true,72.0)
	check(honor.claim_state(session.state,"katana").ok and session.state.equip_weapon("katana"),"fixture equips legitimately awarded katana")
	world.gameplay.rage.restore(100)
	check(world.gameplay.request_rage() and world.gameplay.rage.active,"fixture starts real RAGE slow motion")
	await key(KEY_Q,true)
	check(wheel.active and not world.gameplay.rage.active and is_equal_approx(Engine.time_scale,.2),"wheel ends RAGE before taking clock ownership")
	await key(KEY_Q,false)
	check(is_equal_approx(Engine.time_scale,1),"wheel after RAGE restores normal time instead of stale slow motion")
	check(await session.enter_place("maciota",false),"real Maciota interior admission")
	await frames(5)
	var weapons_before: Dictionary = economy.snapshot().weapons.duplicate(true)
	await key(KEY_Q,true)
	check(wheel.active and not wheel.entries[1].enabled,"Maciota wheel cannot equip guns")
	await point_to(1)
	await key(KEY_Q,false)
	check(session.state.equipped_weapon == "fists" and not session.state.can_attack(),"Maciota preserves holster and attack restriction")
	check(economy.snapshot().weapons == weapons_before,"safe area preserves owned weapons and ammunition")
	var restored = preload("res://runtime/GameState.gd").new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(session.state.snapshot()))) and not restored.weapons_allowed() and restored.equipped_weapon == "fists","garage snapshot restore stays unarmed")
	await key(KEY_Q,true)
	for dimensions: Vector2i in [Vector2i(800,600),Vector2i(1920,1080)]:
		root.content_scale_size = dimensions
		root.size = dimensions
		await frames(4)
		check(wheel.view.size.is_equal_approx(Vector2(dimensions)),"wheel covers resized viewport "+str(dimensions))
		await shot("weapons-"+str(dimensions.x))
	await key(KEY_Q,false)
	check(wheel.open(),"wheel can open again after all lifecycle interruptions")
	world.free()
	await frames()
	check(is_equal_approx(Engine.time_scale,1),"scene disposal releases time owner")
	print("EQUIPMENT_WHEEL_RESULT ",checks," checks failures=",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
