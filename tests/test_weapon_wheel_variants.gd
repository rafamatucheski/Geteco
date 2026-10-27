extends SceneTree
## Uses production input, carried inventory transfers and garage restrictions.
## Rendered runs also save the actual wheel at 1280x720 and 800x600.
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
const ECONOMY := preload("res://systems/economy/Economy.gd")
const ICONS := preload("res://systems/inventory/InventoryIcons.gd")
const VARIANTS := [
	["pistol", "magnum", "pistol_suppressed"],
	["smg", "smg_compact", "smg_tactical"],
	["shotgun", "sawed_off", "shotgun_auto"],
]
var world
var checks := 0
var failures: Array[String] = []
var out := "res://artifacts/weapon-variants-20261027/wheel"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("WEAPON_WHEEL_VARIANTS: " + label)
func frames(count := 2) -> void:
	for i in count: await process_frame
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()
func pad(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()
func point_to(index: int) -> void:
	var wheel = world.session.equipment_wheel
	var event := InputEventMouseMotion.new()
	event.position = wheel.view.size * .5 + Vector2.from_angle(-PI*.5+TAU*float(index)/8.0)*minf(wheel.view.size.x,wheel.view.size.y)*.25
	Input.parse_input_event(event)
	await frames()
func shot(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out+"/"+label+".png")
func move_stored_to_trunk(id: String) -> bool:
	var economy = world.session.state.economy
	var data: Dictionary = economy.grid_snapshot()
	for container: String in ["pockets", "storage"]:
		for index in data[container].size():
			if data[container][index].id == "weapon:" + id:
				return economy.grid_move(container, index, "trunk")
	return false

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	root.size = Vector2i(1280, 720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	check(await STARTUP.wait_for_startup(world), "production session starts")
	if not failures.is_empty(): world.free(); quit(1); return
	var session = world.session
	var wheel = session.equipment_wheel
	var economy = session.state.economy
	var controls := root.get_node("GameInput")
	controls.reset_bindings()
	TranslationServer.set_locale("pt_BR")
	var clean = ECONOMY.new()
	clean.enable_grid_inventory()
	check(clean.grid_equip_bag("backpack"), "inventory fixture has a carried backpack")
	var initial: Dictionary = clean.snapshot()
	for family_index in VARIANTS.size():
		var family: Array = VARIANTS[family_index]
		var sector := family_index + 1
		check(economy.restore_snapshot(initial), "isolated inventory fixture restores for " + family[0])
		for id: String in family:
			check(economy.collect_weapon_drop(id, 12), "pickup is carried: " + id)
			check(ICONS.get_icon(id) != null, "inventory icon exists: " + id)
		check(world.gameplay.equip_slot(family[0]), "initial family weapon equips")
		await key(KEY_Q, true)
		await point_to(sector)
		check(wheel.active and wheel.entries[sector].variant_count == 3, "three carried choices share one sector: " + family[0])
		var before: Dictionary = economy.snapshot().weapons.duplicate(true)
		await key(KEY_RIGHT, true)
		await key(KEY_RIGHT, false)
		check(wheel.entries[sector].id == family[1] and session.state.equipped_weapon == family[0], "right arrow previews second weapon without early equip")
		await key(KEY_RIGHT, true)
		await key(KEY_RIGHT, false)
		check(wheel.entries[sector].id == family[2], "right arrow reaches new third weapon")
		check(wheel.entries[sector].stats.size() == 2 and not wheel.entries[sector].role.is_empty(), "new choice shows effective combat values and role")
		await shot(family[2]+"-1280")
		await key(KEY_RIGHT, true)
		await key(KEY_RIGHT, false)
		check(wheel.entries[sector].id == family[0], "variant wraps inside category")
		var scroll := InputEventMouseButton.new()
		scroll.button_index = MOUSE_BUTTON_WHEEL_DOWN
		scroll.pressed = true
		Input.parse_input_event(scroll)
		await frames()
		check(wheel.entries[sector].id == family[2], "reverse scroll returns to third variant")
		await key(KEY_Q, false)
		check(session.state.equipped_weapon == family[2] and economy.can_carry_weapon(family[2]), "release equips carried variant through real inventory transfer")
		check(economy.snapshot().weapons == before, "preview and equip preserve per-weapon ammunition")
		check(is_equal_approx(Engine.time_scale, 1) and not world.player.input_locked, "variant selection releases time and input")
		await key(KEY_Q, true)
		check(wheel.selected == sector and wheel.entries[sector].id == family[2], "reopening focuses actually equipped variant")
		check(move_stored_to_trunk(family[0]), "fixture removes earlier sibling from carried inventory")
		wheel._rebuild()
		check(wheel.entries[sector].id == family[2] and wheel.entries[sector].variant_count == 2, "refresh preserves selected identity when earlier sibling disappears")
		await key(KEY_ESCAPE, true)
		await key(KEY_ESCAPE, false)
		await key(KEY_Q, false)
		check(session.state.equipped_weapon == family[2], "cancel preserves equipped variant")

	# Shared L1/LB must be consumed by the hold wheel before legacy cycling.
	check(economy.restore_snapshot(initial), "controller inventory fixture restores")
	for id: String in VARIANTS[0]: check(economy.collect_weapon_drop(id, 12), "controller pickup: " + id)
	check(world.gameplay.equip_slot("pistol"), "controller begins with pistol")
	await pad(JOY_BUTTON_LEFT_SHOULDER, true)
	check(wheel.active and session.state.equipped_weapon == "pistol", "L1/LB opens without cycling the live weapon")
	await pad(JOY_BUTTON_DPAD_RIGHT, true)
	await pad(JOY_BUTTON_DPAD_RIGHT, false)
	check(wheel.entries[1].id == "magnum", "D-pad right previews next variant")
	await pad(JOY_BUTTON_RIGHT_SHOULDER, true)
	await pad(JOY_BUTTON_RIGHT_SHOULDER, false)
	check(wheel.entries[1].id == "pistol_suppressed", "next-weapon action cycles within the selected sector")
	await shot("controller-1280")
	await pad(JOY_BUTTON_LEFT_SHOULDER, false)
	check(not wheel.active and session.state.equipped_weapon == "pistol_suppressed", "release L1/LB equips exactly the previewed weapon")
	check(is_equal_approx(Engine.time_scale, 1) and not world.player.input_locked, "controller release restores normal play")
	await key(KEY_Q, true)
	root.content_scale_size = Vector2i(800,600)
	root.size = Vector2i(800,600)
	await frames(4)
	await shot("pistol-suppressed-800")
	TranslationServer.set_locale("en")
	wheel._rebuild()
	await frames(4)
	check(wheel.entries[1].label == "SUPPRESSED 9MM PISTOL", "weapon name is localized in the wheel")
	check(wheel.entries[0].slot_label == "FISTS", "unarmed label does not reuse the attachment translation for grip")
	await shot("pistol-suppressed-800-en")
	await key(KEY_Q, false)
	TranslationServer.set_locale("pt_BR")
	check(await session.enter_place("maciota", false), "real garage entry finishes")
	await frames(4)
	var owned_before: Dictionary = economy.snapshot().weapons.duplicate(true)
	await pad(JOY_BUTTON_LEFT_SHOULDER, true)
	await point_to(1)
	await pad(JOY_BUTTON_DPAD_LEFT, true)
	await pad(JOY_BUTTON_DPAD_LEFT, false)
	check(wheel.active and not wheel.entries[1].enabled, "garage variants remain visibly restricted")
	await pad(JOY_BUTTON_LEFT_SHOULDER, false)
	check(session.state.equipped_weapon == "fists" and not session.state.can_attack(), "new variants cannot bypass garage holster")
	check(economy.snapshot().weapons == owned_before, "garage selection preserves all owned variant ammunition")
	world.free()
	await frames()
	check(is_equal_approx(Engine.time_scale, 1), "scene cleanup releases wheel time ownership")
	print("WEAPON_WHEEL_VARIANTS_RESULT ", checks, " checks failures=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
