extends SceneTree
## Geometric/physical regression checks for the mountain facades. Rendered
## inspection and frame-time comparison remain separate evidence.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
const DOOR := preload("res://world/places/WalkupFacadeDoor.gd")
const SOURCE := "res://assets/regions/source/world/mountain_pass/"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func _run() -> void:
	var actor := preload("res://scripts/Actor.gd").new()
	actor.is_player = true
	root.add_child(actor)
	actor.set_physics_process(false)
	var cases := [
		["ski_lodge", "SummitSkiLodge3D.gd", Vector3(6.8, 3.375, 4.05)],
		["mountain_cabin_village_1", "art/winter_props/LumberjackCabin3D.gd", Vector3(1.72, 2.43, 1.97)],
		["mountain_boutique", "ResortShop3D.gd", Vector3(3.27, 3.1, 1.92)],
	]
	for row in cases:
		var id: String = row[0]
		var definition := CATALOG.get_definition(id)
		var art: Node3D = load(SOURCE + row[1]).new()
		art.position = definition.exterior_position
		root.add_child(art)
		var wall: Vector3 = row[2]
		var roofs: Array[MeshInstance3D] = []
		var windows: Array[MeshInstance3D] = []
		var gables: Array[MeshInstance3D] = []
		for mesh in art.find_children("*", "MeshInstance3D", true, false):
			match str(mesh.get_meta("exterior_part", "")):
				"roof_slope": roofs.append(mesh)
				"window_glass": windows.append(mesh)
				"roof_gable": gables.append(mesh)
		check(roofs.size() == 2, id + " has two authored roof slopes")
		check(gables.size() >= 2, id + " front and rear gables close the roof")
		if roofs.size() == 2:
			var peaks: Array[Vector3] = []
			for roof in roofs:
				check(roof.mesh is BoxMesh, id + " roof slab is measurable")
				var side := signf(roof.position.x)
				var bottom := _roof_bottom(roof, side * wall.x, 0)
				check(bottom >= wall.y - .02, id + " wall does not pierce roof at eave " + str(side) + " y=" + str(bottom))
				var peak: Vector3 = roof.transform * Vector3(-side * roof.mesh.size.x * .5, 0, 0)
				peaks.append(peak)
				check(peak.y > roof.position.y, id + " roof drains outward " + str(side))
			var left_peak := peaks[0] if roofs[0].position.x < 0 else peaks[1]
			var right_peak := peaks[1] if roofs[0].position.x < 0 else peaks[0]
			check(left_peak.x >= right_peak.x - .03 and absf(left_peak.y - right_peak.y) < .05, id + " roof slopes meet or overlap without open ridge")
			for gable in gables:
				var faces: PackedVector3Array = gable.mesh.get_faces()
				var clear := true
				for point in faces:
					var vertex: Vector3 = gable.transform * point
					var roof := roofs[0] if vertex.x * roofs[0].position.x >= 0 else roofs[1]
					if vertex.y > _roof_bottom(roof, vertex.x, vertex.z) + .02: clear = false
				check(clear, id + " gable remains beneath roof " + str(gable.name))
		var exposures := {"left": 0, "right": 0, "back": 0}
		for window in windows:
			var window_transform := art.global_transform.affine_inverse() * window.global_transform
			var p := window_transform.origin
			var bounds: AABB = window_transform * window.get_aabb()
			if p.x < -wall.x:
				exposures.left += 1
				check(bounds.end.x < -wall.x, id + " left glass outside opaque wall")
			elif p.x > wall.x:
				exposures.right += 1
				check(bounds.position.x > wall.x, id + " right glass outside opaque wall")
			elif p.z < -wall.z:
				exposures.back += 1
				check(bounds.end.z < -wall.z, id + " rear glass outside opaque wall")
		for face in exposures:
			check(exposures[face] > 0, id + " visible window on " + face)
		var door := DOOR.install(art, definition)
		await physics_frame
		var entry_z := CATALOG.walkup_door_z(CATALOG.walkup_family(id))
		var start := art.to_global(Vector3(0, .08, entry_z + .8))
		actor.global_position = start
		check(actor.move_and_collide(Vector3(0, 0, -1.1), true) != null, id + " closed door blocks whole player")
		door.set_open_amount(1)
		await physics_frame
		actor.global_position = start
		var collision := actor.move_and_collide(Vector3(0, 0, -1.1), true)
		if collision != null: print("EXTERIOR_DOOR_BLOCKER ", id, " ", collision.get_collider().get_path())
		check(collision == null, id + " open door admits whole player")
		for side in [-1.0, 1.0]:
			actor.global_position = art.to_global(Vector3(side * (wall.x + .8), .08, 0))
			check(actor.move_and_collide(Vector3(-side * 1.3, 0, 0), true) != null, id + " window wall remains solid " + str(side))
		art.free()
		await physics_frame
	actor.free()
	print("MOUNTAIN_EXTERIOR_FINISH checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _roof_bottom(roof: MeshInstance3D, x: float, z: float) -> float:
	var normal: Vector3 = roof.transform.basis.y.normalized()
	var point: Vector3 = roof.transform * Vector3(0, -roof.mesh.size.y * .5, 0)
	return (normal.dot(point) - normal.x * x - normal.z * z) / normal.y
