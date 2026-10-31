extends Node3D
## Ciclo de carga de 40 pés em tamanho real sob cada lança do Northstar em streaming. A carga fica
## acima do convés caminhável e o guindaste autorado continua sendo o objeto físico.
const PAINT := preload("res://world/regions/PortShipMaterials3D.gd")
var anchor := Vector2.ZERO
var phase_offset := 0.0
var clock := 0.0
var trolley: MeshInstance3D
var cable: MeshInstance3D
var spreader: MeshInstance3D
const CONTAINERS := preload("res://world/regions/PortContainerBatch.gd")
const CARGO_SIZE := Vector3(2.44,2.89,12.19)
var load_mesh: Node3D
## Pintura do guindaste e do contêiner é triplanar em espaço de MUNDO (PortShipMaterials3D,
## PortArtMaterials via UrbanSurfaces.detail): na peça que anda, a textura ficava parada no
## mundo e "escorria" sobre a carga e o spreader (playtest de 29/10, vídeo do canal).
## Cada peça móvel ganha cópias desses materiais (mesmo shader: nada compila) e o
## uv1_offset desconta o deslocamento da peça, então a textura anda junto com ela.
var _texture_anchors: Array[Dictionary] = []

func configure(point: Vector2, offset: float) -> void:
	anchor = point
	phase_offset = offset

func _ready() -> void:
	name = "NorthstarCargoHoist3D"
	trolley = _part("Trolley",Vector3(.82,.32,.8),PAINT.material("crane"))
	cable = _part("HoistCable",Vector3(.045,1,.045),_color("384448"))
	spreader = _part("Spreader",Vector3(2.2,.16,11.9),PAINT.material("crane"))
	load_mesh = CONTAINERS.create(2,CARGO_SIZE)
	load_mesh.name = "SuspendedCargo40ft"
	add_child(load_mesh)
	# Quatro travas de canto ligam o spreader às peças de canto ISO.
	for x in [-1.1,1.1]:
		for z in [-5.92,5.92]:
			var lock := _part("TwistLock",Vector3(.18,.28,.18),_color("384448"))
			remove_child(lock)
			spreader.add_child(lock)
			lock.position = Vector3(x,-.15,z)
	for moving in [trolley, spreader, load_mesh]:
		_anchor_texture(moving)
	_update_pose()

func _anchor_texture(node: Node3D) -> void:
	var copies := {}
	var parts: Array = [node]
	parts.append_array(node.find_children("*", "MeshInstance3D", true, false))
	for part in parts:
		if not part is MeshInstance3D: continue
		var source := (part as MeshInstance3D).material_override as StandardMaterial3D
		if source == null or not (source.uv1_triplanar and source.uv1_world_triplanar): continue
		if not copies.has(source):
			var copy := source.duplicate() as StandardMaterial3D
			copies[source] = copy
			_texture_anchors.append({"node": node, "material": copy, "offset": source.uv1_offset, "scale": source.uv1_scale, "last": Vector3.INF})
		(part as MeshInstance3D).material_override = copies[source]

## Triplanar de mundo: posição × uv1_scale + uv1_offset. A peça só translada em
## relação ao guindaste (parado), então descontar posição × escala fixa a textura nela.
func _follow_textures() -> void:
	for follow in _texture_anchors:
		var at: Vector3 = (follow.node as Node3D).position
		if at == follow.last: continue
		follow.last = at
		(follow.material as StandardMaterial3D).uv1_offset = (follow.offset as Vector3) - at * (follow.scale as Vector3)

func _part(label: String, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = material
	add_child(instance)
	return instance

func _color(hex: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = .8
	return material

func _process(delta: float) -> void:
	clock += delta
	_update_pose()

func _update_pose() -> void:
	var cycle := fposmod(clock/30.0+phase_offset,1.0)
	var x := anchor.x+17.0
	var lift := 3.05
	if cycle < .20:
		lift = lerpf(3.05,3.9,smoothstep(0.0,.20,cycle))
	elif cycle < .50:
		x = lerpf(anchor.x+17.0,anchor.x+6.0,smoothstep(.20,.50,cycle))
		lift = 3.9
	elif cycle < .70:
		x = anchor.x+6.0
		lift = lerpf(3.9,3.05,smoothstep(.50,.70,cycle))
	elif cycle < .85:
		x = anchor.x+6.0
		lift = lerpf(3.05,3.9,smoothstep(.70,.85,cycle))
	else:
		x = lerpf(anchor.x+6.0,anchor.x+17.0,smoothstep(.85,1.0,cycle))
		lift = 3.9
	var boom_y := 5.15
	# A carga em tamanho real tem origem na base, ao contrário da antiga caixa em miniatura.
	lift = lerpf(1.55,3.05,clampf((lift-3.05)/.85,0,1))
	var cargo_top := lift+1.445
	var cable_length := boom_y-cargo_top-.16
	trolley.position = Vector3(x,boom_y,anchor.y)
	load_mesh.position = Vector3(x,lift-1.445,anchor.y)
	spreader.position = Vector3(x,cargo_top+.12,anchor.y)
	cable.position = Vector3(x,cargo_top+.16+cable_length*.5,anchor.y)
	cable.scale.y = cable_length
	_follow_textures()
