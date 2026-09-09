extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func refresh(actor: AnimatedPedestrian3D) -> void:
	actor._viewport_cull_timer = 0.0
	actor._viewport_frame_timer = 0.0
	actor._update_viewport_render_state(1.0 / 60.0)

func run() -> void:
	root.size = Vector2i(800, 600)
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var actor := AnimatedPedestrian3D.new()
	actor.position = Vector2(400, 300)
	stage.add_child(actor)
	actor.set_physics_process(false)
	refresh(actor)
	check(actor._viewport_render_active, "Near actor must render")
	var initial := actor.viewport_render_requests
	for i in 120:
		actor._update_viewport_render_state(1.0 / 60.0)
	var near_requests := actor.viewport_render_requests - initial
	check(near_requests == 120, "Near render must follow all 60Hz physics poses")
	actor.hide()
	refresh(actor)
	check(actor.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden actor must stop rendering")
	actor.show()
	actor.position = Vector2(1500, 300)
	refresh(actor)
	check(not actor._viewport_render_active, "Offscreen actor must stop rendering")
	# Exercise the actual physics callback while its render target is culled.
	actor.is_flying = true
	actor.fly_velocity = Vector2(300, 0)
	var start := actor.position
	actor._physics_process(1.0 / 60.0)
	check(actor.position.x > start.x and actor.position.is_finite(), "Culling must preserve finite physical movement")
	actor.is_flying = false
	actor.position = Vector2(400, 300)
	refresh(actor)
	check(actor._viewport_render_active and actor.viewport.render_target_update_mode == SubViewport.UPDATE_ONCE, "Returning actor must refresh immediately")
	# Actual canvas projection, including translation, determines eligibility.
	root.canvas_transform = Transform2D(0.0, Vector2(-2000, 0))
	refresh(actor)
	check(not actor._viewport_render_active, "Canvas camera offset must affect culling")
	root.canvas_transform = Transform2D(Vector2(0.25, 0), Vector2(0, 0.25), Vector2.ZERO)
	refresh(actor)
	initial = actor.viewport_render_requests
	for i in 120:
		actor._update_viewport_render_state(1.0 / 60.0)
	var small_requests := actor.viewport_render_requests - initial
	check(small_requests >= 28 and small_requests <= 31, "Small overview actor must render at 15Hz")
	# Intermediate rigs retain 30Hz even with a non-divisor physics rate.
	root.canvas_transform = Transform2D(Vector2(0.75, 0), Vector2(0, 0.75), Vector2.ZERO)
	refresh(actor)
	initial = actor.viewport_render_requests
	for i in 100:
		actor._update_viewport_render_state(1.0 / 50.0)
	var intermediate_requests := actor.viewport_render_requests - initial
	check(intermediate_requests >= 59 and intermediate_requests <= 61, "30Hz rendering must retain fractional timer remainder at 50Hz physics")
	initial = actor.viewport_render_requests
	actor._update_viewport_render_state(0.5)
	check(actor.viewport_render_requests - initial == 1, "A stall must not submit a catch-up burst")
	check(is_finite(actor._viewport_frame_interval), "LOD interval must remain finite")
	root.canvas_transform = Transform2D.IDENTITY
	stage.queue_free()
	await process_frame
	print("PEDESTRIAN_RENDER_LOD_RESULT failures=%d near_requests=%d small_requests=%d" % [failures, near_requests, small_requests])
	quit(0 if failures == 0 else 1)
