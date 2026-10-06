extends SceneTree
## The real settings/menu save cycle writes only the unique test file below.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const ARRIVAL := preload("res://runtime/ArrivalDialogue.gd")
var failures: Array[String] = []
var checks := 0

class IsolatedSettings extends "res://runtime/Settings.gd":
	var test_path := ""
	func _ready() -> void: _setup_audio_buses()
	func save_settings(_path := "user://settings.cfg") -> Error:
		return super.save_settings(test_path)

class IsolatedMenu extends "res://ui/SettingsMenu.gd":
	var test_settings: Node
	func _settings() -> Node: return test_settings

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func select_language(menu: Control, index: int) -> void:
	menu._widgets.voice_language.select(index)
	menu._widgets.voice_language.item_selected.emit(index)

func run() -> void:
	var original_locale := TranslationServer.get_locale()
	var runtime_settings := root.get_node("V2Settings")
	var original_language: String = runtime_settings.voice_language
	var settings := IsolatedSettings.new()
	settings.test_path = "user://voice-language-test-%d.cfg" % Time.get_ticks_usec()
	root.add_child(settings)
	check(settings.voice_language == "pt_BR", "New and legacy settings default to Brazilian Portuguese")
	var legacy := ConfigFile.new()
	legacy.set_value("audio", "master_volume", .63)
	check(legacy.save(settings.test_path) == OK, "Isolated legacy preferences created")
	settings.voice_language = "en"
	check(settings.load_settings(settings.test_path) == OK and settings.voice_language == "pt_BR", "Loading legacy config restores Portuguese without a migration prompt")
	check(is_equal_approx(settings.master_volume, .63), "Language migration preserves other preferences")
	settings.voice_language = "unsupported"
	check(settings.voice_language == "pt_BR", "Invalid language safely normalizes to Portuguese")
	settings.voice_language = "en-US"
	check(settings.voice_language == "en", "English locale aliases normalize to one bank")
	settings.voice_language = "pt_BR"
	TranslationServer.set_locale("pt_BR")
	var menu := IsolatedMenu.new()
	menu.test_settings = settings
	root.add_child(menu)
	menu.size = Vector2(1280, 720)
	menu.open()
	menu._select_tab(1)
	check(menu._widgets.voice_language.item_count == 2, "Audio menu offers both voice languages")
	check(menu._widgets.voice_language.get_item_text(0) == "Português (Brasil)" and menu._widgets.voice_language.get_item_text(1) == "English", "Audio selector has recognizable language names")
	select_language(menu, 1)
	check(settings.voice_language == "en", "Selecting English applies to the next line")
	check(TranslationServer.get_locale().begins_with("pt"), "Selecting voice never changes subtitle language")
	menu.close()
	check(settings.voice_language == "pt_BR", "Cancel restores the voice language from menu entry")
	menu.show()
	menu.open()
	select_language(menu, 1)
	menu._save()
	check(settings.voice_language == "en" and not menu.visible, "Save closes the menu and retains English")
	settings.voice_language = "pt_BR"
	check(settings.load_settings(settings.test_path) == OK and settings.voice_language == "en", "Saved voice language survives reloading preferences")
	menu.show()
	menu.open()
	menu._restore_tab_defaults()
	check(settings.voice_language == "pt_BR" and menu._widgets.voice_language.selected == 0, "Audio defaults restore Portuguese and update the control")
	menu.close()
	check(settings.voice_language == "en", "Cancel also undoes restoring tab defaults")
	menu.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings.test_path))
	settings.queue_free()
	# Use real banks and the real autoload for playback resolution.
	runtime_settings.voice_language = "pt_BR"
	var portuguese := VOICE.recorded_line("Alô?", "dante")
	check(portuguese != null and not portuguese.resource_path.begins_with("res://audio/mission_voices/en/"), "Portuguese keeps its existing Dante take")
	runtime_settings.voice_language = "en"
	var english := VOICE.recorded_line("Alô?", "dante")
	check(english != null and english.resource_path.begins_with("res://audio/mission_voices/en/"), "English uses its own recorded bank with Portuguese subtitles")
	check(english == VOICE.recorded_line("Hello?", "DANTE"), "English subtitle alias and speaker case resolve to the same take")
	TranslationServer.set_locale("en")
	check(VOICE.recorded_line("Alô?", "dante", "pt-BR") == portuguese, "Explicit Portuguese remains independent of English subtitles and current voice preference")
	check(VOICE.recorded_line("Hello?", "dante", "pt_BR") == portuguese, "English subtitles with Portuguese dubbing resolve the Portuguese take")
	check(VOICE.line("Alô?", "dante", 0.0, "en") == english and VOICE.line("Alô?", "dante", 0.0, "pt_BR") == portuguese, "Cached lines cannot leak audio across languages")
	var maciota_pt := VOICE.recorded_line(ARRIVAL.MEETING[0][1], "maciota", "pt_BR")
	var maciota_en := VOICE.recorded_line(ARRIVAL.MEETING[0][1], "maciota", "en")
	check(maciota_pt != null and maciota_pt.resource_path.begins_with("res://audio/mission_voices/maciota_baritone/"), "Portuguese preserves the fixed Maciota baritone bank")
	check(VOICE.recorded_line(ARRIVAL.MEETING[0][2], "maciota", "pt_BR") == maciota_pt, "English Maciota subtitle keeps the stable Portuguese actor when selected")
	check(maciota_en != null and maciota_en != maciota_pt, "English Maciota resolves independently of Portuguese baritone")
	var maciota_key := VOICE.recording_key(ARRIVAL.MEETING[0][1], "maciota")
	var maciota_path: String = VOICE.english_recordings.get(maciota_key, "")
	VOICE.english_recordings.erase(maciota_key)
	check(VOICE.recorded_line(ARRIVAL.MEETING[0][1], "maciota") == null, "A missing English take remains silent even when the Portuguese take exists")
	check(VOICE.line(ARRIVAL.MEETING[0][1], "maciota") == null, "A missing English take cannot fall through to the Portuguese synthesis path")
	if not maciota_path.is_empty(): VOICE.english_recordings[maciota_key] = maciota_path
	check(VOICE.recorded_line("__missing_language_test__", "maciota") == null, "Missing English dialogue never falls back to Portuguese")
	check(VOICE.line("__missing_language_test__", "maciota") == null, "Missing English dialogue never produces robotic nonverbal speech")
	runtime_settings.voice_language = original_language
	TranslationServer.set_locale(original_locale)
	await process_frame
	print("VOICE_LANGUAGE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
