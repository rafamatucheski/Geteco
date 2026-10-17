extends SceneTree

## Música e sons de menu gerados no Firefly: o menu escolhe uma das duas faixas em loop, os
## sons de hover/clique/voltar/início vêm das gravações, botão de voltar toca "voltar" e a
## tela de carregamento toca sua música e a retira junto com a cobertura.
const MENU_AUDIO := preload("res://ui/MenuAudio.gd")
const LOADING_MUSIC := preload("res://ui/LoadingMusic.gd")
const CURTAIN := preload("res://runtime/StartupCurtain.gd")
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	var music := MENU_AUDIO.get_music_stream()
	check(music is AudioStreamOggVorbis and (music as AudioStreamOggVorbis).loop, "música do menu é uma faixa nova em loop")
	check(music != null and music.get_length() > 30.0, "faixa do menu tem mais de 30 s (%.1f)" % (music.get_length() if music != null else 0.0))
	check(MENU_AUDIO.get_music_stream() == music, "a faixa escolhida fica a mesma na sessão")
	var streams := {"hover": MENU_AUDIO.get_hover_stream(), "click": MENU_AUDIO.get_click_stream(), "start": MENU_AUDIO.get_start_stream()}
	for kind in streams:
		var stream: AudioStream = streams[kind]
		check(stream != null and stream.resource_path.begins_with("res://audio/menu/%s_" % kind), "%s usa a gravação (%s)" % [kind, stream.resource_path if stream != null else "nulo"])
	check(MENU_AUDIO.get_hover_stream().get_length() < 0.4, "hover é curto")
	check(MENU_AUDIO.get_click_stream().get_length() < 0.5, "clique é curto")
	check(MENU_AUDIO.get_start_stream().get_length() > 1.0, "início de partida é um swell")
	# Botão de voltar toca o som de voltar; os demais tocam o clique.
	var holder := Control.new()
	root.add_child(holder)
	var back := Button.new()
	back.text = "Voltar"
	var play := Button.new()
	play.text = "Novo jogo"
	holder.add_child(back)
	holder.add_child(play)
	MENU_AUDIO.hook_buttons(holder, holder)
	back.pressed.emit()
	await process_frame
	await process_frame
	var back_player := root.get_node_or_null("__MenuBackPlayer") as AudioStreamPlayer
	check(back_player != null and back_player.stream != null and back_player.stream.resource_path.begins_with("res://audio/menu/back_"), "botão Voltar toca o som de voltar")
	play.pressed.emit()
	await process_frame
	await process_frame
	var click_player := root.get_node_or_null("__MenuClickPlayer") as AudioStreamPlayer
	check(click_player != null and click_player.stream != null and click_player.stream.resource_path.begins_with("res://audio/menu/click_"), "botão comum toca o clique")
	holder.free()
	# Tela de carregamento: música entra com a cobertura e sai junto.
	var curtain := CURTAIN.new()
	root.add_child(curtain)
	var player := curtain.get_node_or_null("LoadingMusic") as AudioStreamPlayer
	check(player != null and player.playing, "tela de carregamento toca a música")
	check(player != null and player.stream is AudioStreamOggVorbis and (player.stream as AudioStreamOggVorbis).loop, "música de carregamento repete")
	check(player != null and is_equal_approx((player.stream as AudioStreamOggVorbis).loop_offset, LOADING_MUSIC.LOOP_OFFSET), "loop volta depois da introdução")
	# Começa baixinha (mas audível, o bloqueio da cena congela tweens) e cresce.
	check(player != null and player.volume_db <= LOADING_MUSIC.START_DB + 0.5, "música de carregamento começa baixa (%.1f dB)" % (player.volume_db if player != null else 0.0))
	await create_timer(1.0).timeout
	check(player != null and player.volume_db > LOADING_MUSIC.START_DB + 0.1, "música de carregamento cresce (%.1f dB)" % (player.volume_db if player != null else 0.0))
	# A cobertura some e a música termina o fade sozinha, sem corte, e depois se libera.
	LOADING_MUSIC.fade_out(curtain, 0.2)
	curtain.free()
	await create_timer(0.5).timeout
	check(is_instance_valid(player) and player.playing, "música segue em fade depois que a cobertura some")
	await create_timer(LOADING_MUSIC.OUT_SECONDS).timeout
	check(not is_instance_valid(player), "música de carregamento termina o fade e é liberada")
	await process_frame
	print("MENU_AUDIO_FIREFLY failures=", failures)
	quit(0 if failures.is_empty() else 1)
