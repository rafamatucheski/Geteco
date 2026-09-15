extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
	else: print("PASS: ", message)

func run() -> void:
	var scene = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	while not scene.world_build_ready: await process_frame
	for i in 10: await physics_frame
	var port = scene.get_node("SouthPort")
	var cp = port.checkpoint
	var player = scene.get_node("Player")
	port.set_process(false)
	cp.set_process(false)
	player.set_physics_process(false)
	player.position = Vector2(3310,3320)
	cp.initialized = false
	player.velocity = Vector2.ZERO
	cp._process(0.1)
	check(not cp.panel.visible, "Dialogue waits for the player to stop near the guard")
	cp._process(1.2)
	check(cp.panel.visible, "Guard asks why the player wants to enter")
	cp.refuse.pressed.emit()
	cp._process(0.1)
	port._update_gate(player.position)
	check(cp.panel.visible and cp.speech.text.contains("meia-volta") and not port.gate_open and not cp.alerted, "Refusal receives a reply and keeps entry closed without pursuit")
	cp._process(5.0)
	check(not cp.panel.visible, "Refusal does not immediately reopen the offer")
	player.position = Vector2(3310,3120)
	cp._process(0.1)
	player.position = Vector2(3310,3320)
	cp._process(1.3)
	check(cp.panel.visible and cp.pay.visible, "Returning to the guard restores the choices")
	check(port.get_node("PortBuilding2").footprint.position.y == 4050, "Office is set back from the entrance curve")
	check(cp.guards.size() == 3, "Checkpoint guard and two private security responders")
	check(port._second_gate_collision != null, "Both lanes have physical barriers")
	player.money = 99
	cp.pay_bribe()
	check(player.money == 99 and not cp.authorized, "Insufficient funds do not authorize entry")
	player.money = 200
	cp.pay_bribe()
	cp.pay_bribe()
	check(player.money == 100 and cp.authorized, "Bribe charges exactly once")
	port._update_gate(player.position)
	check(port.gate_open, "Payment opens barriers")
	player.position = Vector2(3310,3450)
	cp._process(0.1)
	check(not cp.alerted, "Paid entry does not trigger pursuit")
	player.position = Vector2(3310,3320)
	cp._process(0.1)
	check(not cp.authorized, "Leaving ends the paid visit")
	player.position = Vector2(3310,3450)
	cp._process(0.1)
	check(cp.alerted, "Entering without paying alerts private security")
	var guard = cp.guards[1]
	guard._physics_process(0.1)
	check(guard.target == player and guard.security_alert == 3, "Responders pursue the intruder")
	player.position = Vector2(2500,1800)
	cp._process(11)
	check(not cp.alerted, "Escaping all guards clears the local pursuit")
	print("CHECKPOINT_FAILURES=", failures)
	quit(1 if failures else 0)
