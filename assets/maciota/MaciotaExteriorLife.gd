extends RefCounted
## Static, collision-free dressing for Maciota's authored street facade.
## The existing shell and piers remain the only ground-level solids.

const KIT := preload("res://world/city_look/CityPropKit.gd")
const CITY_MATERIALS := preload("res://world/city_look/CityLookMaterials.gd")
const FONT := preload("res://assets/Barlow.ttf")

const IRON := Color("202d31")
const STEEL := Color("52666a")
const BRASS := Color("d6a74d")
const CREAM := Color("dfd4bd")
# Identidade da oficina (28/09/2026): a fachada só em grafite e latão lia como
# prédio qualquer, "pobrinho" para o lugar mais importante do jogo. Vermelho de
# corrida, quadriculado e neon laranja dão a marca; nada disso toca o chão.
const RACING_RED := Color("b8392a")
const CHECK_DARK := Color("1b2124")
const NEON_ORANGE := Color("ff7a2e")
const FACE := 7.8125
const WEST_WALL := -5.9
const TOTEM_X := -5.45
const TOTEM_Y := 4.95
const TOTEM_Z := FACE + .32


static func build(facade: Node3D) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_smooth_group(-1)
	_build_static_geometry(tool)
	_build_brand(tool)
	tool.generate_normals()
	var detail := MeshInstance3D.new()
	detail.name = "MaciotaExteriorDetails"
	detail.mesh = tool.commit()
	detail.material_override = KIT.material()
	detail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	facade.add_child(detail)
	_build_name(facade)
	_build_work_lamps(facade)
	_build_neon(facade)
	_build_blade_letters(facade)


## Faixa quadriculada: `count` casas por linha, duas linhas, no plano XY (`axis`
## = "x") ou ZY (`axis` = "z") a partir de `origin` (canto inferior).
static func _checker(t: SurfaceTool, origin: Vector3, count: int, cell: float, axis: String, depth: float) -> void:
	for row in 2:
		for index in count:
			var color := CHECK_DARK if (index + row) % 2 == 0 else CREAM
			var along := (index + .5) * cell
			var center := origin + Vector3(along, (row + .5) * cell, 0) if axis == "x" else origin + Vector3(0, (row + .5) * cell, along)
			var size := Vector3(cell, cell, depth) if axis == "x" else Vector3(depth, cell, cell)
			KIT.box(t, center, size, color)


static func _build_brand(t: SurfaceTool) -> void:
	# Parapeito frontal: faixa quadriculada inteira sob o friso de latão.
	_checker(t, Vector3(-5.96, 4.57, FACE - .06 + .17), 27, .15, "x", .03)
	# Pilares em vermelho com friso creme (sobre a alvenaria, acima da cintura).
	for x in [-5.45, 1.45]:
		KIT.box(t, Vector3(x, 1.95, FACE + .035), Vector3(.72, 1.7, .03), RACING_RED)
		KIT.box(t, Vector3(x, 1.95, FACE + .052), Vector3(.12, 1.7, .012), CREAM)
	# Toldo com lona vermelha por cima da estrutura de aço.
	KIT.box(t, Vector3(-2.0, 3.49, 8.06), Vector3(6.5, .03, .62), RACING_RED)
	# Telhado: duas faixas de corrida no sentido do comprimento, entre as nervuras
	# da claraboia (a câmera vê o telhado inteiro de cima).
	for x in [.25, .7]:
		KIT.box(t, Vector3(x, 4.545, 4.69), Vector3(.28, .012, 6.0), RACING_RED if x < .5 else CREAM)
	# Parede lateral oeste (a que a câmera enxerga): mural com faixa vermelha,
	# quadriculado e emblema de roda.
	KIT.box(t, Vector3(WEST_WALL - .02, 2.55, 4.7), Vector3(.03, .75, 5.9), RACING_RED)
	KIT.box(t, Vector3(WEST_WALL - .03, 2.12, 4.7), Vector3(.02, .06, 5.9), CREAM)
	_checker(t, Vector3(WEST_WALL - .025, 3.02, 1.8), 39, .15, "z", .02)
	for ring in [[.95, CHECK_DARK], [.72, STEEL], [.3, BRASS]]:
		KIT.box(t, Vector3(WEST_WALL - .04 - (1.0 - ring[0]) * .02, 1.25, 3.2), Vector3(.02, ring[0] * 1.2, ring[0] * 1.2), ring[1], PI * .25)
		KIT.box(t, Vector3(WEST_WALL - .041 - (1.0 - ring[0]) * .02, 1.25, 3.2), Vector3(.02, ring[0] * 1.2, ring[0] * 1.2), ring[1])
	# Totem vertical no pilar esquerdo, de frente para a rua: a câmera olha do
	# sul, então um letreiro-bandeira (de perfil) ficava ilegível. Começa acima
	# de 3,3 m, fora da altura de quem passa, e passa da linha do telhado.
	KIT.box(t, Vector3(TOTEM_X, TOTEM_Y, TOTEM_Z), Vector3(.92, 3.2, .18), RACING_RED)
	KIT.box(t, Vector3(TOTEM_X, TOTEM_Y + 1.66, TOTEM_Z), Vector3(1.02, .12, .24), IRON)
	KIT.box(t, Vector3(TOTEM_X, TOTEM_Y - 1.66, TOTEM_Z), Vector3(1.02, .12, .24), IRON)
	for y in [TOTEM_Y - 1.0, TOTEM_Y + 1.0]:
		KIT.box(t, Vector3(TOTEM_X, y, FACE + .12), Vector3(.12, .12, .3), IRON)


static func _build_static_geometry(t: SurfaceTool) -> void:
	var face := 7.8125
	# Heavy charcoal frame, inset workshop bay and a continuous brass datum.
	KIT.box(t, Vector3(-2.0, 3.79, face + .075), Vector3(5.92, .74, .19), IRON)
	KIT.box(t, Vector3(-2.0, 4.17, face + .14), Vector3(5.72, .065, .21), BRASS)
	KIT.box(t, Vector3(-2.0, 3.39, face + .14), Vector3(5.72, .05, .16), BRASS)
	for x in [-5.02, 1.02]:
		KIT.box(t, Vector3(x, 1.68, face + .06), Vector3(.14, 3.28, .2), IRON)
		KIT.box(t, Vector3(x, 1.68, face + .17), Vector3(.045, 3.15, .045), BRASS)
		KIT.box(t, Vector3(x, 4.60, face - .33), Vector3(.19, .24, .68), IRON)
	# The original shell remains the physical back of the bay. A parked project
	# car and lift are seen in shadow; the roller is gathered above the opening.
	KIT.box(t, Vector3(-2.0, 1.59, 6.833), Vector3(5.68, 3.0, .045), Color("263539"))
	for x in [-4.36, .36]:
		KIT.box(t, Vector3(x, 1.39, 6.94), Vector3(.19, 2.55, .11), Color("6f8587"))
		KIT.box(t, Vector3(x, 2.71, 6.96), Vector3(.31, .09, .18), BRASS)
	KIT.box(t, Vector3(-2.0, .42, 6.95), Vector3(3.7, .17, .17), Color("171f22"))
	KIT.box(t, Vector3(-2.0, .76, 7.01), Vector3(3.31, .56, .17), Color("57534c"))
	KIT.box(t, Vector3(-2.0, 1.16, 6.995), Vector3(1.82, .29, .13), Color("364a4d"))
	KIT.box(t, Vector3(-2.0, 1.32, 7.04), Vector3(1.55, .025, .035), Color("9ca6a1"))
	for x in [-3.12, -.88]:
		KIT.box(t, Vector3(x, .49, 7.105), Vector3(.48, .22, .075), Color("151b1c"))
	for rib in 4:
		var y := 2.94 + float(rib) * .056
		KIT.box(t, Vector3(-2.0, y, 7.59), Vector3(5.65, .022, .045), Color("617579"))
	KIT.box(t, Vector3(-2.0, 3.13, 7.35), Vector3(5.85, .29, .45), STEEL)
	for x in [-4.55, .55]:
		KIT.box(t, Vector3(x, 3.13, 7.63), Vector3(.18, .38, .15), IRON)
	# Shallow steel awning and exposed braces frame the approach without
	# entering the car or pedestrian clearance at ground level.
	KIT.box(t, Vector3(-2.0, 3.43, 8.06), Vector3(6.55, .10, .65), IRON)
	KIT.box(t, Vector3(-2.0, 3.48, 8.38), Vector3(6.55, .055, .055), BRASS)
	for x in [-5.12, 1.12]:
		KIT.box(t, Vector3(x, 3.22, 8.04), Vector3(.09, .46, .53), STEEL)
	# Individually authored roofline: stepped parapet, long skylight ribs,
	# industrial extraction duct and a compact service exhaust.
	KIT.box(t, Vector3(-2.0, 4.77, 7.58), Vector3(8.04, .42, .30), IRON)
	KIT.box(t, Vector3(-2.0, 5.02, 7.62), Vector3(8.04, .055, .33), BRASS)
	for x in [-4.84, -3.36, -1.88, -.40, 1.08]:
		KIT.box(t, Vector3(x, 4.60, 4.48), Vector3(.085, .12, 5.9), STEEL)
	for z in [3.24, 4.54, 5.84]:
		KIT.box(t, Vector3(-1.88, 4.72, z), Vector3(5.9, .20, .065), Color("809398"))
	KIT.box(t, Vector3(-4.61, 4.95, 3.18), Vector3(.68, .70, .76), STEEL)
	KIT.box(t, Vector3(-4.61, 5.32, 3.18), Vector3(.79, .065, .88), IRON)
	KIT.cylinder(t, Vector3(-4.61, 5.32, 3.18), .18, .53, Color("617579"), 8)
	KIT.cylinder(t, Vector3(-4.61, 5.85, 3.18), .26, .055, IRON, 8)
	# Overhead utilities and a weathered masonry band on the front piers.
	for x in [-5.49, 1.49]:
		for y in [.64, 1.38, 2.12, 2.86]:
			KIT.box(t, Vector3(x, y, face + .015), Vector3(.79, .025, .022), Color("819196"))
		KIT.box(t, Vector3(x, 4.06, 7.96), Vector3(.12, .13, .45), IRON)
	# Paint and old oil live flush with the apron; neither changes collision.
	for x in [-3.64, -.36]:
		KIT.box(t, Vector3(x, .013, 8.48), Vector3(.11, .018, 1.03), BRASS)
	for index in 5:
		KIT.box(t, Vector3(-4.68 + float(index) * .34, .014, 8.03), Vector3(.16, .019, .46), Color("9b793a"), -.40)
	KIT.box(t, Vector3(-1.97, .012, 8.91), Vector3(1.12, .016, .36), Color("343a38"), .12)
	KIT.box(t, Vector3(-.78, .011, 8.80), Vector3(.53, .014, .17), Color("3a403b"), -.23)


static func _build_name(facade: Node3D) -> void:
	var label := Label3D.new()
	label.name = "MaciotaName"
	label.text = "MACIOTA"
	label.font = FONT
	label.font_size = 128
	label.pixel_size = .0066
	label.position = Vector3(-2.0, 3.80, 7.985)
	label.modulate = CREAM
	label.outline_size = 10
	label.outline_modulate = IRON
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.set_meta("neon_color", CREAM)
	label.add_to_group(&"city_neon_label")
	facade.add_child(label)


## Tubos de neon: contorno do portão e moldura do letreiro-bandeira. Material
## compartilhado da cidade (`neon`), que acende sozinho ao anoitecer.
static func _build_neon(facade: Node3D) -> void:
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	var tube := .045
	for x in [-4.9, .9]:
		KIT.box(t, Vector3(x, 1.8, FACE + .21), Vector3(tube, 2.9, tube), Color.WHITE)
	KIT.box(t, Vector3(-2.0, 3.26, FACE + .21), Vector3(5.85, tube, tube), Color.WHITE)
	var front := TOTEM_Z + .1
	for x in [TOTEM_X - .4, TOTEM_X + .4]:
		KIT.box(t, Vector3(x, TOTEM_Y, front), Vector3(tube, 3.0, tube), Color.WHITE)
	for y in [TOTEM_Y - 1.48, TOTEM_Y + 1.48]:
		KIT.box(t, Vector3(TOTEM_X, y, front), Vector3(.84, tube, tube), Color.WHITE)
	t.generate_normals()
	var neon := MeshInstance3D.new()
	neon.name = "MaciotaNeon"
	neon.mesh = t.commit()
	neon.material_override = CITY_MATERIALS.neon(NEON_ORANGE)
	neon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	facade.add_child(neon)


## Letras do totem, uma por Label3D, empilhadas de cima para baixo.
static func _build_blade_letters(facade: Node3D) -> void:
	var word := "MACIOTA"
	for index in word.length():
		var letter := Label3D.new()
		letter.name = "MaciotaTotem%d" % index
		letter.text = word[index]
		letter.font = FONT
		letter.font_size = 112
		letter.pixel_size = .0045
		letter.position = Vector3(TOTEM_X, TOTEM_Y + 1.2 - index * .4, TOTEM_Z + .1)
		letter.modulate = CREAM
		letter.outline_size = 8
		letter.outline_modulate = CHECK_DARK
		letter.double_sided = false
		letter.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		letter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		letter.set_meta("neon_color", Color("ffd9a8"))
		letter.add_to_group(&"city_neon_label")
		facade.add_child(letter)


static func _build_work_lamps(facade: Node3D) -> void:
	var lens_mesh := BoxMesh.new()
	lens_mesh.size = Vector3(.31, .15, .12)
	for x in [-5.45, 1.45]:
		var lens := MeshInstance3D.new()
		lens.name = "MaciotaWorkLampLeft" if x < 0.0 else "MaciotaWorkLampRight"
		lens.mesh = lens_mesh
		lens.position = Vector3(x, 3.04, 8.14)
		lens.material_override = CITY_MATERIALS.lamp_head()
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		facade.add_child(lens)
