extends Node3D
## Forja da Serra: ferraria do Seu Bento na clareira ao norte do lago alpino (antes o
## zoológico "Serra Viva", 03/10–17/10/2026), com acesso a pé pela estrada. Origem do nó =
## CENTER; a entrada fica em z = +7, virada para a estrada. FOOTPRINT reserva terreno, árvores
## e pilares da ferrovia. 18/10: o pátio de 46x39 m herdado do zoológico era grande e verde
## demais para uma ferraria; agora é um terreiro de terra batida só em volta da oficina.
const GEO := preload("res://world/mountain_detail/forge/ForgeGeometry.gd")
const SURFACE := preload("res://world/mountain_detail/forge/forge_surface.gdshader")
const RESIDENT := preload("res://world/mountain_detail/forge/ForgeResident.gd")
const CENTER := Vector3(716,0,-363)
const FOOTPRINT := Rect2(702,-378,28,25)
const BOUNDARY := [Vector2(-2,7),Vector2(-9,7),Vector2(-12,4),Vector2(-12,-10),Vector2(-10,-13),Vector2(10,-13),Vector2(12,-10),Vector2(12,4),Vector2(9,7),Vector2(2,7)]
## Centro da brasa da fornalha, local. É também a fonte de calor `blade_forge` do frio
## (OriginalHeatSources), que acende a chama por cima dela.
const HEARTH := Vector3(-3.5,0,-8.4)
const SMITH_STAND := Vector3(-1.0,.06,-3.9)
var smith: Node3D
var session
static var _surfaces: Dictionary = {}

static func approach() -> Dictionary:
	return {"id":"mountain_forge_walk","width":3.0,"points":PackedVector3Array([Vector3(716,0,-330),Vector3(716,0,-343),Vector3(716,0,-356)])}

func _ready() -> void:
	name = "MountainForge"
	add_to_group("blade_forge_site")
	var g := GEO.new()
	var outer := PackedVector2Array(BOUNDARY)
	# Terra batida, não capim: o verde do pátio antigo lia como gramado de parque.
	GEO.polygon(self, outer, .035, Color("857559"))
	_yard_fence(g, outer)
	# Caminho de cascalho da porteira até a frente da oficina.
	for polygon in Geometry2D.offset_polyline(PackedVector2Array([Vector2(0,7),Vector2(0,4),Vector2(-.6,1.0)]), 1.6, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
		GEO.polygon(self, polygon, .052, Color("9e937a"))
	_gate(g)
	_workshop(g)
	_hearth(g)
	_tools(g)
	_woodpile(g, Vector3(9.6,0,-7.0))
	_ore_pile(g, Vector3(-9.5,0,-6.0))
	for at in [Vector3(-7.5,0,3.0), Vector3(7.5,0,3.0)]: _bench(g, at)
	# Pedras baixas e arbustos amaciam a cerca sem esconder a oficina da estrada.
	for i in outer.size():
		var p: Vector2 = outer[i]
		if absf(p.x) < 4: continue
		g.part("round", Vector3(p.x*.95,.22,p.y*.95), Vector3(1.1,.65,.8), "62704b")
	g.flush(self)
	smith = RESIDENT.new()
	smith.name = "Smith"
	smith.site_id = "smith"
	smith.speaker = "Seu Bento"
	smith.identity = 731
	smith.stand = SMITH_STAND
	smith.facing = 0.0
	add_child(smith)

func nearest_action() -> Dictionary:
	return smith.nearest_action() if is_instance_valid(smith) else {}

func _yard_fence(g: RefCounted, outer: PackedVector2Array) -> void:
	# Cerca de varas: dois varões e mourões, com colisão por trecho; a porteira fica aberta.
	for i in range(outer.size()-1):
		var a: Vector2 = outer[i]
		var b: Vector2 = outer[i+1]
		var gap := b-a
		var length := gap.length()
		var yaw := atan2(gap.x, gap.y)
		var mid := (a+b)*.5
		var body := GEO.solid(self, "YardFence", Vector3(mid.x,.6,mid.y), Vector3(.18,1.2,length+.06))
		body.rotation.y = yaw
		for y in [.45,.95]: g.part("box", Vector3(mid.x,y,mid.y), Vector3(.09,.11,length+.04), "6b5236", Vector3(0,yaw,0))
		var count := ceili(length/2.4)
		for j in count+1:
			var p := a.lerp(b, float(j)/count)
			g.part("pole", Vector3(p.x,.6,p.y), Vector3(.14,1.2,.14), "59452e")

func _gate(g: RefCounted) -> void:
	for x in [-2.05,2.05]:
		g.part("box", Vector3(x,1.7,7), Vector3(.32,3.4,.32), "59452e")
		GEO.solid(self, "GatePost", Vector3(x,1.7,7), Vector3(.32,3.4,.32))
	g.part("box", Vector3(0,3.4,7), Vector3(4.6,.7,.30), "3d3129")
	GEO.solid(self, "GateBeam", Vector3(0,3.4,7), Vector3(4.6,.7,.30))
	var label := Label3D.new()
	label.text = "Forja da Serra"
	label.font_size = 64
	label.pixel_size = .008
	label.position = Vector3(0,3.41,7.17)
	label.modulate = Color("f0c890")
	label.outline_size = 0
	add_child(label)
	# Ferradura e martelo cruzados sobre a viga: o ofício lido de longe, sem letreiro explicativo.
	g.part("box", Vector3(0,4.05,7.05), Vector3(.9,.10,.10), "2d3033", Vector3(0,0,.6))
	g.part("box", Vector3(0,4.05,7.05), Vector3(.9,.10,.10), "2d3033", Vector3(0,0,-.6))

func _workshop(g: RefCounted) -> void:
	# Oficina aberta na frente (z = -1,5): fundo e laterais de pedra, esteios de madeira,
	# telhado de duas águas com cumeeira em z = -6. Origem no chão do pátio.
	_piece("BackWall", Vector3(0,1.8,-10.6), Vector3(14.4,3.6,.6), 3, "77776c")
	for side in [-1.0,1.0]:
		_piece("SideWall", Vector3(side*7.0,1.5,-7.4), Vector3(.6,3.0,6.4), 3, "6f6f65")
	for x in [-7.0,-2.4,2.4,7.0]:
		_piece("FrontPost", Vector3(x,1.7,-1.6), Vector3(.28,3.4,.28), 1, "695339")
	_piece("FrontBeam", Vector3(0,3.45,-1.6), Vector3(14.6,.3,.32), 1, "59452e", false)
	_piece("RidgeBeam", Vector3(0,5.2,-6.0), Vector3(14.6,.26,.26), 1, "59452e", false)
	var rise := 5.2-3.4
	var run := 4.6
	var slope := atan2(rise, run)
	var length := sqrt(rise*rise+run*run)+.7
	for side in [1.0,-1.0]:
		var roof := _piece("RoofSlab", Vector3(0,4.3,-6.0+side*run*.5), Vector3(15.4,.18,length), 2, "4d4038", false)
		roof.rotation.x = slope*side
	# Empenas fechadas por tábuas acima das paredes laterais.
	for side in [-1.0,1.0]:
		for step in 4:
			var h := 3.0+float(step)*.55
			var depth := 9.0*(1.0-float(step)/4.0)
			_piece("Gable", Vector3(side*7.0,h+.27,-6.0), Vector3(.22,.55,depth), 0, "6b5236", false)
	# Piso de pedra batida dentro da oficina.
	GEO.polygon(self, PackedVector2Array([Vector2(-7,-10.3),Vector2(7,-10.3),Vector2(7,-1.4),Vector2(-7,-1.4)]), .06, Color("6f6a5c"))

func _hearth(g: RefCounted) -> void:
	var h := HEARTH
	# Fornalha de pedra com a brasa em cima, coifa e chaminé atravessando o telhado.
	_piece("ForgeHearth", h+Vector3(0,.5,0), Vector3(2.6,1.0,1.8), 3, "5b5c55")
	_piece("HearthRim", h+Vector3(0,1.03,0), Vector3(2.7,.08,1.9), 3, "4a4a44", false)
	var coals := MeshInstance3D.new()
	coals.name = "ForgeCoals"
	var bed := BoxMesh.new()
	bed.size = Vector3(1.5,.07,.95)
	coals.mesh = bed
	coals.position = h+Vector3(0,1.08,0)
	# Mesmo material do fio lendário (WeaponAttachmentVisuals): uma variante de shader só, pré-aquecida.
	coals.material_override = preload("res://gameplay/WeaponAttachmentVisuals.gd").legendary_glow()
	coals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(coals)
	for i in 7:
		g.part("round", h+Vector3(-.6+float(i%4)*.4,1.12,-.25+floorf(i/4.0)*.5), Vector3(.22,.12,.2), "1d1b1a")
	_piece("ForgeHood", h+Vector3(0,2.55,-.15), Vector3(2.2,.9,1.5), 3, "4a4a44", false)
	_piece("Chimney", h+Vector3(0,4.6,-.4), Vector3(.9,3.4,.9), 3, "5b5c55", false)
	# Marcador da fonte de calor: HeatPresentation acende a chama sobre a brasa
	# (sem luz dinâmica nova) e a colisão é a da própria fornalha.
	var heat := Marker3D.new()
	heat.name = "ForgeHeatSource"
	heat.position = h
	add_child(heat)
	heat.add_to_group("native_heat_source")
	heat.set_meta("native_heat_source", "blade_forge")
	heat.set_meta("native_heat_flame_offset", Vector3(0,1.1,0))
	heat.set_meta("native_heat_has_solids", true)
	# Fole de couro ao lado, apontado para a brasa.
	g.part("box", h+Vector3(-1.95,.75,.1), Vector3(.7,.32,1.1), "6b4a32", Vector3(0,0,.12))
	g.part("box", h+Vector3(-1.95,.45,.1), Vector3(.5,.6,.5), "59452e")
	GEO.solid(self, "Bellows", h+Vector3(-1.95,.5,.1), Vector3(.8,1.0,1.1))

func _tools(g: RefCounted) -> void:
	# Bigorna no toco, de frente para o ferreiro.
	var anvil := Vector3(-1.0,0,-5.2)
	g.part("pole", anvil+Vector3(0,.3,0), Vector3(.75,.6,.75), "5f4a33")
	g.part("box", anvil+Vector3(0,.72,0), Vector3(.34,.24,.62), "2d3033")
	g.part("box", anvil+Vector3(0,.9,0), Vector3(.42,.12,.78), "34383c")
	g.part("round", anvil+Vector3(0,.9,-.47), Vector3(.16,.10,.3), "34383c")
	GEO.solid(self, "Anvil", anvil+Vector3(0,.48,0), Vector3(.8,.96,.9))
	g.part("box", anvil+Vector3(.12,.99,.1), Vector3(.05,.05,.32), "6b4a32", Vector3(0,.4,0))
	g.part("box", anvil+Vector3(.06,1.0,-.04), Vector3(.12,.08,.14), "2d3033", Vector3(0,.4,0))
	# Tina de têmpera com água.
	var tub := Vector3(1.2,0,-8.4)
	g.part("pole", tub+Vector3(0,.42,0), Vector3(.9,.84,.9), "5f4a33")
	g.part("pole", tub+Vector3(0,.82,0), Vector3(.8,.02,.8), "4f7173")
	GEO.solid(self, "QuenchTub", tub+Vector3(0,.42,0), Vector3(.9,.84,.9))
	# Rebolo de afiar na armação, com pedal.
	var wheel := Vector3(3.4,0,-5.4)
	g.part("pole", wheel+Vector3(0,.78,0), Vector3(.95,.16,.95), "8a8574", Vector3(0,0,PI*.5))
	for x in [-.18,.18]: g.part("box", wheel+Vector3(x,.42,0), Vector3(.08,.84,.12), "59452e")
	g.part("box", wheel+Vector3(0,.12,.35), Vector3(.5,.06,.25), "59452e")
	GEO.solid(self, "Grindstone", wheel+Vector3(0,.5,0), Vector3(1.0,1.0,1.0))
	# Bancada na parede direita e o painel de lâminas acabadas no fundo.
	_piece("Workbench", Vector3(6.0,.47,-6.2), Vector3(1.1,.94,3.6), 1, "695339")
	for z in [-7.4,-6.5,-5.4]: g.part("box", Vector3(6.0,1.0,z), Vector3(.5,.10,.14), "34383c")
	_piece("BladeBoard", Vector3(4.2,1.9,-10.25), Vector3(3.0,1.4,.08), 0, "6b5236", false)
	for i in 5:
		var x := 3.0+float(i)*.6
		g.part("box", Vector3(x,1.95,-10.18), Vector3(.05,1.0-float(i%2)*.3,.02), "abbcca")
		g.part("box", Vector3(x,1.35+float(i%2)*.15,-10.17), Vector3(.12,.16,.04), "3d3129")
	# Sacos de carvão encostados na fornalha.
	for i in 3: g.part("round", HEARTH+Vector3(1.75,.32,.3+float(i)*.55), Vector3(.6,.64,.5), "2b2826")

func _woodpile(g: RefCounted, at: Vector3) -> void:
	# Lenha da serraria em pilha baixa, fora da oficina; colisão de uma caixa só.
	for row in 3:
		for i in 6-row:
			g.part("pole", at+Vector3(0,.18+row*.32,-1.0+float(i)*.36+row*.18), Vector3(.34,2.2,.34), "7a5a3a", Vector3(0,0,PI*.5))
	GEO.solid(self, "Woodpile", at+Vector3(0,.5,-.1), Vector3(2.3,1.0,2.3))

func _ore_pile(g: RefCounted, at: Vector3) -> void:
	for i in 6:
		g.part("round", at+Vector3(-.6+float(i%3)*.6,.22+floorf(i/3.0)*.25,floorf(i/3.0)*.3), Vector3(.62,.48,.55), "4b4644")
	g.part("box", at+Vector3(1.5,.35,0), Vector3(1.0,.7,.7), "5f4a33")
	GEO.solid(self, "OrePile", at+Vector3(.4,.4,.1), Vector3(2.6,.8,1.2))

func _bench(g: RefCounted, at: Vector3) -> void:
	g.part("box", at+Vector3(0,.48,0), Vector3(1.8,.15,.55), "806044")
	g.part("box", at+Vector3(0,.85,-.25), Vector3(1.8,.6,.10), "806044")
	for x in [-.65,.65]: g.part("box", at+Vector3(x,.23,0), Vector3(.12,.46,.5), "48584d")
	GEO.solid(self, "Bench", at+Vector3(0,.55,0), Vector3(1.8,1.1,.65))

## Peça com o shader de tábua/metal/pedra em escala de metro, malha e material em cache.
func _piece(id: String, at: Vector3, size: Vector3, kind: int, color: String, solid := true) -> MeshInstance3D:
	var mesh_key := "mesh:" + str(size)
	if not _surfaces.has(mesh_key):
		var mesh := BoxMesh.new()
		mesh.size = size
		_surfaces[mesh_key] = mesh
	var material_key := "mat:%d:%s" % [kind, color]
	if not _surfaces.has(material_key):
		var material := ShaderMaterial.new()
		material.shader = SURFACE
		material.set_shader_parameter("surface_kind", kind)
		material.set_shader_parameter("base_color", Color(color))
		_surfaces[material_key] = material
	var visual := MeshInstance3D.new()
	visual.name = id + "Surface"
	visual.position = at
	visual.mesh = _surfaces[mesh_key]
	visual.material_override = _surfaces[material_key]
	add_child(visual)
	if solid: GEO.solid(self, id, at, size)
	return visual
