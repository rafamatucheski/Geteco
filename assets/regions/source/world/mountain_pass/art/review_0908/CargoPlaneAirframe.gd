extends RefCounted

## Acabamento estático da fuselagem. Cada material é uma malha por seção de corte;
## o lugar nativo é dono da colisão, das recompensas e da presença da câmera.
var plane: Node3D
var _surfaces: Dictionary = {}

func build(model: Node3D) -> void:
	plane = model
	_fuselage()
	_cockpit_and_nose()
	_wings()
	_engines()
	_tail()
	_cargo_details()
	_flush()

func _material(id: String) -> Material:
	return plane._materials[id]

func _surface(parent: Node3D, material: Material) -> SurfaceTool:
	if not _surfaces.has(parent):
		_surfaces[parent] = {}
	var material_surfaces: Dictionary = _surfaces[parent]
	if not material_surfaces.has(material):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		material_surfaces[material] = surface
	return material_surfaces[material]

func _triangle(parent: Node3D, material: Material, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var surface := _surface(parent, material)
	var normal := (c - a).cross(b - a).normalized()
	var vertices: Array[Vector3] = [a, b, c]
	if normal.dot(outward) < 0.0:
		vertices = [a, c, b]
		normal = -normal
	for vertex in vertices:
		surface.set_normal(normal)
		surface.set_uv(Vector2(vertex.z, vertex.y))
		surface.add_vertex(vertex)

func _quad(parent: Node3D, material: Material, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, double_sided := false) -> void:
	_triangle(parent, material, a, b, c, outward)
	_triangle(parent, material, a, c, d, outward)
	if double_sided:
		_triangle(parent, material, a, c, b, -outward)
		_triangle(parent, material, a, d, c, -outward)

func _prism(parent: Node3D, material: Material, polygon: Array[Vector3], depth: Vector3) -> void:
	var centre := Vector3.ZERO
	for point in polygon:
		centre += point
	centre /= float(polygon.size())
	for index in range(1, polygon.size() - 1):
		_triangle(parent, material, polygon[0], polygon[index], polygon[index + 1], -depth.normalized())
		_triangle(parent, material, polygon[0] + depth, polygon[index] + depth, polygon[index + 1] + depth, depth.normalized())
	for index in polygon.size():
		var next := (index + 1) % polygon.size()
		var outward: Vector3 = (polygon[index] + polygon[next]) * 0.5 - centre
		_quad(parent, material, polygon[index], polygon[next], polygon[next] + depth, polygon[index] + depth, outward)

func _skin(parent: Node3D, material: Material, profile: Array[Vector2], z_start: float, z_finish: float, side := 1.0) -> void:
	for index in profile.size() - 1:
		var first: Vector2 = profile[index]
		var second: Vector2 = profile[index + 1]
		var outward := Vector3(side * (second.y - first.y), -(second.x - first.x), 0)
		_quad(parent, material,
			Vector3(first.x * side, first.y, z_start), Vector3(first.x * side, first.y, z_finish),
			Vector3(second.x * side, second.y, z_finish), Vector3(second.x * side, second.y, z_start), outward, true)

func _roof_skin(parent: Node3D, material: Material, profile: Array[Vector2], z_start: float, z_finish: float) -> void:
	for index in profile.size() - 1:
		var first: Vector2 = profile[index]
		var second: Vector2 = profile[index + 1]
		_quad(parent, material, Vector3(first.x, first.y, z_start), Vector3(first.x, first.y, z_finish),
			Vector3(second.x, second.y, z_finish), Vector3(second.x, second.y, z_start), Vector3.UP, true)

func _fuselage() -> void:
	var paint := _material("fuselage")
	var belly := _material("belly")
	var snow := _material("snow")
	var seam: Material = plane._mat("airframe_seam", Color("364139"), 0.82, 0.22)
	var exposed: Material = plane._mat("exposed_alloy", Color("a4aba8"), 0.65, 0.50)
	for side in [-1.0, 1.0]:
		var shell: Node3D = plane.port_shell if side < 0 else plane.starboard_shell
		# O peitoril inferior continua visível quando a pele superior é cortada.
		_skin(plane, belly, [Vector2(1.43, 0.06), Vector2(1.60, 0.23), Vector2(1.66, 0.60)], -9.0, 6.5, side)
		_skin(shell, paint, [Vector2(1.66, 0.60), Vector2(1.66, 1.53), Vector2(1.62, 2.08), Vector2(1.43, 2.42)], -9.0, 6.5, side)
		plane._add_box_to(shell, Vector3(side * 1.678, 1.61, -1.25), Vector3(0.012, 0.19, 15.35), _material("tactical_stripe"))
		for index in 9:
			var z := -8.48 + float(index) * 1.80
			plane._add_box_to(shell, Vector3(side * 1.682, 1.15, z), Vector3(0.008, 1.15, 0.018), seam)
			for y in [0.71, 1.16, 1.88]:
				plane._add_cyl_to(shell, Vector3(side * 1.69, y, z), 0.026, 0.012, exposed, Vector3(0, 0, 90))
		# Uneven exposed strips show a worn aircraft without floating signage.
		for index in 5:
			var z := -7.30 + float(index) * 2.75
			plane._add_box_to(shell, Vector3(side * 1.68, 0.86 + float(index % 2) * 0.32, z), Vector3(0.008, 0.045, 0.45 + float(index % 3) * 0.12), exposed, Vector3(7 + index * 3, 0, 0))
		_cobra_insignia(shell, side)
	_roof_skin(plane.cutaway_roof, paint, [Vector2(-1.43, 2.42), Vector2(-1.02, 2.80), Vector2(-0.48, 3.02), Vector2(0.48, 3.02), Vector2(1.02, 2.80), Vector2(1.43, 2.42)], -9.0, 6.5)
	_roof_skin(plane.cutaway_roof, snow, [Vector2(-1.02, 2.85), Vector2(-0.47, 3.075), Vector2(0.47, 3.075), Vector2(1.02, 2.85)], -8.70, 6.15)
	# Carenagem arredondada na raiz da asa, em vez de uma caixa retangular sólida no teto.
	_roof_skin(plane.cutaway_roof, paint, [Vector2(-1.69, 2.65), Vector2(-1.19, 3.05), Vector2(-0.68, 3.20), Vector2(0.68, 3.20), Vector2(1.19, 3.05), Vector2(1.69, 2.65)], -4.85, -2.05)

func _cobra_insignia(shell: Node3D, side: float) -> void:
	var ink: Material = plane._mat("cobra_insignia", Color("d0b16b"), 0.90)
	var points: Array[Vector2] = [Vector2(-0.25, -0.25), Vector2(-0.32, -0.10), Vector2(-0.19, 0.03), Vector2(0.10, 0.03), Vector2(0.24, 0.18), Vector2(0.16, 0.33), Vector2(-0.05, 0.34)]
	for index in points.size() - 1:
		var first: Vector2 = points[index]
		var second: Vector2 = points[index + 1]
		var centre: Vector2 = (first + second) * 0.5
		var difference: Vector2 = second - first
		plane._add_box_to(shell, Vector3(side * 1.686, 1.11 + centre.y, 4.25 + centre.x), Vector3(0.012, 0.045, difference.length() + 0.02), ink, Vector3(-rad_to_deg(atan2(difference.y, difference.x)), 0, 0))
	# A flared hood makes the graphic readable as a cobra from either flank.
	var x: float = side * 1.69
	_quad(shell, ink, Vector3(x, 1.34, 4.13), Vector3(x, 1.52, 4.08), Vector3(x, 1.57, 4.22), Vector3(x, 1.40, 4.29), Vector3(side, 0, 0), true)

func _cockpit_and_nose() -> void:
	var paint := _material("fuselage")
	var roof: Node3D = plane.cutaway_roof
	var glass := _material("cockpit_glass")
	var frame := _material("interior_rib")
	var radome: Material = plane._mat("radome", Color("272c29"), 0.70)
	for side in [-1.0, 1.0]:
		var shell: Node3D = plane.port_shell if side < 0 else plane.starboard_shell
		_skin(plane, _material("belly"), [Vector2(1.43, 0.40), Vector2(1.61, 0.65)], -13.35, -9.0, side)
		_skin(shell, paint, [Vector2(1.61, 0.65), Vector2(1.66, 1.53), Vector2(1.52, 2.03)], -13.35, -9.0, side)
		var x: float = side * 1.525
		_quad(shell, glass, Vector3(x, 1.96, -13.14), Vector3(x, 1.96, -11.76), Vector3(side * 1.19, 2.45, -11.91), Vector3(side * 1.13, 2.42, -13.17), Vector3(side, 1, 0), true)
		plane._add_box_to(shell, Vector3(side * 1.53, 1.95, -12.44), Vector3(0.06, 0.07, 1.51), frame)
		plane._add_box_to(shell, Vector3(side * 1.35, 2.21, -12.45), Vector3(0.08, 0.59, 0.07), frame, Vector3(0, 0, side * 35))
	_roof_skin(roof, paint, [Vector2(-1.52, 2.03), Vector2(-1.08, 2.48), Vector2(-0.40, 2.67), Vector2(0.40, 2.67), Vector2(1.08, 2.48), Vector2(1.52, 2.03)], -11.75, -9.0)
	_roof_skin(roof, paint, [Vector2(-1.13, 2.42), Vector2(-0.40, 2.67), Vector2(0.40, 2.67), Vector2(1.13, 2.42)], -13.17, -11.75)
	_roof_skin(roof, _material("snow"), [Vector2(-0.94, 2.54), Vector2(-0.39, 2.71), Vector2(0.39, 2.71), Vector2(0.94, 2.54)], -12.93, -9.18)
	for side in [-1.0, 1.0]:
		_quad(roof, glass, Vector3(side * 0.07, 1.77, -14.04), Vector3(side * 0.86, 1.77, -14.04), Vector3(side * 1.13, 2.42, -13.17), Vector3(side * 0.07, 2.64, -13.17), Vector3(0, 1, -1), true)
	plane._add_box_to(roof, Vector3(0, 2.21, -13.60), Vector3(0.10, 0.10, 1.27), frame, Vector3(43, 0, 0))
	# A barriga baixa fica fixa. Todas as seções superiores do nariz compartilham o corte do teto,
	# incluindo o cone do radar, para que uma câmera ao norte veja dentro da cabine.
	var sections: Array[Vector4] = [Vector4(-13.35, 1.10, 1.55, 0.92), Vector4(-14.12, 1.09, 1.09, 0.88), Vector4(-15.04, 1.03, 0.88, 0.76), Vector4(-15.92, 0.97, 0.49, 0.47), Vector4(-16.50, 0.95, 0.035, 0.04)]
	for section in sections.size() - 1:
		for ring in 16:
			var a := TAU * float(ring) / 16.0
			var b := TAU * float(ring + 1) / 16.0
			var average := (a + b) * 0.5
			var parent: Node3D = plane if sin(average) < -0.58 else roof
			var material: Material = radome if section > 1 else paint
			_quad(parent, material, _ring(sections[section], a), _ring(sections[section + 1], a), _ring(sections[section + 1], b), _ring(sections[section], b), Vector3(cos(average), sin(average), -0.2), true)
	# Pequenos mostradores e manetes ficam dentro da colisão do painel de instrumentos.
	for side in [-1.0, 1.0]:
		for index in 3:
			plane._add_cyl_to(plane, Vector3(side * (0.37 + index * 0.18), 1.32, -12.301), 0.060, 0.012, glass, Vector3(90, 0, 0))
		plane._add_box_to(plane, Vector3(side * 0.12, 1.39, -12.43), Vector3(0.025, 0.17, 0.05), frame, Vector3(12, 0, 0))

func _ring(section: Vector4, angle: float) -> Vector3:
	return Vector3(cos(angle) * section.z, section.y + sin(angle) * section.w, section.x)

func _wings() -> void:
	var paint := _material("fuselage")
	var snow := _material("snow")
	var seam := _material("airframe_seam")
	_prism(plane, paint, [Vector3(1.65, 2.90, -4.90), Vector3(14.00, 3.64, -4.09), Vector3(14.00, 3.64, -2.62), Vector3(1.65, 2.90, -2.10)], Vector3(0, 0.30, 0))
	_prism(plane, snow, [Vector3(1.83, 3.23, -4.68), Vector3(13.68, 3.965, -3.96), Vector3(13.58, 3.96, -2.80), Vector3(1.83, 3.23, -2.31)], Vector3(0, 0.045, 0))
	# O painel externo de bombordo se partiu da longarina e está caído no gelo.
	_prism(plane, paint, [Vector3(-1.65, 2.64, -4.90), Vector3(-9.28, 1.76, -4.44), Vector3(-9.17, 1.76, -2.63), Vector3(-1.65, 2.64, -2.10)], Vector3(0, 0.30, 0))
	_prism(plane, snow, [Vector3(-1.86, 2.96, -4.70), Vector3(-9.09, 2.095, -4.23), Vector3(-8.91, 2.095, -2.82), Vector3(-1.86, 2.96, -2.31)], Vector3(0, 0.045, 0))
	_prism(plane, paint, [Vector3(-9.65, 1.95, -4.48), Vector3(-14.10, 0.23, -4.07), Vector3(-14.10, 0.23, -2.75), Vector3(-9.54, 1.95, -2.59)], Vector3(0, 0.25, 0))
	_prism(plane, snow, [Vector3(-9.78, 2.23, -4.30), Vector3(-13.88, 0.61, -3.93), Vector3(-13.85, 0.61, -2.90), Vector3(-9.74, 2.23, -2.76)], Vector3(0, 0.055, 0))
	# Exposed jagged spar ends stay within the existing wing footprint.
	for index in 4:
		var z := -4.13 + index * 0.39
		plane._add_box_to(plane, Vector3(-9.44, 1.91, z), Vector3(0.61, 0.075, 0.085), _material("exposed_alloy"), Vector3(0, 4 + index * 9, -7))
	for side in [-1.0, 1.0]:
		var root_y := 2.915 if side > 0 else 2.66
		var tip_y := 3.66 if side > 0 else 1.82
		var length := 12.15 if side > 0 else 7.50
		var line: Array[Vector3] = [Vector3(side * 1.72, root_y + 0.31, -2.58), Vector3(side * (1.72 + length), tip_y + 0.31, -2.91), Vector3(side * (1.72 + length), tip_y + 0.31, -2.945), Vector3(side * 1.72, root_y + 0.31, -2.615)]
		_prism(plane, seam, line, Vector3(0, 0.012, 0))

func _engines() -> void:
	var coords: Array[Vector3] = [Vector3(-4.2, 2.60, -4.8), Vector3(-8.2, 1.85, -4.8), Vector3(4.2, 3.05, -4.8), Vector3(8.8, 3.35, -4.8)]
	for index in coords.size():
		var centre: Vector3 = coords[index]
		var broken := index == 1
		var sections: Array[Vector2] = [Vector2(-1.35, 0.45), Vector2(-0.94, 0.56), Vector2(0.64, 0.55), Vector2(1.38, 0.34)]
		for section in sections.size() - 1:
			for ring in 16:
				var a := TAU * float(ring) / 16.0
				var b := TAU * float(ring + 1) / 16.0
				var average := (a + b) * 0.5
				var material := _material("belly") if sin(average) < -0.1 else _material("fuselage")
				_quad(plane, material, _nacelle_point(centre, sections[section], a), _nacelle_point(centre, sections[section + 1], a), _nacelle_point(centre, sections[section + 1], b), _nacelle_point(centre, sections[section], b), Vector3(cos(average), sin(average), 0))
		plane._add_cyl_to(plane, centre + Vector3(0, 0, -1.355), 0.42, 0.035, _material("engine_cowling"), Vector3(90, 0, 0))
		plane._add_cyl_to(plane, centre + Vector3(0.21, 0.20, 0.86), 0.13, 0.58, _material("engine_cowling"), Vector3(79, 0, 0))
		for ring in 16:
			var a := TAU * float(ring) / 16.0
			var b := TAU * float(ring + 1) / 16.0
			_quad(plane, _material("exposed_alloy"), centre + Vector3(cos(a) * 0.455, sin(a) * 0.455, -1.375), centre + Vector3(cos(b) * 0.455, sin(b) * 0.455, -1.375), centre + Vector3(cos(b) * 0.388, sin(b) * 0.388, -1.375), centre + Vector3(cos(a) * 0.388, sin(a) * 0.388, -1.375), Vector3.FORWARD)
			_triangle(plane, _material("prop_spinner"), centre + Vector3(cos(a) * 0.26, sin(a) * 0.26, -1.46), centre + Vector3(cos(b) * 0.26, sin(b) * 0.26, -1.46), centre + Vector3(0, 0, -1.91), Vector3(cos((a + b) * 0.5), sin((a + b) * 0.5), -1))
		for blade in 4:
			if broken and blade == 2:
				continue
			_propeller_blade(centre, blade, broken)
		if broken:
			plane._add_box_to(plane, centre + Vector3(0, 0.52, 0.05), Vector3(0.75, 0.11, 1.45), _material("snow"), Vector3(0, 0, -8))

func _nacelle_point(centre: Vector3, section: Vector2, angle: float) -> Vector3:
	return centre + Vector3(cos(angle) * section.y, sin(angle) * section.y, section.x)

func _propeller_blade(centre: Vector3, blade: int, broken: bool) -> void:
	var angle := deg_to_rad(28.0 + float(blade) * 90.0)
	var length := 0.64 if broken and blade == 1 else 1.10
	var twist := 0.17 if broken else 0.025
	var outline: Array[Vector3] = [Vector3(-0.06, 0.20, -1.52), Vector3(0.08, 0.25, -1.52), Vector3(0.14, length * 0.78, -1.52 - twist), Vector3(0.07, length, -1.52 - twist), Vector3(-0.12, length * 0.98, -1.52 - twist)]
	var polygon: Array[Vector3] = []
	for point in outline:
		polygon.append(centre + Vector3(point.x * cos(angle) - point.y * sin(angle), point.x * sin(angle) + point.y * cos(angle), point.z))
	_prism(plane, _material("prop_spinner"), polygon, Vector3(0, 0, 0.045))
	if not broken:
		plane._add_box_to(plane, centre + Vector3(-sin(angle) * 0.998, cos(angle) * 0.998, -1.565), Vector3(0.18, 0.17, 0.012), _material("prop_tip"), Vector3(0, 0, rad_to_deg(angle)))

func _tail() -> void:
	var roof: Node3D = plane.cutaway_roof
	var paint := _material("fuselage")
	var snow := _material("snow")
	var seam := _material("airframe_seam")
	# A cauda oca sobe sobre a rampa aberta; nenhuma caixa sólida enche a porta.
	for side in [-1.0, 1.0]:
		_quad(roof, paint, Vector3(side * 1.43, 2.42, 6.5), Vector3(side * 0.40, 3.36, 10.30), Vector3(side * 0.33, 3.89, 10.30), Vector3(side * 0.97, 3.04, 6.5), Vector3(side, 0.6, 0), true)
	_quad(roof, paint, Vector3(-0.97, 3.04, 6.5), Vector3(-0.33, 3.89, 10.30), Vector3(0.33, 3.89, 10.30), Vector3(0.97, 3.04, 6.5), Vector3.UP, true)
	_prism(roof, paint, [Vector3(-0.14, 2.89, 6.70), Vector3(-0.14, 7.08, 8.02), Vector3(-0.14, 7.08, 9.19), Vector3(-0.14, 3.45, 10.28)], Vector3(0.28, 0, 0))
	_prism(roof, seam, [Vector3(-0.147, 3.53, 9.83), Vector3(-0.147, 6.98, 8.95), Vector3(-0.147, 6.98, 9.18), Vector3(-0.147, 3.53, 10.12)], Vector3(0.294, 0, 0))
	_prism(roof, paint, [Vector3(-4.6, 6.81, 8.73), Vector3(-0.4, 6.81, 7.57), Vector3(0.4, 6.81, 7.57), Vector3(4.6, 6.81, 8.73), Vector3(4.6, 6.81, 9.73), Vector3(-4.6, 6.81, 9.73)], Vector3(0, 0.20, 0))
	_prism(roof, snow, [Vector3(-4.38, 7.045, 8.83), Vector3(-0.34, 7.045, 7.78), Vector3(0.34, 7.045, 7.78), Vector3(4.38, 7.045, 8.83), Vector3(4.38, 7.045, 9.54), Vector3(-4.38, 7.045, 9.54)], Vector3(0, 0.045, 0))
	# As dobradiças do leme e as linhas de corte do profundor são largas o bastante para a vista de gameplay.
	for y in [4.05, 5.19, 6.29]:
		plane._add_box_to(roof, Vector3(0, y, 10.12 - (y - 3.53) * 0.255), Vector3(0.33, 0.09, 0.12), _material("exposed_alloy"))
	plane._add_box_to(roof, Vector3(0, 7.098, 9.22), Vector3(8.79, 0.015, 0.04), seam)

func _cargo_details() -> void:
	var alloy := _material("rollers")
	var dark := _material("airframe_seam")
	# Roletes e pontos de amarração rentes ficam sobre o mesmo convés caminhável.
	for index in 30:
		var z := -8.62 + index * 0.50
		for x in [-0.65, 0.65]:
			plane._add_cyl_to(plane, Vector3(x, 0.219, z), 0.024, 0.30, alloy, Vector3(0, 0, 90))
	for index in 9:
		var z := -8.48 + index * 1.80
		for x in [-1.19, 1.19]:
			plane._add_cyl_to(plane, Vector3(x, 0.213, z), 0.06, 0.011, dark)
			plane._add_cyl_to(plane, Vector3(x, 0.220, z), 0.035, 0.007, alloy)
	for index in 8:
		var z := 6.62 + index * 0.38
		for side in [-1.0, 1.0]:
			plane._add_box_to(plane, Vector3(side * 1.14, 0.18 - (z - 6.62) * 0.061, z), Vector3(0.08, 0.012, 0.18), _material("hazard_yellow") if index % 2 == 0 else dark, Vector3(3.5, 0, 0))
	# As tampas de ripa e as cintas laterais ficam dentro dos dois sólidos de carga autorais.
	for cargo_z in [-3.2, 2.55]:
		var top_y := 1.445 if cargo_z < 0 else 0.912
		for z_offset in [-0.42, 0.0, 0.42]:
			plane._add_box_to(plane, Vector3(-0.95, top_y, cargo_z + z_offset), Vector3(0.54, 0.035, 0.055), _material("crate_metal"))
		for z_offset in [-0.43, 0.43]:
			plane._add_box_to(plane, Vector3(-0.66, (top_y + 0.21) * 0.5, cargo_z + z_offset), Vector3(0.018, top_y - 0.21, 0.055), dark)

func _flush() -> void:
	for parent_key in _surfaces:
		var parent := parent_key as Node3D
		var material_surfaces: Dictionary = _surfaces[parent]
		for material_key in material_surfaces:
			var material := material_key as Material
			var surface: SurfaceTool = material_surfaces[material_key]
			surface.index()
			var part := MeshInstance3D.new()
			part.name = "Airframe_%s" % material.resource_name
			part.mesh = surface.commit()
			part.material_override = material
			parent.add_child(part)
	_surfaces.clear()
