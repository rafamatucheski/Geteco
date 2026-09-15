extends SceneTree

const CHECKPOINT := preload("res://world/harbor/HarborPortCheckpoint.gd")

class PlayerStub extends CharacterBody2D:
	var money := 300
	var health := 100
	var is_in_dialogue := false
	var is_control_disabled := false
	var notices: Array[String] = []

	func _refresh_weapon_ui() -> void:
		pass

	func _show_weapon_notice(message: String) -> void:
		notices.append(message)

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if value:
		print("PASS: ", message)
	else:
		failures += 1
		push_error(message)

func run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var player := PlayerStub.new()
	player.name = "Player"
	player.position = Vector2(3310, 3320)
	world.add_child(player)

	var port := Node2D.new()
	port.name = "SouthPort"
	world.add_child(port)
	var checkpoint := CHECKPOINT.new()
	port.add_child(checkpoint)
	await process_frame
	await process_frame
	checkpoint.set_process(false)
	for guard in checkpoint.guards:
		if is_instance_valid(guard):
			guard.set_physics_process(false)

	checkpoint.initialized = false
	checkpoint._process(1.3)
	check(checkpoint.panel.visible, "Bribe choices open near the checkpoint guard")
	check(player.is_in_dialogue and player.is_control_disabled,
		"Open bribe choices suppress movement and weapon input")

	checkpoint.pay.pressed.emit()
	check(checkpoint.authorized and player.money == 200,
		"Paying through the real button authorizes entry and charges once")
	check(not checkpoint.panel.visible and not player.is_in_dialogue and not player.is_control_disabled,
		"Payment closes the choices and restores the previous controls")

	player.position = Vector2(3310, 3450)
	checkpoint._process(0.1)
	check(not checkpoint.alerted, "Crossing after the button payment keeps port security peaceful")

	var guard = checkpoint.guards[0]
	guard.take_damage(1, true)
	guard._physics_process(0.1)
	check(checkpoint.alerted and not checkpoint.authorized,
		"Attacking a guard still revokes authorization and raises the local alarm")
	check(guard.target == player and guard.security_alert == 3,
		"Port security still responds to real aggression")

	print("PORT_CHECKPOINT_DIALOGUE_FAILURES=", failures)
	quit(1 if failures else 0)
