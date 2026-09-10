extends "res://tests/test_npc_shared_presentation.gd"

func get_output_directory() -> String:
	return "res://docs/measurements/civilian-identity-0910/"

func _run() -> void:
	seed(9011)
	create_timer(60).timeout.connect(func(): quit(2))
	scene = Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var variants := [
		["Homem · encorpado",1,2,1,0,0],
		["Mulher · encorpada",2,2,1,2,3],
		["Homem · alto",1,3,0,1,2],
		["Mulher · cabelo comprido",2,0,1,6,7],
		["Mulher · baixa / Civil 4",2,4,4,3,5],
		["Homem · curto",1,0,1,0,1],
		["Mulher · chanel",2,1,2,2,4],
		["Homem · moicano",1,1,1,4,6],
		["Mulher · cacheada",2,0,1,7,9],
		["Homem · grisalho",1,4,7,1,10],
	]
	for data in variants:
		var actor = add_actor("res://AnimatedPedestrian3D.gd", data[0], {"district_theme":1,"appearance_gender":data[1],"body_type_override":data[2],"archetype_override":data[3],"hair_style_override":data[4],"appearance_seed":data[5]})
		check(actor.get_meta("appearance_female") == (data[1]==2), "Gênero configurado: " + data[0])
		check(actor.head_node.has_node("HairStyle"), "Cabelo autoral: " + data[0])
		check(not actor.torso_node.has_node("Belly"), "Sem barriga esférica sobreposta: " + data[0])
		var body: MeshInstance3D = actor.torso_node.get_node("BodyShell")
		check(body.mesh is ArrayMesh, "Tronco com ombros e cintura: " + data[0])
		if data[2] == 2:
			check(body.mesh.get_aabb().size.x * actor.torso_node.scale.x < .63, "Biotipo encorpado tem largura moderada")
		for movement in [false,true]:
			actor.is_scared = movement
			actor.velocity = Vector2(90,0) if movement else Vector2.ZERO
			actor._physics_process(.1)
			var neck: MeshInstance3D = actor.head_node.get_node("Neck")
			var low: Vector3 = actor.model_root.to_local(neck.to_global(Vector3(0,-.5,0)))
			var high: Vector3 = actor.model_root.to_local(neck.to_global(Vector3(0,.5,0)))
			var torso_top: float = actor.torso_node.position.y + .235
			var head_bottom: float = actor.head_node.position.y - .17 * actor.head_node.scale.y
			check(low.y < torso_top and high.y > head_bottom, "Pescoço une cabeça e tronco parado/correndo: " + data[0])
		actor.velocity = Vector2.ZERO
		actor.is_scared = false
	for profile in 6:
		var role: String = ["lookout","enforcer","leader"][profile%3]
		var cobra = add_actor("res://world/harbor/cobras/CobraResident.gd", "Cobra", {"profile":profile,"combat_role":role,"body_type_override":profile%5})
		labels[labels.size()-1] = "%s · %s" % [cobra.get_meta("character_name"),preload("res://world/shared/pedestrians/CitizenAppearance.gd").HAIR_NAMES[cobra.get_meta("hair_style")]]
		check(cobra.shirt_color.g > cobra.shirt_color.r and cobra.shirt_color.g > cobra.shirt_color.b, "Cobra usa verde: %s" % profile)
		var rig = cobra.get_node("NPCCombatRig")
		for frame in 100: rig.combat_pose.update(rig,1.0/60,true,false,0)
		check(rig.weapon_mount_node.transform.is_finite(), "Nova identidade preserva arma: %s" % profile)
	var boss = add_actor("res://world/harbor/cobras/CobraBoss.gd", "Takeshi · líder")
	check(boss.shirt_color.g > boss.shirt_color.r, "Líder mantém identidade verde")
	var women := 0
	var hairstyles := {}
	for index in 8:
		var walker = preload("res://world/harbor/HarborLife.gd").HarborWalker.new()
		walker.appearance_variant = index
		walker.route_points = PackedVector2Array([Vector2(100,100),Vector2(180,100)])
		scene.add_child(walker)
		walker.set_physics_process(false)
		check(walker.viewport == null, "Identidade mantém criação sob demanda")
		walker.ensure_presentation()
		women += int(walker.get_meta("appearance_female"))
		hairstyles[walker.get_meta("hair_style")] = true
		walker.free()
	check(women == 4, "Rua efetivamente instancia homens e mulheres")
	check(hairstyles.size() >= 4, "Elenco da rua recebe cortes distintos")
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(get_output_directory()))
		await capture_gallery("gameplay",false)
		await capture_gallery("identidades",true)
	for actor in actors: actor.free()
	scene.free()
	print("CIVILIAN_IDENTITY: %s verificações, %s falhas" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
