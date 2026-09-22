extends RefCounted
## Malhas procedurais dos adereços urbanos (mobiliário, telhado, chão).
##
## Cada tipo vira UMA ArrayMesh com cor por vértice, montada uma vez e
## reutilizada em MultiMesh por chunk: centenas de hidrantes/lixeiras custam
## um draw call por tipo por chunk, não um por objeto. Medidas em metros,
## origem no chão, frente do objeto para +Z.

static var _meshes := {}
static var _material: StandardMaterial3D


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.82
	return _material


static func mesh(kind: String) -> ArrayMesh:
	if _meshes.has(kind): return _meshes[kind]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Normais facetadas: sem isso o generate_normals suaviza as quinas das
	# caixas e tudo fica com cara de sabonete.
	tool.set_smooth_group(-1)
	match kind:
		"hydrant": _hydrant(tool)
		"trash_can": _trash_can(tool)
		"news_box": _news_box(tool)
		"mailbox": _mailbox(tool)
		"phone_booth": _phone_booth(tool)
		"dumpster": _dumpster(tool)
		"trash_bags": _trash_bags(tool)
		"bollard": _bollard(tool)
		"signal_pole": _signal_pole(tool)
		"stop_sign": _stop_sign(tool)
		"ac_unit": _ac_unit(tool)
		"vent": _vent(tool)
		"antenna": _antenna(tool)
		"dish": _dish(tool)
		"roof_hatch": _roof_hatch(tool)
		"pipe_run": _pipe_run(tool)
		"billboard_frame": _billboard_frame(tool)
		"manhole": _manhole(tool)
		"drain": _drain(tool)
		"bench_seat": _bench_seat(tool)
		"planter": _planter(tool)
		_: preload("res://world/city_look/BuildingLifeKit.gd").build(kind, tool)
	tool.generate_normals()
	var result := tool.commit()
	_meshes[kind] = result
	return result


# --- Primitivas ---

static func box(tool: SurfaceTool, center: Vector3, size: Vector3, color: Color, yaw := 0.0) -> void:
	var h := size * 0.5
	var basis := Basis(Vector3.UP, yaw)
	var corners := []
	for i in 8:
		var local := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(center + basis * local)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	tool.set_color(color)
	for face in faces:
		var a: Vector3 = corners[face[0]]
		var b: Vector3 = corners[face[1]]
		var c: Vector3 = corners[face[2]]
		var d: Vector3 = corners[face[3]]
		# Ordem conferida com generate_normals: normal para fora.
		tool.add_vertex(a); tool.add_vertex(b); tool.add_vertex(c)
		tool.add_vertex(a); tool.add_vertex(c); tool.add_vertex(d)


static func cylinder(tool: SurfaceTool, base: Vector3, radius: float, height: float, color: Color, sides := 8, top_radius := -1.0) -> void:
	var top := radius if top_radius < 0.0 else top_radius
	tool.set_color(color)
	for i in sides:
		var a0 := TAU * float(i) / sides
		var a1 := TAU * float(i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := base + d0 * radius
		var b1 := base + d1 * radius
		var t0 := base + d0 * top + Vector3.UP * height
		var t1 := base + d1 * top + Vector3.UP * height
		tool.add_vertex(b0); tool.add_vertex(b1); tool.add_vertex(t0)
		tool.add_vertex(b1); tool.add_vertex(t1); tool.add_vertex(t0)
		var cap := base + Vector3.UP * height
		tool.add_vertex(cap); tool.add_vertex(t0); tool.add_vertex(t1)


# --- Mobiliário de calçada ---

static func _hydrant(t: SurfaceTool) -> void:
	var red := Color("b8322a")
	cylinder(t, Vector3.ZERO, .17, .08, Color("7c2520"), 6)
	cylinder(t, Vector3(0, .08, 0), .12, .5, red, 6)
	cylinder(t, Vector3(0, .58, 0), .14, .08, red, 6, .06)
	box(t, Vector3(0, .38, 0), Vector3(.42, .09, .09), Color("d8c24a"))
	box(t, Vector3(0, .38, .12), Vector3(.09, .09, .1), Color("d8c24a"))


static func _trash_can(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .26, .82, Color("2f5a43"), 7, .29)
	cylinder(t, Vector3(0, .82, 0), .31, .06, Color("1f3a2c"), 7)
	cylinder(t, Vector3(0, .88, 0), .22, .05, Color("16261e"), 7)


static func _news_box(t: SurfaceTool) -> void:
	box(t, Vector3(-.26, .55, 0), Vector3(.46, .75, .42), Color("c63a2f"))
	box(t, Vector3(-.26, .72, .215), Vector3(.36, .22, .02), Color("dfe7e8"))
	box(t, Vector3(.26, .55, 0), Vector3(.46, .75, .42), Color("2d6fb6"))
	box(t, Vector3(.26, .72, .215), Vector3(.36, .22, .02), Color("dfe7e8"))
	for x in [-.44, -.08, .08, .44]: box(t, Vector3(x, .09, 0), Vector3(.04, .18, .36), Color("2a2e30"))


static func _mailbox(t: SurfaceTool) -> void:
	box(t, Vector3(0, .1, 0), Vector3(.5, .2, .44), Color("1d2a55"))
	box(t, Vector3(0, .62, 0), Vector3(.5, .84, .44), Color("27418a"))
	box(t, Vector3(0, 1.08, 0), Vector3(.46, .12, .4), Color("27418a"))
	box(t, Vector3(0, .9, .225), Vector3(.3, .05, .02), Color("0f152b"))
	box(t, Vector3(0, .6, .225), Vector3(.26, .14, .02), Color("e6e2d4"))


static func _phone_booth(t: SurfaceTool) -> void:
	box(t, Vector3(0, .06, 0), Vector3(.9, .12, .9), Color("5b6063"))
	for x in [-.41, .41]: box(t, Vector3(x, 1.15, 0), Vector3(.08, 2.1, .9), Color("8a9396"))
	box(t, Vector3(0, 1.15, -.41), Vector3(.9, 2.1, .08), Color("8a9396"))
	box(t, Vector3(0, 2.26, 0), Vector3(.98, .16, .98), Color("c9a634"))
	box(t, Vector3(0, 1.25, -.34), Vector3(.34, .5, .1), Color("2c3134"))
	box(t, Vector3(0, 2.26, .5), Vector3(.7, .12, .02), Color("f3efe0"))


static func _dumpster(t: SurfaceTool) -> void:
	var body := Color("2f6b4f")
	box(t, Vector3(0, .62, 0), Vector3(1.9, 1.05, 1.1), body)
	box(t, Vector3(0, 1.17, -.05), Vector3(1.95, .08, 1.2), Color("24523c"), 0.0)
	box(t, Vector3(0, .9, .56), Vector3(1.7, .1, .04), Color("1c3c2d"))
	for x in [-.8, .8]:
		for z in [-.45, .45]: cylinder(t, Vector3(x, 0, z), .07, .1, Color("222"))
	box(t, Vector3(.95, .7, 0), Vector3(.06, .14, .9), Color("1c3c2d"))


static func _trash_bags(t: SurfaceTool) -> void:
	var bag := Color("1d1f22")
	cylinder(t, Vector3(0, 0, 0), .28, .5, bag, 7, .12)
	cylinder(t, Vector3(.42, 0, .12), .24, .42, Color("26292c"), 7, .1)
	cylinder(t, Vector3(.18, 0, -.34), .22, .38, Color("3f4a2e"), 7, .1)
	box(t, Vector3(-.4, .16, .2), Vector3(.4, .32, .34), Color("9a7d55"), .4)


static func _bollard(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .11, .85, Color("2e3336"), 8)
	cylinder(t, Vector3(0, .62, 0), .115, .1, Color("d6b43c"), 8)


static func _bench_seat(t: SurfaceTool) -> void:
	for x in [-.7, .7]: box(t, Vector3(x, .22, 0), Vector3(.08, .44, .44), Color("2c3134"))
	box(t, Vector3(0, .46, 0), Vector3(1.7, .06, .44), Color("7a5a3a"))
	box(t, Vector3(0, .78, -.2), Vector3(1.7, .3, .05), Color("7a5a3a"))


static func _planter(t: SurfaceTool) -> void:
	box(t, Vector3(0, .25, 0), Vector3(1.1, .5, 1.1), Color("9a948a"))
	box(t, Vector3(0, .52, 0), Vector3(.94, .06, .94), Color("4a3a2a"))
	cylinder(t, Vector3(0, .5, 0), .42, .5, Color("46703f"), 7, .12)


# --- Sinalização viária ---

## Poste de semáforo com braço sobre a via. Braço para -X; a cabeça do sinal
## fica separada (malha emissiva que pisca) e é posicionada pelo chamador.
static func _signal_pole(t: SurfaceTool) -> void:
	var metal := Color("2d3437")
	cylinder(t, Vector3.ZERO, .16, .3, Color("3c4447"), 8)
	cylinder(t, Vector3.ZERO, .09, 5.2, metal, 8)
	box(t, Vector3(-2.1, 5.05, 0), Vector3(4.2, .1, .1), metal)
	box(t, Vector3(-.5, 4.75, 0), Vector3(1.0, .06, .06), metal, 0.0)
	# Caixa do sinal pendurada no braço (as lentes vêm do CityChunkDressing).
	box(t, Vector3(-3.3, 4.55, 0), Vector3(.36, 1.0, .3), Color("1f2426"))
	box(t, Vector3(-3.3, 4.55, .17), Vector3(.5, 1.14, .04), Color("15191a"))
	# Placa de nome de rua (verde, padrão americano do Harbor).
	box(t, Vector3(.0, 3.2, 0), Vector3(1.3, .26, .03), Color("1f6b3e"))
	box(t, Vector3(.0, 3.2, 0), Vector3(1.22, .18, .035), Color("2a8a50"))
	# Botoeira de pedestre.
	box(t, Vector3(.13, 1.1, 0), Vector3(.1, .2, .12), Color("c9a634"))


static func _stop_sign(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .04, 2.2, Color("8a9396"), 6)
	# Octógono aproximado por quatro barras giradas em 45°.
	var red := Color("c0231e")
	var face_z := .05
	for i in 4:
		var angle := PI / 4.0 * i
		var basis := Basis(Vector3.FORWARD, angle)
		var center := Vector3(0, 2.2, face_z)
		var size := Vector3(.72, .3, .03)
		_rotated_box(t, center, size, red, basis)
	box(t, Vector3(0, 2.2, face_z + .02), Vector3(.5, .1, .01), Color("f4f1e8"))


static func _rotated_box(t: SurfaceTool, center: Vector3, size: Vector3, color: Color, basis: Basis) -> void:
	var h := size * 0.5
	var corners := []
	for i in 8:
		var local := Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z)
		corners.append(center + basis * local)
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	t.set_color(color)
	for face in faces:
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[1]]); t.add_vertex(corners[face[2]])
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[2]]); t.add_vertex(corners[face[3]])


# --- Telhado ---

static func _ac_unit(t: SurfaceTool) -> void:
	box(t, Vector3(0, .05, 0), Vector3(1.3, .1, 1.0), Color("5a5f61"))
	box(t, Vector3(0, .45, 0), Vector3(1.2, .7, .9), Color("b9bdb8"))
	box(t, Vector3(.61, .45, 0), Vector3(.02, .5, .7), Color("6c7274"))
	cylinder(t, Vector3(-.2, .8, 0), .3, .04, Color("3a3f41"), 10)
	box(t, Vector3(-.2, .85, 0), Vector3(.5, .02, .06), Color("8a8f90"))


static func _vent(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .16, .7, Color("9aa0a2"), 8)
	cylinder(t, Vector3(0, .7, 0), .3, .1, Color("7e8486"), 8, .08)


static func _antenna(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .04, 2.6, Color("5a6063"), 5)
	for y in [1.6, 2.0, 2.35]: box(t, Vector3(0, y, 0), Vector3(1.0 - (y - 1.6) * .6, .03, .03), Color("5a6063"))


static func _dish(t: SurfaceTool) -> void:
	box(t, Vector3(0, .3, 0), Vector3(.08, .6, .08), Color("6c7274"))
	cylinder(t, Vector3(0, .5, .05), .05, .06, Color("dfe0dc"), 10, .42)


static func _roof_hatch(t: SurfaceTool) -> void:
	box(t, Vector3(0, .2, 0), Vector3(1.0, .4, 1.0), Color("7d8284"))
	box(t, Vector3(0, .43, 0), Vector3(.9, .06, .9), Color("4b5052"))


static func _pipe_run(t: SurfaceTool) -> void:
	for x in [-.12, .12]: box(t, Vector3(x, .14, 0), Vector3(.12, .12, 4.0), Color("8f5a3a"))
	for z in [-1.8, 0.0, 1.8]: box(t, Vector3(0, .05, z), Vector3(.5, .1, .12), Color("4b5052"))


## Estrutura de outdoor de telhado: dois pés e passarela. O painel com a marca
## é montado por cima pelo CityChunkDressing (material/texto por marca).
static func _billboard_frame(t: SurfaceTool) -> void:
	var steel := Color("3a4043")
	for x in [-2.4, 2.4]:
		box(t, Vector3(x, 1.2, 0), Vector3(.14, 2.4, .14), steel)
		box(t, Vector3(x, 1.0, -.8), Vector3(.1, 2.0, .1), steel)
		box(t, Vector3(x, 1.2, -.4), Vector3(.06, .06, .9), steel)
	box(t, Vector3(0, 1.2, .18), Vector3(5.4, .06, .5), Color("2a2f31"))
	box(t, Vector3(0, 2.4, 0), Vector3(6.2, 3.1, .12), Color("1d2123"))
	# Três refletores voltados para o painel.
	for x in [-2.0, 0.0, 2.0]: box(t, Vector3(x, 1.28, .5), Vector3(.2, .14, .2), Color("55595b"))


# --- Chão ---

static func _manhole(t: SurfaceTool) -> void:
	cylinder(t, Vector3.ZERO, .42, .015, Color("2a2c2c"), 10)
	cylinder(t, Vector3(0, .0, 0), .34, .02, Color("3d403f"), 10)
	for z in [-.16, 0.0, .16]: box(t, Vector3(0, .02, z), Vector3(.5, .006, .05), Color("2a2c2c"))


static func _drain(t: SurfaceTool) -> void:
	box(t, Vector3(0, .008, 0), Vector3(.9, .016, .4), Color("2c2f30"))
	for x in [-.3, -.15, 0.0, .15, .3]: box(t, Vector3(x, .018, 0), Vector3(.06, .006, .34), Color("111314"))
