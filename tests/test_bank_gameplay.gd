extends SceneTree
## Production bank: real walking, gunfire, pickup, vault and outward crossing.
## Damage is injected only to finish guards after checking their first real hit.
const PLACES = preload("res://world/places/PlaceCatalog.gd")
const HEIST = preload("res://runtime/Robberies.gd")
var world
var checks := 0
var failures: Array[String] = []
var folder := "res://evidence/bank-gameplay-20261002"

func _initialize() -> void:
	create_timer(240).timeout.connect(func(): push_error("BANK gameplay timeout"); quit(3))
	run.call_deferred()
func frames(count: int) -> void:
	for i in count: await physics_frame
func check(ok: bool, label: String) -> void:
	checks+=1
	print("BANK ","PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func walk(point: Vector3, seconds := 5.0) -> bool:
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec()-began < seconds*1000:
		var direction: Vector3 = point-world.player.global_position
		direction.y=0
		if direction.length()<.14:
			world.player.automatic_direction=Vector3.ZERO
			return true
		world.player.automatic_direction=direction.normalized()
		await physics_frame
	world.player.automatic_direction=Vector3.ZERO
	print("WALK blocked from ",world.player.global_position," to ",point)
	return false

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world=load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 3600:
		await physics_frame
		if world.session!=null and world.session.ready_for_play: break
	check(world.session!=null and world.session.ready_for_play,"Main ready with real runtime")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var heist = session.robberies
	world.player.controlled_automatically=true
	world.player.speed=3.0
	world.player.automatic_direction=Vector3.ZERO
	session.weather.time_of_day=.45
	session.weather.weather_state=0
	session.weather.weather_timer=99999
	var access = session.weapon_shop_entrance
	var definition: Dictionary = access._definition_for("harbor_bank")
	var door: Vector3 = access._door_position("harbor_bank",definition)
	session.controller.region.set_focus(door)
	world.player.teleport(door+Vector3(0,.08,2.0))
	await frames(90)
	world.player.automatic_direction=Vector3.FORWARD
	for i in 180:
		await physics_frame
		if session.state.place_id=="harbor_bank": break
	world.player.automatic_direction=Vector3.ZERO
	await frames(50)
	check(session.state.place_id=="harbor_bank","walk through exterior door enters bank")
	if session.state.place_id!="harbor_bank": quit(1); return
	var room = session.room
	var initial_health: float = world.gameplay.health
	session.state.grant_weapon("pistol")
	session.state.equip_weapon("pistol")
	await frames(150)
	check(world.gameplay.health==initial_health and not heist.data.bank_shots,"entering and carrying pistol do not trigger shooting")
	check(heist._actors.size()==4,"two guards and two clerks installed")
	await capture("01-lobby")
	check(await walk(room.to_global(Vector3(0,0,.5))),"walk from entry into lobby")
	var guard = heist._actors[0]
	check(world.gameplay.fire_at(guard.global_position),"real pistol shot starts the robbery")
	await frames(24)
	check(heist.data.bank_alarm and not guard.dead and guard.health<160,"guard survives real first hit and alarm starts")
	check(world.gameplay.health==initial_health,"guards telegraph before returning fire")
	# Finish combat deterministically; walk/loot below still use actual collisions.
	for actor in heist._actors:
		if actor.guard: actor.receive_damage(200,world.player)
	check(heist.data.keycard_available and not heist.data.keycard_taken,"defeated guard drops a card at his feet")
	var card = heist._card
	var rotation_before: float = card.art.rotation.y
	var height_before: float = card.art.position.y
	await frames(20)
	check(absf(card.art.rotation.y-rotation_before)>.1 and absf(card.art.position.y-height_before)>.001,"keycard visibly spins and bobs")
	await frames(65)
	check(room.has_node("RobberyBlood") and room.get_node("RobberyBlood").stains.size()==2,"both dead guards leave visible room-owned blood")
	await capture("02-card")
	check(await walk(room.to_global(Vector3(-4.4,0,.5))),"walk to keycard without passing through furniture")
	check(heist.data.keycard_taken and session.notice.text.contains("Cartão"),"card collects automatically with confirmation")
	check(await walk(room.to_global(Vector3(0,0,.5))),"return to central corridor")
	check(await walk(room.to_global(HEIST.VAULT)),"approach vault through clear central aisle")
	check(not session.position_clear(room.to_global(Vector3(0,.08,-3.2))),"closed vault door physically blocks entry")
	check(heist.perform("bank_vault"),"keycard enables vault interaction")
	Input.action_press("interact")
	await frames(42)
	Input.action_release("interact")
	check(heist.lockpick.active and world.player.input_locked,"holding opens puzzle and locks movement")
	# Exercise cancellation then solve the actual dial controller.
	heist.lockpick.finish(false)
	check(not session.modal and not world.player.input_locked,"cancel restores player control")
	heist.perform("bank_vault")
	Input.action_press("interact")
	await frames(42)
	Input.action_release("interact")
	for i in 3:
		heist.lockpick.angle=heist.lockpick.target_angle
		heist.lockpick.attempt()
	await frames(195)
	check(heist.data.vault_open and session.position_clear(room.to_global(Vector3(0,.08,-3.2))),"animated vault opens a physical passage")
	var cash = heist._piles[0]
	rotation_before=cash.art.rotation.y
	await frames(20)
	check(absf(cash.art.rotation.y-rotation_before)>.1 and cash.art.position.y>.3,"cash floats and rotates above the floor")
	await capture("03-vault-open")
	var balance: int = session.state.economy.balance
	check(await walk(room.to_global(Vector3(0,0,-4.2))),"walk across vault threshold")
	check(heist.data.bank_cash1 and heist.data.bank_pending==5000 and session.state.economy.balance==balance,"vault money appears as carried haul until escape")
	check(session.notice.text.contains("5.000") and heist.haul_label.text.contains("5.000"),"cash feedback and persistent haul name the amount collected")
	await frames(20)
	check(room.bank_cutaway_amount>.85,"vault walls fade when inside")
	check(not session.position_clear(room.to_global(Vector3(-3,.08,-3.2))),"transparent partition still blocks physical bodies")
	await capture("04-inside-vault")
	check(await walk(room.to_global(HEIST.LOOT[0])),"walk to left cash pile")
	check(await walk(room.to_global(HEIST.LOOT[2])),"walk to right cash pile")
	check(session.state.economy.balance==balance and heist.data.bank_pending==15000,"all three piles carry exactly R$ 15000 at risk")
	check(heist.haul_label.text.contains("15.000"),"last reward shows total haul")
	await capture("05-haul")
	check(await walk(room.to_global(Vector3(0,0,-4.2))),"return through vault aisle")
	check(await walk(room.to_global(Vector3(0,0,.5))),"leave vault without clipping door")
	await frames(20)
	check(room.bank_cutaway_amount==0,"vault walls restore opacity in lobby")
	check(await walk(room.to_global(Vector3(.95,0,3.3))),"reach wide exit approach off center")
	world.player.automatic_direction=Vector3.BACK
	for i in 180:
		await physics_frame
		if session.state.place_id.is_empty(): break
	world.player.automatic_direction=Vector3.ZERO
	await frames(50)
	check(session.state.place_id.is_empty() and not world.player.input_locked,"wide exit crossing returns control outdoors")
	check(heist.can_enter_bank() and heist.data.aftermath.is_empty(),"escaping alive does not close bank")
	check(heist.data.bank_pending==0 and session.state.economy.snapshot().transactions["reward:bank_haul:0:7"].amount==15000,"escaping alive secures exactly R$ 15000")
	await capture("06-escaped")
	var receipts_before: Dictionary = session.state.economy.snapshot().transactions.duplicate(true)
	var balance_before_reentry: int = session.state.economy.balance
	check(await session.enter_place("harbor_bank",false),"immediate re-entry remains available")
	await frames(20)
	# Crossing outdoors can pay legitimate wallet/escape achievements. Compare
	# against the settled exterior balance and the bank's immutable receipts.
	check(heist.data.bank_cash0 and heist.data.bank_cash1 and heist.data.bank_cash2 and session.state.economy.balance==balance_before_reentry,"re-entry preserves loot without paying twice")
	check(session.state.economy.snapshot().transactions["reward:bank_haul:0:7"]==receipts_before["reward:bank_haul:0:7"],"bank receipt unchanged on re-entry")
	check(HEIST.validate_snapshot(heist.snapshot()),"complete robbery state is save-valid")
	await aftermath_review(session,heist,door)
	print("BANK gameplay checks=%d failures=%d"%[checks,failures.size()])
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)

func aftermath_review(session,heist,door: Vector3) -> void:
	var before_death: int = session.state.economy.balance
	world.gameplay.damage_player(10000)
	await frames(30)
	check(session.rescue_pending and heist.data.bank_failed,"real player death arms investigation")
	check(session.state.economy.balance==before_death-5000,"real bank death loses R$5000")
	await capture("07-death-penalty")
	for i in 480:
		await physics_frame
		if not session.rescue_pending and not session.respawn_busy and world.gameplay.health>0: break
	check(session.state.place_id.is_empty() and world.gameplay.health>0 and not world.player.input_locked,"death rescue restores exterior play")
	check(heist.can_enter_bank(),"death does not immediately close bank")
	var far: Vector3 = world.production.nearest_road(door+Vector3(0,0,140))
	await place_outside(session,far)
	check(heist.aftermath_controller.bank_is_away(),"bank is distant and outside camera before time advances")
	# Advance the actual production calendar; only elapsed waiting is shortened.
	session.state.world_state.moon_day=session.weather.moon_day()+1
	await frames(20)
	check(not heist.can_enter_bank() and heist.data.aftermath=="closed","one actual game day away closes bank")
	await place_outside(session,door+Vector3(0,0,3))
	check(is_instance_valid(heist.aftermath_controller._tape) and heist.aftermath_controller._tape.visible,"return displays exterior investigation tape")
	await capture("08-closed-bank")
	check(not await session.enter_place("harbor_bank",false),"closed bank refuses entry")
	await place_outside(session,far)
	session.state.world_state.moon_day=session.weather.moon_day()+3
	await frames(20)
	check(heist.can_enter_bank() and heist.data.bank_cycle==1,"three calendar days reopen bank offscreen")
	await place_outside(session,door+Vector3(0,0,3))
	check(not is_instance_valid(heist.aftermath_controller._tape),"reopened bank removes tapes and physical posts")
	check(await session.enter_place("harbor_bank",false),"reopened bank admits player")
	await frames(30)
	check(heist._actors[0].generation==2 and heist._actors[0].health==160 and not heist._actors[0].dead,"reopened bank has a different healthy guard generation")
	check(not heist.data.bank_cash0 and not heist.data.bank_cash1 and not heist.data.bank_cash2,"reopened vault restores the next heist's loot")
	await capture("09-new-guards")

func place_outside(session,point: Vector3) -> void:
	session.controller.region.set_focus(point)
	for i in 180:
		await physics_frame
		if session.controller.region.prepare_collision_at(point): break
	world.player.teleport(point+Vector3.UP*.08)
	world.camera.initialized=false
	await frames(60)
