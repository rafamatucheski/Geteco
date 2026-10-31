extends SceneTree
## Contrato lógico de física nativa, sem Main/render/FPS. A unidade começa estacionada
## para isolar o dono compartilhado do movimento. Dispatch, Responder, BodyFlight, queima,
## dano de pouso e callbacks de física são reais; nenhum recebe tick manual.
const KIT := preload("res://tests/dispatch/DispatchTestKit.gd")
const FLIGHT := preload("res://gameplay/street_physics/BodyFlight3D.gd")
const BURN := preload("res://gameplay/BurningActor.gd")

# Mesmo diretor mínimo de pouso de test_body_flight.gd: só a inicialização não relacionada
# de broadphase/watch/áudio é omitida. O pouso usa o código real.
class LandingDirector extends "res://gameplay/street_physics/StreetPhysics.gd":
	var landings := 0
	func _ready() -> void:
		blood = BLOOD.new()
		add_child(blood)
		set_physics_process(false)
	func on_body_landed(actor: CharacterBody3D, lethal: bool, source: Node, speed: float, heading: Vector3) -> void:
		landings += 1
		super.on_body_landed(actor,lethal,source,speed,heading)

var checks := 0
var failures: Array[String] = []
var completed: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
	print("PASS " if ok else "FAIL ",label)
func frames(count: int) -> void:
	for i in count: await physics_frame

func setup_case(label: String, ramp := false) -> Dictionary:
	var bundle := KIT.build(self,KIT.grid_roads(),Vector3(20,0,12))
	var controller: Node3D = bundle.controller
	controller.set_physics_process(false)
	bundle.gameplay.set_physics_process(false)
	bundle.player.set_physics_process(false)
	await frames(3)
	# O roteador é preguiçoso: uma fixture estacionada ainda não pediu nenhum caminho.
	# Exercita a API normal dele antes de exigir o backend compilado.
	var edge: Dictionary = controller.router.nearest_edge(Vector3(20,0,2))
	check(controller._ensure_bridge() and not edge.is_empty() and controller.router._native != null,label+": real bridge and C# router")
	var patient := KIT.add_patient(bundle.scene,Vector3(34,0,14))
	bundle.gameplay.emergency.report_injury(patient,false)
	var key: int = bundle.gameplay.emergency.serial
	var car: CharacterBody3D = controller._create_vehicle("medic",Vector3(20,0,2),0.0)
	var unit: RefCounted = controller._make_unit("medic",car,10.0,.45)
	unit.actor = patient
	unit.incident_id = key
	unit.state = "working"
	if ramp:
		var support := KIT.add_wall(bundle.scene,Vector3(31,0,2),Vector3(14,.4,12))
		support.rotation.x = .08
		bundle["ramp"] = support
	unit.crew = controller.spawn_responder(unit,Vector3(26,.35 if ramp else .05,2))
	controller.claim_incident(unit)
	unit.driver.hold(true)
	var street := LandingDirector.new()
	bundle.scene.add_child(street)
	bundle["street"] = street
	bundle["unit"] = unit
	bundle["crew"] = unit.crew
	controller.set_physics_process(true)
	await frames(2)
	check(is_instance_valid(unit.crew) and not unit.crew.dead and unit.crew.is_physics_processing(),label+": real living responder is active")
	return bundle

func launch(bundle: Dictionary, label: String, speed := 8.0) -> Node:
	var flight: Node = FLIGHT.launch(bundle.crew,Vector3.RIGHT*speed,false,bundle.street,null)
	check(is_instance_valid(flight) and bundle.crew.has_meta("street_flying") and not bundle.crew.is_physics_processing(),label+": BodyFlight alone owns locomotion after impact")
	return flight

func wait_land(bundle: Dictionary, flight: Node, label: String) -> void:
	for i in 180:
		await physics_frame
		if not is_instance_valid(flight) or not flight.flying: break
	check(is_instance_valid(flight) and not flight.flying and bundle.street.landings == 1,
		label+": normal swept-body callbacks land and apply damage once")
	check(not bundle.crew.dead and bundle.crew.health < 60.0 and bundle.crew.has_meta("street_down"),label+": survivor remains prone awaiting recovery")
	# Confere o apoio real separado da folga. Um contato de piso/rampa não pode
	# ser confundido com uma parede/viga recém-inserida obstruindo a retomada.
	var point: Vector3 = bundle.crew.global_position
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP,point-Vector3.UP,1)
	ray.exclude = [bundle.crew.get_rid()]
	var support: Dictionary = bundle.scene.get_world_3d().direct_space_state.intersect_ray(ray)
	var expected_normal: Vector3 = bundle.ramp.global_basis.y if bundle.has("ramp") else Vector3.UP
	check(not support.is_empty() and support.normal.dot(expected_normal)>.9999
		and (not bundle.has("ramp") or support.collider == bundle.ramp),label+": native landing support has the expected floor/ramp normal")
	print("BODY_FLIGHT_SUPPORT ",label," actor=",point," support=",support.get("position")," normal=",support.get("normal"))
	for child in bundle.crew.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		var standing := PhysicsShapeQueryParameters3D.new()
		standing.shape = child.shape
		standing.transform = child.global_transform
		standing.collision_mask = 7
		standing.exclude = [bundle.crew.get_rid(),bundle.unit.vehicle.get_rid()]
		print("BODY_FLIGHT_STANDING_CONTACT ",label," ",bundle.scene.get_world_3d().direct_space_state.collide_shape(standing,8))

func suspend(bundle: Dictionary, label: String) -> void:
	bundle.player.global_position = Vector3(20,0,220)
	await frames(4)
	check(bundle.unit.suspended and not bundle.crew.visible,label+": distance suspends and hides the responder")

func resume(bundle: Dictionary, label: String) -> void:
	bundle.player.global_position = bundle.unit.vehicle.global_position+Vector3(0,0,10)
	for i in 60:
		await physics_frame
		if not bundle.unit.suspended: break
	check(not bundle.unit.suspended and bundle.crew.visible,label+": normal approach restores visibility")

func finish_case(bundle: Dictionary, label: String) -> void:
	KIT.teardown(bundle)
	await frames(3)
	completed.append(label)

func during_flight() -> void:
	var label := "during_flight"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label,12.0)
	await suspend(bundle,label)
	var position: Vector3 = bundle.crew.global_position
	var flight_age: float = flight._age
	await frames(4)
	check(bundle.crew.global_position.distance_to(position)<.001 and is_equal_approx(flight._age,flight_age),label+": suspended motion owner and its flight clock stay frozen")
	check(bundle.crew.collision_layer == 0 and bundle.crew.collision_mask == 0,label+": hidden flight cannot republish collision mask")
	var actor_age: float = bundle.crew.age
	await resume(bundle,label)
	await frames(3)
	check(is_instance_valid(flight) and bundle.crew.has_meta("street_down") and not bundle.crew.is_physics_processing(),label+": resumption keeps the impact owner exclusive")
	check(is_equal_approx(bundle.crew.age,actor_age),label+": walking/service callback did not run beside BodyFlight")
	await wait_land(bundle,flight,label)
	# O solver nativo pode assentar um pouco dentro do apoio depois do voo
	# retomado. Um segundo ciclo de distância precisa manter esse sobrevivente apoiado retomável.
	# Um piso inserido ACIMA do apoio real de pouso antes da suspensão nunca
	# pode virar linha de base aceita só porque já existia naquele momento.
	var point: Vector3 = bundle.crew.global_position
	var raised := KIT.add_wall(bundle.scene,Vector3(point.x,-.09,point.z),Vector3(2,.2,2))
	await frames(3)
	await suspend(bundle,label+"_second")
	check(bundle.controller.footprint_clear(bundle.unit.vehicle,bundle.unit.vehicle.global_position,bundle.unit.vehicle.rotation.y),
		label+"_second: raised support is separate from the ambulance")
	bundle.player.global_position = bundle.unit.vehicle.global_position+Vector3(0,0,10)
	await frames(20)
	check(bundle.unit.suspended,label+"_second: newly raised floor cannot be accepted as old movement support")
	raised.queue_free()
	await frames(3)
	await resume(bundle,label+"_second")
	await finish_case(bundle,label)

func during_get_up() -> void:
	var label := "during_get_up"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label)
	await wait_land(bundle,flight,label)
	# Só preparação de limite, como em test_body_flight: simula uma espera de ferimento
	# já decorrida. O tween real de levantar precisa começar e terminar pelo motor.
	flight.down_time = FLIGHT.SELF_RECOVERY_SECONDS
	await frames(2)
	check(flight._getting_up and flight._recovery_tween != null,label+": natural callback starts the recovery tween")
	await suspend(bundle,label)
	var pose: Transform3D = bundle.crew.visual.transform
	var elapsed: float = flight._recovery_tween.get_total_elapsed_time()
	var hit: Tween
	if bundle.crew.has_meta("v2_hit_tween"): hit = bundle.crew.get_meta("v2_hit_tween") as Tween
	print("BODY_FLIGHT_HIT_AT_PAUSE valid=",hit != null and hit.is_valid()," running=",hit != null and hit.is_running())
	await frames(70)
	check(is_instance_valid(flight) and bundle.crew.has_meta("street_down"),label+": recovery does not complete while its actor is suspended")
	if is_instance_valid(flight):
		print("BODY_FLIGHT_TWEEN elapsed_before=",elapsed," elapsed_after=",flight._recovery_tween.get_total_elapsed_time(),
			" running=",flight._recovery_tween.is_running()," pose_before=",pose," pose_after=",bundle.crew.visual.transform)
	check(is_instance_valid(flight) and is_equal_approx(flight._recovery_tween.get_total_elapsed_time(),elapsed)
		and bundle.crew.visual.transform.is_equal_approx(pose),label+": pause preserves remaining tween time and prone pose")
	check(not bundle.crew.visible and not bundle.crew.is_physics_processing()
		and bundle.crew.collision_layer == 0 and bundle.crew.collision_mask == 0,label+": no invisible walking collider is restored by the tween")
	await resume(bundle,label)
	await frames(70)
	check(not is_instance_valid(flight) and not bundle.crew.has_meta("street_down"),label+": remaining recovery completes after resume")
	check(bundle.crew.visible and bundle.crew.is_physics_processing() and bundle.crew.collision_layer == 2
		and bundle.crew.collision_mask == 7,label+": recovered living responder regains normal collision once")
	await finish_case(bundle,label)

func death_while_paused() -> void:
	var label := "death_while_paused"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label)
	await wait_land(bundle,flight,label)
	await suspend(bundle,label)
	var crew: CharacterBody3D = bundle.crew
	var burn := BURN.new()
	burn.configure(crew,bundle.gameplay,null)
	crew.add_child(burn)
	for i in 120:
		await physics_frame
		if crew.dead: break
	check(crew.dead and bundle.unit.suspended,label+": independent burn callback can still kill a suspended actor")
	bundle.player.global_position = bundle.unit.vehicle.global_position+Vector3(0,0,10)
	await frames(30)
	check(not bundle.unit.suspended and crew.visible,label+": corpse can reappear without blocking the surviving vehicle")
	check(not is_instance_valid(flight),label+": dead actor does not retain a permanently paused motion owner")
	check(crew.collision_layer == 0 and crew.collision_mask == 0 and not crew.is_physics_processing(),label+": death remains authoritative after resume")
	await finish_case(bundle,label)

func occupied_flight_shape() -> void:
	var label := "occupied_flight_shape"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label,12.0)
	await suspend(bundle,label)
	check(is_instance_valid(flight._shape),label+": impact capsule still exists for real geometry query")
	var wall := KIT.add_wall(bundle.scene,flight._shape.global_position,Vector3(3,3,3))
	await frames(2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = flight._shape.shape
	query.transform = flight._shape.global_transform
	query.collision_mask = 1
	query.exclude = [bundle.crew.get_rid()]
	var hits: Array[Dictionary] = bundle.scene.get_world_3d().direct_space_state.intersect_shape(query,16)
	check(hits.any(func(hit: Dictionary): return hit.collider == wall),label+": new solid intersects the actual horizontal impact capsule")
	check(bundle.controller.footprint_clear(bundle.unit.vehicle,bundle.unit.vehicle.global_position,bundle.unit.vehicle.rotation.y),label+": new solid does not block the separate ambulance")
	bundle.player.global_position = bundle.unit.vehicle.global_position+Vector3(0,0,10)
	await frames(20)
	check(bundle.unit.suspended and not bundle.crew.visible,label+": occupied prone/flight geometry prevents whole-unit resumption")
	wall.queue_free()
	await frames(3)
	await resume(bundle,label)
	check(is_instance_valid(flight) and not bundle.crew.is_physics_processing(),label+": removing the solid resumes only the current motion owner")
	await finish_case(bundle,label)

func cancel_owner(deferred: bool) -> void:
	var label := "queue_owner" if deferred else "cancel_owner"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label)
	if deferred:
		# O cancelamento entra na fila antes do callback normal do controlador. O dono
		# ainda é válido quando a suspensão esconde o ator, e sai no fim do quadro.
		var witnessed: Array[bool] = []
		var observer: WeakRef = weakref(flight)
		bundle.controller.dispatch_event.connect(func(event: String, _data: Dictionary):
			if event == "unit_suspended":
				var owner: Node = observer.get_ref()
				witnessed.append(is_instance_valid(owner) and owner.is_queued_for_deletion()))
		flight.queue_free()
		await suspend(bundle,label)
		check(witnessed.size()==1 and witnessed[0],label+": queued owner is still valid during the real suspension callback")
	else:
		await suspend(bundle,label)
		flight.free()
	await frames(3)
	check(not is_instance_valid(flight) and not bundle.crew.has_meta("street_down"),label+": ordinary owner exit cleans its motion markers")
	check(not bundle.crew.visible and not bundle.crew.is_physics_processing()
		and bundle.crew.collision_layer == 0 and bundle.crew.collision_mask == 0,label+": owner cancellation does not publish hidden collision")
	await resume(bundle,label)
	check(bundle.crew.is_physics_processing() and bundle.crew.collision_layer == 2 and bundle.crew.collision_mask == 7,
		label+": resume uses the restored owner state instead of the obsolete flight snapshot")
	await finish_case(bundle,label)

func original_processing() -> void:
	var label := "original_processing"
	var bundle: Dictionary = await setup_case(label)
	bundle.crew.set_physics_process(false)
	await suspend(bundle,label)
	await resume(bundle,label)
	check(not bundle.crew.is_physics_processing() and bundle.crew.collision_layer == 2 and bundle.crew.collision_mask == 7,
		label+": a character without an impact owner preserves original physics=false")
	await finish_case(bundle,label)

func prepaused_tween() -> void:
	var label := "prepaused_tween"
	var bundle: Dictionary = await setup_case(label,true)
	var flight := launch(bundle,label)
	await wait_land(bundle,flight,label)
	flight.down_time = FLIGHT.SELF_RECOVERY_SECONDS
	await frames(2)
	flight._recovery_tween.pause()
	var elapsed: float = flight._recovery_tween.get_total_elapsed_time()
	await suspend(bundle,label)
	await resume(bundle,label)
	await frames(5)
	check(not flight._recovery_tween.is_running() and is_equal_approx(elapsed,flight._recovery_tween.get_total_elapsed_time()),
		label+": dispatch does not play a tween paused by another owner")
	check(not bundle.crew.is_physics_processing(),label+": paused recovery still owns locomotion after dispatch resumes")
	flight._recovery_tween.play()
	await frames(70)
	check(not is_instance_valid(flight) and bundle.crew.is_physics_processing(),label+": external unpause completes recovery normally")
	await finish_case(bundle,label)

func queued_actor() -> void:
	var label := "queued_actor"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label)
	await suspend(bundle,label)
	var observed: Array[Dictionary] = []
	var crew: CharacterBody3D = bundle.crew
	flight.tree_exited.connect(func():
		if is_instance_valid(crew):
			observed.append({"queued":crew.is_queued_for_deletion(),"physics":crew.is_physics_processing(),
				"layer":crew.collision_layer,"mask":crew.collision_mask}))
	bundle.controller.dismiss_all("test_cleanup")
	await frames(3)
	check(not is_instance_valid(crew) and not is_instance_valid(flight),label+": normal controller dismissal frees actor and motion owner")
	check(observed.size()==1 and observed[0].queued and not observed[0].physics and observed[0].layer==0 and observed[0].mask==0,
		label+": owner exit never reactivates an actor queued for deletion")
	await finish_case(bundle,label)

func recovered_under_new_beam() -> void:
	var label := "recovered_under_new_beam"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label)
	await wait_land(bundle,flight,label)
	await suspend(bundle,label)
	# A cura pode ocorrer independente da posse do movimento. Mantém o callback normal
	# de levantar pendente e põe um sólido real acima do corpo deitado.
	bundle.crew.health = 60.0
	var beam := KIT.add_wall(bundle.scene,bundle.crew.global_position+Vector3.UP*1.4,Vector3(2,.2,2))
	await frames(2)
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.exclude = [bundle.crew.get_rid()]
	var standing_hit := false
	for child in bundle.crew.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		query.shape = child.shape
		query.transform = child.global_transform
		var hits: Array[Dictionary] = bundle.scene.get_world_3d().direct_space_state.intersect_shape(query,16)
		standing_hit = standing_hit or hits.any(func(hit: Dictionary): return hit.collider == beam)
	check(standing_hit,label+": beam overlaps the actual standing collider awaiting restoration")
	check(bundle.controller.footprint_clear(bundle.unit.vehicle,bundle.unit.vehicle.global_position,bundle.unit.vehicle.rotation.y),
		label+": beam does not obstruct the ambulance")
	bundle.player.global_position = bundle.unit.vehicle.global_position+Vector3(0,0,10)
	await frames(20)
	check(bundle.unit.suspended,label+": imminent recovery cannot resume into the new standing obstruction")
	beam.queue_free()
	await frames(3)
	await resume(bundle,label)
	await frames(70)
	check(not is_instance_valid(flight) and bundle.crew.is_physics_processing() and bundle.crew.collision_layer == 2
		and bundle.crew.collision_mask == 7,label+": clearing the beam permits normal recovery and walking collision")
	await finish_case(bundle,label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(38.0).timeout.connect(func(): push_error("DISPATCH_BODY_FLIGHT timeout"); quit(3))
	if "--flight-only" in OS.get_cmdline_user_args():
		await during_flight()
		print("BODY_FLIGHT_SECOND_SUSPENSION checks=%d failures=%d"%[checks,failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	if "--get-up-only" in OS.get_cmdline_user_args():
		await during_get_up()
		print("BODY_FLIGHT_TWEEN_DIAGNOSTIC checks=%d failures=%d"%[checks,failures.size()])
		quit(0 if failures.is_empty() else 1)
		return
	await during_flight()
	await during_get_up()
	await death_while_paused()
	await occupied_flight_shape()
	await cancel_owner(false)
	await cancel_owner(true)
	await original_processing()
	await prepaused_tween()
	await queued_actor()
	await recovered_under_new_beam()
	check(completed.size()==10 and checks>=88,"all ten finite ownership contracts completed")
	print("DISPATCH_BODY_FLIGHT groups=%d/10 checks=%d failures=%d"%[completed.size(),checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
