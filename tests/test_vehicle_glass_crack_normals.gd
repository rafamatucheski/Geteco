extends "res://tests/test_vehicle_glass_damage.gd"

func run() -> void:
	for id in ["union_sedan", "monaliza", "courier_van"]:
		for stretched in [false, true]:
			var car := car_at(id, Vector3.ZERO)
			car.finish_doors()
			if stretched: car.scale = Vector3(1.7, .65, 1.2)
			var owner := GLASS.owner_for(car, true)
			for axis in [0, 2]:
				var label := "%s eixo%d escala_desigual=%s" % [id, axis, stretched]
				var ray := ray_for(car, axis)
				check(not ray.is_empty(), label + " vidro alcançável")
				if ray.is_empty(): continue
				var hit: Dictionary = owner.contact(ray[0], ray[1])
				var part: MeshInstance3D = hit.part
				var arrays := INTERIOR.contact_arrays(part.mesh, hit.surface)
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices := GLASS._indices(arrays)
				var normal := (normals[indices[hit.triangle]] + normals[indices[hit.triangle + 1]] + normals[indices[hit.triangle + 2]]).normalized()
				var expected := (part.global_basis.inverse().transposed() * normal).normalized()
				owner.shoot(ray[0], ray[1])
				var decals: Array = owner._cracks.get(part, [])
				check(not decals.is_empty(), label + " impacto cria trinca")
				if not decals.is_empty():
					var decal: Decal = decals.back()
					check(decal.global_basis.y.dot(expected) > .9999, label + " projeção acompanha normal externa renderizada")
					check(decal.global_basis.is_conformal() and absf(decal.global_basis.determinant() - 1.0) < .0001, label + " marca mantém escala métrica sem distorção")
				owner.clear()
			car.free()
	print("VEHICLE_GLASS_CRACK_NORMALS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
