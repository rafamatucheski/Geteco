extends SceneTree
var checks := 0
var failures := 0
var outcomes: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var game := preload("res://ui/ContainerLockpick.gd").new()
	root.add_child(game)
	game.set_process(false)
	game.resolved.connect(func(result): outcomes.append(result))
	game.begin(3,40)
	for i in 60: game.step(1.0/60,1,false)
	check(is_equal_approx(game.angle,85),"Angle moves with directional control and clamps")
	game.begin(3,60)
	for i in 30: game.step(1.0/60,0,true)
	check(game.active and game.turn < .2 and game.wear > 0,"Wrong angle jams cylinder and wears tool")
	var wear: float = game.wear
	game.step(.1,1,false)
	check(game.turn == 0 and game.wear == wear,"Releasing torque relaxes cylinder but does not heal tool")
	for i in 120: game.step(1.0/60,0,true)
	check(not game.active and outcomes == ["broken"],"Excess torque resolves one break")
	game.step(.1,0,true)
	game.finish("opened")
	check(outcomes.size() == 1,"Resolved minigame cannot emit twice")
	game.begin(2,-30)
	for i in 60: game.step(1.0/60,clampf((game.target_angle-game.angle)/(85.0/60),-1,1),false)
	for i in 80: game.step(1.0/60,0,true)
	check(not game.active and outcomes[-1] == "opened" and game.wear == 0,"Correct angle opens through torque with no wear")
	game.begin(2,20)
	game.angle = 5
	for i in 60: game.step(1.0/60,0,true)
	check(game.active and game.turn > .7 and game.turn < 1,"Near angle provides partial-turn feedback")
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	game._input(cancel)
	check(not game.active and outcomes[-1] == "cancelled","Cancel action exits distinctly from break")
	print("CONTAINER_LOCKPICK: ",checks," checks; failures=",failures)
	quit(1 if failures else 0)
