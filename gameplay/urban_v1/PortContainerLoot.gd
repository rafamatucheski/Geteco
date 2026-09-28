extends Node
const STATE := preload("res://gameplay/urban_v1/PortContainerState.gd")
var session
var records: Dictionary = {}
var pending: Node3D
var minigame: CanvasLayer
var occupied: Node3D
var scan_clock := 0.0
var release_controls := false
var rng := RandomNumberGenerator.new()
var maintenance_clock := 0.0
var witness_clock := 0.0
var reported_attempt := false

func configure(owner_session) -> void:
	session = owner_session
	name = "PortContainerLoot"
	records = session.state.world_state.get("port_containers",{}).duplicate(true)
	rng.randomize()
	add_to_group("port_container_service")

func _ready() -> void:
	minigame = preload("res://ui/ContainerLockpick.gd").new()
	add_child(minigame)
	minigame.resolved.connect(_resolve_lock)
	for container in get_tree().get_nodes_in_group("lootable_port_containers"): bind_container(container)

func bind_container(container: Node3D) -> void:
	container.apply_state(records.get(container.cargo_id,{}))

func available() -> bool:
	return outdoor_context() and not session.modal and not session.world.player.input_locked

func outdoor_context() -> bool:
	return session != null and session.ready_for_play and session.state.region_id == "harbor" and session.state.place_id.is_empty() and not session.is_transition_blocked() and not session.world.driving.occupied and session.world.gameplay.health > 0

func picks() -> int:
	return int(session.state.economy.inventory.get("lockpick",0))

func nearest_action() -> Dictionary:
	if not available(): return {}
	var point: Vector3 = session.world.player.global_position
	for container in get_tree().get_nodes_in_group("lootable_port_containers"):
		if not container.opened and point.distance_to(container.door_point()) < 1.6:
			return {"id":"port_container","target":container.cargo_id,"label":"Arrombar · Lockpicks: %d" % picks() if picks() > 0 else "Precisa de lockpick · Lockpicks: 0"}
		if container.contains(point) and not container.looted and point.distance_to(container.loot_point()) < 1.6:
			return {"id":"port_container","target":container.cargo_id,"label":"Vasculhar"}
	return {}

func perform(id: String) -> bool:
	if not available() or is_instance_valid(pending): return false
	var action := nearest_action()
	if action.get("target","") != id: return false
	for container in get_tree().get_nodes_in_group("lootable_port_containers"):
		if container.cargo_id != id: continue
		if container.opened: return collect(container)
		if picks() <= 0:
			session.show_message("Precisa de lockpick. Disponível na Ammu-Nation.")
			return false
		pending = container
		reported_attempt = false
		witness_clock = 0.0
		session.modal = true
		session.world.player.input_locked = true
		minigame.begin(picks(),rng.randf_range(-75,75))
		container.play_lock_sound()
		return true
	return false

func _process(delta: float) -> void:
	if session.ready_for_play:
		maintenance_clock += delta
		if maintenance_clock >= 1.0:
			advance_restock(maintenance_clock)
			maintenance_clock = 0.0
	if is_instance_valid(pending) and not reported_attempt:
		witness_clock -= delta
		if witness_clock <= 0.0:
			witness_clock = .5
			reported_attempt = report_witnessed_theft()
	if release_controls and not Input.is_action_pressed("interact") and not Input.is_action_pressed("fire") and not Input.is_action_pressed("ui_accept"):
		release_controls = false
		if not session.is_transition_blocked() and session.world.gameplay.health > 0 and not session.modal:
			session.world.player.input_locked = false
	if is_instance_valid(pending):
		if session.world.gameplay.health <= 0 or session.is_transition_blocked() or not session.state.place_id.is_empty() or session.world.driving.occupied or session.world.player.global_position.distance_to(pending.door_point()) >= 1.6:
			cancel_attempt()
	elif pending != null:
		cancel_attempt()
	scan_clock -= delta
	if scan_clock > 0: return
	scan_clock = .1
	var inside: Node3D
	if outdoor_context():
		for container in get_tree().get_nodes_in_group("lootable_port_containers"):
			if container.contains(session.world.player.global_position):
				inside = container
				break
	if inside != occupied or not is_instance_valid(occupied):
		if is_instance_valid(occupied): occupied.set_revealed(false,session.world.camera)
		occupied = inside
		if is_instance_valid(occupied):
			occupied.set_obstructing(false)
			occupied.set_revealed(true,session.world.camera)
	for container in get_tree().get_nodes_in_group("lootable_port_containers"):
		if container == occupied:
			container.set_revealed(true,session.world.camera)
			continue
		var blocks := false
		if is_instance_valid(occupied):
			var direction: Vector3 = session.world.camera.global_basis.z
			for point in [session.world.player.global_position+Vector3.UP,occupied.global_position+Vector3.UP*.3,occupied.loot_point()]:
				if container.blocks_view(point,direction): blocks = true; break
		container.set_obstructing(blocks)
	# CameraRig remains the sole owner of camera interpolation and ordinary zoom.
	session.world.camera.set_meta("port_container_zoom",.84 if is_instance_valid(occupied) else 1.0)
	session.world.player.set_meta("port_container_shelter",is_instance_valid(occupied))
	if is_instance_valid(occupied): session.world.camera.set_meta("port_container_focus",occupied.global_position)
	else: session.world.camera.remove_meta("port_container_focus")

func cancel_attempt() -> void:
	if is_instance_valid(minigame) and minigame.active: minigame.finish("cancelled")
	else: pending = null

func _resolve_lock(result: String) -> void:
	var container := pending
	pending = null
	session.modal = false
	release_controls = Input.is_action_pressed("interact") or Input.is_action_pressed("fire") or Input.is_action_pressed("ui_accept")
	if not session.is_transition_blocked() and session.world.gameplay.health > 0:
		session.world.player.input_locked = false
	if result == "cancelled" or not is_instance_valid(container) or not available() or picks() <= 0: return
	container.play_lock_sound()
	if result == "opened":
		var row := STATE.normalized(records.get(container.cargo_id,{}))
		row.opened = true
		records[container.cargo_id] = row
		container.apply_state(records[container.cargo_id],true)
		session.show_message("Contêiner arrombado · Lockpicks: %d" % picks())
	elif result == "broken":
		session.state.economy.consume_item("lockpick")
		session.show_message("Lockpick quebrou · Restam %d" % picks())
	_persist()
	if release_controls: session.world.player.input_locked = true

func collect(container: Node3D) -> bool:
	if not available() or not container.contains(session.world.player.global_position) or container.looted or session.world.player.global_position.distance_to(container.loot_point()) >= 1.6: return false
	var wallet = session.state.economy
	var row := STATE.normalized(records.get(container.cargo_id,{}))
	var reward := STATE.loot(container.cargo_id,row.cycle)
	var receipt: String = STATE.receipt(container.cargo_id,row.cycle)
	var message := "Contêiner vazio"
	if wallet.snapshot().transactions.has("reward:"+receipt):
		message = "Já recolhido"
	elif reward.kind == "cash":
		if not wallet.grant_reward(receipt,int(reward.amount)):
			session.show_message("Sem espaço na carteira")
			return false
		message = "+R$ %d" % reward.amount
	elif reward.kind == "armor":
		if session.world.gameplay.armor >= 100.0:
			session.show_message("Colete cheio")
			return false
		if not wallet.grant_reward(receipt,0): return false
		session.world.gameplay.armor = minf(100.0,session.world.gameplay.armor+reward.amount)
		session.world.gameplay.changed.emit()
		message = "Colete recolhido"
	elif reward.kind == "weapon":
		var before: Dictionary = wallet.snapshot()
		var owned: bool = wallet.owns_weapon(reward.weapon)
		var granted: bool = wallet.add_ammo(reward.weapon,int(reward.amount)) if owned else wallet.grant_weapon(reward.weapon)
		if not granted:
			session.show_message("Sem espaço para recolher a arma ou munição")
			return false
		if not wallet.grant_reward(receipt,0):
			wallet.restore_snapshot(before)
			return false
		message = "+%d munições" % reward.amount if owned else "Arma recolhida: "+str(wallet.Weapons.WEAPONS[reward.weapon].label)
		session.world.gameplay.changed.emit()
	elif reward.kind == "ammo":
		var before: Dictionary = wallet.snapshot()
		if not wallet.add_ammo(reward.weapon,int(reward.amount)):
			session.show_message("Munição de pistola · Precisa de pistola e espaço na reserva")
			return false
		if not wallet.grant_reward(receipt,0):
			wallet.restore_snapshot(before)
			return false
		message = "+%d munições de pistola" % reward.amount
	else:
		if not wallet.grant_reward(receipt,0): return false
	row.opened = true
	row.looted = true
	records[container.cargo_id] = row
	container.apply_state(records[container.cargo_id])
	session.show_message(message)
	report_witnessed_theft()
	_persist()
	return true

func advance_restock(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0: return
	var loaded := {}
	for container in get_tree().get_nodes_in_group("lootable_port_containers"):
		loaded[container.cargo_id] = container
	var replaced := false
	for id in records:
		var row := STATE.normalized(records[id])
		if not row.opened or row.cycle >= STATE.MAX_CYCLE: continue
		row.elapsed = minf(STATE.RESTOCK_SECONDS,row.elapsed+delta)
		var container: Node3D = loaded.get(id)
		if row.elapsed >= STATE.RESTOCK_SECONDS and safe_to_restock(id,container):
			row = {"opened":false,"looted":false,"cycle":row.cycle+1,"elapsed":0.0}
			if is_instance_valid(container): container.apply_state(row)
			replaced = true
		records[id] = row
	# Keep normal saves current without writing a checkpoint every second.
	session.state.world_state.port_containers = records.duplicate(true)
	if replaced: _persist()

func safe_to_restock(id: String, container: Node3D) -> bool:
	var parts := id.split("_")
	var center := Vector3(float(parts[1])/16.0,0,float(parts[2])/16.0)
	if session.state.region_id == "harbor" and session.state.place_id.is_empty():
		if session.world.player.global_position.distance_to(center) < 70.0: return false
		if not session.world.camera.is_position_behind(center) and session.world.camera.is_position_in_frustum(center): return false
	if is_instance_valid(container) and (container == pending or container == occupied): return false
	# Includes dead bodies and NPCs, plus the door swing outside the shell.
	var shape := BoxShape3D.new()
	shape.size = Vector3(25.625,3.0,6.0625)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,center+Vector3.UP*1.3)
	query.collision_mask = 2
	for group in ["v1_routine_actor","v2_damageable"]:
		for actor in get_tree().get_nodes_in_group(group):
			if actor is Node3D and AABB(center-Vector3(12.8125,.3,3.03125),shape.size).has_point(actor.global_position): return false
	return session.world.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func witness_can_see(actor: Node3D) -> bool:
	if not is_instance_valid(actor) or actor == session.world.player or not actor.is_visible_in_tree(): return false
	if actor.get_meta("gameplay_role","") not in ["civilian","ambient_worker","urban_routine","police","emergency"]: return false
	if actor.get("dead") == true or (actor.get("health") != null and float(actor.get("health")) <= 0.0): return false
	var suspect: Vector3 = session.world.player.global_position
	var distance := actor.global_position.distance_to(suspect)
	if distance > 22.0: return false
	var facing: Node3D = actor.get("model") as Node3D
	if not is_instance_valid(facing): facing = actor.get("visual") as Node3D
	if not is_instance_valid(facing): facing = actor
	var direction := suspect-actor.global_position
	direction.y = 0
	var forward := -facing.global_basis.z
	# PortWorker's authored model faces +Z; routine civilians face -Z.
	if actor.has_method("_facing_yaw") and absf(wrapf(float(actor._facing_yaw(Vector3.FORWARD)),-PI,PI)) > PI*.5: forward = facing.global_basis.z
	if distance > 2.5 and forward.dot(direction.normalized()) < .15: return false
	var query := PhysicsRayQueryParameters3D.create(actor.global_position+Vector3.UP*1.5,suspect+Vector3.UP*1.1,1)
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func report_witnessed_theft() -> bool:
	if not outdoor_context(): return false
	var seen := {}
	for group in ["v1_routine_actor","v2_damageable"]:
		for actor in get_tree().get_nodes_in_group(group):
			if not actor is CharacterBody3D or seen.has(actor.get_instance_id()): continue
			seen[actor.get_instance_id()] = true
			if not witness_can_see(actor): continue
			var gameplay = session.world.gameplay
			# This property crime happens during a modal lockpick too. The combat
			# API rejects input-locked players; restore the lock synchronously,
			# without yielding a frame or enabling weapon input in the minigame.
			var was_locked: bool = session.world.player.input_locked
			session.world.player.input_locked = false
			gameplay.register_crime(maxi(0,12-gameplay.crime_points),session.world.player.global_position)
			session.world.player.input_locked = was_locked
			if not gameplay.report_civilian_call(actor.global_position,session.world.player.global_position): return false
			session.show_message("Roubo denunciado")
			return true
	return false

func _persist() -> void:
	session.state.world_state.port_containers = records.duplicate(true)
	session.save_game()

func _exit_tree() -> void:
	if not is_instance_valid(session):
		pending = null
		return
	if is_instance_valid(session.world) and is_instance_valid(session.world.camera):
		if is_instance_valid(session.world.player): session.world.player.remove_meta("port_container_shelter")
		session.world.camera.remove_meta("port_container_zoom")
		session.world.camera.remove_meta("port_container_focus")
		if is_instance_valid(occupied): occupied.set_revealed(false,session.world.camera)
		for container in get_tree().get_nodes_in_group("lootable_port_containers"): container.set_obstructing(false)
	cancel_attempt()
