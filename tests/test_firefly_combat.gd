extends SceneTree

## Sons de combate do Firefly no Gameplay: sacar/guardar (katana e arma de fogo), zunido de bala e
## ricochete. Usa o mesmo fixture do teste da katana nas costas; não mede a qualidade do som.
const ACTOR := preload("res://scripts/Actor.gd")

class SoundGameplay extends "res://gameplay/Gameplay.gd":
	func _ready() -> void:
		_build_socket()

class State extends RefCounted:
	func owns_weapon(_id: String) -> bool: return true
	func weapons_allowed() -> bool: return true
	func can_attack() -> bool: return true

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(message)
	push_error(message)

func playing_paths(channels: Array[AudioStreamPlayer3D]) -> Array[String]:
	var paths: Array[String] = []
	for channel in channels:
		if channel.playing and channel.stream != null: paths.append(channel.stream.resource_path)
	return paths

func silence(channels: Array[AudioStreamPlayer3D]) -> void:
	for channel in channels: channel.stop()

func heard(channels: Array[AudioStreamPlayer3D], prefix: String) -> bool:
	for path in playing_paths(channels):
		if path.begins_with(prefix): return true
	return false

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := ACTOR.new()
	actor.is_player = true
	actor.controlled_automatically = true
	stage.add_child(actor)
	await physics_frame
	var gp := SoundGameplay.new()
	gp.process_mode = Node.PROCESS_MODE_DISABLED
	gp.world = stage
	gp.player = actor
	gp.state = State.new()
	gp.enabled = true
	gp.health = 100.0
	stage.add_child(gp)
	var channels: Array[AudioStreamPlayer3D] = []
	for i in 6:
		var channel: AudioStreamPlayer3D = gp._combat_voice("Master")
		stage.add_child(channel)
		channels.append(channel)
	gp._audio_pool = channels
	# Katana: sacar e embainhar.
	gp._weapon_switch_sound("fists", "katana")
	check(heard(channels, "res://audio/katana/draw_"), "equipar a katana toca o som de sacar")
	silence(channels)
	gp._weapon_switch_sound("katana", "fists")
	check(heard(channels, "res://audio/katana/sheath_"), "guardar a katana toca o som de embainhar")
	silence(channels)
	# Arma de fogo: sacar do coldre e guardar.
	gp._weapon_switch_sound("fists", "pistol")
	check(heard(channels, "res://audio/weapons_fire/gun_draw_"), "equipar a pistola toca o som de sacar")
	silence(channels)
	gp._weapon_switch_sound("pistol", "")
	check(heard(channels, "res://audio/weapons_fire/gun_holster_"), "guardar a pistola toca o coldre")
	silence(channels)
	gp._weapon_switch_sound("pistol", "pistol")
	check(playing_paths(channels).is_empty(), "mesma arma não faz barulho")
	gp._weapon_switch_sound("fists", "bat")
	check(playing_paths(channels).is_empty(), "arma branca comum não saca do coldre")
	gp._weapon_switch_sound("fists", "grenade")
	check(playing_paths(channels).is_empty(), "granada não saca do coldre")
	# Zunido: bala que passa a 1 m toca uma vez; bala longe ou indo embora não toca.
	var origin: Vector3 = actor.global_position + Vector3(8.0, 1.0, 1.0)
	var passing := {"point": origin, "direction": Vector3.LEFT, "speed": 34.0}
	gp._bullet_whiz(passing)
	check(passing.get("whizzed", false) == false, "bala ainda longe do ponto mais próximo não zune")
	passing.point = actor.global_position + Vector3(0.5, 1.0, 1.0)
	gp._bullet_whiz(passing)
	check(heard(channels, "res://audio/weapons_fire/bullet_whiz_") and passing.get("whizzed", false), "bala que passa perto zune")
	silence(channels)
	gp._bullet_whiz(passing)
	check(playing_paths(channels).is_empty(), "a mesma bala zune uma vez só")
	var far := {"point": actor.global_position + Vector3(0, 1, 20), "direction": Vector3.LEFT, "speed": 34.0}
	gp._bullet_whiz(far)
	check(not far.get("whizzed", false), "bala a 20 m não zune")
	var leaving := {"point": actor.global_position + Vector3(9.0, 1.0, 1.0), "direction": Vector3.RIGHT, "speed": 34.0}
	gp._bullet_whiz(leaving)
	check(not leaving.get("whizzed", false), "bala que se afasta não zune")
	# Ricochete e cauda de explosão saem do mesmo ajudante.
	gp._firefly_sound("weapons_fire", "ricochet", actor.global_position, -13.0, 40.0)
	check(heard(channels, "res://audio/weapons_fire/ricochet_"), "ricochete toca")
	silence(channels)
	gp._firefly_sound("weapons_fire", "explosion_tail", actor.global_position, -7.0, 140.0)
	check(heard(channels, "res://audio/weapons_fire/explosion_tail_"), "cauda de explosão toca")
	silence(channels)
	gp._firefly_sound("weapons_fire", "nao_existe", actor.global_position, 0.0, 10.0)
	check(playing_paths(channels).is_empty(), "som inexistente não faz nada")
	# Foguete em voo: loop de chiado preso ao projétil, que some com ele.
	var rocket := preload("res://gameplay/Projectile.gd").new()
	rocket.grenade = false
	stage.add_child(rocket)
	var flight := rocket.get_node_or_null("RocketFlight") as AudioStreamPlayer3D
	check(flight != null and flight.playing and flight.stream is AudioStreamWAV and (flight.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "foguete em voo toca o chiado em loop")
	var thrown := preload("res://gameplay/Projectile.gd").new()
	thrown.grenade = true
	stage.add_child(thrown)
	check(thrown.get_node_or_null("RocketFlight") == null, "granada não chia como foguete")
	stage.free()
	await process_frame
	print("FIREFLY_COMBAT failures=", failures)
	quit(0 if failures.is_empty() else 1)
