extends SceneTree
## Porta/ignição do carro do jogador saíam cortadas: o ouvinte é a câmera ~36 m acima/atrás e o
## max_distance desses sons é 24-35 m. Com a cidade viva, a perda vem da distância ao alvo da câmera.
const FIREFLY := preload("res://audio/FireflyBank.gd")

class RigLike extends Camera3D:
	var target: Node3D

var failures := 0

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := Node3D.new()
	world.add_child(player)
	var camera := RigLike.new()
	camera.target = player
	world.add_child(camera)
	camera.global_position = Vector3(0, 25.3, 25.3)
	camera.current = true
	var stream := AudioStreamWAV.new()
	var near := FIREFLY.play_at(world, stream, Vector3(1.5, 0, 0), -8.0, 1.0, 30.0)
	_check(near != null and near.attenuation_model == AudioStreamPlayer3D.ATTENUATION_DISABLED, "som colado no jogador não depende da câmera")
	_check(near != null and absf(near.volume_db - (-8.0 + linear_to_db(1.0 - 1.5 / 30.0))) < .01, "perto do jogador mantém o volume autorado")
	var mid := FIREFLY.play_at(world, stream, Vector3(15, 0, 0), -8.0, 1.0, 30.0)
	_check(mid != null and mid.volume_db < near.volume_db - 6.0, "a 15 m soa bem mais baixo")
	_check(FIREFLY.play_at(world, stream, Vector3(31, 0, 0), -8.0, 1.0, 30.0) == null, "fora do alcance não toca")
	OS.set_environment("GETECO_CITY_LIFE_AUDIO", "0")
	var legacy := FIREFLY.play_at(world, stream, Vector3(1.5, 0, 0), -8.0, 1.0, 30.0)
	_check(legacy != null and legacy.attenuation_model != AudioStreamPlayer3D.ATTENUATION_DISABLED and legacy.max_distance == 30.0, "interruptor desligado volta à atenuação da câmera")
	print("firefly_play_at_hearing: ", "OK" if failures == 0 else "FALHOU (%d)" % failures)
	quit(0 if failures == 0 else 1)
