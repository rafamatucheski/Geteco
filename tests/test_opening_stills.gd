extends SceneTree
const Timeline=preload("res://cutscenes/opening/v3/opening_timeline.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func run() -> void:
	var opening: Control=load("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.auto_start=false; root.add_child(opening); await process_frame
	check(opening.get_node_or_null("CinematicSurface")==null,"Runtime usa imagens, sem palco 3D")
	var end:=0.0
	for i in Timeline.SHOTS.size():
		var shot: Dictionary=Timeline.SHOTS[i]
		check(is_equal_approx(float(shot.start),end) and float(shot.duration)>0,"Plano %d tem continuidade e duração positiva" % i)
		end=float(shot.start)+float(shot.duration)
		opening.seek(float(shot.start)+.3); opening.pause_playback()
		var texture: Texture2D=opening._still.texture
		check(texture!=null and texture.get_size()==Vector2(1920,1080),"Fotografia %d em Full HD" % i)
		opening.seek(end-.05); opening.pause_playback()
		check(opening._still.texture==texture and opening._still.scale==Vector2.ONE,"Imagem %d fica parada até o corte" % i)
	check(is_equal_approx(end,Timeline.TOTAL_DURATION_SECONDS),"Montagem completa")
	TranslationServer.set_locale("pt_BR"); opening.seek(20); opening.pause_playback()
	check(opening._subtitle.text.contains("Você não me conhece"),"Ligação anônima em português brasileiro")
	TranslationServer.set_locale("en"); opening.seek(20); opening.pause_playback()
	check(opening._subtitle.text.contains("released from prison"),"Legendas em inglês preservadas")
	check(opening._procedural_audio.players[2].stream.resource_path.ends_with("voice_en.ogg"),"Voz acompanha idioma")
	opening.queue_free(); await process_frame; await create_timer(.2).timeout
	print("OPENING_STILLS failures=",failures)
	quit(1 if failures else 0)
