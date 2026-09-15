extends "res://ui/BankLockpick.gd"
## Keeps the world running while the player works on a parked police lock.
var actor: CharacterBody2D
var vehicle: Node2D
var _controls_were_disabled := false
var _owns_controls := false
var _waiting_for_release := false

func _ready() -> void:
	lock_title = "VIATURA"
	instruction_text = "ESPAÇO / CLIQUE — travar na faixa verde\nErrou: alarme • ESC — desistir"
	allowed_mistakes = 1
	super._ready()

func begin_for(pedestrian: CharacterBody2D, car: Node2D) -> void:
	actor = pedestrian
	vehicle = car
	if "is_control_disabled" in actor:
		_controls_were_disabled = actor.is_control_disabled
		actor.is_control_disabled = true
		_owns_controls = true
	actor.velocity = Vector2.ZERO
	begin()

func can_complete() -> bool:
	return is_instance_valid(actor) and is_instance_valid(vehicle) \
		and actor.is_visible_in_tree() and vehicle.is_visible_in_tree() \
		and actor.get("is_dead") != true and actor.get("is_arrested") != true \
		and not vehicle.is_broken and not vehicle.is_driven_by_player \
		and actor.global_position.distance_to(vehicle.global_position) <= 100.0

func _process(delta: float) -> void:
	if _waiting_for_release:
		if not _attempt_input_held():
			_release_controls()
			queue_free()
		return
	if active and not can_complete():
		finish(false)
		return
	super._process(delta)

func finish(success: bool) -> void:
	if not active: return
	success = success and can_complete()
	# The click that misses the lock must not fire the player's weapon afterward.
	_waiting_for_release = not success and _attempt_input_held()
	if not _waiting_for_release: _release_controls()
	super.finish(success)
	if not _waiting_for_release: queue_free()

func _attempt_input_held() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("ui_accept") \
		or Input.is_action_pressed("ui_cancel") or Input.is_action_pressed("fire")

func _release_controls() -> void:
	if _owns_controls and is_instance_valid(actor):
		actor.is_control_disabled = _controls_were_disabled
	_owns_controls = false

func _exit_tree() -> void:
	_release_controls()
