extends SceneTree
## Productive Harbor establishments through the same exterior entry and input
## path used by the player. Run only with --no-save --skip-arrival.

const PLACES := preload("res://world/places/PlaceCatalog.gd")
const SERVICES := preload("res://runtime/Services.gd")
const CUSTOM := preload("res://gameplay/WeaponCustomization.gd")

var world: Node3D
var session: Node
var state: RefCounted
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, detail := "") -> bool:
	checks += 1
	print(("HARBOR_SHOPS PASS " if ok else "HARBOR_SHOPS FAIL ") + label + ((" | " + detail) if not detail.is_empty() else ""))
	if not ok:
		failures.append(label)
		push_error(label + ((" | " + detail) if not detail.is_empty() else ""))
	return ok

func frames(count: int) -> void:
	for _i in count: await physics_frame

func wait_until(predicate: Callable, maximum: int, label: String) -> bool:
	for _i in maximum:
		if predicate.call(): return true
		await physics_frame
	return check(false, label, "timeout_frames=%d" % maximum)

func press_key(code: Key, settle := 2) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await frames(settle)

func place_player(point: Vector3) -> void:
	# Interior rooms live far below the streamed exterior. Moving the exterior
	# streamer to an interior-local point can legitimately keep travel_busy set
	# and is not how the player walks to an interior action.
	if state == null or state.place_id.is_empty(): world.production.region.set_focus(point)
	world.player.teleport(point + Vector3.UP * .08)
	await frames(5)

func enter_place(id: String) -> bool:
	if id == "harbor_ammunation":
		var facade: Vector3 = PLACES.get_definition(id).exterior_position
		await place_player(facade + Vector3(0, 0, 6.92))
		check(session.nearest().get("id", "") != "enter", "Ammu-Nation has no E entry")
		Input.action_press("move_up")
		await frames(20)
		Input.action_release("move_up")
		return await wait_until(func(): return state.place_id == id and is_instance_valid(session.room), 180, "entrada caminhando: " + id)
	var point: Vector3 = world.maciota_place.entry_position if id == "maciota" else PLACES.get_definition(id).entry_position
	await place_player(point)
	var action: Dictionary = session.nearest()
	check(action.get("id", "") == "enter" and action.get("place", "") == id, "entrada oferecida: " + id, str(action))
	await press_key(KEY_E)
	return await wait_until(func(): return state.place_id == id and is_instance_valid(session.room), 180, "entrada concluída: " + id)

func leave_place(id: String) -> bool:
	if session.modal:
		await press_key(KEY_ESCAPE)
		check(not session.modal, "cancelamento fecha menu: " + id)
		if session.modal: session.close_menu()
		await frames(3)
	if id == "harbor_ammunation":
		await place_player(session.room.exit_position + Vector3(0, 0, -0.53))
		check(session.nearest().get("id", "") != "exit", "Ammu-Nation has no E exit")
		Input.action_press("move_down")
		await frames(16)
		Input.action_release("move_down")
		return await wait_until(func(): return state.place_id.is_empty() and not is_instance_valid(session.room), 180, "saída caminhando: " + id)
	await place_player(session.room.exit_position)
	check(session.nearest().get("id", "") == "exit", "saída oferecida: " + id, str(session.nearest()))
	await press_key(KEY_E)
	return await wait_until(func(): return state.place_id.is_empty() and not is_instance_valid(session.room), 180, "saída concluída: " + id)

func interact_at(point: Vector3, expected: String) -> bool:
	await place_player(point)
	var action: Dictionary = session.nearest()
	check(action.get("id", "") == expected, "ação física oferecida: " + expected, str(action))
	await press_key(KEY_E)
	await frames(4)
	return action.get("id", "") == expected

func find_store_button(fragment: String) -> Button:
	for child in session.storefronts.find_children("*", "Button", true, false):
		if fragment.to_lower() in child.text.to_lower(): return child
	return null

func activate(button: Button, label: String) -> bool:
	if not check(is_instance_valid(button), label): return false
	button.grab_focus()
	await frames(2)
	await press_key(KEY_ENTER, 3)
	return true

func drain_dialogue(limit := 16) -> int:
	var advanced := 0
	while session.dialogue_open and advanced < limit:
		await press_key(KEY_E)
		advanced += 1
	return advanced

func capture(label: String) -> void:
	if not "--capture" in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://evidence/harbor-establishments")
	DirAccess.make_dir_recursive_absolute(directory)
	var error := root.get_viewport().get_texture().get_image().save_png(directory.path_join(label + ".png"))
	check(error == OK, "captura gravada: " + label, error_string(error))

func set_aim_at(target: Vector3) -> void:
	var flat: Vector3 = target - world.player.global_position
	flat.y = 0
	flat = flat.normalized()
	var right: Vector3 = world.camera.global_basis.x
	var down: Vector3 = world.camera.global_basis.z
	right.y = 0
	down.y = 0
	root.get_node("GameInput").touch_aim = Vector2(flat.dot(right.normalized()), flat.dot(down.normalized()))

func aim_at(target: Vector3) -> void:
	set_aim_at(target)
	await frames(4)

func _complete_intro_and_first_mission() -> bool:
	var intro: Dictionary = state.intro.snapshot()
	intro.phase = "complete"
	intro.location_id = "harbor_street"
	intro.inventory = {}
	intro.equipped_weapon = ""
	intro.completed_missions = [intro.mission_id]
	if not state.intro.restore_snapshot(intro): return false
	var campaign: Dictionary = state.campaign.snapshot()
	campaign.active_id = ""
	campaign.step = 0
	campaign.completed = ["primeiro_giro"]
	campaign.pending_rewards = {}
	campaign.claimed_rewards = ["primeiro_giro"]
	campaign.flags = {}
	for flag in session.MISSIONS.MISSIONS.primeiro_giro.sets_flags: campaign.flags[flag] = true
	campaign.race_elapsed = 0.0
	campaign.race_outside = 0.0
	campaign.race_run = {}
	campaign.failure = ""
	return state.campaign.restore_snapshot(campaign)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--no-save" in args or not "--skip-arrival" in args:
		push_error("HARBOR_SHOPS refuses to run without --no-save --skip-arrival")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	if not await wait_until(func(): return world.session != null and world.session.ready_for_play and world.production.ready_for_play, 900, "sessão inicia"):
		quit(1)
		return
	session = world.session
	state = session.state
	check(world.production.no_save, "fixture não usa save pessoal")

	# Ammu-Nation: exterior real -> sala -> balcão -> catálogo produtivo.
	if await enter_place("harbor_ammunation"):
		await interact_at(session.room.interaction_points.service, "service")
		check(session.storefronts.active_kind == "weapons" and session.modal, "Ammu-Nation abre catálogo específico")
		await capture("ammunation-menu")
		var catalog = session.storefronts.ammunation
		check(catalog.stock == ["pistol", "magnum", "shotgun", "sawed_off", "smg", "ak47", "m4a1", "hunting_rifle", "knife", "knuckles", "bat", "axe", "grenade", "rpg", "flamethrower", "armor"], "catálogo preserva estoque e ordem produtivos V1", str(catalog.stock))
		check(catalog.gun.get_child_count() == 1 and catalog.preview.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "catálogo V1 abre preview 3D giratório")
		check(is_instance_valid(find_store_button("ARMAS CURTAS")) and is_instance_valid(find_store_button("ARMAS LONGAS")) and is_instance_valid(find_store_button("EXPLOSIVOS")), "categorias V1 permanecem disponíveis")
		check(is_instance_valid(catalog.buy) and not catalog.buy.disabled and "$0" in catalog.buy.text, "pistola gratuita produtiva localizável", catalog.buy.text)
		await activate(catalog.buy, "botão COMPRAR real da pistola")
		check(state.owns_weapon("pistol") and state.equipped_weapon == "pistol", "pistola é comprada e equipada")
		state.economy.grant_reward("harbor_store_fixture", 10000)
		await activate(find_store_button("ARMAS LONGAS"), "categoria ARMAS LONGAS localizável")
		check(catalog.stock[catalog.selection] == "shotgun" and "$1800" in catalog.buy.text, "categoria V1 seleciona escopeta e preço original", catalog.buy.text)
		var before_shotgun: int = state.economy.balance
		var shotgun_transactions_before: Dictionary = state.economy.snapshot().transactions
		await activate(catalog.buy, "compra real da escopeta")
		var shotgun_ready: bool = state.equipped_weapon == "shotgun" if state.economy.can_carry_weapon("shotgun") else "porta-malas" in catalog.feedback.text.to_lower()
		var charged_shotgun := false
		for key in state.economy.snapshot().transactions:
			var receipt: Dictionary = state.economy.snapshot().transactions[key]
			if not shotgun_transactions_before.has(key) and receipt.get("kind", "") == "weapon" and receipt.get("item", "") == "shotgun" and int(receipt.get("amount", 0)) == 1800: charged_shotgun = true
		check(state.owns_weapon("shotgun") and shotgun_ready and charged_shotgun, "escopeta compra uma vez por $1800 e respeita o loadout", "owned=%s carry=%s equipped=%s balance=%d->%d feedback=%s" % [state.owns_weapon("shotgun"), state.economy.can_carry_weapon("shotgun"), state.equipped_weapon, before_shotgun, state.economy.balance, catalog.feedback.text])
		var after_shotgun: int = state.economy.balance
		await activate(catalog.buy, "botão de arma adquirida permanece localizável")
		check(state.economy.balance == after_shotgun, "arma já adquirida não cobra novamente")
		await activate(find_store_button("ARMAS CURTAS"), "retorno à categoria ARMAS CURTAS")
		check(catalog.stock[catalog.selection] == "pistol", "categoria retorna à pistola")
		var before_ammo: int = state.economy.balance
		var ammo_transactions_before: Dictionary = state.economy.snapshot().transactions
		var reserve_before := int(state.get_ammo("pistol").reserve)
		await activate(catalog.ammo_button, "reposição V1 de pistola localizável")
		var ammo_transactions_after: Dictionary = state.economy.snapshot().transactions
		var charged_48 := false
		for key in ammo_transactions_after:
			if not ammo_transactions_before.has(key) and str(key).begins_with("spend:ammunition:") and int(ammo_transactions_after[key].amount) == 48: charged_48 = true
		check(charged_48 and state.economy.balance == before_ammo - 48 and int(state.get_ammo("pistol").reserve) == reserve_before + 24, "reposição produtiva cobra R$ 48 e entrega 24", "balance=%d->%d reserve=%d->%d status=%s" % [before_ammo, state.economy.balance, reserve_before, int(state.get_ammo("pistol").reserve), session.storefronts.status_label.text])
		var full: Dictionary = state.economy.snapshot()
		full.weapons.pistol.reserve = state.economy.MAX_AMMO
		check(state.economy.restore_snapshot(full), "fixture prepara inventário cheio")
		var full_balance: int = state.economy.balance
		catalog.refresh()
		await activate(catalog.ammo_button, "reposição continua acessível")
		check(state.economy.balance == full_balance and int(state.get_ammo("pistol").reserve) == state.economy.MAX_AMMO, "inventário cheio não cobra nem altera munição")
		await activate(catalog.workbench_button, "bancada V1 abre pela arma selecionada")
		check(catalog.workbench.visible and catalog.panel.visible == false, "bancada V1 substitui o catálogo sem abrir menu genérico")
		await capture("ammunation-workbench")
		await activate(find_store_button("Preto fosco"), "acabamento V1 localizável na bancada")
		await activate(catalog.workbench.apply_button, "comprar e instalar acabamento pela bancada real")
		check(CUSTOM.selected(world.gameplay.customization, "pistol", "finish") == "matte", "bancada aplica a personalização ao combate V2")
		await press_key(KEY_ESCAPE)
		check(not catalog.workbench.visible and catalog.panel.visible, "ESC retorna da bancada ao catálogo V1")
		var closed_preview: SubViewport = catalog.preview
		await leave_place("harbor_ammunation")
		check(not is_instance_valid(closed_preview) or closed_preview.render_target_update_mode == SubViewport.UPDATE_DISABLED, "preview da Ammu-Nation para de atualizar ao fechar")

	# Union: menu próprio com preview, compra, equipamento e cancelamento.
	if await enter_place("harbor_clothing"):
		await interact_at(session.room.interaction_points.service, "service")
		check(session.storefronts.active_kind == "clothing" and is_instance_valid(session.storefronts.preview_actor), "Union abre provador 3D específico")
		var union_close := find_store_button("Fechar")
		check(is_instance_valid(union_close) and union_close.is_visible_in_tree() and union_close.get_global_rect().end.x <= root.get_viewport().get_visible_rect().end.x, "Union mantém botão Fechar visível", str(union_close.get_global_rect()) if is_instance_valid(union_close) else "missing")
		await capture("union-menu")
		await activate(find_store_button("Terno"), "roupa Terno localizável")
		var before_suit: int = state.economy.balance
		await activate(find_store_button("Comprar e vestir"), "ação de compra da Union localizável")
		check(state.economy.owns_outfit("dante_suit") and state.economy.outfit == "dante_suit", "Union compra e equipa Terno")
		check(state.economy.balance == before_suit - 2500, "Union preserva preço V1 do Terno")
		var empty_wallet: Dictionary = state.economy.snapshot()
		empty_wallet.balance = 0
		check(state.economy.restore_snapshot(empty_wallet), "fixture prepara saldo insuficiente da Union")
		await activate(find_store_button("Parka ártica"), "Parka localizável")
		await activate(find_store_button("Comprar e vestir"), "compra bloqueada da Union localizável")
		check(not state.economy.owns_outfit("dante_arctic") and "faltam" in session.storefronts.status_label.text.to_lower(), "Union não cobra nem equipa com saldo insuficiente", session.storefronts.status_label.text)
		await leave_place("harbor_clothing")

	# Fuel is a robbery consumer, never a generic convenience-store menu.
	if await enter_place("harbor_fuel"):
		await place_player(session.room.interaction_points.service)
		check(session.nearest().get("id", "") != "service", "posto não oferece balcão genérico sem resultado", str(session.nearest()))
		session.robberies.data.fuel_resists = false
		session.robberies.data.fuel_initialized = true
		await wait_until(func(): return not session.robberies._actors.is_empty(), 120, "caixa do posto aparece")
		if not session.robberies._actors.is_empty():
			var clerk: Node3D = session.robberies._actors[0]
			await place_player(session.room.interaction_points.service)
			state.equip_weapon("pistol")
			await aim_at(clerk.global_position)
			var before_register: int = state.economy.balance
			Input.action_press("aim")
			for _i in 220:
				set_aim_at(clerk.global_position)
				await physics_frame
			Input.action_release("aim")
			await frames(3)
			var cashier_direction: Vector3 = clerk.global_position - world.player.global_position
			cashier_direction.y = 0
			var aimed_direction: Vector3 = world.gameplay.aim_point - world.player.global_position
			aimed_direction.y = 0
			check(session.robberies.data.fuel_register and state.economy.balance == before_register + 180, "ameaça real abre caixa e entrega R$ 180 uma vez", "equipped=%s distance=%.2f dot=%.3f hold=%.2f register=%s" % [state.equipped_weapon, cashier_direction.length(), cashier_direction.normalized().dot(aimed_direction.normalized()), session.robberies._intimidation, session.robberies.data.fuel_register])
		await leave_place("harbor_fuel")

	# Bank operation remains Helena/mission; there is no unrelated teller menu.
	world.gameplay.clear_wanted()
	state.equip_weapon("fists")
	check(state.campaign.begin("primeiro_giro"), "fixture inicia Primeiro Giro")
	if await enter_place("harbor_bank"):
		await interact_at(session.room.interaction_points.service, "service")
		check(await drain_dialogue() > 0 and state.campaign.step == 1, "Helena entrega comprovante pelo balcão real")
		await leave_place("harbor_bank")

	# Public establishments expose their productive actions, not dead counters.
	if await enter_place("harbor_hospital"):
		world.gameplay.health = 45
		await place_player(session.room.to_global(SERVICES.HOSPITAL_PICKUP))
		await frames(5)
		check(world.gameplay.health == 100 and session.services.hospital_cooldown > 0, "Bay Medical coleta cura e inicia recarga")
		world.gameplay.health = 55
		await frames(5)
		check(world.gameplay.health == 55, "Bay Medical bloqueia segunda cura durante recarga")
		await leave_place("harbor_hospital")

	if await enter_place("harbor_police"):
		await interact_at(session.room.to_global(Vector3(-4.2, 0, 1.5)), "original_service")
		check(await drain_dialogue() > 0, "Harbor Patrol abre terminal produtivo")
		await place_player(session.room.interaction_points.service)
		check(session.nearest().get("id", "") != "service", "delegacia não oferece Atender sem consumidor")
		await leave_place("harbor_police")

	if await enter_place("harbor_fire_station"):
		world.gameplay.health = 45
		await place_player(session.room.to_global(SERVICES.FIRE_HEAL))
		await frames(90)
		check(world.gameplay.health > 50, "Northgate Fire aplica cura contínua")
		await interact_at(session.room.to_global(Vector3(-10, 0, -120.0 / 28.0)), "original_service")
		check(await drain_dialogue() > 0, "alarme dos bombeiros abre interação própria")
		await leave_place("harbor_fire_station")

	# Maciota: unlock synthetic only prepares the already-earned service; access
	# and operation still run through the actual exterior, workbench and UI.
	check(_complete_intro_and_first_mission(), "fixture libera Monaliza sem save pessoal")
	session.personal_car.refresh()
	await frames(6)
	if await enter_place("maciota"):
		await interact_at(world.maciota_place.interaction_points.workbench, "personal_car")
		check(session.storefronts.active_kind == "maciota", "bancada abre interface própria da Monaliza")
		await capture("maciota-service-menu")
		var monaliza = session.personal_car._car()
		if is_instance_valid(monaliza): monaliza.health = maxf(1.0, monaliza.max_health - 50.0)
		var before_repair: int = state.economy.balance
		await activate(find_store_button("Reparar"), "reparo da Monaliza localizável")
		check(is_instance_valid(monaliza) and is_equal_approx(monaliza.health, monaliza.max_health), "Maciota repara a Monaliza")
		check(state.economy.balance == before_repair - 50, "Maciota cobra R$ 50 uma vez")
		await leave_place("maciota")

	print("HARBOR_ESTABLISHMENTS ", "PASS" if failures.is_empty() else "FAIL", " checks=", checks, " failures=", failures.size())
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
