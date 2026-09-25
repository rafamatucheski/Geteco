extends SceneTree
var world
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(condition: bool, label: String) -> void:
	if not condition: failures.append(label); push_error(label)
func settle(frames := 3) -> void:
	for i in frames: await physics_frame
func run() -> void:
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 240:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	check(world.session != null and world.session.ready_for_play,"Integrated world starts")
	if not failures.is_empty(): quit(1); return
	var session = world.session
	var state = session.state
	check(world.production.no_save,"Fixture must not touch player save")
	var removed_actor = preload("res://scripts/Actor.gd").new()
	world.add_child(removed_actor)
	world.people.append(removed_actor)
	removed_actor.free()
	world.production._process(.3)
	check(world.people.all(func(actor): return is_instance_valid(actor)),"Streaming removes freed residents safely")
	check(state.grant_weapon("pistol"),"Grant owned pistol")
	check(state.equip_weapon("pistol"),"Outdoor weapon equip")
	check(await session.enter_place("maciota",false),"Enter original garage")
	check(not state.can_attack() and not state.weapons_allowed(),"All attacks blocked in garage")
	check(state.equipped_weapon == "fists","Entering garage holsters weapon")
	check(not state.equip_weapon("pistol"),"Cannot draw owned weapon indoors")
	for id in ["maciota","mechanic","part","maciota"]:
		world.player.teleport(world.maciota_place.interaction_points[id]+Vector3.UP*.05)
		await settle()
		check(session.interact(),"Physical intro interaction: "+id)
		while session.dialogue_open: session._advance_dialogue()
	check(state.intro.stage == "complete","Intro completed through real interactions")
	var restored = load("res://runtime/GameState.gd").new()
	check(restored.restore_snapshot(state.snapshot()),"Integrated state roundtrip")
	check(not restored.weapons_allowed() and restored.equipped_weapon == "fists","Restore preserves garage restriction")
	check(session.leave_place(),"Leave garage with physical clearance")
	check(state.weapons_allowed() and state.equip_weapon("pistol"),"Inventory released outside")
	check(state.campaign.begin("primeiro_giro"),"Original first delivery starts")
	check(not session.mission_world.perform("helena"),"No remote mission completion")
	check(await session.enter_place("harbor_bank",false),"Native bank transition")
	check(is_instance_valid(session.room_npc),"Bank clerk installed")
	check(world.camera.locked,"Interior camera locked")
	check(not state.campaign.apply_event("bank_receipt_received",{"target_id":"helena","on_foot":true,"unarmed":false}).get("ok",false),"Bank refuses armed delivery event")
	check(session.leave_place(),"Leave bank")
	await settle()
	for place in ["harbor_police","harbor_hospital","harbor_fire_station"]:
		check(await session.enter_place(place,false),"Enter populated service: "+place)
		check(session.room_npcs.size()==session.room.definition.npcs.size(),"All original residents installed: "+place)
		for npc in session.room.definition.npcs:
			var center: Vector3 = session.room.to_global(npc.local_position)
			var approached := false
			for offset in [Vector3(0,0,.9),Vector3(.9,0,0),Vector3(-.9,0,0),Vector3(0,0,-.9)]:
				var point: Vector3 = center+offset+Vector3.UP*.05
				if session.position_clear(point):
					world.player.teleport(point)
					approached = true
					break
			check(approached,"Solid-free approach to "+npc.id)
			check(approached and session.services.perform(npc.id),"Original dialogue: "+npc.id)
			while session.dialogue_open: session._advance_dialogue()
		if place == "harbor_hospital":
			world.gameplay.health = 40
			world.player.teleport(session.room.to_global(session.services.HOSPITAL_PICKUP)+Vector3.UP*.05)
			await settle()
			check(world.gameplay.health==100 and session.services.hospital_cooldown>0,"Physical hospital pickup heals and starts cooldown")
		check(session.leave_place(),"Leave populated service: "+place)
		await settle()
	check(session.cancel_mission(),"Cancel active delivery")
	var campaign_fixture: Dictionary = state.campaign.snapshot()
	campaign_fixture.completed = ["primeiro_giro"]
	campaign_fixture.claimed_rewards = ["primeiro_giro"]
	check(state.economy.grant_reward("campaign:primeiro_giro", int(session.MISSIONS.MISSIONS.primeiro_giro.reward)), "Prepare paid first-delivery receipt")
	for flag in session.MISSIONS.MISSIONS.primeiro_giro.sets_flags: campaign_fixture.flags[flag] = true
	check(state.campaign.restore_snapshot(campaign_fixture) and state.campaign.begin("cobra_contact"),"Prepare unlocked towing mission")
	check(session.mission_world.begin_tow_job({"story":true,"kind":"local"}),"Create physical mission cargo")
	check(session.cancel_mission(),"Cancel towing mission releases its cargo")
	check(session.mission_world.tow_job.is_empty(),"No orphaned tow ownership after cancellation")
	check(restored.restore_snapshot(state.snapshot()),"Cancelled mission can be saved and restored")
	session.close_menu()
	world.free()
	await process_frame
	print("FULL_SESSION ","PASS" if failures.is_empty() else "FAIL"," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
