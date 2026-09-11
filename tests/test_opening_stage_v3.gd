extends SceneTree
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func run() -> void:
	var opening: Control=load("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.auto_start=false; root.add_child(opening)
	await process_frame
	var stage: Node3D=opening.stage
	stage.set_time(2.4)
	var coffee_hand: Vector3=stage.host.right_lower_arm.get_node("Palm").global_position
	check(coffee_hand.distance_to(stage.pot.position+Vector3(.056,.01,0))<.03,"Mão permanece no recipiente durante o café")
	stage.set_time(21)
	var phone_hand: Vector3=stage.host.right_lower_arm.get_node("Palm").global_position
	check(phone_hand.distance_to(stage.phone.position)<.03,"Mão acompanha o telefone no ouvido")
	for eye in stage.eyes: check(eye.scale.y<.03,"Animação de piscar preserva a anatomia")
	stage.set_time(35)
	var photo: Texture2D=stage.frame_photo.material_override.albedo_texture
	check(photo==stage.loose_photo.get_child(0).material_override.albedo_texture,"Fotografia idêntica no quadro e nas mãos")
	check(not stage.frame_photo.visible and stage.loose_photo.visible,"Foto sai do quadro quando Dante a pega")
	stage.set_time(57)
	check(stage.loose_photo.visible and stage.cabin.visible and not stage.room.visible,"Foto acompanha Dante no ônibus")
	stage.set_time(67.8)
	check(stage.terminal.visible and stage.terminal_bus.platform_leaves.size()==2,"Chegada usa o ônibus do gameplay")
	var left: Node3D=stage.terminal_bus.platform_leaves[0]
	var right: Node3D=stage.terminal_bus.platform_leaves[1]
	check(absf(left.position.z-right.position.z)>1.1,"Porta abre ao fim da cena")
	TranslationServer.set_locale("en"); opening.seek(19.4); opening.pause_playback()
	check(opening._subtitle.text.contains("released from prison"),"Legenda acompanha o idioma inglês")
	check(opening._procedural_audio.players[2].stream.resource_path.ends_with("voice_en.ogg"),"Áudio acompanha o idioma inglês")
	opening.queue_free(); await process_frame
	await create_timer(.15).timeout # Let the audio mixer release the stopped streams.
	print("OPENING_STAGE_V3 failures=",failures)
	quit(1 if failures else 0)
