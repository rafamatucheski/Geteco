extends "res://tests/dispatch/test_dispatch_lifecycle.gd"
## Logical/native-physics contract. Real dispatch creates the ambulance; damage
## precedes distance suspension, and VehicleDamage burns through normal callbacks.
## Only the observer is moved. No unit/damage callback is invoked by this test.
## No Main, rendering, timing approval or persistence is exercised here.

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
	print("PASS " if condition else "FAIL ",label)

func state_of(car: CharacterBody3D, unit: RefCounted) -> Dictionary:
	var look: Node = car.damage_look
	var body: RigidBody3D = look._wreck_body
	return {"suspended":unit.suspended,"finished":unit.finished,"reason":unit.end_reason,
		"health":car.health,"position":str(car.global_position),"car_layer":car.collision_layer,
		"car_mask":car.collision_mask,"car_physics":car.is_physics_processing(),
		"burning":look.burning,"look_physics":look.is_physics_processing(),
		"saved_layer":look._driving_layer,"saved_mask":look._driving_mask,
		"saved_physics":look._driving_physics,"wreck":is_instance_valid(body),
		"wreck_layer":body.collision_layer if is_instance_valid(body) else -1,
		"wreck_mask":body.collision_mask if is_instance_valid(body) else -1,
		"wreck_frozen":body.freeze if is_instance_valid(body) else false}

func _vehicle_case(repair_while_suspended: bool) -> void:
	var label := "repair_suspended" if repair_while_suspended else "resume_wreck"
	var bundle: Dictionary = await _medic_world()
	var unit: RefCounted = await _wait_unit(bundle)
	check(unit != null, label+": real dispatch created the ambulance")
	if unit == null:
		KIT.teardown(bundle)
		return
	var car: CharacterBody3D = unit.vehicle
	check(bundle.controller.router._native != null, label+": compiled C# router is active")
	check(car.health == car.max_health and car.collision_layer == 4 and car.collision_mask == 7,
		label+": healthy native collider starts at 4/7")
	# Ordinary nonterminal damage starts the existing burn. No health assignment
	# or direct call to wreck()/a physics callback substitutes for the lifecycle.
	car.receive_damage(car.max_health * .90 / car.damage_resistance)
	check(car.health > 0.0 and car.damage_look.burning, label+": partial damage starts burn before suspension")
	bundle.player.global_position = Vector3(30, 0, 220)
	await _frames(4)
	check(unit.suspended and not car.visible and not car.is_physics_processing()
		and car.collision_layer == 0 and car.collision_mask == 0,
		label+": normal distance callback suspends the living vehicle")
	check(car.health > 0.0 and car.damage_look.is_physics_processing(),
		label+": burn child continues under a suspended living parent")
	# O incêndio agora reserva dez segundos de fuga; a suspensão não o congela.
	for index in ceili(12.0 * Engine.physics_ticks_per_second):
		await physics_frame
		if car.health <= 0.0 and car.damage_look.wrecked: break
	check(car.health <= 0.0 and car.damage_look.wrecked and unit.suspended,
		label+": ordinary burn callbacks destroy the suspended vehicle")
	var wreck: RigidBody3D = car.damage_look._wreck_body
	check(is_instance_valid(wreck), label+": destruction creates the real rigid wreck")
	print("SUSPENDED_VEHICLE_STATE ",label," death ",JSON.stringify(state_of(car,unit)))
	if not is_instance_valid(wreck):
		KIT.teardown(bundle)
		return
	if repair_while_suspended:
		car.repair()
		check(car.health == car.max_health and not car.damage_look.wrecked,
			label+": repair restores health while suspension remains owned by dispatch")
		check(not car.is_physics_processing() and car.collision_layer == 0 and car.collision_mask == 0,
			label+": repair does not expose an invisible driving collider")
		await _frames(2)
		check(not is_instance_valid(wreck), label+": suspended repair removes the old rigid body")
	else:
		var resting_position := car.global_position
		await _frames(20)
		check(car.global_position.distance_to(resting_position) < .001,
			label+": the hidden wreck remains frozen with its suspended unit")
	# Approach the actual current point rather than assuming a stationary car.
	bundle.player.global_position = car.global_position + Vector3(20, 0, 10)
	for index in 60:
		await physics_frame
		if not unit.suspended: break
	check(not unit.suspended and car.visible, label+": normal approach resumes the vehicle")
	print("SUSPENDED_VEHICLE_STATE ",label," resumed ",JSON.stringify(state_of(car,unit)))
	if not repair_while_suspended:
		check(car.collision_layer == 0 and car.collision_mask == 0 and not car.is_physics_processing(),
			label+": rigid wreck keeps exclusive physics/collision ownership after resume")
		check(wreck.collision_layer == 4 and wreck.collision_mask == 7 and not wreck.freeze,
			label+": resumed wreck has the original collision and native integration")
		await _frames(4)
		var bounds: AABB = car.damage_look._wreck_bounds()
		var center: Vector3 = car.to_global(bounds.get_center())
		var query := PhysicsRayQueryParameters3D.create(center+car.global_basis.x*(bounds.size.x+2.0),center,4)
		var hit := car.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider == wreck,
			label+": native ray hits the moving wreck and not the disabled CharacterBody")
		car.repair()
		await _frames(2)
		check(not is_instance_valid(wreck), label+": repair removes the former rigid collider")
	check(car.health == car.max_health and not car.damage_look.wrecked,
		label+": repaired vehicle is healthy")
	check(car.collision_layer == 4 and car.collision_mask == 7 and car.is_physics_processing(),
		label+": repaired/resumed vehicle recovers the original driving collision and processing")
	print("SUSPENDED_VEHICLE_STATE ",label," repaired ",JSON.stringify(state_of(car,unit)))
	KIT.teardown(bundle)
	await _frames(3)
	done(label)

func _preexisting_wreck() -> void:
	var bundle: Dictionary = await _medic_world()
	var unit: RefCounted = await _wait_unit(bundle)
	check(unit != null, "existing_wreck: real dispatch created the ambulance")
	if unit == null:
		KIT.teardown(bundle)
		return
	var car: CharacterBody3D = unit.vehicle
	car.receive_damage(car.max_health * 2.0 / car.damage_resistance)
	var wreck: RigidBody3D = car.damage_look._wreck_body
	check(is_instance_valid(wreck) and wreck.collision_layer == 4 and wreck.collision_mask == 7
		and not wreck.freeze and not car.is_physics_processing(),
		"existing_wreck: rigid body owns normal collision before suspension")
	# The rigid body exists before dispatch's next normal callback. The observer
	# leaves in the same turn, so no completed/adopted unit is artificially revived.
	bundle.player.global_position = Vector3(30, 0, 220)
	await _frames(4)
	check(unit.suspended and not unit.finished and not car.visible,
		"existing_wreck: dispatch suspends an already wrecked owned vehicle")
	check(wreck.freeze and wreck.collision_layer == 0 and wreck.collision_mask == 0,
		"existing_wreck: suspension also freezes and hides the rigid collider")
	var paused_position := car.global_position
	await _frames(15)
	check(car.global_position.distance_to(paused_position) < .001,
		"existing_wreck: native rigid body does not drift while suspended")
	bundle.player.global_position = car.global_position + Vector3(20, 0, 10)
	for index in 60:
		await physics_frame
		if not unit.suspended: break
	check(not unit.suspended and car.visible,"existing_wreck: approach restores visibility")
	check(wreck.collision_layer == 4 and wreck.collision_mask == 7 and not wreck.freeze
		and car.collision_layer == 0 and car.collision_mask == 0 and not car.is_physics_processing(),
		"existing_wreck: resume restores only the rigid collider")
	check(unit.finished and unit.end_reason == "wrecked" and bundle.controller.wrecks.count(car) == 1,
		"existing_wreck: dispatch adopts the visible wreck exactly once")
	await _frames(5)
	check(bundle.controller.wrecks.count(car) == 1 and car.visible,
		"existing_wreck: subsequent callbacks do not duplicate adoption or hide the wreck")
	car.repair()
	await _frames(2)
	check(not is_instance_valid(wreck) and car.collision_layer == 4 and car.collision_mask == 7
		and car.is_physics_processing(),"existing_wreck: repair after adoption restores original driving state")
	KIT.teardown(bundle)
	await _frames(3)
	done("existing_wreck")

func _original_processing() -> void:
	var bundle: Dictionary = await _medic_world()
	var unit: RefCounted = await _wait_unit(bundle)
	check(unit != null,"original_processing: real unit exists")
	if unit == null:
		KIT.teardown(bundle)
		return
	var car: CharacterBody3D = unit.vehicle
	car.set_physics_process(false)
	bundle.player.global_position = Vector3(30, 0, 220)
	await _frames(4)
	check(unit.suspended and not car.is_physics_processing(),"original_processing: inactive body suspends")
	bundle.player.global_position = car.global_position + Vector3(20, 0, 10)
	for index in 60:
		await physics_frame
		if not unit.suspended: break
	check(not unit.suspended and car.visible and car.collision_layer == 4 and car.collision_mask == 7,
		"original_processing: normal visibility and collision resume")
	check(not car.is_physics_processing(),"original_processing: resume preserves original physics=false")
	KIT.teardown(bundle)
	await _frames(3)
	done("original_processing")

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Suspended vehicle contract requires --no-save and isolated runner storage")
		quit(2)
		return
	create_timer(28.0).timeout.connect(func(): push_error("DISPATCH_SUSPENDED_VEHICLE timeout"); quit(3))
	await _vehicle_case(false)
	await _vehicle_case(true)
	await _preexisting_wreck()
	await _original_processing()
	report("DISPATCH_SUSPENDED_VEHICLE",["resume_wreck","repair_suspended","existing_wreck","original_processing"],44)
