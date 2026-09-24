extends SceneTree
class Actor extends CharacterBody2D:
	var viewport_3d: SubViewport
	var sprite_3d_display: Sprite2D
	var model_root: Node3D
	var meshy_rig: Node
class Car extends CharacterBody2D:
	var body_viewport: SubViewport
	var sprite: Sprite2D
	var model: Node3D
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func viewport(parent: Node) -> SubViewport:
	var result := SubViewport.new()
	result.size = Vector2i(384, 384)
	result.own_world_3d = true
	parent.add_child(result)
	var camera := Camera3D.new()
	result.add_child(camera)
	camera.position = Vector3(0, 4, 3)
	camera.look_at(Vector3.ZERO)
	return result
func actor() -> Actor:
	var result := Actor.new()
	root.add_child(result)
	result.viewport_3d = viewport(result)
	result.model_root = Node3D.new()
	result.viewport_3d.add_child(result.model_root)
	result.sprite_3d_display = Sprite2D.new()
	result.add_child(result.sprite_3d_display)
	return result
func run() -> void:
	var car := Car.new()
	root.add_child(car)
	car.body_viewport = viewport(car)
	car.sprite = Sprite2D.new()
	car.add_child(car.sprite)
	car.model = Node3D.new()
	car.body_viewport.add_child(car.model)
	var first := actor()
	var second := actor()
	var first_view := preload("res://world/harbor/campaign/TourActorPresentation.gd").new()
	var second_view := preload("res://world/harbor/campaign/TourActorPresentation.gd").new()
	root.add_child(first_view)
	root.add_child(second_view)
	first_view.configure(first, car, 1.0)
	second_view.configure(second, car, -1.0)
	check(car.body_viewport.size == Vector2i(768, 768) and car.sprite.scale == Vector2.ONE * 0.5, "two occupants share one sampling boost")
	first.model_root.free()
	first_view.restore()
	check(car.body_viewport.get_meta("boarding_actor_users") == 1, "unexpected rig deletion releases its sampling reference")
	check(car.body_viewport.size == Vector2i(768, 768), "remaining occupant retains required sampling")
	first_view.restore()
	check(car.body_viewport.get_meta("boarding_actor_users") == 1, "repeat cleanup does not release another actor")
	second_view.restore()
	check(car.body_viewport.size == Vector2i(384, 384) and car.sprite.scale == Vector2.ONE, "last actor restores original render cost and sprite scale")
	first.free()
	second.free()
	first_view.free()
	second_view.free()
	car.free()
	print("TOUR_ACTOR_SAMPLING failures=", failures)
	quit(0 if failures == 0 else 1)
