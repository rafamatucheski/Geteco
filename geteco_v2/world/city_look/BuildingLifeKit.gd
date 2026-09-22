extends RefCounted
## Malhas de fachada e telhado "vivos" (BuildingLife). Mesma convenção do
## CityPropKit: origem no ponto de apoio, frente para +Z (para fora da parede),
## cor por vértice, uma malha por tipo reutilizada em MultiMesh.

const KIT := preload("res://world/city_look/CityPropKit.gd")

const IRON := Color("2b2f31")
const IRON_LIGHT := Color("3d4346")


static func build(kind: String, t: SurfaceTool) -> void:
	match kind:
		"window_ac": _window_ac(t)
		"flower_box": _flower_box(t)
		"fe_platform": _fe_platform(t)
		"fe_stair": _fe_stair(t, 1.0)
		"fe_stair_m": _fe_stair(t, -1.0)
		"fe_ladder": _fe_ladder(t)
		"drainpipe": _drainpipe(t)
		"pigeons": _pigeons(t)
		"laundry": _laundry(t)
		"posters": _posters(t)
		"beacon_mast": _beacon_mast(t)
		"satellite_row": _satellite_row(t)
		"awning_small": _awning_small(t)
		"roof_garden": _roof_garden(t)
		"roof_shed": _roof_shed(t)
		"roof_chairs": _roof_chairs(t)
		"water_tank": _water_tank(t)
		"skylight": _skylight(t)
		"solar_row": _solar_row(t)
		"cooling_tower": _cooling_tower(t)


## Ar-condicionado de janela: pendurado no peitoril, grade frontal e suporte.
static func _window_ac(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, 0.2, 0.2), Vector3(0.66, 0.42, 0.44), Color("c9ccc4"))
	KIT.box(t, Vector3(0, 0.2, 0.425), Vector3(0.56, 0.32, 0.02), Color("7c817f"))
	for y in [0.1, 0.18, 0.26, 0.34]: KIT.box(t, Vector3(0, y, 0.44), Vector3(0.54, 0.02, 0.015), Color("5b605f"))
	KIT.box(t, Vector3(0, -0.06, 0.12), Vector3(0.5, 0.04, 0.3), IRON)
	# Mancha de água escorrida na parede embaixo (o pingo clássico).
	KIT.box(t, Vector3(0.18, -0.5, 0.005), Vector3(0.06, 0.9, 0.01), Color("3b3f40"))


static func _flower_box(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, 0.1, 0.14), Vector3(0.95, 0.2, 0.24), Color("6b4a33"))
	var petals := [Color("d8454b"), Color("f2c14e"), Color("e8e3d8"), Color("c05ab0")]
	for index in 6:
		var x := -0.38 + index * 0.15
		KIT.cylinder(t, Vector3(x, 0.18, 0.14), 0.07, 0.16, Color("3f7a3a"), 5, 0.02)
		KIT.box(t, Vector3(x, 0.33, 0.14 + (0.03 if index % 2 else -0.03)), Vector3(0.09, 0.07, 0.09), petals[index % petals.size()])


## Patamar da escada de incêndio (2,6 m × 0,95 m), grade e guarda-corpo.
static func _fe_platform(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, 0, 0.5), Vector3(2.6, 0.05, 0.95), IRON)
	for x in [-1.25, -0.75, -0.25, 0.25, 0.75, 1.25]: KIT.box(t, Vector3(x, 0.03, 0.5), Vector3(0.02, 0.02, 0.9), IRON_LIGHT)
	KIT.box(t, Vector3(0, 0.95, 0.96), Vector3(2.6, 0.04, 0.04), IRON)
	KIT.box(t, Vector3(0, 0.5, 0.96), Vector3(2.6, 0.03, 0.03), IRON)
	for x in [-1.28, -0.64, 0.0, 0.64, 1.28]: KIT.box(t, Vector3(x, 0.48, 0.96), Vector3(0.03, 0.96, 0.03), IRON)
	for side in [-1.29, 1.29]:
		KIT.box(t, Vector3(side, 0.95, 0.5), Vector3(0.04, 0.04, 0.95), IRON)
		KIT.box(t, Vector3(side, 0.48, 0.5), Vector3(0.03, 0.96, 0.03), IRON)
	# Mãos-francesas sob o patamar.
	for x in [-1.1, 1.1]: KIT.box(t, Vector3(x, -0.28, 0.35), Vector3(0.04, 0.6, 0.04), IRON)


## Lance diagonal por FORA do patamar (faixa z 1,0–1,6 m da parede): sobe
## 2,5 m em 2,6 m (44°, dentro do limite de chão de 45° do CharacterBody).
## Todos os lances sobem no mesmo sentido e ficam empilhados a 2,5 m um do
## outro, então quem sobe nunca bate a cabeça no patamar de cima (a versão em
## zigue-zague, dentro do patamar, era impossível de subir). `sign` fica para
## compatibilidade com malhas já registradas.
const FE_RUN := 2.6
const FE_RISE := 2.5
const FE_Z := 1.3

static func _fe_stair(t: SurfaceTool, sign: float) -> void:
	var steps := 10
	for i in steps:
		var f := (i + 0.5) / steps
		KIT.box(t, Vector3((-FE_RUN * 0.5 + f * FE_RUN) * sign, f * FE_RISE, FE_Z), Vector3(0.24, 0.03, 0.6), IRON_LIGHT)
	var angle := atan2(FE_RISE, FE_RUN) * sign
	var length := sqrt(FE_RISE * FE_RISE + FE_RUN * FE_RUN)
	for z in [FE_Z - 0.32, FE_Z + 0.32]:
		_slanted(t, Vector3(0, FE_RISE * 0.5 - 0.05, z), Vector3(length, 0.1, 0.04), angle, IRON)
	# Corrimão só do lado de fora; o de dentro deixaria o patamar inacessível.
	_slanted(t, Vector3(0, FE_RISE * 0.5 + 0.85, FE_Z + 0.32), Vector3(length, 0.035, 0.035), angle, IRON)


static func _slanted(t: SurfaceTool, center: Vector3, size: Vector3, angle: float, color: Color) -> void:
	var basis := Basis(Vector3.BACK, angle)
	var h := size * 0.5
	var corners := []
	for i in 8:
		corners.append(center + basis * Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var faces := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	t.set_color(color)
	for face in faces:
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[1]]); t.add_vertex(corners[face[2]])
		t.add_vertex(corners[face[0]]); t.add_vertex(corners[face[2]]); t.add_vertex(corners[face[3]])


## Escada de mão recolhida sob o primeiro patamar (não chega ao chão, como na rua real).
static func _fe_ladder(t: SurfaceTool) -> void:
	for x in [-0.22, 0.22]: KIT.box(t, Vector3(x, -0.8, 0.8), Vector3(0.04, 1.6, 0.04), IRON)
	for i in 6: KIT.box(t, Vector3(0, -0.1 - i * 0.28, 0.8), Vector3(0.44, 0.03, 0.03), IRON_LIGHT)


## Calha vertical de 1 m (escalada em Y pelo chamador) com braçadeiras.
static func _drainpipe(t: SurfaceTool) -> void:
	KIT.cylinder(t, Vector3(0, 0, 0.1), 0.055, 1.0, Color("56595a"), 6)
	KIT.box(t, Vector3(0, 0.5, 0.05), Vector3(0.14, 0.03, 0.1), Color("3e4142"))


## Bando de pombos pousado (5 aves) na borda da platibanda.
static func _pigeons(t: SurfaceTool) -> void:
	var offsets := [-0.9, -0.55, -0.1, 0.35, 0.8]
	var tones := [Color("7d8288"), Color("8e939a"), Color("6c7076"), Color("9aa0a6"), Color("777b80")]
	for i in offsets.size():
		var x: float = offsets[i]
		var yaw := (i * 1.7)
		KIT.box(t, Vector3(x, 0.07, 0), Vector3(0.1, 0.1, 0.18), tones[i], yaw)
		KIT.box(t, Vector3(x + sin(yaw) * 0.09, 0.14, cos(yaw) * 0.09), Vector3(0.06, 0.06, 0.06), Color("4d6a63"), yaw)
		KIT.box(t, Vector3(x - sin(yaw) * 0.1, 0.06, -cos(yaw) * 0.1), Vector3(0.07, 0.03, 0.08), Color("4a4d51"), yaw)


## Varal de telhado: dois postes, arame e roupas de cores variadas.
static func _laundry(t: SurfaceTool) -> void:
	for x in [-1.6, 1.6]:
		KIT.box(t, Vector3(x, 0.8, 0), Vector3(0.05, 1.6, 0.05), Color("8a8f90"))
		KIT.box(t, Vector3(x, 1.58, 0), Vector3(0.05, 0.05, 0.4), Color("8a8f90"))
	KIT.box(t, Vector3(0, 1.55, 0), Vector3(3.2, 0.012, 0.012), Color("c9c9c0"))
	var cloth := [Color("e8e4d8"), Color("3f6fb0"), Color("d44b4b"), Color("f0c75a"), Color("5ba36b"), Color("e8e4d8"), Color("9a5bb5")]
	var x0 := -1.35
	for i in cloth.size():
		var w := 0.3 + fmod(i * 0.37, 0.22)
		var h := 0.35 + fmod(i * 0.53, 0.3)
		KIT.box(t, Vector3(x0 + w * 0.5, 1.55 - h * 0.5, 0), Vector3(w, h, 0.015), cloth[i])
		x0 += w + 0.08


## Cartazes lambe-lambe colados na parede (frente para +Z).
static func _posters(t: SurfaceTool) -> void:
	var colors := [Color("e9d34a"), Color("d6453f"), Color("f1ede2"), Color("3d6fb6"), Color("e98a3a"), Color("f1ede2")]
	var sizes := [Vector2(0.55, 0.8), Vector2(0.5, 0.7), Vector2(0.6, 0.85), Vector2(0.45, 0.65), Vector2(0.55, 0.75), Vector2(0.5, 0.7)]
	var x := -1.4
	for i in colors.size():
		var s: Vector2 = sizes[i]
		var y := 1.35 + fmod(i * 0.21, 0.25)
		KIT.box(t, Vector3(x + s.x * 0.5, y, 0.01), Vector3(s.x, s.y, 0.01), colors[i])
		# Faixa de título escura: lê como cartaz, não como azulejo colorido.
		KIT.box(t, Vector3(x + s.x * 0.5, y + s.y * 0.28, 0.016), Vector3(s.x * 0.8, 0.09, 0.005), Color("1f1f22"))
		x += s.x - 0.08 if i % 2 == 0 else s.x + 0.04


## Mastro de balizamento (a lente vermelha piscante é outra MultiMesh).
static func _beacon_mast(t: SurfaceTool) -> void:
	KIT.cylinder(t, Vector3.ZERO, 0.05, 1.8, Color("9aa0a2"), 6)
	KIT.box(t, Vector3(0, 0.05, 0), Vector3(0.4, 0.1, 0.4), Color("5a5f61"))


## Fileira de parabólicas pequenas na borda do telhado de prédio residencial.
static func _satellite_row(t: SurfaceTool) -> void:
	for x in [-0.8, 0.0, 0.8]:
		KIT.box(t, Vector3(x, 0.25, 0), Vector3(0.05, 0.5, 0.05), Color("6c7274"))
		KIT.cylinder(t, Vector3(x, 0.45, 0.06), 0.03, 0.05, Color("e3e4df"), 10, 0.26)


## Toldo pequeno de loja/entrada de fundos.
static func _awning_small(t: SurfaceTool) -> void:
	var stripes := [Color("b8352f"), Color("efe9dc")]
	for i in 6:
		KIT.box(t, Vector3(-0.75 + i * 0.3, 0, 0.45), Vector3(0.3, 0.05, 0.9), stripes[i % 2])
	KIT.box(t, Vector3(0, -0.12, 0.9), Vector3(1.8, 0.22, 0.03), stripes[0])



## Horta/vasos de telhado: jardineiras de madeira com plantas e um guarda-sol.
static func _roof_garden(t: SurfaceTool) -> void:
	for x in [-0.9, 0.9]:
		KIT.box(t, Vector3(x, 0.2, 0), Vector3(1.4, 0.4, 0.7), Color("7a5537"))
		KIT.box(t, Vector3(x, 0.41, 0), Vector3(1.3, 0.04, 0.6), Color("4a3524"))
		for p in 4:
			var px: float = x - 0.5 + p * 0.33
			KIT.cylinder(t, Vector3(px, 0.42, 0), 0.16, 0.34 + fmod(p * 0.17, 0.2), [Color("4f8a45"), Color("6aa04f"), Color("3f7a3a")][p % 3], 6, 0.05)
	KIT.cylinder(t, Vector3(0, 0, 0.8), 0.03, 1.9, Color("8a8f90"), 5)
	KIT.cylinder(t, Vector3(0, 1.75, 0.8), 0.9, 0.18, Color("d65a44"), 8, 0.05)


## Casinha de depósito/escada com porta e telhado de zinco.
static func _roof_shed(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, 1.0, 0), Vector3(2.0, 2.0, 1.6), Color("a39b8c"))
	KIT.box(t, Vector3(0, 2.07, 0.05), Vector3(2.2, 0.14, 1.8), Color("6e7577"))
	KIT.box(t, Vector3(0.4, 0.85, 0.81), Vector3(0.8, 1.7, 0.04), Color("5a4a3c"))
	KIT.box(t, Vector3(-0.55, 1.4, 0.81), Vector3(0.5, 0.4, 0.03), Color("2e3a40"))


## Canto de convivência: duas cadeiras de praia e uma caixa térmica.
static func _roof_chairs(t: SurfaceTool) -> void:
	for x in [-0.45, 0.45]:
		var seat: Color = Color("2f7bbf") if x < 0 else Color("e0b23c")
		KIT.box(t, Vector3(x, 0.22, 0), Vector3(0.55, 0.05, 0.9), seat)
		KIT.box(t, Vector3(x, 0.45, -0.4), Vector3(0.55, 0.5, 0.05), seat)
		for leg in [-0.22, 0.22]: KIT.box(t, Vector3(x + leg, 0.1, 0), Vector3(0.03, 0.2, 0.8), Color("9aa0a2"))
	KIT.box(t, Vector3(0, 0.15, 0.6), Vector3(0.4, 0.3, 0.3), Color("d8453c"))



## Caixa-d'água de madeira sobre torre de ferro (a silhueta de telhado de Nova York).
static func _water_tank(t: SurfaceTool) -> void:
	for x in [-0.7, 0.7]:
		for z in [-0.7, 0.7]:
			KIT.box(t, Vector3(x, 1.0, z), Vector3(0.1, 2.0, 0.1), IRON)
	KIT.box(t, Vector3(0, 1.0, 0.7), Vector3(1.5, 0.05, 0.05), IRON)
	KIT.box(t, Vector3(0, 1.0, -0.7), Vector3(1.5, 0.05, 0.05), IRON)
	KIT.box(t, Vector3(0, 2.02, 0), Vector3(1.8, 0.08, 1.8), Color("4a3b2e"))
	KIT.cylinder(t, Vector3(0, 2.06, 0), 0.95, 1.8, Color("6b4f36"), 12, 0.9)
	for y in [2.4, 3.0, 3.55]: KIT.cylinder(t, Vector3(0, y, 0), 0.97, 0.05, IRON, 12)
	KIT.cylinder(t, Vector3(0, 3.86, 0), 1.0, 0.55, Color("3f3a35"), 12, 0.08)
	KIT.box(t, Vector3(0.95, 1.9, 0), Vector3(0.05, 3.8, 0.35), IRON_LIGHT)


static func _skylight(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, 0.2, 0), Vector3(1.6, 0.4, 1.1), Color("8a8f90"))
	KIT.box(t, Vector3(0, 0.46, 0), Vector3(1.45, 0.12, 0.95), Color("7fa6b8"))
	KIT.box(t, Vector3(0, 0.53, 0), Vector3(0.05, 0.03, 0.95), Color("5a5f61"))


static func _solar_row(t: SurfaceTool) -> void:
	for i in 3:
		var x := -1.3 + i * 1.3
		KIT.box(t, Vector3(x, 0.25, -0.2), Vector3(0.05, 0.5, 0.05), Color("9aa0a2"))
		KIT.box(t, Vector3(x, 0.45, 0), Vector3(1.2, 0.04, 0.9), Color("1d2e4a"), 0.0)
		for c in 3: KIT.box(t, Vector3(x - 0.4 + c * 0.4, 0.475, 0), Vector3(0.015, 0.01, 0.88), Color("8fa3bf"))


## Torre de resfriamento de escritório (caixa com ventilador no topo).
static func _cooling_tower(t: SurfaceTool) -> void:
	KIT.box(t, Vector3(0, 0.9, 0), Vector3(2.2, 1.8, 1.8), Color("9ea3a0"))
	for y in [0.4, 0.7, 1.0, 1.3]: KIT.box(t, Vector3(0, y, 0.91), Vector3(2.0, 0.08, 0.02), Color("5f666a"))
	KIT.cylinder(t, Vector3(0, 1.8, 0), 0.8, 0.35, Color("6f7577"), 12, 0.75)
	KIT.cylinder(t, Vector3(0, 2.1, 0), 0.72, 0.04, Color("2b2f31"), 12)
