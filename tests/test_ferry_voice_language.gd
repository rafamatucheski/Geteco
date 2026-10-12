extends SceneTree
const FILM := preload("res://cutscenes/opening/ferry/FerryFilm.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	var settings := root.get_node("V2Settings")
	var original_voice: String = settings.voice_language
	var original_locale := TranslationServer.get_locale()
	for text_language in ["pt_BR", "en"]:
		TranslationServer.set_locale(text_language)
		for voice_language in ["pt_BR", "en"]:
			settings.voice_language = voice_language
			var film := FILM.new()
			root.add_child(film)
			await create_timer(.35).timeout
			check(film.video.is_playing(), "Ferry video plays with %s/%s" % [text_language, voice_language])
			check(film.voice_language == voice_language, "Ferry voice choice is independent")
			check(film.stems.size() == (3 if voice_language == "en" else 2), "Exactly one dialogue source plus ambience and music")
			check(film.video.volume_db < -70 if voice_language == "en" else is_zero_approx(film.video.volume_db), "Embedded Portuguese is silent only with English dub")
			if voice_language == "en":
				check(film.stems[2].stream.resource_path.ends_with("voice_en.ogg") and film.stems[2].playing, "English production stem plays")
				check(absf(film.stems[2].stream.get_length()-film.duration)<.1 and film.stems[2].bus == "SFX", "Dub covers full movie on voice bus")
			film._show_caption(16.1)
			check(("I'm here to see my brother" in film.subtitle.text) if text_language=="en" else ("Vim encontrar meu irmão" in film.subtitle.text), "Subtitles follow text choice")
			film.pause_playback()
			check(film.video.paused and film.stems.all(func(stem): return stem.stream_paused), "Pause freezes movie and every stem")
			film.resume_playback()
			check(not film.video.paused and film.stems.all(func(stem): return not stem.stream_paused), "Resume preserves synchronized stem lifecycle")
			film.free()
			await process_frame
	settings.voice_language = original_voice
	TranslationServer.set_locale(original_locale)
	print("FERRY_VOICE_LANGUAGE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
