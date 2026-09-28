extends Node
## Pátio lateral da delegacia (V1 `world/harbor/HarborPatrolParking.gd`): duas
## viaturas estacionadas e trancadas. Entrar exige lockpick (V1
## `ui/VehicleLockpick.gd`, uma única chance de erro). Errar ou desistir dispara o
## alarme da viatura por 10–15 s, com giroflex, e não gera estrela; acertar rende
## exatamente uma estrela (V1 `WantedManager.report_police_car_theft`). A vaga
## esvaziada é reposta depois de 45 s (V1 `EmergencyStandbyPoint.notify_stolen`,
## `restore_after_seconds * 2.5`), preservando a viatura roubada.
##
## Não persiste no save, como na V1: ao carregar, o pátio volta com as duas
## viaturas trancadas. Uma viatura roubada que o jogador estava dirigindo volta
## pelo caminho normal de veículo do jogador, já destrancada.
const LOCKPICK := preload("res://runtime/BankLockpick.gd")
## V1: PatrolAccess (939,2045) px + vagas (-95,-165) e (-95,-45), a 16 px/m.
## A rotação 2D PI/2 (frente para +y, sul) vira yaw PI: a frente do Vehicle é -Z.
const BAYS := [
	{"archetype":"police_cruiser","position":Vector3(844,0,1880)/16.0},
	{"archetype":"police_suv","position":Vector3(844,0,2000)/16.0},
]
const YAW := PI
const SPAWN_RADIUS := 120.0
const RESTOCK_SECONDS := 45.0
## V1 `VehicleLockpick.can_complete`: até 100 px (6,25 m) entre ator e viatura.
const LOCK_REACH := 100.0 / 16.0
var session
var cars: Array = [null, null]
var restock: Array[float] = [0.0, 0.0]
var lockpick: CanvasLayer
var target: CharacterBody3D
var awaiting_release := false
var _clock := 0.0
var _editor_transform := Transform3D.IDENTITY
var _editor_yaw := 0.0

func configure(owner_session) -> void:
	session = owner_session
	var edit := preload("res://world/editing/WorldServiceBuildings.gd").row_for("harbor_police")
	if edit.has("service_base"):
		_editor_transform = preload("res://world/editing/WorldServiceBuildings.gd").transform_for(edit)
		_editor_yaw = deg_to_rad(float(edit.rotation))
	process_mode = Node.PROCESS_MODE_PAUSABLE
	lockpick = LOCKPICK.new()
	lockpick.lock_title = "VIATURA"
	lockpick.instruction_text = "ESPAÇO / CLIQUE — travar na faixa verde\nErrou: alarme • ESC — desistir"
	lockpick.allowed_mistakes = 1
	add_child(lockpick)
	lockpick.unlocked.connect(_unlocked)
	lockpick.cancelled.connect(_cancelled)

func lockpick_active() -> bool:
	return is_instance_valid(lockpick) and lockpick.active

## Modal do lockpick, inclusive a espera pela soltura do clique que falhou.
func blocks_input() -> bool:
	return lockpick_active() or awaiting_release

func _process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	for index in restock.size(): restock[index] = maxf(0, restock[index] - delta)
	if lockpick_active() and not _can_complete(target): lockpick.finish(false)
	# O clique que errou a trava não pode virar tiro depois (V1 `_waiting_for_release`).
	if awaiting_release and not _attempt_held():
		awaiting_release = false
		session.close_menu()
	_clock += delta
	if _clock < .5: return
	_clock = 0
	_sync()

func _sync() -> void:
	if session.is_transition_blocked() or session.state.region_id != "harbor" or not session.state.place_id.is_empty(): return
	var player: CharacterBody3D = session.world.player
	for index in BAYS.size():
		var car = cars[index]
		if is_instance_valid(car) and not car.is_queued_for_deletion(): continue
		cars[index] = null
		if restock[index] > 0: continue
		var bay: Vector3 = _editor_transform*BAYS[index].position
		if player.global_position.distance_to(bay) > SPAWN_RADIUS: continue
		cars[index] = _spawn(index)

func _spawn(index: int) -> CharacterBody3D:
	var bay: Vector3 = _editor_transform*BAYS[index].position
	var space: PhysicsDirectSpaceState3D = session.world.get_world_3d().direct_space_state
	var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(bay + Vector3.UP * 8, bay - Vector3.UP * 4, 1))
	# Chão ainda não carregado pelo streaming: tenta no próximo ciclo.
	if ground.is_empty(): return null
	# Checagem barata antes de instanciar o modelo: a viatura roubada devolvida à
	# vaga, ou o próprio jogador parado nela, bloqueiam a reposição.
	if session.world.player.global_position.distance_to(bay) < 3.5: return null
	for other in get_tree().get_nodes_in_group("drivable"):
		if other is Node3D and other.global_position.distance_to(bay) < 3.5: return null
	var point: Vector3 = ground.position + Vector3.UP * .04
	var car: CharacterBody3D = session.controller.spawn_vehicle(BAYS[index].archetype, point, YAW+_editor_yaw)
	if car == null: return null
	car.vehicle_id = "harbor_patrol_parked_%d" % index
	car.set_meta("police_locked", true)
	car.set_meta("lockpick_handler", begin_lockpick)
	car.ensure_equipment(session.world)
	return car

func begin_lockpick(car: CharacterBody3D) -> bool:
	if lockpick_active() or awaiting_release or not _can_complete(car): return false
	if session.modal or session.is_transition_blocked(): return false
	target = car
	session.modal = true
	session.world.player.input_locked = true
	lockpick.begin()
	return true

func _can_complete(car) -> bool:
	if not is_instance_valid(car) or not car.is_inside_tree() or car.is_queued_for_deletion(): return false
	if not car.get_meta("police_locked", false) or car.health <= 0 or car.controlled: return false
	if float(session.world.gameplay.health) <= 0 or session.is_transition_blocked(): return false
	return session.world.player.global_position.distance_to(car.global_position) <= LOCK_REACH

func _unlocked() -> void:
	var car := target
	target = null
	if not _can_complete(car):
		_cancelled_for(car)
		return
	car.remove_meta("police_locked")
	car.remove_meta("lockpick_handler")
	if is_instance_valid(car.equipment): car.equipment.stop_alarm()
	var index := cars.find(car)
	if index >= 0:
		cars[index] = null
		restock[index] = RESTOCK_SECONDS
	_report_theft(car)
	session.close_menu()
	# Entra direto na viatura destrancada, como a V1 fazia ao fim do lockpick.
	var driving = session.world.driving
	var option: Dictionary = driving._entry_option()
	if option.get("car") == car: driving._begin_entry(car, int(option.side))
	else: session.show_message("Viatura destrancada.")

## Cada viatura roubada soma uma estrela, preservando a perseguição existente.
func _report_theft(car: CharacterBody3D) -> void:
	var gameplay = session.world.gameplay
	var next: int = mini(int(gameplay.stars) + 1, gameplay.STAR_THRESHOLDS.size() - 1)
	gameplay.register_crime(maxi(1, int(gameplay.STAR_THRESHOLDS[next]) - int(gameplay.crime_points)), car.global_position)

func _cancelled() -> void:
	var car := target
	target = null
	_cancelled_for(car)

func _cancelled_for(car) -> void:
	# Falha e desistência disparam o alarme, mas ficam locais: nenhuma estrela.
	if is_instance_valid(car) and car.get_meta("police_locked", false) and car.health > 0:
		if is_instance_valid(car.equipment) and car.equipment.start_alarm():
			session.show_message("LOCKPICK FALHOU · alarme da viatura disparado.")
	awaiting_release = _attempt_held()
	if not awaiting_release: session.close_menu()

func _attempt_held() -> bool:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return true
	for action in ["ui_accept", "ui_cancel", "fire"]:
		if InputMap.has_action(action) and Input.is_action_pressed(action): return true
	return false
