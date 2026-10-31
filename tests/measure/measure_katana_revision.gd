extends "res://tests/measure/measure_katana_session.gd"
## Mesmo benchmark de aço de 30 segundos da linha de base; checagens extras rodam DEPOIS dessa janela.
var revision_moves: Array[int] = []
func phase(label: String, use_rage := false) -> void:
	await super.phase(label,use_rage)
	if label == "steel": await verify_revision()

func picture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir.path_join(label+".png"))

func verify_revision() -> void:
	# Exercita a cadeia real dano -> HUD -> teclado, não um medidor pré-preenchido.
	var saved_health: float = gameplay.health
	var saved_armor: float = gameplay.armor
	gameplay.god_mode = false
	gameplay._sync_god_mode()
	gameplay.health = 100.0
	gameplay.armor = 0.0
	gameplay.rage.restore(0.0)
	world.player.receive_damage(20.0)
	await frames(12)
	check(is_equal_approx(gameplay.rage.charge,50.0),"real player damage charges RAGE")
	var hud = world.find_child("PlayerStatusHUD",true,false)
	check(hud != null and is_equal_approx(hud.rage_bar.value,50.0),"HUD displays charge from real damage")
	world.player.receive_damage(20.0)
	await frames(12)
	check(gameplay.health > 0.0 and gameplay.rage.can_activate(),"damage fills RAGE while Dante remains alive")
	var key := InputEventKey.new(); key.keycode=KEY_V; key.physical_keycode=KEY_V; key.pressed=true
	Input.parse_input_event(key)
	await frames(2)
	check(gameplay.rage.active,"damage-filled RAGE activates through V")
	key = InputEventKey.new(); key.keycode=KEY_V; key.physical_keycode=KEY_V; key.pressed=false
	Input.parse_input_event(key)
	gameplay.rage.cancel("test_complete")
	gameplay.health = saved_health
	gameplay.armor = saved_armor
	gameplay.god_mode = true
	gameplay._sync_god_mode()
	gameplay.clear_loot()
	if is_instance_valid(target): target.queue_free()
	await frames(4)
	var detail := Camera3D.new()
	world.player.add_child(detail)
	detail.look_at_from_position(world.player.global_position+direction*3.0+direction.cross(Vector3.UP)*3.0+Vector3.UP*2.1,world.player.global_position+Vector3.UP*0.9)
	detail.make_current()
	gameplay._katana_combo = -1
	for kind in ["police","civilian"]:
		var victim = preload("res://gameplay/PoliceAgent.gd").new() if kind == "police" else preload("res://scripts/Actor.gd").new()
		if kind == "police":
			victim.controller = gameplay
			# Coletas de arma nova se equipam sozinhas na produção. Toma posse deste drop antes de a
			# fixture morrer para que os golpes restantes ainda exercitem a katana.
			state.grant_weapon(victim.weapon_id)
		state.equip_weapon("katana")
		world.add_child(victim)
		victim.set_physics_process(false)
		victim.global_position = ground(world.player.global_position+direction*1.1)
		await frames(3)
		var initial: float = victim.health
		var hits := 0
		while not victim.dead and hits < 4:
			await frames(52)
			victim.global_position = ground(world.player.global_position+direction*1.1)
			var fired: bool = gameplay.fire_at(victim.global_position+Vector3.UP)
			check(gameplay.equipped()=="katana","physical strike uses equipped katana")
			check(fired,"%s swing %d accepted"%[kind,hits+1])
			revision_moves.append(gameplay._katana_combo)
			for frame in 24:
				await frames(1)
				if frame in [7,15,23]: await picture("%s-swing-%d-frame-%d"%[kind,hits+1,frame+1])
			var grip_error: float = world.player.combat_palm_position("Left").distance_to(gameplay.gun.to_global(Vector3(0,0,0.18)))
			print("KATANA support error ",grip_error)
			check(grip_error<0.08,"support hand remains on katana handle")
			hits += 1
			if hits == 1: check(not victim.dead and victim.health < initial,"%s survives first physical katana hit"%kind)
			await picture("%s-hit-%d"%[kind,hits])
		check(victim.dead and hits == (2 if kind=="police" else 3),"%s needs %d hits from full health"%[kind,2 if kind=="police" else 3])
		victim.queue_free()
		gameplay.clear_loot()
		await frames(3)
	check(revision_moves.slice(0,3)==[0,1,2],"deliberate clicks cycle three distinct attacks")
	# Limpa a recuperação de mira/ataque e então usa as ações reais de movimento do desktop.
	root.get_node("GameInput").touch_aim=Vector2.ZERO
	await frames(90)
	var start: Vector3 = world.player.global_position
	Input.action_press("move_left")
	Input.action_press("sprint")
	await frames(24)
	check(world.player.combat_clip=="" and not world.player.combat_weapon_pose.get("native_sword",false),"running uses locomotion, not frozen sword idle")
	await picture("katana-running")
	await frames(24)
	Input.action_release("move_left")
	Input.action_release("sprint")
	check(world.player.global_position.distance_to(start)>0.5,"running request moves real Dante")
	world.player.teleport(start)
	world.camera.make_current()
	detail.queue_free()
	await frames(8)
	aim()
