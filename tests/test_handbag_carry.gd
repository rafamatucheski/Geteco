extends SceneTree

## Mala de mão: a mão esquerda fica no carregamento ao mirar, atirar, recarregar e socar, só a
## direita trabalha, e a mala balança como pêndulo ao arrancar e parar (parada, não balança).
const RIG := preload("res://gameplay/WeaponRigPose.gd")
const POSE := preload("res://gameplay/WeaponPoseData.gd")
var actor
var field
var bag
var rig
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

## Palma esquerda no espaço do Actor (metros) depois de `frames` quadros da pose.
func settle_pose(id: String, aiming: bool, reloading: bool, fire: bool, bag_carry := true) -> Vector3:
	rig.reset()
	actor._combat_weight = 0.0
	for i in 40:
		actor._apply_pose(actor._idle_pose)
		if fire and i == 36: rig.attack(id, 3.0)
		var info: Dictionary = actor.combat_rig_info()
		info["bag_carry"] = bag_carry
		var pose: Dictionary = rig.update(id, 1.0 / 60.0, aiming, reloading, 0.45 if reloading else 0.0, false, false, 0.0, info)
		actor.set_combat_weapon_pose(id, pose)
		actor._pose_delta = 1.0 / 60.0
		actor._apply_combat_weapon_pose()
		bag._process(1.0 / 60.0)
		await process_frame
	return actor.to_local(actor.combat_palm_position("Left"))

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	actor = load("res://scripts/Actor.gd").new()
	actor.is_player = true
	stage.add_child(actor)
	actor.set_physics_process(false)
	actor._apply_pose(actor._idle_pose)
	var economy = load("res://runtime/GameState.gd").new().economy
	economy.enable_grid_inventory()
	economy.grid_equip_bag("handbag")
	field = load("res://systems/inventory/FieldInventoryRuntime.gd").new()
	field.session = {"state": {"economy": economy}, "world": {"player": actor, "driving": {"occupied": false}}}
	stage.add_child(field)
	field.set_process(false)
	field._update_carried()
	for i in 3: await process_frame
	bag = field.carried
	rig = RIG.new()
	check(bag != null and bag.kind == "handbag","mala de mão equipada")
	# --- a mão da mala fica ao lado da coxa em todas as situações de combate
	var rest := await settle_pose("pistol",false,false,false)
	check(rest.y < 0.95 and rest.y > 0.55,"parado: a mão da mala fica junto da coxa (y=%.2f)" % rest.y)
	for case in [["pistol",true,false,false,"mirando"],["pistol",true,false,true,"atirando"],["pistol",false,true,false,"recarregando"],["magnum",true,false,true,"magnum atirando"],["fists",true,false,false,"guarda de soco"],["knife",true,false,false,"faca"]]:
		var hand := await settle_pose(case[0],case[1],case[2],case[3])
		check(hand.distance_to(rest) < 0.08,"%s: a mala não vai para a mira (deslocou %.2f m)" % [case[4],hand.distance_to(rest)])
		check(hand.y < 1.0,"%s: a mão da mala fica baixa (y=%.2f)" % [case[4],hand.y])
	# --- sem mala, a mão esquerda continua indo ao apoio da pistola (comportamento antigo)
	var free_aim := await settle_pose("pistol",true,false,false,false)
	check(free_aim.y > rest.y + 0.25,"sem mala, mirar ainda sobe a mão de apoio (y=%.2f)" % free_aim.y)
	# --- só a direita soca com a mala
	rig.reset()
	rig.bag_carry = true
	rig.attack("fists")
	check(not rig.punch_left,"com a mala, o soco nunca sai da esquerda")
	rig.attack("fists")
	check(not rig.punch_left,"nem no golpe seguinte")
	# --- pêndulo: parado não balança, arrancar balança, parar amortece
	bag._sway = Vector2.ZERO
	bag._sway_velocity = Vector2.ZERO
	bag._handle_world = Vector3.INF
	await settle_pose("pistol",false,false,false)
	check(bag._sway.length() < 0.02,"parado a mala não balança (%.4f)" % bag._sway.length())
	var peak := 0.0
	var x := 0.0
	var velocity := 0.0
	for i in 40:
		velocity += 7.0 / 60.0
		x += velocity / 60.0
		actor.global_position.x = x
		await process_frame
		peak = maxf(peak,bag._sway.length())
	check(peak > 0.04,"ao arrancar a mala fica para trás (balanço máximo %.3f)" % peak)
	check(peak <= bag.SWAY_LIMIT + 0.001,"o balanço respeita o limite")
	var handle_world: Vector3 = bag.global_transform * Vector3(0,bag.DUFFEL_HANDLE_TOP,0)
	var palm: Vector3 = actor.combat_palm_position("Left")
	check(handle_world.distance_to(palm) < 0.18,"balançando, a alça continua na mão (%.2f m)" % handle_world.distance_to(palm))
	# velocidade constante: sem aceleração o balanço amortece
	for i in 150:
		x += velocity / 60.0
		actor.global_position.x = x
		await process_frame
	check(bag._sway.length() < 0.03,"em velocidade constante o balanço amortece (%.3f)" % bag._sway.length())
	# teleporte não vira balanço gigante
	actor.global_position.x = x + 50.0
	for i in 3: await process_frame
	check(bag._sway.length() < 0.05,"teleporte não balança a mala (%.3f)" % bag._sway.length())
	stage.free()
	await process_frame
	print("HANDBAG_CARRY checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
