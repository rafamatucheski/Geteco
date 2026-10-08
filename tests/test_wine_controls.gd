extends SceneTree
## Focused actor/camera boundary checks. Run with the compiled Godot .NET project.
## The rendered Main walkthrough remains the evidence for presentation and FPS.
const ACTOR := preload("res://scripts/Actor.gd")
const CAMERA := preload("res://scripts/CameraRig.gd")
const WINE := preload("res://gameplay/wine/WineRuntime.gd")
var checks := 0
var failures: Array[String] = []

class CameraGameplay extends Node:
	var health := 100.0
	func scope_active() -> bool: return false

class CameraWorld extends Node3D:
	var gameplay: Node
	var hud: Control

class SessionFixture extends Node:
	var world: Dictionary
	var modal := false
	var ready_for_play := true
	func is_transition_blocked() -> bool: return false

func _initialize() -> void: run.call_deferred()
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok: failures.append(text); push_error(text)
func frames(count: int) -> void:
	for frame in count: await physics_frame
func flat(vector: Vector3) -> Vector3: return Vector3(vector.x,0,vector.z)
func floor_body() -> StaticBody3D:
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=Vector3(50,.2,50)
	collider.shape=shape
	collider.position.y=-.1
	floor.add_child(collider)
	return floor

func run() -> void:
	var stage := CameraWorld.new()
	root.add_child(stage)
	stage.gameplay=CameraGameplay.new()
	stage.add_child(stage.gameplay)
	stage.hud=Control.new()
	stage.add_child(stage.hud)
	stage.add_child(floor_body())
	var actor=ACTOR.new()
	actor.is_player=true
	stage.add_child(actor)
	var camera=CAMERA.new()
	camera.target=actor
	stage.add_child(camera)
	camera.set_process(false)
	actor.camera=camera
	await frames(3)
	camera._process(1.0/60.0)
	var input := root.get_node("GameInput")
	var previous_touch: Vector2=input.touch_move
	var previous_sprint: bool=input.touch_sprint
	input.touch_move=Vector2.RIGHT
	input.touch_sprint=false
	actor.controlled_automatically=false
	await frames(3)
	var sober: Vector3=flat(actor.velocity)
	check(sober.length()>3.4 and absf(sober.z)<.001,"human sober movement retains the ordinary walking speed and heading")
	actor.set_meta("alcohol_intensity",1.0)
	actor.set_meta("alcohol_sway",1.0)
	await frames(3)
	var impaired: Vector3=flat(actor.velocity)
	check(impaired.length()<sober.length()*.9 and impaired.length()>sober.length()*.7,"human intoxication slows the real actor within a playable range")
	check(absf(impaired.normalized().dot(sober.normalized()))<.999,"human intoxication changes voluntary heading")
	input.touch_move=Vector2.ZERO
	await frames(3)
	check(flat(actor.velocity).length()<.001,"intoxication cannot move an idle player without input")
	actor.controlled_automatically=true
	actor.automatic_direction=Vector3.RIGHT
	actor.speed=3.5
	await frames(3)
	check(flat(actor.velocity).distance_to(sober)<.001,"automatic transition movement preserves its exact speed and direction while drunk")
	actor.input_locked=true
	await frames(3)
	check(flat(actor.velocity).length()<.001,"locked controls remain stationary despite intoxication and an automatic direction")
	actor.input_locked=false
	actor.controlled_automatically=false
	input.touch_move=Vector2.RIGHT
	actor.set_meta("alcohol_intensity",0.0)
	actor.set_meta("alcohol_sway",0.0)
	await frames(3)
	check(flat(actor.velocity).distance_to(sober)<.001,"sober recovery restores the original human movement")
	input.touch_move=Vector2.ZERO
	await frames(3)
	actor.reset_physics_interpolation()
	camera.initialized=false
	camera._process(1.0/60.0)
	var sober_basis: Basis=camera.global_basis
	camera.set_meta("alcohol_intensity",1.0)
	camera.set_meta("alcohol_sway",1.0)
	camera._process(1.0/60.0)
	var drunk_basis: Basis=camera.global_basis
	var difference := sober_basis.get_rotation_quaternion().angle_to(drunk_basis.get_rotation_quaternion())
	check(difference>.005 and difference<.025,"camera receives a small visible roll within the authored framing")
	for frame in 120: camera._process(1.0/60.0)
	check(camera.global_basis.is_equal_approx(drunk_basis),"camera roll is rebuilt each frame and never accumulates")
	var session := SessionFixture.new()
	session.world={"player":actor,"camera":camera,"gameplay":stage.gameplay}
	stage.add_child(session)
	var wine=WINE.new()
	wine.session=session
	wine.model.claim_gift()
	wine.model.drink("zacharias_malagousia",100.0)
	var before_pause: Dictionary=wine.snapshot()
	paused=true
	wine._process(10.0)
	for frame in 10: camera._process(1.0/60.0)
	check(wine.snapshot()==before_pause,"pause freezes intoxication and sip cooldown")
	check(camera.global_basis.is_equal_approx(drunk_basis),"pause preserves the current camera inclination without animation or jumping")
	paused=false
	var stock: Dictionary=wine.snapshot().servings
	wine.recover()
	camera._process(1.0/60.0)
	check(camera.global_basis.is_equal_approx(sober_basis),"runtime recovery clears camera roll on its next frame")
	check(float(actor.get_meta("alcohol_intensity",-1.0))==0.0 and wine.snapshot().servings==stock,"runtime recovery clears movement impairment and retains bought wine")
	wine.free()
	input.touch_move=previous_touch
	input.touch_sprint=previous_sprint
	stage.free()
	print("WINE_CONTROLS checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
