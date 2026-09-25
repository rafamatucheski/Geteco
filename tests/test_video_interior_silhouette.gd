extends SceneTree
## Scope and ownership of the exterior-only occlusion aid.
const LOOK := preload("res://world/city_look/CityLook.gd")
var failures: Array[String] = []
var checks := 0

class WorldStub extends Node3D:
	var player: Node3D
	var driving := {"occupied": false, "car": null, "transition": null}

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("VIDEO_SILHOUETTE PASS " if ok else "VIDEO_SILHOUETTE FAIL ") + label)
	if not ok: failures.append(label)

func box(parent: Node3D, size: Vector3, point: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = point
	parent.add_child(mesh)
	return mesh

func _run() -> void:
	var world := WorldStub.new()
	root.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	world.player.position = Vector3(3, 0, 4)
	var body := box(world.player, Vector3(.6, 1.8, .5), Vector3(0, .9, 0))
	var accessory := box(world.player, Vector3(.1, .1, .1), Vector3(0, 1.2, 0))
	var unrelated := StandardMaterial3D.new()
	accessory.material_overlay = unrelated
	var bike := Node3D.new()
	world.add_child(bike)
	bike.position = Vector3(3, 0, 4)
	bike.rotation.y = .4
	var chassis := box(bike, Vector3(.8, 1.0, 2.2), Vector3(0, .5, 0))
	world.driving.car = bike
	var state := {"place_id": ""}
	var look := LOOK.new()
	look.controller = {"world": world, "state": state, "session": null, "environment": null}
	world.add_child(look)
	look.set_process(false)
	check(body.material_overlay is ShaderMaterial, "walking outdoors receives occlusion aid")
	check(chassis.material_overlay == null, "unoccupied motorcycle has no player aid")
	check(accessory.material_overlay == unrelated, "unrelated overlay preserved on install")
	state.place_id = "harbor_bank"
	look._refresh_silhouette()
	check(body.material_overlay == null and look._silhouette_targets.is_empty(), "interior removes xray in admission frame")
	check(accessory.material_overlay == unrelated, "interior preserves unrelated overlay")
	state.place_id = ""
	look._refresh_silhouette()
	check(body.material_overlay is ShaderMaterial, "exterior return restores occlusion aid")
	# Boarding first owns the vehicle while the seated player is still hidden.
	# Its final show must refresh the bounds before the next periodic scan.
	world.player.hide()
	world.driving.occupied = true
	look._follow_silhouettes()
	check(body.material_overlay is ShaderMaterial and chassis.material_overlay is ShaderMaterial, "mounting refreshes both targets before next 4Hz scan")
	var hidden_box_max: Vector3 = chassis.material_overlay.get_shader_parameter("box_max")
	check(hidden_box_max.y < 1.2, "hidden pilot is absent from motorcycle-only bounds")
	world.player.show()
	look._follow_silhouettes()
	var shown_box_max: Vector3 = chassis.material_overlay.get_shader_parameter("box_max")
	check(shown_box_max.y > 1.8, "boarding completion includes visible pilot before next 4Hz scan")
	# A long frame can hide/show between observations. Completion still changes
	# the transition identity and updates the final pose/position once.
	var transition := Node.new()
	world.add_child(transition)
	world.driving.transition = transition
	look._follow_silhouettes()
	body.position.y += .3
	world.driving.transition = null
	look._follow_silhouettes()
	var final_box_max: Vector3 = chassis.material_overlay.get_shader_parameter("box_max")
	check(final_box_max.y > 2.1, "transition completion refreshes final pose even when visibility is unchanged")
	transition.queue_free()
	var player_material := body.material_overlay as ShaderMaterial
	var bike_material := chassis.material_overlay as ShaderMaterial
	if player_material != null and bike_material != null:
		check(player_material.get_shader_parameter("target_inverse") == bike_material.get_shader_parameter("target_inverse"), "rider and bike share self-occlusion coordinates")
		check(player_material.get_shader_parameter("box_min") == bike_material.get_shader_parameter("box_min") and player_material.get_shader_parameter("box_max") == bike_material.get_shader_parameter("box_max"), "rider and bike share one enclosing box")
		var combined := AABB(Vector3(player_material.get_shader_parameter("box_min")), Vector3(player_material.get_shader_parameter("box_max")) - Vector3(player_material.get_shader_parameter("box_min")))
		check(combined.has_point(bike.to_local(body.to_global(Vector3(0, .9, 0)))) and combined.has_point(bike.to_local(chassis.to_global(Vector3(0, 0, 1.1)))), "self-occlusion box contains rider head and motorcycle end")
		check(not combined.has_point(Vector3(0, 0, 8)), "external building point remains outside self-occlusion box")
	state.place_id = "maciota"
	look._refresh_silhouette()
	check(body.material_overlay == null and chassis.material_overlay == null, "driven vehicle and rider have real depth in interior")
	state.place_id = ""
	world.driving.occupied = false
	look._follow_silhouettes()
	check(body.material_overlay is ShaderMaterial and chassis.material_overlay == null, "dismount restores only walking target")
	check(accessory.material_overlay == unrelated, "unrelated overlay survives every transition")
	world.queue_free()
	await process_frame
	print("VIDEO_SILHOUETTE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
