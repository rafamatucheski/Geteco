extends "res://tests/dispatch/test_dispatch_body_flight_suspension.gd"
## Contrato independente de posse de golpe/pose. Dano, voo, pouso, recuperação
## e morte passam pelo responder real e pelos callbacks normais do motor.

func hit_owner() -> void:
	var label := "hit_owner"
	var bundle: Dictionary = await setup_case(label)
	var crew: CharacterBody3D = bundle.crew
	var base_rotation: Vector3 = crew.visual.rotation
	crew.receive_damage(1.0)
	var old_hit: Tween = crew.get_meta("v2_hit_tween",null) as Tween
	check(old_hit != null and old_hit.is_running(),label+": standing damage creates the normal hit tween")
	await frames(3)
	check(not crew.visual.rotation.is_equal_approx(base_rotation),label+": normal hit really changes the presented pose")
	var flight := launch(bundle,label)
	check(not old_hit.is_valid() and not crew.has_meta("v2_hit_tween"),label+": impact ownership cancels the previous hit writer")
	check(is_equal_approx(flight._visual_base.basis.get_euler().x,base_rotation.x)
		and is_equal_approx(flight._visual_base.basis.get_euler().z,base_rotation.z),label+": impact captures the restored pose instead of transient hit tilt")
	var health: float = crew.health
	crew.receive_damage(1.0)
	check(crew.health == health-1.0 and not crew.has_meta("v2_hit_tween"),label+": flight takes real damage without a second pose writer")
	await wait_land(bundle,flight,label)
	check(not crew.has_meta("street_pose_owned") and crew.has_meta("street_down"),label+": landing releases the death-presentation guard while retaining down state")
	check(not crew.has_meta("v2_hit_tween"),label+": landing damage cannot start a competing hit tween")
	var prone: Transform3D = crew.visual.transform
	health = crew.health
	crew.receive_damage(1.0)
	await frames(3)
	check(crew.health == health-1.0 and not crew.has_meta("v2_hit_tween")
		and crew.visual.transform.is_equal_approx(prone),label+": prone damage preserves the owned pose")
	flight.down_time = FLIGHT.SELF_RECOVERY_SECONDS
	await frames(2)
	check(flight._getting_up,label+": normal callback starts recovery")
	health = crew.health
	crew.receive_damage(1.0)
	check(crew.health == health-1.0 and not crew.has_meta("v2_hit_tween"),label+": recovering actor takes damage without competing hit tween")
	await frames(70)
	check(not is_instance_valid(flight) and not crew.has_meta("street_down"),label+": recovery releases ownership")
	crew.receive_damage(1.0)
	var new_hit: Tween = crew.get_meta("v2_hit_tween",null) as Tween
	check(new_hit != null and new_hit.is_running(),label+": standing hit presentation works again after recovery")
	await finish_case(bundle,label)

func death_pose(recovering: bool) -> void:
	var label := "death_recovering" if recovering else "death_prone"
	var bundle: Dictionary = await setup_case(label)
	var flight := launch(bundle,label)
	await wait_land(bundle,flight,label)
	if recovering:
		flight.down_time = FLIGHT.SELF_RECOVERY_SECONDS
		await frames(3)
		check(flight._getting_up,label+": death interrupts actual recovery")
	var crew: CharacterBody3D = bundle.crew
	var previous: Transform3D = crew.visual.transform
	crew.receive_damage(1000.0)
	check(crew.dead and crew.has_meta("destroyed_cleanup"),label+": normal death still schedules cleanup")
	await frames(20)
	check(not is_instance_valid(flight),label+": death releases the flight owner")
	check(not crew.visual.transform.is_equal_approx(previous),label+": independent death fall still animates")
	check(crew.collision_layer == 0 and crew.collision_mask == 0 and not crew.is_physics_processing(),label+": death retains sole authority over collision")
	await finish_case(bundle,label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(25.0).timeout.connect(func(): push_error("BODY_FLIGHT_HIT_OWNER timeout"); quit(3))
	await hit_owner()
	await death_pose(false)
	await death_pose(true)
	check(completed.size()==3,"all hit and death presentation contracts completed")
	print("BODY_FLIGHT_HIT_OWNER checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
