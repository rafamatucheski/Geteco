extends SceneTree
## Production armored truck and ice-cream attachment: semantic bindings and
## reversible visible states. Functional contracts; this does not measure FPS.
const TRUCK := preload("res://gameplay/armored/ArmoredTruck.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
var checks := 0
var failures: Array[String] = []
class Stage extends Node3D:
	var player: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("SPECIAL_FLOW ", "PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	var stage := Stage.new()
	root.add_child(stage)
	stage.player = Node3D.new()
	stage.add_child(stage.player)
	var truck := TRUCK.new()
	stage.add_child(truck)
	truck.set_physics_process(false)
	check(truck.visual.has_meta("fleet_redesign_version"), "armored production class uses redesigned model")
	check(truck.vault_doors.size() == 2 and truck.cargo != null, "both vault leaves and cargo bound by runtime")
	var closed: Array[Transform3D] = []
	for door in truck.vault_doors: closed.append(door.transform)
	var hull: Vector3 = truck.shape.shape.size
	check(not truck.cargo.visible and not truck.opened, "cash hidden behind closed vault")
	truck.set_vault(true)
	check(truck.opened and truck.cargo.is_visible_in_tree(), "opening reveals visible cargo")
	for index in truck.vault_doors.size():
		var door := truck.vault_doors[index]
		check(not door.transform.is_equal_approx(closed[index]) and door.visible, "vault leaf actually moves and stays visible %d" % index)
	check(truck.vault_doors[0].rotation.y * truck.vault_doors[1].rotation.y < 0.0, "vault leaves open in opposite directions")
	truck.set_vault(true, true)
	check(truck.opened and not truck.cargo.visible, "taking cash leaves opened vault empty")
	truck.set_vault(false)
	for index in truck.vault_doors.size():
		check(truck.vault_doors[index].transform.is_equal_approx(closed[index]), "vault leaf restores exact closed transform %d" % index)
	check(truck.shape.shape.size.is_equal_approx(hull), "vault sequence preserves vehicle collider")
	var interaction: Vector3 = truck.to_local(truck.door_point())
	check(interaction.z > truck.half_length and absf(interaction.x) < .01 and interaction.y < .8, "vault interaction remains reachable outside rear hull")
	var van := VEHICLE.new()
	van.archetype = "courier_van"
	van.vehicle_id = "street_icecream_redesign_semantics"
	van.position.x = 8
	stage.add_child(van)
	van.set_physics_process(false)
	var glass_count := 0
	var paint_count := 0
	for part: MeshInstance3D in van.visual.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		for surface in part.mesh.get_surface_count():
			var role := ROLES.key(part, surface)
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null: continue
			if role == "glass":
				glass_count += 1
				check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.albedo_color.a < .3, "variant glass exposes the seated crew")
			elif role == "paint":
				paint_count += 1
				check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a > .99, "variant paint remains opaque")
	check(glass_count > 0 and paint_count > 0, "variant has independently addressable glass and paint")
	var rig := van.get_node("IceCreamVan")
	var mount: CollisionShape3D = van.get_node("IceCreamRoofCollision")
	var roof_height: float = rig._roof_height()
	var collider_bottom: float = mount.position.y - mount.shape.size.y * .5
	check(collider_bottom >= roof_height and collider_bottom - roof_height < .06, "ornament collider follows the new roof without floating")
	stage.free()
	await process_frame
	check(get_nodes_in_group("icecream_vans").is_empty(), "variant teardown releases its runtime group")
	print("SPECIAL_FLOW_RESULT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
