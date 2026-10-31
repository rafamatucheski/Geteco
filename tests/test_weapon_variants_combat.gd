extends SceneTree
## Sessão real do Main / física / GameState / Gameplay / entrada da FullSession.
## O alvo é um grande receptor inerte de dano numa faixa de teste elevada isolada;
## isto valida tiros, não travessia da cidade, IA inimiga nem apresentação renderizada.
const STARTUP := preload("res://tests/fixtures/TravelBagScene.gd")
const CATALOG := preload("res://gameplay/WeaponCatalog.gd")
const IDS := ["pistol", "magnum", "pistol_suppressed", "smg", "smg_compact", "smg_tactical", "shotgun", "sawed_off", "shotgun_auto"]
class Target extends StaticBody3D:
	var health := 100000.0
	var dead := false
	func receive_damage(amount: float, _source: Node = null) -> void: health -= amount
var world
var gameplay
var state
var target: Target
var wall: StaticBody3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func box(body: StaticBody3D, extent: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = extent
	collision.shape = shape
	body.add_child(collision)

func prepare(id: String) -> void:
	Input.action_release("fire")
	Input.action_release("aim")
	gameplay.cooldown = 0.0
	gameplay.reload_timer = 0.0
	gameplay.reloading_id = ""
	gameplay._reload_audio.stop()
	gameplay._handling.clear()
	check(gameplay.equip_slot(id), id + " equips through Gameplay")
	# Restaura só a munição gasta da fixture pela API real de estado.
	state.add_ammo(id, 30)
	state.reload_weapon(id)
	await frames(12)
	gameplay.cooldown = 0.0
	gameplay._rng.seed = 27102026

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("WEAPON_VARIANTS_COMBAT requires --no-save")
		quit(2)
		return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	if not await STARTUP.wait_for_startup(world):
		push_error("WEAPON_VARIANTS_COMBAT startup did not finish")
		world.free()
		quit(3)
		return
	gameplay = world.gameplay
	state = world.session.state
	state.economy.activate_arsenal_cheat()
	gameplay.health = 100000.0
	# O isolamento físico impede que trânsito e cenário invalidem a geometria do tiro.
	world.player.teleport(Vector3(132, 50, 72))
	world.player.controlled_automatically = true
	world.player.automatic_direction = Vector3.ZERO
	world.player.velocity = Vector3.ZERO
	world.player.set_physics_process(false)
	target = Target.new()
	target.set_meta("gameplay_role", "cobra")
	target.collision_layer = 4
	box(target, Vector3(5, 4, .2))
	world.add_child(target)
	target.global_position = world.player.global_position + Vector3(0, 1.1, -2)
	wall = StaticBody3D.new()
	wall.collision_layer = 0
	box(wall, Vector3(5, 4, .3))
	world.add_child(wall)
	wall.global_position = world.player.global_position + Vector3(0, 1.1, -1)
	await frames(3)
	var reload_only := "--reload-only" in OS.get_cmdline_user_args()
	for id: String in ([] if reload_only else IDS):
		await prepare(id)
		var data: Dictionary = gameplay.weapon_data(id)
		var before: Dictionary = state.get_ammo(id).duplicate()
		var health_before := target.health
		check(gameplay.fire_at(target.global_position), id + " fires a real physics ray")
		check(int(state.get_ammo(id).magazine) == int(before.magazine)-1, id + " spends one cartridge, including pellet volleys")
		check(is_equal_approx(health_before-target.health, float(data.damage)*int(data.pellets)), id + " applies its close-range damage and pellet count")
		check(not gameplay.fire_at(target.global_position) and int(state.get_ammo(id).magazine) == int(before.magazine)-1, id + " cooldown rejects duplicate shot and ammo use")
		wall.collision_layer = 1
		await frames(2)
		gameplay.cooldown = 0
		health_before = target.health
		if id == "shotgun_auto":
			var obstruction: Dictionary = gameplay._muzzle_obstruction(gameplay._muzzle_world_position())
			check(not obstruction.is_empty() and obstruction.collider == wall, "long semi shotgun detects wall crossed between chest and muzzle")
		check(gameplay.fire_at(target.global_position) and is_equal_approx(target.health, health_before), id + " solid wall blocks every pellet")
		wall.collision_layer = 0
		await frames(2)
	# Hold the actual fire action through FullSession. Semiautomatic weapons must
	# fire once per press; each SMG must continue until released.
	var controls = root.get_node("GameInput")
	for id: String in ([] if reload_only else ["pistol_suppressed", "shotgun_auto", "smg_compact", "smg_tactical"]):
		await prepare(id)
		var direction := Vector3.FORWARD
		var right: Vector3 = world.camera.global_basis.x
		var down: Vector3 = world.camera.global_basis.z
		right.y = 0; down.y = 0
		controls.touch_aim = Vector2(direction.dot(right.normalized()), direction.dot(down.normalized()))
		var before := int(state.get_ammo(id).magazine)
		Input.action_press("fire")
		await create_timer(.65).timeout
		Input.action_release("fire")
		await frames(2)
		var used := before-int(state.get_ammo(id).magazine)
		check(used >= 3 if CATALOG.get_weapon(id).automatic else used == 1, id + " honors held-trigger fire mode (%d rounds)" % used)
	# Terminar uma recarga usa o mesmo timer e a mesma API de estado do jogo normal.
	# A trapaça do arsenal recarrega de propósito sem gastar a reserva
	# infinita. Usa uma economia normal para estas asserções de conservação.
	var cheat_economy = state.economy
	state.economy = preload("res://systems/economy/Economy.gd").new()
	state.economy.enable_grid_inventory()
	state.economy.grant_weapon("pistol_suppressed")
	await prepare("pistol_suppressed")
	gameplay.fire_at(target.global_position)
	var before_reload: Dictionary = state.get_ammo("pistol_suppressed").duplicate()
	check(gameplay.reload_weapon(), "variant reload starts after shooting")
	await create_timer(2.05).timeout
	var after_reload: Dictionary = state.get_ammo("pistol_suppressed")
	check(after_reload.magazine == 15 and after_reload.reserve == int(before_reload.reserve)-1, "completed reload moves exactly one reserve round: %s -> %s" % [before_reload,after_reload])
	gameplay.cooldown = 0
	gameplay.fire_at(target.global_position)
	check(gameplay.reload_weapon(), "second reload starts for interrupt test")
	var interrupted: Dictionary = state.get_ammo("pistol_suppressed").duplicate()
	check(gameplay.equip_slot("fists") and gameplay.reload_timer == 0, "holstering the weapon cancels active reload")
	await create_timer(2.05).timeout
	check(state.get_ammo("pistol_suppressed") == interrupted, "cancelled reload cannot transfer or duplicate ammunition later")
	for id: String in ["pistol_suppressed", "smg_compact", "smg_tactical", "shotgun_auto"]:
		var cobra := preload("res://gameplay/CobraAgent.gd").new()
		cobra.configure(gameplay)
		cobra.weapon_id = id
		cobra.set_physics_process(false)
		world.add_child(cobra)
		cobra.set_physics_process(false)
		cobra.global_position = world.player.global_position + Vector3(3, 0, 0)
		cobra.magazine = 0
		cobra._shoot(world.player)
		check(is_equal_approx(cobra.reload_timer, float(CATALOG.get_weapon(id).reload_duration)) and cobra.magazine == 0, id + " NPC starts authored reload when empty")
		cobra._shoot(world.player)
		check(is_equal_approx(cobra.reload_timer, float(CATALOG.get_weapon(id).reload_duration)) and cobra.magazine == 0, id + " NPC cannot fire or refill during reload")
		cobra.free()
	# Protected target and both garage IDs retain their existing shared policy.
	state.economy = cheat_economy
	await prepare("shotgun_auto")
	target.set_meta("invulnerable", true)
	var protected_health := target.health
	gameplay.fire_at(target.global_position)
	check(target.health == protected_health, "variant pellets cannot damage a protected character")
	for garage: String in ["maciota", "harbor_garage"]:
		state.set_location("harbor", garage)
		var inventory: Dictionary = state.economy.snapshot()
		gameplay.cooldown = 0
		check(not gameplay.equip_slot("smg_compact") and not gameplay.fire_at(target.global_position) and not gameplay.reload_weapon(), garage + " blocks equip, shot, melee and reload")
		check(state.economy.snapshot().weapons == inventory.weapons, garage + " preserves weapon inventory")
	state.set_location("harbor")
	check(gameplay.equip_slot("smg_compact"), "leaving garage restores selection")
	Input.action_release("fire")
	Input.action_release("aim")
	controls.touch_aim = Vector2.ZERO
	world.free()
	print("WEAPON_VARIANTS_COMBAT checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
