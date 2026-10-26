extends SceneTree
## Forja da Serra na sessão real (Main.tscn, sem gravar): ferreiro nasce no chão da
## clareira, conversa e menu de verdade, compra com dinheiro, pista até o eremita (cabana
## real no norte da serra) e o minerador (acampamento montado ao lado do jogador sobre um
## piso de teste, porque o deserto exige a campanha concluída), volta à forja, lendária,
## mapa, calor da fornalha e save. Rodar com `-- --no-save`.
const FORGE_SITE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const HERMIT_SITE := preload("res://world/mountain_detail/forge/ForgeHermitCabin.gd")
const CAMP := preload("res://world/desert/DesertMinerCamp.gd")
const GEO := preload("res://world/mountain_detail/forge/ForgeGeometry.gd")
const FORGE := preload("res://gameplay/forge/BladeForge.gd")
const TALK := preload("res://gameplay/forge/BladeForgeTalk.gd")
const ATLAS := preload("res://ui/hud/WorldMapData.gd")
const HEAT := preload("res://runtime/cold/OriginalHeatSources.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
var world
var session
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(300.0, true, false, true).timeout.connect(func():
		push_error("Blade forge session exceeded 300 seconds")
		print("BLADE_FORGE_SESSION ", checks, " checks ", failures, " failures; TIMEOUT")
		quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func frames(count: int) -> void:
	for i in count: await physics_frame

func close_dialogue() -> void:
	for i in 12:
		if not session.dialogue_open: break
		session._advance_dialogue()
	await frames(2)

func stage() -> String:
	return str(FORGE.quest(session.state.world_state).stage)

func site(name: String) -> Node:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		var found: Node = world.production.region.find_child(name, true, false)
		if is_instance_valid(found) and found.is_node_ready(): return found
		await process_frame
	return null

func resident_ready(resident: Node) -> bool:
	for i in 300:
		await physics_frame
		if resident.available() and resident.actor.is_on_floor(): return true
	return resident.available()

func talk(resident: Node) -> bool:
	world.player.teleport(resident.actor.global_position + Vector3(0,.05,1.6))
	await frames(4)
	var action: Dictionary = session.nearest()
	check(action.get("id","") == "blade_forge" and action.get("target","") == resident.site_id, "Interaction offered by " + resident.site_id + ": " + str(action.get("label","")))
	if action.get("id","") != "blade_forge": return false
	var ok: bool = await session.interact()
	await frames(2)
	return ok

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	# Espera por tempo, não por quadros: os quadros da cortina de carga são rápidos e 3000 deles
	# acabavam antes da sessão ficar pronta (26/10).
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if world.get("session") != null and world.session.ready_for_play: break
	session = world.session
	check(session != null and session.ready_for_play, "Main session starts")
	if failures: await finish(); return
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	session.state.economy.grant_reward("blade_forge_session_cash", 30000)
	check(session.state.grant_weapon("knife"), "Knife granted")
	var money_before: int = session.state.economy.balance

	# Forja: lugar real na clareira, ferreiro de pé no chão da oficina.
	world.production._update_physical_residency(FORGE_SITE.CENTER)
	world.production._update_logical_region(FORGE_SITE.CENTER)
	world.player.teleport(FORGE_SITE.CENTER + Vector3(0,.1,12))
	var forge: Node = await site("MountainForge")
	check(is_instance_valid(forge), "Forge built in the production mountain")
	if failures: await finish(); return
	check(world.production.region.find_child("MountainZoo", true, false) == null, "No zoo left in the clearing")
	check(await resident_ready(forge.smith), "Smith spawns standing on the workshop floor")
	if failures: await finish(); return
	check(absf(forge.smith.actor.global_position.y - FORGE_SITE.CENTER.y) < .5, "Smith rests on the yard, not on the anvil: y=%.2f" % forge.smith.actor.global_position.y)
	check(HEAT.nearest(FORGE_SITE.CENTER + FORGE_SITE.HEARTH + Vector3(1.5,.1,2.0)).get("id","") == "blade_forge", "Hearth warms the player like the other fires")

	check(await talk(forge.smith), "Talking to the smith starts")
	check(session.dialogue_open, "Smith introduction is a dialogue")
	await close_dialogue()
	check(stage() == "met", "Meeting the smith records the trail stage")
	check(session.modal and session.column.get_child_count() > 2, "Forge menu opens after the introduction")
	var before_edge: int = session.state.economy.balance
	TALK._buy(session, forge.smith, "knife", "edge")
	var after_edge: int = session.state.economy.balance
	await frames(2)
	check(FORGE.level(world.gameplay.customization, "knife", "edge") == 1, "Knife edge level 1 bought from the menu")
	check(after_edge == before_edge - 400, "Edge level charged the listed price: %d -> %d (start %d)" % [before_edge, after_edge, money_before])
	check(int(world.gameplay.weapon_data("knife").damage) == roundi(float(CATALOG.get_weapon("knife").damage)*1.12), "Combat damage uses the forge level")
	check(session.modal, "Menu stays open after buying")
	check(not FORGE.offer(world.gameplay.customization, stage(), "knife", "legendary").ok, "Legendary not offered before the trail")
	TALK._clue(session, forge.smith, FORGE.quest(session.state.world_state))
	await close_dialogue()
	check(stage() == "seek_hermit", "Smith points to the hermit")
	var map := ATLAS.new()
	map.collect({"state":session.state, "world":world, "region":world.production.region})
	check(map.markers.any(func(m): return m.id == "forge_hermit"), "Hermit cabin appears on the map after the clue")
	check(not map.markers.any(func(m): return m.id == "forge_miner"), "Miner stays hidden until the hermit speaks")
	check(map.markers.any(func(m): return m.kind == "forge"), "Forge marker on the map")
	session.close_menu()

	# Eremita: cabana real no norte da serra.
	world.production._update_physical_residency(HERMIT_SITE.CENTER)
	world.production._update_logical_region(HERMIT_SITE.CENTER)
	world.player.teleport(HERMIT_SITE.CENTER + Vector3(0,.1,9))
	var cabin: Node = await site("ForgeHermitCabin")
	check(is_instance_valid(cabin), "Hermit cabin built far north in the mountain")
	if failures: await finish(); return
	check(await resident_ready(cabin.hermit), "Hermit spawns in front of the cabin")
	if failures: await finish(); return
	check(HEAT.nearest(HERMIT_SITE.CENTER + HERMIT_SITE.FIRE + Vector3(1,.1,0)).get("id","") == "hermit_camp", "Hermit fire is a heat source")
	check(await talk(cabin.hermit), "Talking to the hermit starts")
	await close_dialogue()
	check(stage() == "seek_miner", "Hermit sends the player to the miner")

	# Minerador: o acampamento do deserto, montado aqui sobre um piso de teste.
	var stage_floor := Node3D.new()
	world.add_child(stage_floor)
	stage_floor.global_position = HERMIT_SITE.CENTER + Vector3(30,0,0)
	GEO.solid(stage_floor, "FixtureFloor", Vector3(0,-.1,0), Vector3(40,.2,40))
	var camp: Node3D = CAMP.new()
	stage_floor.add_child(camp)
	camp.position = Vector3.ZERO
	camp.session = session
	world.player.teleport(stage_floor.global_position + Vector3(0,.1,8))
	check(await resident_ready(camp.miner), "Miner spawns at the camp")
	if failures: await finish(); return
	check(await talk(camp.miner), "Talking to the miner starts")
	await close_dialogue()
	check(stage() == "has_ore", "Miner hands over the ore")
	stage_floor.queue_free()

	# Volta à forja: lendária só com tudo no máximo.
	world.production._update_physical_residency(FORGE_SITE.CENTER)
	world.production._update_logical_region(FORGE_SITE.CENTER)
	world.player.teleport(FORGE_SITE.CENTER + Vector3(0,.1,12))
	forge = await site("MountainForge")
	check(is_instance_valid(forge) and await resident_ready(forge.smith), "Smith back after the trip")
	if failures: await finish(); return
	check(await talk(forge.smith), "Talking to the smith with the ore")
	await close_dialogue()
	check(stage() == "done", "Ore unlocks the legendary steel")
	check(not world.gameplay.buy_forge_upgrade("knife", "legendary", stage()).ok, "Legendary refused before maxing both tracks")
	for track in ["edge", "temper", "temper"]:
		check(world.gameplay.buy_forge_upgrade("knife", track, stage()).ok, "Bought knife " + track)
	var result: Dictionary = world.gameplay.buy_forge_upgrade("knife", "legendary", stage())
	check(result.ok, "Legendary knife bought")
	check(FORGE.legendary(world.gameplay.customization, "knife"), "Knife marked legendary")
	check(int(world.gameplay.weapon_data("knife").damage) == roundi(float(CATALOG.get_weapon("knife").damage)*1.24*1.25), "Legendary damage in combat data")
	for receipt in [FORGE.receipt("knife","edge",1), FORGE.receipt("knife","edge",2), FORGE.receipt("knife","temper",1), FORGE.receipt("knife","temper",2), FORGE.receipt("knife","legendary")]:
		check(not preload("res://systems/economy/RecurringReceipts.gd").lookup(session.state.economy.snapshot(), "spend", receipt).is_empty(), "Receipt recorded: " + receipt)
	session.close_menu()
	check(session.state.equip_weapon("knife"), "Equip the knife")
	for i in 30:
		await process_frame
		if world.gameplay.gun.find_child("LegendaryEdge", true, false) != null: break
	check(world.gameplay.gun.find_child("LegendaryEdge", true, false) != null, "Equipped knife shows the glowing legendary edge")

	# Save: os níveis e a pista voltam e o recibo de cada compra é exigido.
	session.state.combat_state = world.gameplay.snapshot()
	var saved: Dictionary = JSON.parse_string(JSON.stringify(session.state.snapshot()))
	var restored = preload("res://runtime/GameState.gd").new()
	check(restored.restore_snapshot(saved), "Save with forge progress restores")
	check(str(restored.world_state.blade_forge.stage) == "done", "Trail stage restored")
	check(FORGE.legendary(restored.combat_state.customization, "knife"), "Legendary knife restored")
	await finish()

func finish() -> void:
	if world != null: world.free()
	await process_frame
	print("BLADE_FORGE_SESSION ", checks, " checks ", failures, " failures")
	quit(1 if failures else 0)
