extends SceneTree

const RIG := preload("res://prototypes/living_cast/VehicleWheelRig.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

# Independent geometric check: chords through the actual tire must not cross
# any body triangle. It catches intersections even with no vertex in the tire.
func intersections(model: Node3D, rig) -> int:
	var count := 0
	for pivot in rig.pivots:
		var tires: Array = []
		for part in pivot.get_child(0).get_children():
			if part is MeshInstance3D and part.mesh is CylinderMesh and part.position.length() < 0.01:
				tires.append(part)
		for tire: MeshInstance3D in tires:
			var tire_to_model: Transform3D = model.global_transform.affine_inverse() * tire.global_transform
			var bounds: AABB = tire_to_model * tire.mesh.get_aabb()
			var faces := PackedVector3Array()
			for body in model.get_children():
				if not body is MeshInstance3D or not body.visible or body.mesh == null: continue
				if not bounds.intersects(body.transform * body.mesh.get_aabb()): continue
				var vertices: PackedVector3Array = body.mesh.get_faces()
				for vertex in vertices: faces.append(body.transform * vertex)
			for slice in [-0.48, 0.0, 0.48]:
				for spoke in 24:
					var radial: Vector3 = Vector3(cos(TAU * spoke / 24), 0, sin(TAU * spoke / 24)) * tire.mesh.top_radius * 0.995
					var center := Vector3(0, tire.mesh.height * slice, 0)
					var a := tire_to_model * (center - radial)
					var b := tire_to_model * (center + radial)
					for i in range(0, faces.size(), 3):
						if Geometry3D.segment_intersects_triangle(a, b, faces[i], faces[i+1], faces[i+2]) != null:
							count += 1
	return count

func run() -> void:
	var bench := Node3D.new()
	root.add_child(bench)
	var paths: Array[String] = []
	for id in VehicleCatalog.VEHICLES:
		var path: String = VehicleCatalog.get_vehicle_spec(id).model_class
		if not paths.has(path): paths.append(path)
	for path in paths:
		var model: Node3D = load(path).new()
		bench.add_child(model)
		var rig := RIG.new()
		rig.mount(model)
		var hits := 0
		for angle in [-0.58, 0.0, 0.58]:
			rig.update(1.0/60, 0.0, 0.0, angle)
			hits += intersections(model, rig)
		check(hits == 0, path.get_file() + ": tire clears body at both locks and center (%d crossings)" % hits)
		if model.has_method("apply_impact"):
			model.apply_impact(Vector3(.8,.65,-1.4), Vector3(-1,0,0), 12.0)
			model.repair()
			check(intersections(model, rig) == 0, path.get_file() + ": repair preserves wheel wells")
		model.free()
	bench.free()
	print("WHEEL_BODY_CLEARANCE failures=", failures)
	quit(0 if failures == 0 else 1)
