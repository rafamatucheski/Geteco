extends SceneTree
## Ciclo de vida do som compartilhado de coleta com uma voz real e a amostra original.
## Este teste isolado não certifica volume subjetivo nem FPS renderizado.
const PICKUP := preload("res://systems/inventory/PickupPresentation.gd")
const REWARD_AUDIO := preload("res://gameplay/RewardAudio.gd")
var failures := 0
var checks := 0

class FollowCamera:
	extends Camera3D
	var target: Node3D

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PICKUP_PROXIMITY_AUDIO ", "PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func run() -> void:
	var holder := PICKUP.new()
	var listener := Node3D.new()
	var host := Node3D.new()
	root.add_child(listener)
	root.add_child(host)
	host.add_child(holder)
	var art := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	art.add_child(mesh)
	holder.configure(art, "smg")
	await create_timer(.3).timeout
	check(not holder.proximity_audio_enabled and holder.proximity_voice == null, "ordinary pickups remain silent until explicitly enabled")
	listener.position = Vector3(0, 0, 30)
	holder.set_proximity_audio(true, listener)
	await create_timer(.3).timeout
	check(holder.proximity_voice == null, "distant pickup creates no voice")
	listener.position = Vector3(0, 0, 3)
	await create_timer(1.7).timeout
	check(holder.proximity_voice != null and int(holder.proximity_voice.get_meta("cue_count", 0)) == 1, "nearby pickup plays one bounded approach cue")
	if holder.proximity_voice == null: finish(); return
	check(holder.proximity_voice.stream == REWARD_AUDIO.stream("collectible") and holder.proximity_voice.pitch_scale == 1.0, "approach sound preserves the original collectible sample and pitch")
	check(holder.proximity_voice.bus == REWARD_AUDIO.AUDIO.SFX_BUS_NAME, "approach sound obeys the existing SFX volume")
	holder.set_available(false)
	check(not holder.proximity_voice.playing, "hiding a reward immediately stops its approach sound")
	var hidden_count := int(holder.proximity_voice.get_meta("cue_count", 0))
	await create_timer(1.4).timeout
	check(int(holder.proximity_voice.get_meta("cue_count", 0)) == hidden_count, "hidden reward cannot restart sound")
	holder.set_available(true)
	await create_timer(1.7).timeout
	check(int(holder.proximity_voice.get_meta("cue_count", 0)) == hidden_count + 1, "new-game availability rearms approach sound")
	holder.collect(true)
	check(not holder.proximity_voice.playing, "collection immediately stops the approach voice")
	await create_timer(.35).timeout
	check(not holder.visible and holder.consumed, "normal retained absorption still finishes")
	holder.set_available(true)
	listener.position = Vector3(0, 0, 30)
	await create_timer(.3).timeout
	check(not holder.proximity_voice.playing, "restored reward stays quiet outside its distance limit")
	var distant_count := int(holder.proximity_voice.get_meta("cue_count", 0))
	listener.position = Vector3.ZERO
	await create_timer(1.7).timeout
	check(int(holder.proximity_voice.get_meta("cue_count", 0)) == distant_count + 1, "returning to the nearby restored reward plays the cue")
	holder.set_proximity_audio(false)
	check(not holder.proximity_voice.playing, "disabling the optional signal stops its existing voice")
	var camera := FollowCamera.new()
	root.add_child(camera)
	camera.current = true
	camera.target = listener
	var remote_listener := Node3D.new()
	root.add_child(remote_listener)
	remote_listener.position = Vector3(30, 0, 0)
	holder.set_proximity_audio(true)
	await create_timer(1.7).timeout
	var handoff_count := int(holder.proximity_voice.get_meta("cue_count", 0))
	check(handoff_count == distant_count + 2, "real viewport camera target supplies the optional listener")
	camera.target = remote_listener
	await create_timer(.3).timeout
	check(not holder.proximity_voice.playing, "camera retargeting to a distant actor stops the old near cue")
	await create_timer(1.4).timeout
	check(int(holder.proximity_voice.get_meta("cue_count", 0)) == handoff_count, "fallback distance follows the new camera target")
	holder.set_proximity_audio(true, listener)
	await create_timer(1.7).timeout
	check(int(holder.proximity_voice.get_meta("cue_count", 0)) == handoff_count + 1, "an explicit listener stays authoritative despite a different camera target")
	host.hide()
	await process_frame
	check(not holder.proximity_voice.playing, "hiding the streamed parent stops its pickup cue")
	var hidden_parent_count := int(holder.proximity_voice.get_meta("cue_count", 0))
	await create_timer(1.4).timeout
	check(int(holder.proximity_voice.get_meta("cue_count", 0)) == hidden_parent_count, "pickup under a hidden parent cannot restart")
	var freed_voice_id := holder.proximity_voice.get_instance_id()
	host.queue_free()
	listener.queue_free()
	remote_listener.queue_free()
	camera.queue_free()
	await process_frame
	check(not is_instance_id_valid(freed_voice_id), "streamed-parent unload frees its owned audio voice")
	finish()

func finish() -> void:
	print("PICKUP_PROXIMITY_AUDIO_RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
