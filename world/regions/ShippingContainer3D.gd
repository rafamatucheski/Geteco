extends RefCounted
## Contêiner de carga do porto sul com cara de contêiner: parede ondulada,
## cantoneiras ISO, trilhos de topo e base, portas com barras de trava e faixa
## de marca. Era uma caixa lisa de 5,85 m que passava da plataforma de 4,5 m do
## caminhão e cobria a cabine (relato de 28/09/2026). Agora cabe na plataforma
## do `cargo_flatbed_truck` (4,5 × 2,4 m) com a mesma proporção de um de 20 pés.
## Uma malha em cache por cor; origem no centro da base, comprimento em X.
const KIT := preload("res://world/city_look/CityPropKit.gd")

const LENGTH := 4.4
const WIDTH := 2.3
const HEIGHT := 2.3
const STEEL := Color("2b3033")
const MARK := Color("e9e4d8")

static var _meshes: Dictionary = {}

static func mesh(color: Color) -> ArrayMesh:
	var key := color.to_html(false)
	if _meshes.has(key): return _meshes[key]
	var t := SurfaceTool.new()
	t.begin(Mesh.PRIMITIVE_TRIANGLES)
	t.set_smooth_group(-1)
	var hx := LENGTH * .5
	var hz := WIDTH * .5
	var shade := color.darkened(.18)
	# Casco.
	KIT.box(t, Vector3(0, HEIGHT * .5, 0), Vector3(LENGTH - .1, HEIGHT - .12, WIDTH - .06), color)
	# Ondulação das laterais: nervuras verticais alternando claro e sombra.
	var ribs := 22
	for i in ribs:
		var x := -hx + .18 + (i + .5) * (LENGTH - .36) / ribs
		for side in [-1.0, 1.0]:
			KIT.box(t, Vector3(x, HEIGHT * .5, side * (hz - .01)), Vector3(.1, HEIGHT - .3, .04), shade if i % 2 == 0 else color.lightened(.05))
	# Teto ondulado leve.
	for i in 8:
		KIT.box(t, Vector3(-hx + .3 + i * (LENGTH - .6) / 7.0, HEIGHT - .04, 0), Vector3(.12, .03, WIDTH - .2), shade)
	# Quadro: trilhos de topo/base e colunas de canto com cantoneiras ISO.
	for y in [.06, HEIGHT - .06]:
		for side in [-1.0, 1.0]:
			KIT.box(t, Vector3(0, y, side * (hz - .02)), Vector3(LENGTH, .12, .08), STEEL)
		for end in [-1.0, 1.0]:
			KIT.box(t, Vector3(end * (hx - .03), y, 0), Vector3(.08, .12, WIDTH), STEEL)
	for end in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			KIT.box(t, Vector3(end * (hx - .06), HEIGHT * .5, side * (hz - .06)), Vector3(.14, HEIGHT, .14), STEEL)
			for y in [.08, HEIGHT - .08]:
				KIT.box(t, Vector3(end * (hx - .07), y, side * (hz - .07)), Vector3(.18, .16, .18), Color("1a1d1f"))
	# Portas no lado +X: duas folhas, dobradiças e quatro barras de trava.
	var door_x := hx - .005
	KIT.box(t, Vector3(door_x, HEIGHT * .5, 0), Vector3(.02, HEIGHT - .3, .03), STEEL)
	for z in [-.78, -.36, .36, .78]:
		KIT.box(t, Vector3(door_x + .03, HEIGHT * .5, z), Vector3(.04, HEIGHT - .4, .045), Color("9aa3a8"))
		for y in [.45, HEIGHT - .45]:
			KIT.box(t, Vector3(door_x + .04, y, z), Vector3(.05, .08, .09), STEEL)
	for side in [-1.0, 1.0]:
		for y in [.5, HEIGHT * .5, HEIGHT - .5]:
			KIT.box(t, Vector3(door_x + .02, y, side * (hz - .16)), Vector3(.04, .14, .08), STEEL)
	# Faixa de marca e placa de identificação nas laterais.
	for side in [-1.0, 1.0]:
		KIT.box(t, Vector3(-.4, HEIGHT - .45, side * (hz + .012)), Vector3(2.4, .22, .01), MARK)
		KIT.box(t, Vector3(hx - .55, .55, side * (hz + .012)), Vector3(.5, .3, .01), MARK)
	t.generate_normals()
	var result := t.commit()
	_meshes[key] = result
	return result

static func create(color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "ShippingContainer"
	node.mesh = mesh(color)
	node.material_override = KIT.material()
	return node
