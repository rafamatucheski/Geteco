extends SceneTree
## Cabin lining must remain below the roof, clear of the sloping rear glazing.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	for id in ["monaliza", "union_sedan", "metro_hatch", "sport_coupe"]:
		var car := VEHICLE.new()
		car.archetype = id
		root.add_child(car)
		car.set_physics_process(false)
		var spec := INTERIOR.spec(car)
		INTERIOR.attach(car)
		var interior: MeshInstance3D = car.visual.get_node("Interior")
		var checked := 0
		for surface in interior.mesh.get_surface_count():
			var material := interior.get_active_material(surface) as StandardMaterial3D
			if material == null or material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED: continue
			var vertices: PackedVector3Array = interior.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var rear := -INF
			var top := -INF
			for vertex in vertices:
				rear = maxf(rear, vertex.z)
				top = maxf(top, vertex.y)
			check(rear <= float(spec.rear_top) - .025, id + " lining ends before rear glass slopes down")
			check(top < float(spec.roof) - .015, id + " lining stays under roof")
			checked += vertices.size()
		check(checked > 0 or not bool(spec.get("roof_liner", true)), id + " lining actually checked or authored without liner")
		INTERIOR.attach(car)
		check(car.visual.find_children("Interior", "MeshInstance3D", true, false).size() == 1, id + " re-entry keeps a single interior")
		car.free()
	print("ROOF_LINER checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
