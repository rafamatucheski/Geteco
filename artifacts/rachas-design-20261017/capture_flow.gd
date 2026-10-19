extends "res://tests/test_desert_drag_board_session.gd"
## Read-only visual audit instrumentation. Uses the existing isolated fixture.
## Captures are evidence of appearance, never a frame-time benchmark.
var captured: Dictionary = {}

func _initialize() -> void:
	super._initialize()
	RenderingServer.frame_post_draw.connect(_capture_design_state)

func _capture_design_state() -> void:
	if output.is_empty() or not is_instance_valid(world): return
	if world.session == null or not world.session.ready_for_play: return
	var race = world.session.desert.drag
	var label := "01-encontro"
	if world.session.modal: return
	if race.active:
		label = "03-" + race.phase
		if race.phase == "racing":
			var distance_run: float = race._offset(race.racers[0].car.global_position)
			if distance_run < 150.0: return
			label = "04-corrida" if distance_run < 500.0 else "05-horizonte"
	if captured.has(label): return
	var screenshot = root.get_texture().get_image()
	if screenshot == null or screenshot.is_empty(): return
	if screenshot.save_png(output.path_join(label + ".png")) == OK:
		captured[label] = true
		print("DESIGN_CAPTURE ", output.path_join(label + ".png"))
