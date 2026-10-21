extends "res://tests/desert_village_homes_session.gd"
## Keep the inventory/save/Main benchmark coverage while using the current push doors.
func enter(id: String) -> bool:
	world.player.automatic_direction=world.session.weapon_shop_entrance._inward(id)
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session.state.place_id==id and not world.session.is_transition_blocked(): break
	world.player.automatic_direction=Vector3.ZERO
	return check(world.session.state.place_id==id and not world.player.input_locked,id+" pushes physical door and regains control")

func leave() -> bool:
	world.player.teleport(world.session.room.exit_position+Vector3(0,.02,-.45))
	world.player.automatic_direction=Vector3.BACK
	var deadline := Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		await physics_frame
		if world.session.state.place_id.is_empty() and not world.session.is_transition_blocked(): break
	world.player.automatic_direction=Vector3.ZERO
	await create_timer(.35).timeout
	return check(world.session.state.place_id.is_empty() and not world.player.input_locked and world.session.position_clear(world.player.global_position),"physical exit restores exterior support and control")
