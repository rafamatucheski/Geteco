extends RefCounted
## Called only after the session accepted and applied a loadout/part. Reuse the
## game's recorded tactile menu cue and its configured effects volume bus.
const MENU_AUDIO := preload("res://ui/MenuAudio.gd")
const PLAYER := "TuningInstallConfirmation"

static func play(host: Node) -> void:
	if not is_instance_valid(host) or not host.is_inside_tree(): return
	var player := host.get_node_or_null(PLAYER) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.name = PLAYER
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.max_polyphony = 1
		host.add_child(player)
	player.bus = MENU_AUDIO.get_sfx_bus_name()
	player.volume_db = -6.0
	player.stream = MENU_AUDIO.get_click_stream()
	player.play()
