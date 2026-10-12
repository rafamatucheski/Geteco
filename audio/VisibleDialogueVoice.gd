extends RefCounted
## The player belongs to its subtitle surface, including visibility and lifetime.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const PLAYER_NAME := "AuthoredDialogueVoice"

class SurfacePlayer extends AudioStreamPlayer:
	var source := ""
	var persona := ""
	var character_id := ""
	var section := ""
	var prefix := ""
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_PAUSABLE
		bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		var surface := get_parent()
		surface.visibility_changed.connect(_visibility_changed)
		surface.tree_exiting.connect(silence)
		finished.connect(silence)
		var settings := get_node_or_null("/root/V2Settings")
		if settings != null:
			settings.voice_language_changed.connect(func(_value): refresh(playing))
			settings.text_language_changed.connect(func(_value): refresh(false))
	func _visibility_changed() -> void:
		if not get_parent().is_visible_in_tree(): silence()
	func silence() -> void:
		stop()
		stream = null
	func refresh(restart: bool) -> void:
		if not get_parent().is_visible_in_tree(): return
		var shown := VOICE.presentation(source, persona, "", "", character_id, section)
		var surface := get_parent()
		if surface is Label or surface is Label3D: surface.text = prefix + str(shown.message)
		elif surface.has_method("set_voice_message"): surface.set_voice_message(str(shown.message))
		if not restart: return
		silence()
		pitch_scale = 1.0
		stream = shown.stream
		volume_db = VOICE.playback_volume(stream)
		if stream != null and surface.is_visible_in_tree(): play()

static func attach(surface: Node, spoken_text: String, persona: String, character_id := "", section := "") -> AudioStreamPlayer:
	var player := surface.get_node_or_null(PLAYER_NAME) as SurfacePlayer
	if player == null:
		player = SurfacePlayer.new()
		player.name = PLAYER_NAME
		surface.add_child(player)
	player.source = spoken_text
	player.persona = persona
	player.character_id = character_id
	player.section = section
	player.prefix = ""
	if surface is Label or surface is Label3D:
		var current := str(surface.text)
		if current.ends_with(spoken_text): player.prefix = current.left(current.length() - spoken_text.length())
	player.refresh(true)
	return player
