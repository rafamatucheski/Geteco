extends Node3D
## Native reconstruction of MountainSceneryBuilder.build_detailed_bunker exterior2D.
## The helipad itself reuses its original native3D model.
const S := 1.0/16.0
var materials: Dictionary = {}
## Estação Zero pintada (PaintedMountainPlaces, 27/10): o casco vem da pintura e este nó só monta
## os equipamentos. `painted_roof_y` é a altura da laje acima do chão (< 0 = casco 3D antigo).
var painted_roof_y := -1.0
var painted_center := Vector3.ZERO
var painted_size := Vector3.ZERO
func _ready() -> void:
	if painted_roof_y >= 0.0:
		_painted_props()
		return
	_box("OriginalBunkerBody",Vector3(0,1.5,-12.5*S),Vector3(250*S,3,115*S),Color("3d444d"),true)
	_box("ConcreteRoof",Vector3(0,3.05,-12.5*S),Vector3(250*S,.1,115*S),Color("6b747a"))
	for x in [-70,0,70]:
		_box("OriginalSlit",Vector3(x*S,1.8,45*S+.02),Vector3(32*S,.6,.05),Color("0f172a"))
	_box("BunkerDoor",Vector3(0,.95,45*S+.05),Vector3(1.35,1.9,.06),Color("263a3f"))
	_box("OriginalGenerator",Vector3(105*S,.8,130*S),Vector3(40*S,1.6,40*S),Color("2c3e50"),true)
	_dress()
	var mast := Vector3(85*S,3,-60*S)
	for side in [-1,1]: _beam(mast+Vector3(side*14*S,0,0),mast+Vector3(0,4.8,0),.14,Color("e74c3c"))
	_box("OriginalBeacon",mast+Vector3(0,4.9,0),Vector3(.23,.23,.23),Color("ff4133"))
	var radar := Vector3(-75*S,3,-20*S)
	_beam(radar,radar+Vector3(0,1.1,0),.15,Color("c4cdcc"))
	_beam(radar+Vector3(-24*S,2.1,0),radar+Vector3(0,1.2,0),.20,Color("ecf0f1"))
	_beam(radar+Vector3(24*S,2.1,0),radar+Vector3(0,1.2,0),.20,Color("ecf0f1"))
	_helipad()

func _helipad() -> void:
	var helipad = preload("res://assets/regions/source/world/mountain_pass/MountainHelipad3D.gd").new()
	helipad.name = "MountainHelipad"
	# Separa a folga de pouso da entrada do bunker e do retorno da estrada.
	helipad.position = Vector3(-20,0,3.625)
	add_child(helipad)
	for mesh in helipad.find_children("*","MeshInstance3D",true,false):
		if mesh.get_meta("interior_solid_id","") != "": mesh.create_trimesh_collision()
	# A trilha conectada da região é dona da aproximação. Sem lajes atravessando a estrada.
## Só os equipamentos em volta do casco pintado: gerador e cabo na frente, mastro, radar e
## respiros na laje (dentro da pegada da pintura) e o heliponto ao lado.
func _painted_props() -> void:
	var roof := painted_roof_y
	var front := painted_center.z+painted_size.z*.5
	var half := Vector2(painted_size.x, painted_size.z)*.5
	var on_roof := func(x: float, z: float) -> Vector3:
		return Vector3(painted_center.x+clampf(x,-half.x+.8,half.x-.8),roof,painted_center.z+clampf(z,-half.y+.8,half.y-.8))
	var gen := Vector3(105*S,0,130*S)
	_box("OriginalGenerator",gen+Vector3(0,.8,0),Vector3(40*S,1.6,40*S),Color("2c3e50"),true)
	_generator(gen, front)
	var mast: Vector3 = on_roof.call(painted_size.x*.3, -painted_size.z*.25)
	for side in [-1,1]: _beam(mast+Vector3(side*14*S,0,0),mast+Vector3(0,4.8,0),.14,Color("e74c3c"))
	_box("OriginalBeacon",mast+Vector3(0,4.9,0),Vector3(.23,.23,.23),Color("ff4133"))
	var radar: Vector3 = on_roof.call(-painted_size.x*.3, -painted_size.z*.1)
	_beam(radar,radar+Vector3(0,1.1,0),.15,Color("c4cdcc"))
	_beam(radar+Vector3(-24*S,2.1,0),radar+Vector3(0,1.2,0),.20,Color("ecf0f1"))
	_beam(radar+Vector3(24*S,2.1,0),radar+Vector3(0,1.2,0),.20,Color("ecf0f1"))
	for at in [Vector2(-.2,-.25),Vector2(.15,.1),Vector2(-.4,.2)]:
		_box("RoofVent",on_roof.call(at.x*painted_size.x,at.y*painted_size.z)+Vector3(0,.2,0),Vector3(.6,.4,.6),Color("4b545c"))
	_helipad()

## O casco original era uma caixa lisa e o gerador um cubo mudo; o playtest de 21/10 não
## reconheceu o lugar. Só caixas na cor única, sem material novo de shader diferente.
func _dress() -> void:
	var front := 45*S
	var half_x := 125*S
	var back := -12.5*S-57.5*S
	# Platibanda do teto de concreto.
	_box("RoofParapet",Vector3(0,3.2,front-.1),Vector3(half_x*2,.3,.2),Color("59626a"))
	_box("RoofParapet",Vector3(0,3.2,back+.1),Vector3(half_x*2,.3,.2),Color("59626a"))
	for side in [-1,1]: _box("RoofParapet",Vector3(side*(half_x-.1),3.2,(front+back)*.5),Vector3(.2,.3,front-back),Color("59626a"))
	# Moldura de aço e faixa de perigo marcam a entrada; ficam fora do vão de 1,4 m.
	for side in [-1,1]: _box("DoorFrame",Vector3(side*.8,1.05,front+.06),Vector3(.18,2.1,.14),Color("1d2a2e"))
	_box("DoorLintel",Vector3(0,2.18,front+.06),Vector3(1.78,.16,.14),Color("1d2a2e"))
	for i in 6: _box("HazardStripe",Vector3(-.75+i*.3,2.42,front+.04),Vector3(.15,.22,.04),Color("f1b51c") if i % 2 == 0 else Color("16181a"))
	_box("DoorLamp",Vector3(0,2.66,front+.12),Vector3(.32,.14,.2),Color("ffd98a"))
	# Pilares de reforço dão escala à parede longa.
	for x in [-6.2,-3.4,3.4,6.2]: _box("Buttress",Vector3(x,1.45,front+.12),Vector3(.38,2.9,.24),Color("343b43"))
	_generator(Vector3(105*S,0,130*S), front)
	# Respiros no teto.
	for at in [Vector3(-3.0,3.3,-2.0),Vector3(2.0,3.3,.6),Vector3(-5.5,3.3,1.2)]: _box("RoofVent",at,Vector3(.6,.4,.6),Color("4b545c"))

## Gerador: radiador, escapamento, tanque, base e o cabo até a parede da frente (`front`).
func _generator(gen: Vector3, front: float) -> void:
	for i in 5: _box("GeneratorFin",gen+Vector3(-.9+i*.45,1.0,1.27),Vector3(.12,1.1,.06),Color("8fa1ad"))
	_box("GeneratorExhaust",gen+Vector3(.8,2.0,-.7),Vector3(.16,1.0,.16),Color("4a4f54"))
	_box("GeneratorTank",gen+Vector3(-1.95,.45,0),Vector3(.7,.9,1.6),Color("b2462e"),true)
	_box("GeneratorBase",gen+Vector3(0,.06,0),Vector3(3.0,.12,3.0),Color("59626a"))
	# Cabos do gerador até a parede.
	_box("PowerCable",Vector3(gen.x-.4,.05,(front+gen.z-1.25)*.5),Vector3(.08,.06,gen.z-1.25-front),Color("111317"))

func _beam(a: Vector3,b: Vector3,width: float,color: Color) -> void:
	var beam := _box("OriginalAntenna",(a+b)*.5,Vector3(width,a.distance_to(b),width),color)
	beam.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
func _box(id: String,at: Vector3,size: Vector3,color: Color,solid := false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = id
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	if not materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		materials[color] = mat
	mesh.material_override = materials[color]
	add_child(mesh)
	if solid: mesh.create_trimesh_collision()
	return mesh
