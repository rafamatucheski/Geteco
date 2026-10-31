extends SceneTree
## Exercita os produtores reais de diálogo fora do padrão sem carregar a cidade.
const SPOKEN_LINE := preload("res://audio/VisibleDialogueVoice.gd")
const MOTOCROSS := preload("res://activities/motocross/Motocross.gd")
const CEMETERY := preload("res://gameplay/urban_v1/CemeteryOperations.gd")
const VOICE := preload("res://audio/ExpressiveVoice.gd")
var failures: Array[String] = []
var checks := 0

class State extends RefCounted:
	var world_state := {}
	var place_id := ""
	func spend(_amount: int, _reason: String) -> bool: return false

class Session extends Node:
	var state := State.new()
	var world := {}
	var modal := false
	var column: VBoxContainer
	var panel: PanelContainer
	var notice := ""
	func _ready() -> void:
		panel = PanelContainer.new()
		add_child(panel)
		column = VBoxContainer.new()
		panel.add_child(column)
	func _menu(_title: String) -> void:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
		modal = true
		panel.show()
	func _button(label: String, action: Callable) -> void:
		var button := Button.new()
		button.text = label
		button.pressed.connect(action)
		column.add_child(button)
	func close_menu() -> void:
		modal = false
		panel.hide()
	func save_game() -> bool: return true
	func _transaction() -> String: return "isolated-special-voice"
	func show_message(text: String) -> void: notice = text

class Guard extends "res://gameplay/urban_v1/HarborPortSecurity.gd":
	func nearest_action() -> Dictionary: return {"target":"south_port_checkpoint"}
	func _available() -> bool: return true

class Resident extends CharacterBody3D:
	var dead := false
	var frightened := false
	var speech: Label3D
	var speech_left := 0.0
	func _ready() -> void:
		speech = Label3D.new()
		add_child(speech)
		speech.hide()
	func finished() -> bool: return true
	func set_route(_route: PackedVector3Array) -> void: pass
	func say(text: String, duration: float) -> void:
		speech.text = text
		speech_left = duration
		speech.show()

func _initialize() -> void: run.call_deferred()

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures.append(description)
		push_error(description)

func is_english(player: AudioStreamPlayer) -> bool:
	return player != null and player.stream != null and player.stream.get_meta("voice_language", "") == "en"

func run() -> void:
	var settings := root.get_node("V2Settings")
	var previous_language: String = settings.voice_language
	settings.voice_language = "en"
	var session := Session.new()
	root.add_child(session)
	var listener := Resident.new()
	root.add_child(listener)
	session.world = {"player": listener}
	var mx := MOTOCROSS.new()
	mx.session = session
	mx._menu()
	var intro_label := session.column.get_child(0) as Label
	var intro_voice := intro_label.get_node(SPOKEN_LINE.PLAYER_NAME) as AudioStreamPlayer
	check(is_english(intro_voice) and intro_voice.playing, "Digo menu plays the selected recording after creating its line")
	check(intro_voice.bus == &"SFX" and is_equal_approx(intro_voice.pitch_scale, 1.0) and is_equal_approx(intro_voice.volume_db, -8.0), "menu speech uses stable pitch, the effects bus and the shared English level")
	var retained_stream := intro_voice.stream
	paused = true
	check(not intro_voice.can_process() and intro_voice.stream == retained_stream and intro_voice.stream_paused, "tree pause suspends the menu voice without discarding it")
	paused = false
	check(intro_voice.can_process() and intro_voice.playing and not intro_voice.stream_paused, "resuming re-enables the same voice player")
	mx._digo_story()
	check(not intro_voice.is_inside_tree() and not intro_voice.playing, "changing Digo's conversation stops the replaced take immediately")
	var story_label := session.column.get_child(0) as Label
	var story_voice := story_label.get_node(SPOKEN_LINE.PLAYER_NAME) as AudioStreamPlayer
	check(is_english(story_voice) and story_voice.playing, "Digo's Gol story has its own recorded take")
	session.close_menu()
	check(not story_voice.playing, "closing the menu stops Digo mid-sentence")
	mx.track.free()
	mx.free()
	var guard := Guard.new()
	guard.session = session
	guard._staff = [listener]
	check(guard.perform("south_port_checkpoint"), "guard's actual conversation opens")
	check(is_english(guard._conversation_voice) and guard._conversation_voice.playing, "guard question resolves canonical text without its speaker prefix")
	guard._pay_bribe()
	check(not guard._conversation_voice.playing and session.notice.begins_with("GUARDA:"), "guard stops initial question before the spoken bribe reply")
	guard.free()
	session.close_menu()
	var cemetery := CEMETERY.new()
	cemetery.session = session
	var storyteller := Resident.new()
	root.add_child(storyteller)
	cemetery.storyteller = storyteller
	for index in CEMETERY.STORIES.size():
		cemetery.storyteller_stop = index
		cemetery.storyteller_told = false
		cemetery._tick_storyteller(.1)
		check(is_english(cemetery.storyteller_voice) and cemetery.storyteller_voice.playing, "Elias story %d plays its selected take" % index)
		check(storyteller.speech_left >= cemetery.storyteller_voice.stream.get_length()+.35, "Elias story %d keeps its caption for the full recording" % index)
	check(storyteller.speech.get_child_count() == 1, "successive Elias stories reuse one owned audio player")
	listener.position.x = 10.0
	cemetery._tick_storyteller(.1)
	check(not cemetery.storyteller_voice.playing and not storyteller.speech.visible, "leaving Elias's speaking range clears both caption and voice")
	listener.position.x = 0.0
	cemetery.storyteller_told = false
	cemetery._tick_storyteller(.1)
	cemetery._actor_threatened(storyteller)
	check(not cemetery.storyteller_voice.playing and storyteller.frightened, "threat cancels Elias's current story immediately")
	storyteller.frightened = false
	cemetery.storyteller_told = false
	cemetery._tick_storyteller(.1)
	var owned_voice := cemetery.storyteller_voice
	root.remove_child(storyteller)
	check(not owned_voice.playing, "unloading the speaker stops the take before freeing its actor")
	storyteller.free()
	cemetery.free()
	# O mesmo helper também resolve o português independente do locale da legenda.
	settings.voice_language = "pt_BR"
	session._menu("phone")
	var caption := Label.new()
	session.column.add_child(caption)
	var portuguese := SPOKEN_LINE.attach(caption, "Alô?", "dante")
	check(portuguese.stream == VOICE.recorded_line("Alô?", "dante", "pt_BR"), "visible dialogue follows the Portuguese preference on the next line")
	check(is_zero_approx(portuguese.volume_db), "Portuguese keeps the established level for these special consumers")
	session.free()
	listener.free()
	settings.voice_language = previous_language
	# AudioServer releases stopped playback on its next mix block.
	await create_timer(.1).timeout
	print("SPECIAL_DIALOGUE_VOICES checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
