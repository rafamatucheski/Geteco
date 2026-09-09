extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## High-performance sport coupe: deep metallic blue, vibrant orange aerodynamic livery,
## front-mount intercooler (FMIC), projector headlights, sport rims with red calipers,
## and swan-neck GT wing on functional trunk pivot.
var trunk_pivot: Node3D

func build() -> void:
	paint = mat("paint", "183b91", 0.65, 0.22)
	var orange := mat("orange", "ef7727", 0.35, 0.30)
	var white := mat("ivory", "f0f2f5", 0.20, 0.40)
	var black := mat("trim", "11151a", 0.25, 0.55)
	var carbon := mat("carbon", "1b1f24", 0.45, 0.45)
	var glass := mat("glass", "121f2b", 0.45, 0.12)
	var silver := mat("alloy", "c4d3de", 0.88, 0.18)
	var head := mat("headlight", "d8f3ff", 0.20, 0.15, 0.95)
	var drl := mat("drl_strip", "c4ebff", 0.15, 0.20, 1.30)
	var tail := mat("taillight", "c41e25", 0.10, 0.20, 0.85)
	var tail_smoked := mat("tail_smoked", "220709", 0.25, 0.25)
	var amber := mat("amber", "ff9800", 0.20, 0.25, 0.65)
	var boost_blue := mat("boost_blue", "1a68d1", 0.15, 0.40)
	var caliper_red := mat("caliper_red", "d63031", 0.35, 0.35)

	# 1. Aerodynamic Chamfered Body Rings: z, half-width, sill height, belt height.
	var rings := [
		Vector4(-2.25, 0.75, 0.30, 0.56),
		Vector4(-1.98, 0.91, 0.29, 0.72),
		Vector4(-1.30, 0.96, 0.27, 0.82),
		Vector4(-0.55, 0.91, 0.28, 0.85),
		Vector4(0.70, 0.94, 0.28, 0.87),
		Vector4(1.35, 0.98, 0.29, 0.84),
		Vector4(2.08, 0.90, 0.32, 0.73),
		Vector4(2.23, 0.78, 0.34, 0.65)
	]
	for i in rings.size() - 1:
		var a: Vector4 = rings[i]
		var b: Vector4 = rings[i + 1]
		for side in [-1.0, 1.0]:
			_quad([Vector3(a.y * side, a.z, a.x), Vector3(b.y * side, b.z, b.x), Vector3(b.y * side, b.w, b.x), Vector3(a.y * side, a.w, a.x)], paint)
		if i < 3:
			_quad([Vector3(-a.y, a.w, a.x), Vector3(a.y, a.w, a.x), Vector3(b.y, b.w, b.x), Vector3(-b.y, b.w, b.x)], paint)

	# Underbody belly pan / undertray
	box(Vector3(0, 0.30, 0), Vector3(1.72, 0.08, 4.30), black)

	# 2. Sleek Sports Coupe Cabin
	_quad([Vector3(-0.83, 0.84, -0.57), Vector3(0.83, 0.84, -0.57), Vector3(0.68, 1.27, 0.05), Vector3(-0.68, 1.27, 0.05)], glass)
	_quad([Vector3(-0.69, 1.28, 0.05), Vector3(0.69, 1.28, 0.05), Vector3(0.66, 1.25, 0.95), Vector3(-0.66, 1.25, 0.95)], paint)
	_quad([Vector3(-0.66, 1.24, 0.95), Vector3(0.66, 1.24, 0.95), Vector3(0.83, 0.84, 1.53), Vector3(-0.83, 0.84, 1.53)], glass)

	for side in [-1.0, 1.0]:
		# Side windows and pillars
		_quad([Vector3(side * 0.84, 0.87, -0.49), Vector3(side * 0.69, 1.23, 0.08), Vector3(side * 0.67, 1.21, 0.90), Vector3(side * 0.86, 0.86, 1.38)], glass)
		tube([Vector3(side * 0.85, 0.84, -0.57), Vector3(side * 0.69, 1.28, 0.05), Vector3(side * 0.66, 1.25, 0.95), Vector3(side * 0.86, 0.84, 1.54)], 0.025, paint)
		tube([Vector3(side * 0.74, 0.86, 0.57), Vector3(side * 0.68, 1.26, 0.57)], 0.021, black)

		# Two-tone aerodynamic side mirrors
		box(Vector3(side * 0.92, 0.86, -0.48), Vector3(0.08, 0.025, 0.04), black)
		box(Vector3(side * 1.00, 0.88, -0.48), Vector3(0.18, 0.09, 0.18), paint)
		box(Vector3(side * 1.00, 0.92, -0.48), Vector3(0.17, 0.022, 0.16), orange)
		box(Vector3(side * 0.93, 0.88, -0.48), Vector3(0.012, 0.07, 0.14), silver)

		# Recessed door handle in silver
		box(Vector3(side * 0.92, 0.79, 0.45), Vector3(0.025, 0.025, 0.16), silver)

		# Dynamic orange side graphic with ivory pin-striping
		_quad([Vector3(side * 0.967, 0.42, -1.25), Vector3(side * 0.967, 0.44, 0.72), Vector3(side * 0.989, 0.80, 1.36), Vector3(side * 0.952, 0.72, -0.55)], orange)
		tube([Vector3(side * 0.958, 0.73, -0.55), Vector3(side * 0.995, 0.81, 1.36)], 0.012, white)
		tube([Vector3(side * 0.968, 0.42, -1.25), Vector3(side * 0.968, 0.44, 0.72)], 0.009, white)

		# Sculpted rocker skirts in satin black with orange winglet
		box(Vector3(side * 0.96, 0.27, 0.02), Vector3(0.09, 0.06, 2.76), black)
		box(Vector3(side * 0.97, 0.28, 0.02), Vector3(0.035, 0.022, 2.50), orange)
		box(Vector3(side * 0.98, 0.31, 0.82), Vector3(0.03, 0.07, 0.16), orange)

		# Sport wheels and wheel arches
		for axle in [-1.28, 1.22]:
			add_wheel(side * 0.94, 0.36, axle, 0.35, 0.25, 0.255, 6, "c1cbd0")
			_sport_rim(side, axle, silver, black, caliper_red)
			var arch: Array[Vector3] = []
			for step in 13:
				var angle := PI * step / 12.0
				arch.append(Vector3(side * 0.976, 0.36 + sin(angle) * 0.38, axle + cos(angle) * 0.38))
			tube(arch, 0.025, black)

	# 3. Aggressive Front Fascia, FMIC and Aerodynamics
	# Main front bumper in deep blue body paint
	box(Vector3(0, 0.47, -2.17), Vector3(1.76, 0.29, 0.16), paint)
	# Satin black lower front splitter
	box(Vector3(0, 0.26, -2.25), Vector3(1.86, 0.045, 0.24), black)
	tube([Vector3(-0.24, 0.27, -2.32), Vector3(-0.21, 0.39, -2.24)], 0.007, silver)
	tube([Vector3(0.24, 0.27, -2.32), Vector3(0.21, 0.39, -2.24)], 0.007, silver)

	# Front aerodynamic canards and corner air intakes
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.84, 0.36, -2.21), Vector3(0.09, 0.025, 0.16), orange)
		box(Vector3(side * 0.86, 0.43, -2.18), Vector3(0.07, 0.022, 0.14), orange)
		box(Vector3(side * 0.68, 0.46, -2.26), Vector3(0.24, 0.14, 0.03), black)

	# Central intake opening in black with orange accent frame
	box(Vector3(0, 0.46, -2.26), Vector3(0.96, 0.22, 0.04), black)
	box(Vector3(0, 0.575, -2.26), Vector3(0.98, 0.022, 0.035), orange)
	box(Vector3(0, 0.345, -2.26), Vector3(0.98, 0.022, 0.035), orange)

	# Front-Mount Intercooler (FMIC): high-density aluminum core and cooling channels
	box(Vector3(0, 0.46, -2.285), Vector3(0.80, 0.17, 0.025), silver)
	for i in 6:
		box(Vector3(0, 0.39 + i * 0.026, -2.298), Vector3(0.78, 0.008, 0.012), black)

	# Intercooler end-tanks and silicone boost couplers
	for side in [-1.0, 1.0]:
		var end_tank := cylinder(Vector3(side * 0.43, 0.46, -2.27), 0.045, 0.14, silver)
		end_tank.rotation.z = PI / 2.0
		var coupler_mat: Material = orange if side < 0 else boost_blue
		var coupler := cylinder(Vector3(side * 0.47, 0.46, -2.25), 0.052, 0.035, coupler_mat)
		coupler.rotation.z = PI / 2.0

	# 4. Projector Headlamps & LED DRLs (centered at _headlamp_mounts)
	for side in [-1.0, 1.0]:
		# Smoked housing
		box(Vector3(side * 0.63, 0.70, -2.065), Vector3(0.44, 0.13, 0.08), black)
		box(Vector3(side * 0.63, 0.70, -2.085), Vector3(0.40, 0.10, 0.03), silver)
		# Dual crystal projector lenses with chrome bezels
		for x in [-0.095, 0.075]:
			var lens := cylinder(Vector3(side * 0.63 + x, 0.695, -2.11), 0.044, 0.026, head)
			lens.rotation.x = PI / 2.0
			var bezel := cylinder(Vector3(side * 0.63 + x, 0.695, -2.10), 0.050, 0.010, silver)
			bezel.rotation.x = PI / 2.0
		# Top LED Daytime Running Light (DRL) strip
		box(Vector3(side * 0.63, 0.75, -2.09), Vector3(0.42, 0.018, 0.025), drl)
		# Amber corner indicator
		box(Vector3(side * 0.81, 0.70, -2.05), Vector3(0.045, 0.08, 0.03), amber)

		# Hood heat extractor vents with orange pin-striping
		for z in [-1.10, -0.99, -0.88]:
			box(Vector3(side * 0.43, 0.846, z), Vector3(0.23, 0.012, 0.026), black)
		tube([Vector3(side * 0.30, 0.848, -1.14), Vector3(side * 0.56, 0.848, -1.14), Vector3(side * 0.56, 0.848, -0.84), Vector3(side * 0.30, 0.848, -0.84)], 0.006, orange)

	# 5. Rear Fascia, Diffuser and Performance Exhaust
	box(Vector3(0, 0.42, 2.22), Vector3(1.72, 0.18, 0.12), paint)
	box(Vector3(0, 0.27, 2.21), Vector3(1.64, 0.08, 0.20), black)
	# Aerodynamic diffuser fins
	for s in [-0.42, -0.16, 0.16, 0.42]:
		box(Vector3(s, 0.26, 2.22), Vector3(0.016, 0.08, 0.18), black)

	# High-performance twin exhaust tips on left
	var exhaust_main := cylinder(Vector3(-0.62, 0.32, 2.31), 0.075, 0.18, silver)
	exhaust_main.rotation.x = PI / 2.0
	var exhaust_main_hole := cylinder(Vector3(-0.62, 0.32, 2.41), 0.060, 0.012, black)
	exhaust_main_hole.rotation.x = PI / 2.0

	var exhaust_sub := cylinder(Vector3(-0.48, 0.32, 2.28), 0.065, 0.16, silver)
	exhaust_sub.rotation.x = PI / 2.0
	var exhaust_sub_hole := cylinder(Vector3(-0.48, 0.32, 2.37), 0.052, 0.012, black)
	exhaust_sub_hole.rotation.x = PI / 2.0

	# Full-width smoked LED taillight bar
	box(Vector3(0, 0.69, 2.15), Vector3(1.70, 0.13, 0.06), tail_smoked)
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.58, 0.69, 2.17), Vector3(0.48, 0.07, 0.04), tail)
		box(Vector3(side * 0.22, 0.69, 2.17), Vector3(0.18, 0.04, 0.03), white)

	# 6. Functional Trunk Lid, Swan-Neck GT Wing & Loadout Storage
	trunk_pivot = Node3D.new()
	trunk_pivot.name = "MonalizaTrunkHinge"
	trunk_pivot.position = Vector3(0, 0.86, 1.48)
	add_child(trunk_pivot)

	var first := get_child_count()
	# Sculpted trunk lid in body color with ducktail lip
	box(Vector3(0, 0.79, 1.83), Vector3(1.74, 0.09, 0.69), paint)
	box(Vector3(0, 0.84, 2.14), Vector3(1.68, 0.04, 0.07), orange)

	# Lightweight swan-neck GT wing uprights
	for side in [-1.0, 1.0]:
		box(Vector3(side * 0.56, 0.95, 1.94), Vector3(0.040, 0.24, 0.08), carbon)
		box(Vector3(side * 0.56, 1.15, 2.00), Vector3(0.035, 0.22, 0.06), carbon)

	# Aerodynamic GT wing airfoil deck in carbon with orange leading edge
	box(Vector3(0, 1.26, 2.02), Vector3(1.98, 0.045, 0.28), carbon)
	box(Vector3(0, 1.28, 2.00), Vector3(1.94, 0.022, 0.18), carbon)
	box(Vector3(0, 1.27, 1.89), Vector3(1.92, 0.022, 0.035), orange)

	# Aerodynamic wing endplates: vibrant orange outer face, carbon inner plate
	for side in [-1.0, 1.0]:
		box(Vector3(side * 1.00, 1.27, 2.02), Vector3(0.020, 0.20, 0.38), orange)
		box(Vector3(side * 0.985, 1.27, 2.02), Vector3(0.015, 0.18, 0.35), carbon)

	# Reparent lid and wing assembly into trunk_pivot
	for node in get_children().slice(first):
		node.position -= trunk_pivot.position
		node.reparent(trunk_pivot, false)

	# Static trunk interior (revealed when lid tilts open)
	box(Vector3(0, 0.51, 1.72), Vector3(1.55, 0.05, 0.88), black)
	# Heavy tactical gun case with orange latch locks
	box(Vector3(-0.32, 0.58, 1.75), Vector3(0.74, 0.10, 0.42), mat("case", "283633", 0.15, 0.85))
	box(Vector3(-0.32, 0.64, 1.75), Vector3(0.46, 0.014, 0.08), orange)
	box(Vector3(-0.52, 0.58, 1.96), Vector3(0.05, 0.04, 0.02), orange)
	box(Vector3(-0.12, 0.58, 1.96), Vector3(0.05, 0.04, 0.02), orange)

	# Spare roadside emergency kit on right side of trunk
	box(Vector3(0.38, 0.56, 1.72), Vector3(0.28, 0.08, 0.22), mat("toolkit", "1e242a", 0.2, 0.7))

	# Emblem badge
	var badge := Label3D.new()
	badge.text = "MONALIZA"
	badge.font_size = 38
	badge.pixel_size = 0.004
	badge.position = Vector3(0, 0.53, 2.30)
	badge.modulate = white.albedo_color
	add_child(badge)

func _sport_rim(side: float, axle: float, silver: Material, black: Material, caliper_mat: Material) -> void:
	var first := get_child_count()
	var x := side * 1.074

	# 1. Drilled sports brake disc rotor
	var rotor := cylinder(Vector3(x - side * 0.06, 0.36, axle), 0.20, 0.018, silver)
	rotor.rotation.z = PI / 2.0

	# 2. High-performance racing red brake caliper
	var caliper := box(Vector3(x - side * 0.05, 0.44, axle + 0.06), Vector3(0.035, 0.08, 0.07), caliper_mat)

	# 3. Outer wheel face & machined lip
	var face := cylinder(Vector3(x, 0.36, axle), 0.253, 0.016, black)
	face.rotation.z = PI / 2.0

	var rim := TorusMesh.new()
	rim.inner_radius = 0.225
	rim.outer_radius = 0.265
	rim.rings = 24
	rim.ring_segments = 8
	var lip := mesh_node(rim, Vector3(x + side * 0.014, 0.36, axle), silver)
	lip.rotation.z = PI / 2.0

	# 4. Six sculpted athletic spokes
	for i in 6:
		var a := TAU * i / 6.0
		tube([
			Vector3(x + side * 0.022, 0.36 + cos(a) * 0.045, axle + sin(a) * 0.045),
			Vector3(x + side * 0.022, 0.36 + cos(a) * 0.23, axle + sin(a) * 0.23)
		], 0.019, silver)

	# 5. Center hub and lug nuts
	var hub := cylinder(Vector3(x + side * 0.027, 0.36, axle), 0.057, 0.025, silver)
	hub.rotation.z = PI / 2.0

	for part in get_children().slice(first):
		part.set_meta("wheel_center", Vector3(side * 0.94, 0.36, axle))
		part.set_meta("wheel_spins", part != caliper)

func _quad(points: Array, material: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(points[index])
	st.generate_normals()
	mesh_node(st.commit(), Vector3.ZERO, material)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
