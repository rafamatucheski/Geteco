extends RefCounted
## Authored speech belongs to its visible line. Rebuilding or dismissing that
## surface stops the take, and tree pause freezes it without a per-frame watcher.
const VOICE := preload("res://audio/ExpressiveVoice.gd")
const PLAYER_NAME := "AuthoredDialogueVoice"

static func attach(surface: Node, spoken_text: String, persona: String) -> AudioStreamPlayer:
	var player := surface.get_node_or_null(PLAYER_NAME) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = PLAYER_NAME
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
		surface.add_child(player)
		surface.visibility_changed.connect(func():
			if is_instance_valid(player) and not surface.is_visible_in_tree(): player.stop())
		surface.tree_exiting.connect(player.stop)
	player.stop()
	player.pitch_scale = 1.0
	player.stream = VOICE.recorded_line(spoken_text, persona)
	player.volume_db = VOICE.playback_volume(player.stream)
	if player.stream != null and surface.is_visible_in_tree(): player.play()
	return player
