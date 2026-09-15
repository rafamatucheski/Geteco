extends SceneTree
## Trajes da loja no Dante Meshy e estados que dependem das âncoras antigas.
## Rodar renderizado (sem --headless) para gerar as imagens de revisão:
##   "$GODOT" --path . --script res://tests/test_meshy_outfits.gd
## Mede: material e acessórios por traje, pose finita, flash de dano, boneco em
## cópia de âncoras (cabine/moto), prévia da loja e embarque seguindo as âncoras.
## Não mede: aparência em partida real, clipping de acessórios em todas as poses.

const OUT := "res://docs/measurements/meshy-outfits-0914"
const ACCESSORIES := {"dante_suit": 2, "dante_arctic": 2, "dante_trench": 1, "dante_cowboy": 2, "dante_madmax": 2, "dante_lumberjack": 2, "dante_ghillie": 2, "dante_hawaii": 2, "dante_badboy": 2}
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok and message not in failures:
		failures.append(message)
		push_error(message)

func count_visible(node: Node) -> int:
	var total := 0
	if node is GeometryInstance3D and node.is_visible_in_tree(): total += 1
	for child in node.get_children(): total += count_visible(child)
	return total

func pose_is_sane(skeleton: Skeleton3D, label: String) -> void:
	var head := skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
	var foot := skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin
	check(head.is_finite() and foot.is_finite(), label + ": pose finita")
	check(head.y - foot.y > 0.6, label + ": cabeça acima dos pés (%.2f)" % (head.y - foot.y))

func frame() -> void:
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw

func run() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	if rendered: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var scene := Node2D.new()
	root.add_child(scene)
	current_scene = scene
	var player = load("res://Player.gd").new()
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	scene.add_child(player)
	player.set_physics_process(false)
	player.viewport_3d.size = Vector2i(384, 384)
	player.viewport_3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam: Camera3D = player.viewport_3d.get_camera_3d()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.7
	cam.position = Vector3(0, 0.75, -3)
	cam.look_at(Vector3(0, 0.72, 0))
	var outfits: Array = OutfitCatalog.ORDER.duplicate()
	outfits.append("dante_ski")
	var atlas := Image.create(384 * outfits.size(), 768, false, Image.FORMAT_RGBA8)
	atlas.fill(Color("273039"))
	for i in outfits.size():
		var outfit: String = outfits[i]
		player.apply_outfit(outfit)
		player.model_root.rotation = Vector3.ZERO
		await frame()
		check(is_instance_valid(player.meshy_rig), outfit + ": usa o Dante Meshy")
		if not is_instance_valid(player.meshy_rig): continue
		var rig = player.meshy_rig
		check(rig.material != null, outfit + ": material de traje aplicado")
		check(bool(rig.material.get_shader_parameter("recolor")) == (outfit != "dante_classic"), outfit + ": recoloração coerente")
		var accessories := 0
		for attachment in rig.skeleton.get_children():
			if String(attachment.name).begins_with("MeshyOutfit"): accessories += count_visible(attachment)
		check(accessories >= ACCESSORIES.get(outfit, 0), outfit + ": acessórios visíveis (%d)" % accessories)
		# A reconstrução posa um quadro pela física; parada, passa às âncoras em seguida.
		for _i in 4: await physics_frame
		check(rig.uses_anchor_pose(), outfit + ": física parada usa as âncoras")
		pose_is_sane(rig.skeleton, outfit)
		if rendered:
			atlas.blit_rect(player.viewport_3d.get_texture().get_image(), Rect2i(0, 0, 384, 384), Vector2i(384 * i, 0))
			player.model_root.rotation.y = PI
			await frame()
			atlas.blit_rect(player.viewport_3d.get_texture().get_image(), Rect2i(0, 0, 384, 384), Vector2i(384 * i, 384))
	if rendered: atlas.save_png(ProjectSettings.globalize_path(OUT + "/outfits.png"))

	player.apply_outfit("dante_classic")
	player.model_root.rotation = Vector3.ZERO
	await frame()
	player.meshy_rig.flash_damage()
	check(is_equal_approx(float(player.meshy_rig.material.get_shader_parameter("hit_flash")), 1.0), "Flash de dano no material Meshy")
	await create_timer(0.4).timeout
	check(float(player.meshy_rig.material.get_shader_parameter("hit_flash")) < 0.01, "Flash de dano apaga")

	# Embarque: VehicleBoardingPose anima as âncoras; o Meshy precisa acompanhar.
	var boarding := preload("res://scripts/player/VehicleBoardingPose.gd").new()
	boarding.setup(player)
	player.set_meta("meshy_anchor_pose", true)
	var sequence := Image.create(384 * 4, 384, false, Image.FORMAT_RGBA8)
	var skeleton: Skeleton3D = player.meshy_rig.skeleton
	var standing_hips := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	for k in 4:
		var t: float = [0.1, 0.35, 0.6, 0.95][k]
		boarding.apply(player, "car", -1.0, t, 0.0)
		await frame()
		pose_is_sane(skeleton, "embarque t=%.2f" % t)
		if rendered: sequence.blit_rect(player.viewport_3d.get_texture().get_image(), Rect2i(0, 0, 384, 384), Vector2i(384 * k, 0))
	var seated_hips := skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin
	check(seated_hips.y < standing_hips.y - 0.05, "Embarque abaixa a pelve do Meshy (%.3f -> %.3f)" % [standing_hips.y, seated_hips.y])
	boarding.restore()
	player.remove_meta("meshy_anchor_pose")
	if rendered: sequence.save_png(ProjectSettings.globalize_path(OUT + "/boarding.png"))

	# Cópia das âncoras, como fazem VehicleCabinOccupant e DanteMotorcycleRider.
	var holder := Node3D.new()
	player.viewport_3d.add_child(holder)
	holder.position = Vector3(3, 0, 0)
	for key in ["torso_node", "head_node", "left_upper_arm", "right_upper_arm", "left_upper_leg", "right_upper_leg"]:
		holder.add_child(player.get(key).duplicate())
	var legacy_visible := count_visible(holder)
	var puppet := preload("res://scripts/player/MeshyDantePuppet.gd").new()
	holder.add_child(puppet)
	check(puppet.configure(holder, "dante_cowboy"), "Boneco Meshy configura sobre cópia de âncoras")
	await frame()
	check(legacy_visible == 0 and count_visible(holder) > 0, "Cópia de cabine/moto fica visível (%d malhas antigas, %d com Meshy)" % [legacy_visible, count_visible(holder)])
	pose_is_sane(puppet.skeleton, "cópia de âncoras")

	# Moto: DanteMotorcycleRider duplica as âncoras e prende o capacete na cópia
	# da cabeça. O teste do capacete de moto está desatualizado (chama
	# ensure_motorcycle_helmet, que não existe nem no HEAD), então a checagem fica aqui.
	var rider := preload("res://cars/motorcycles/DanteMotorcycleRider.gd").new()
	player.viewport_3d.add_child(rider)
	rider.position = Vector3(-3, 0, 0)
	rider.setup(player)
	await frame()
	var rider_puppets := rider.find_children("MeshyDantePuppet", "", false, false)
	check(rider_puppets.size() == 1, "Moto: piloto usa o Dante Meshy (%d)" % rider_puppets.size())
	check(rider.head_node.get_node_or_null("MotorcycleHelmet") != null, "Moto: capacete continua preso à cabeça")
	if rider_puppets.size() == 1:
		check(count_visible(rider_puppets[0]) > 0, "Moto: piloto visível")
		pose_is_sane(rider_puppets[0].skeleton, "piloto de moto")

	# Prévia da loja de roupas.
	var preview := CharacterPreview3D.new()
	scene.add_child(preview)
	await frame()
	preview.set_outfit("dante_hawaii")
	await frame()
	var previewed := preview.model_root.find_children("MeshyDantePuppet", "", true, false)
	check(previewed.size() == 1, "Prévia da loja usa um único Dante Meshy (%d)" % previewed.size())
	if previewed.size() == 1:
		check(count_visible(preview.model_root) - count_visible(previewed[0]) <= 1, "Prévia oculta o boneco antigo")
		check(bool(previewed[0].material.get_shader_parameter("recolor")), "Prévia aplica o traje escolhido")

	print("MESHY_OUTFITS_RESULT failures=%d" % failures.size())
	for failure in failures: print("  FALHA: ", failure)
	quit(0 if failures.is_empty() else 1)
