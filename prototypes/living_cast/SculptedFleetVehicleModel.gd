extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"

## Shared construction primitives for the second-generation fleet. Passenger
## bodies use continuous authored surfaces; boxes remain limited to trim,
## equipment and small details which should actually have hard edges.


func sculpted_shell(
	profile: Array[Vector3],
	axles: Array[float],
	wheel_y: float,
	wheel_radius: float,
	crown: float = 0.055,
	sill_y: float = 0.25
) -> MeshInstance3D:
	assert(profile.size() >= 2)
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var section_count := 64
	var cross_count := 10
	var start_z: float = profile[0].x
	var end_z: float = profile[-1].x
	for section in section_count:
		var z0 := lerpf(start_z, end_z, float(section) / section_count)
		var z1 := lerpf(start_z, end_z, float(section + 1) / section_count)
		var shape0 := _profile_at(profile, z0)
		var shape1 := _profile_at(profile, z1)
		for cross in cross_count:
			var u0 := lerpf(-1.0, 1.0, float(cross) / cross_count)
			var u1 := lerpf(-1.0, 1.0, float(cross + 1) / cross_count)
			var a := Vector3(u0 * shape0.x, shape0.y + crown * (1.0 - u0 * u0), z0)
			var b := Vector3(u0 * shape1.x, shape1.y + crown * (1.0 - u0 * u0), z1)
			var c := Vector3(u1 * shape1.x, shape1.y + crown * (1.0 - u1 * u1), z1)
			var d := Vector3(u1 * shape0.x, shape0.y + crown * (1.0 - u1 * u1), z0)
			_add_quad(mesh, a, b, c, d, false)
		for side in [-1.0, 1.0]:
			var top0 := Vector3(side * shape0.x, shape0.y, z0)
			var top1 := Vector3(side * shape1.x, shape1.y, z1)
			var bottom0 := Vector3(side * (shape0.x - 0.025), _arch_bottom(z0, axles, wheel_y, wheel_radius, sill_y), z0)
			var bottom1 := Vector3(side * (shape1.x - 0.025), _arch_bottom(z1, axles, wheel_y, wheel_radius, sill_y), z1)
			_add_quad(mesh, top0, top1, bottom1, bottom0, side > 0.0)
	mesh.generate_normals()
	var shell := mesh_node(mesh.commit(), Vector3.ZERO, paint)
	shell.name = "SculptedBodyShell"
	for z in [start_z, end_z]:
		var shape := _profile_at(profile, z)
		var cap: Array[Vector3] = [
			Vector3(-shape.x, sill_y, z), Vector3(shape.x, sill_y, z),
			Vector3(shape.x, shape.y, z), Vector3(-shape.x, shape.y, z),
		]
		if z > 0.0:
			cap.reverse()
		surface(cap, paint)
	return shell


func add_greenhouse(
	lower_front_z: float,
	lower_rear_z: float,
	upper_front_z: float,
	upper_rear_z: float,
	belt_y: float,
	roof_y: float,
	belt_half_width: float,
	roof_half_width: float,
	pane_count: int = 2,
	roof_crown: float = 0.045
) -> void:
	var glass := materials.get("glass") as Material
	var trim := materials.get("trim") as Material
	# Curved roof skin, built as one surface so it batches and deforms cleanly.
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z_step in 10:
		var tz0 := float(z_step) / 10.0
		var tz1 := float(z_step + 1) / 10.0
		var z0 := lerpf(upper_front_z, upper_rear_z, tz0)
		var z1 := lerpf(upper_front_z, upper_rear_z, tz1)
		for cross in 8:
			var u0 := lerpf(-1.0, 1.0, float(cross) / 8.0)
			var u1 := lerpf(-1.0, 1.0, float(cross + 1) / 8.0)
			var a := Vector3(u0 * roof_half_width, roof_y + roof_crown * (1.0 - u0 * u0), z0)
			var b := Vector3(u0 * roof_half_width, roof_y + roof_crown * (1.0 - u0 * u0), z1)
			var c := Vector3(u1 * roof_half_width, roof_y + roof_crown * (1.0 - u1 * u1), z1)
			var d := Vector3(u1 * roof_half_width, roof_y + roof_crown * (1.0 - u1 * u1), z0)
			_add_quad(roof, a, b, c, d, false)
	roof.generate_normals()
	mesh_node(roof.commit(), Vector3.ZERO, paint).name = "CurvedCabinRoof"

	# Sloped windshields establish cabin position even at top-down camera angles.
	surface([
		Vector3(-belt_half_width, belt_y, lower_front_z), Vector3(belt_half_width, belt_y, lower_front_z),
		Vector3(roof_half_width, roof_y, upper_front_z), Vector3(-roof_half_width, roof_y, upper_front_z),
	], glass)
	surface([
		Vector3(belt_half_width, belt_y, lower_rear_z), Vector3(-belt_half_width, belt_y, lower_rear_z),
		Vector3(-roof_half_width, roof_y, upper_rear_z), Vector3(roof_half_width, roof_y, upper_rear_z),
	], glass)

	for side in [-1.0, 1.0]:
		for pane in pane_count:
			var t0 := float(pane) / pane_count
			var t1 := float(pane + 1) / pane_count
			var low0 := lerpf(lower_front_z, lower_rear_z, t0)
			var low1 := lerpf(lower_front_z, lower_rear_z, t1)
			var high0 := lerpf(upper_front_z, upper_rear_z, t0)
			var high1 := lerpf(upper_front_z, upper_rear_z, t1)
			surface([
				Vector3(side * belt_half_width, belt_y, low0 + 0.025),
				Vector3(side * belt_half_width, belt_y, low1 - 0.025),
				Vector3(side * roof_half_width, roof_y, high1 - 0.025),
				Vector3(side * roof_half_width, roof_y, high0 + 0.025),
			], glass)
		for pillar in pane_count + 1:
			var t := float(pillar) / pane_count
			var low := lerpf(lower_front_z, lower_rear_z, t)
			var high := lerpf(upper_front_z, upper_rear_z, t)
			tube([
				Vector3(side * belt_half_width, belt_y, low),
				Vector3(side * roof_half_width, roof_y, high),
			], 0.025 if pillar > 0 and pillar < pane_count else 0.038, trim if pillar > 0 and pillar < pane_count else paint)
		tube([
			Vector3(side * belt_half_width, belt_y, lower_front_z),
			Vector3(side * belt_half_width, belt_y, lower_rear_z),
		], 0.014, trim)


func add_axles(
	axles: Array[float],
	track: float,
	wheel_y: float,
	tire_radius: float,
	tire_width: float,
	rim_radius: float,
	spokes: int,
	rim_color: String
) -> void:
	for side in [-track, track]:
		for axle in axles:
			add_wheel(side, wheel_y, axle, tire_radius, tire_width, rim_radius, spokes, rim_color)


func add_aero_mirrors(z: float, x: float, y: float, size := Vector3(0.20, 0.09, 0.16)) -> void:
	var trim := materials.get("trim") as Material
	for side in [-1.0, 1.0]:
		box(Vector3(side * (x - 0.08), y - 0.02, z), Vector3(0.14, 0.025, 0.035), trim).set_meta("door_trim", true)
		ell(Vector3(side * x, y, z), size, paint).set_meta("door_trim", true)


func add_flush_handles(z_positions: Array[float], x: float, y: float, material: Material = null) -> void:
	var finish := material if material != null else materials.get("trim") as Material
	for side in [-1.0, 1.0]:
		for z in z_positions:
			box(Vector3(side * x, y, z), Vector3(0.026, 0.026, 0.16), finish).set_meta("door_trim", true)


func add_lamp_pair(front_z: float, rear_z: float, half_width: float, lamp_size := Vector2(0.34, 0.09)) -> void:
	var head := materials.get("headlight") as Material
	var tail := materials.get("taillight") as Material
	for side in [-1.0, 1.0]:
		box(Vector3(side * half_width, 0.69, front_z), Vector3(lamp_size.x, lamp_size.y, 0.035), head)
		box(Vector3(side * half_width, 0.67, rear_z), Vector3(lamp_size.x, lamp_size.y, 0.035), tail)


func add_underbody(length: float, width: float, y: float = 0.24) -> void:
	box(Vector3(0.0, y, 0.0), Vector3(width, 0.07, length), materials.get("rubber") as Material)


func add_rounded_volume(
	front_z: float,
	rear_z: float,
	front_half_width: float,
	rear_half_width: float,
	base_y: float,
	shoulder_y: float,
	roof_y: float,
	material: Material
) -> MeshInstance3D:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cross_sections: Array[Vector2] = [Vector2(-1.0, base_y), Vector2(-1.0, shoulder_y)]
	for step in 9:
		var angle := PI - PI * float(step) / 8.0
		cross_sections.append(Vector2(cos(angle), shoulder_y + sin(angle) * (roof_y - shoulder_y)))
	cross_sections.append(Vector2(1.0, base_y))
	for index in cross_sections.size() - 1:
		var a2 := cross_sections[index]
		var b2 := cross_sections[index + 1]
		var a := Vector3(a2.x * front_half_width, a2.y, front_z)
		var b := Vector3(a2.x * rear_half_width, a2.y, rear_z)
		var c := Vector3(b2.x * rear_half_width, b2.y, rear_z)
		var d := Vector3(b2.x * front_half_width, b2.y, front_z)
		_add_quad(mesh, a, b, c, d, false)
	for z_data in [[front_z, front_half_width, true], [rear_z, rear_half_width, false]]:
		var center := Vector3(0.0, (base_y + shoulder_y) * 0.5, float(z_data[0]))
		for index in cross_sections.size() - 1:
			var a2 := cross_sections[index]
			var b2 := cross_sections[index + 1]
			var a := Vector3(a2.x * float(z_data[1]), a2.y, float(z_data[0]))
			var b := Vector3(b2.x * float(z_data[1]), b2.y, float(z_data[0]))
			if bool(z_data[2]):
				for point in [center, b, a]: mesh.add_vertex(point)
			else:
				for point in [center, a, b]: mesh.add_vertex(point)
	mesh.generate_normals()
	var volume := mesh_node(mesh.commit(), Vector3.ZERO, material)
	volume.name = "RoundedUtilityVolume"
	return volume


func set_silhouette(signature: String, cabin_kind: String) -> void:
	set_meta("silhouette_signature", signature)
	set_meta("cabin_kind", cabin_kind)


func _profile_at(profile: Array[Vector3], z: float) -> Vector2:
	if z <= profile[0].x:
		return Vector2(profile[0].y, profile[0].z)
	for index in profile.size() - 1:
		var a := profile[index]
		var b := profile[index + 1]
		if z <= b.x:
			var weight := inverse_lerp(a.x, b.x, z)
			weight = weight * weight * (3.0 - 2.0 * weight)
			return Vector2(lerpf(a.y, b.y, weight), lerpf(a.z, b.z, weight))
	return Vector2(profile[-1].y, profile[-1].z)


func _arch_bottom(z: float, axles: Array[float], wheel_y: float, wheel_radius: float, sill_y: float) -> float:
	var result := sill_y
	var cut_radius := wheel_radius + 0.055
	for axle in axles:
		var distance := absf(z - axle)
		if distance < cut_radius:
			result = maxf(result, wheel_y + sqrt(cut_radius * cut_radius - distance * distance))
	return result


func _add_quad(mesh: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, reverse: bool) -> void:
	var points := [a, c, b, a, d, c] if not reverse else [a, b, c, a, c, d]
	for point in points:
		mesh.add_vertex(point)
