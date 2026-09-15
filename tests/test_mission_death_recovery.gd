extends "res://tests/claude_gameplay_audit/AuditCommon.gd"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	_tag = "mission_death_recovery"
	arm_watchdog(120.0)
	isolate_saves(_tag)
	root.get_node("CampaignState").reset_campaign()
	root.get_node("SaveManager").clear_pending_save()
	skip_onboarding_flags()
	var world := await boot_harbor()
	while not world.gameplay_ready: await process_frame
	var player: Node2D = world.get_node("Player")
	var bridge: CanvasLayer = world.get_node("CobraCampaign")
	for arrested in [false, true]:
		check(bridge.runtime.start_mission("cobra_contact"), "Mission can start or retry")
		while bridge._dialog.visible: bridge._next_message()
		if arrested:
			player.arrest_and_respawn()
		else:
			player.take_damage(999)
		await create_timer(0.2).timeout
		check(bridge.runtime.active_id.is_empty(), "Death/arrest fails the active mission")
		check(not paused and not bridge._dialog.visible, "Failure dialogue does not pause recovery")
		# Another modal or the pause menu can interrupt the fall independently
		# of mission feedback. Respawn must also survive that interruption.
		if not arrested: paused = true
		await create_timer(3.5).timeout
		paused = false
		await frames(3)
		check(not player.is_dead and not player.is_arrested and not player.is_recovering, "Recovery finishes before failure acknowledgement")
		check(player.visible and player.is_physics_processing(), "Recovered player is visible and processing")
		check(bridge._dialog.visible, "Failure explanation is retained after recovery")
		while bridge._dialog.visible: bridge._next_message()
		check(not paused and not player.is_control_disabled and not player.is_in_dialogue, "Acknowledgement restores playable controls")
		await create_timer(0.6).timeout
		check(absf(player.model_root.rotation.x) < 0.01 and absf(player.model_root.rotation.z) < 0.01, "Death animation cannot resume over the recovered living pose")
		if not arrested:
			var before := player.global_position
			Input.action_press("move_left")
			await create_timer(0.5).timeout
			Input.action_release("move_left")
			check(player.global_position.distance_to(before) > 3.0, "Native walking works after hospital recovery")
			if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("D:/geteco/artifacts/mission-death-0914/hospital-recovered.png")
	await finish(_tag, world)
