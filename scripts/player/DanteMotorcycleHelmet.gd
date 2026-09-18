extends Node
## Owned by Dante, not by a bike or its viewport. Runs while driving hides the
## actor / disables his physics, and naturally pauses with the scene tree.
const VISUAL = preload("res://scripts/player/DanteHelmetVisual.gd")
const DROPPED = preload("res://scripts/player/DanteDroppedHelmet.gd")
const WAIT_TO_EQUIP := 3.0
const WAIT_TO_REMOVE := 10.0
const ACTION_SECONDS := .75
var actor: CharacterBody2D
var motorcycle: CharacterBody2D
var worn := false
var stopped_seconds := 0.0
var off_bike_seconds := 0.0
var action := ""
var action_seconds := 0.0
var _last_visual_state := ""

func mount(bike: CharacterBody2D) -> void:
	motorcycle = bike
	stopped_seconds = 0.0
	off_bike_seconds = 0.0
	_cancel_action()

func dismount() -> void:
	motorcycle = null
	stopped_seconds = 0.0
	off_bike_seconds = 0.0
	_cancel_action()

func _cancel_action() -> void:
	action = ""
	action_seconds = 0.0
	sync_visual()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not is_instance_valid(actor): return
	if is_instance_valid(motorcycle) and (not motorcycle.is_motorcycle or not motorcycle.is_driven_by_player or motorcycle._driver != actor):
		dismount()
	var mounted := is_instance_valid(motorcycle)
	var stopped := mounted and motorcycle.velocity.length_squared() < 4.0 and not motorcycle.has_meta("vehicle_boarding")
	var action_started := false
	if mounted:
		off_bike_seconds = 0.0
		if not stopped:
			stopped_seconds = 0.0
			if action == "put_on": _cancel_action()
		elif not worn and action.is_empty():
			stopped_seconds += delta
			if stopped_seconds >= WAIT_TO_EQUIP:
				action = "put_on"
				action_seconds = stopped_seconds-WAIT_TO_EQUIP
				action_started = true
	else:
		stopped_seconds = 0.0
		if worn and action.is_empty():
			off_bike_seconds += delta
			if off_bike_seconds >= WAIT_TO_REMOVE:
				action = "take_off"
				action_seconds = off_bike_seconds-WAIT_TO_REMOVE
				action_started = true
	if not action.is_empty():
		if not action_started: action_seconds += delta
		if action_seconds >= ACTION_SECONDS:
			if action == "take_off":
				VISUAL.apply(actor.head_node, worn, action, 1.0)
				var dropped := DROPPED.new()
				actor.get_parent().add_child(dropped)
				dropped.setup(actor)
			worn = action == "put_on"
			action = ""
			action_seconds = 0.0
	sync_visual()

func sync_visual() -> void:
	if is_instance_valid(actor) and is_instance_valid(actor.head_node):
		VISUAL.apply(actor.head_node,worn,action,action_seconds/ACTION_SECONDS)
	if is_instance_valid(motorcycle) and is_instance_valid(motorcycle.body_model) and motorcycle.body_model.has_method("sync_dante_helmet"):
		var presentation: Node3D = motorcycle.body_model.dante_rider
		if is_instance_valid(presentation) and presentation.source_head_id != actor.head_node.get_instance_id():
			motorcycle.body_model.set_dante_rider(actor)
		motorcycle.body_model.sync_dante_helmet(self)
		var state := "%s:%s" % [worn,action]
		if not action.is_empty() or state != _last_visual_state: motorcycle._body_render_visible = false
		_last_visual_state = state

func apply_on_foot_pose() -> void:
	if action != "take_off" or not actor.visible: return
	# Preserve movement and the firing hand; the free hand lifts the helmet.
	var weight := sin(PI*clampf(action_seconds/ACTION_SECONDS,0.0,1.0))
	var rest: Vector3 = actor.model_root.to_local(actor.left_lower_arm.to_global(Vector3(0,-.20,0)))
	var shell: Node3D = actor.head_node.get_node("MotorcycleHelmet")
	var target: Vector3 = actor.head_node.transform*(shell.position+Vector3(-.16,-.06,0))
	actor.combat_pose._solve_arm(actor.left_upper_arm,actor.left_lower_arm,rest.lerp(target,weight),-1.0)
