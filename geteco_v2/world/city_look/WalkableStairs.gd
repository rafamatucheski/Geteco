extends RefCounted
## Degraus que dá para subir.
##
## Os arquétipos montam escadas de entrada (Stoop_* dos brownstones, varanda
## FrontPorch da Cobra) como caixas só visuais: o corpo atravessava. Degrau
## em caixa de colisão também não serve: o CharacterBody3D não sobe degrau de
## 22 cm (não há step-up). Solução de jogo: uma rampa invisível do pé do
## primeiro degrau até a borda do patamar (34° no brownstone, abaixo do limite
## de 45° do chão) e o patamar como caixa sólida.

const STEP_PREFIXES := ["Step_", "PorchStep_"]
const LANDING_NAMES := ["Landing", "PorchDeck"]
const THICKNESS := 0.12


static func build_chunk(chunk: Node3D) -> void:
	for node in chunk.find_children("*", "Node3D", true, false):
		var label := String(node.name)
		if label.begins_with("Stoop_") or label == "FrontPorch":
			_make_walkable(node)


static func _make_walkable(root: Node3D) -> void:
	var steps: Array[MeshInstance3D] = []
	var landing: MeshInstance3D = null
	for child in root.get_children():
		if not child is MeshInstance3D: continue
		var label := String(child.name)
		for prefix in STEP_PREFIXES:
			if label.begins_with(prefix): steps.append(child)
		if label in LANDING_NAMES: landing = child
	if steps.is_empty(): return
	# Tudo no espaço local da escada: os degraus descem para +Z local.
	var box := AABB()
	var first := true
	for step in steps:
		var part := step.transform * step.get_aabb()
		box = part if first else box.merge(part)
		first = false
		_disable_collision(step)
	var top := box.end.y
	var front := box.end.z
	var back := box.position.z
	var body := StaticBody3D.new()
	body.name = "WalkableStairs"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	var d := Vector3(0, top, back - front).normalized()
	# Base com LEFT × normal = d (destra): normal sai para cima e para a rua.
	var normal := d.cross(Vector3.LEFT)
	var basis := Basis(Vector3.LEFT, normal, d)
	var length := Vector2(front - back, top).length()
	var middle := Vector3(box.get_center().x, top * 0.5, (front + back) * 0.5) - normal * THICKNESS * 0.5
	_shape(body, Vector3(box.size.x, THICKNESS, length), Transform3D(basis, middle))
	if landing != null:
		_disable_collision(landing)
		var slab := landing.transform * landing.get_aabb()
		_shape(body, slab.size, Transform3D(Basis.IDENTITY, slab.get_center()))


static func _shape(body: StaticBody3D, size: Vector3, xform: Transform3D) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.transform = xform
	body.add_child(collider)


## Colisão de malha que a fábrica possa ter gerado para o degrau (trimesh):
## a quina do degrau vira parede para o CharacterBody.
static func _disable_collision(mesh: MeshInstance3D) -> void:
	for body in mesh.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0
