extends SceneTree
## Passarela: altura livre sobre a rua, pilares fora da calçada, escada andável
## por uma cápsula de personagem, guarda-corpo que segura e documento válido.
const BRIDGE := preload("res://world/urban_detail/UrbanFootbridge3D.gd")
const DATA := preload("res://world/editing/WorldEditData.gd")
const PROPS := preload("res://world/editing/WorldPropFactory.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)
func _initialize() -> void: run.call_deferred()
func ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	ground_shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(ground_shape)
	world.add_child(ground)
	var row := DATA.new_entity("prop", Vector2.ZERO)
	row.merge({"model": "footbridge", "color": "3f6e8c", "size": [2.6, 34.6]}, true)
	check(DATA.validate_entity(row) == "", "Passarela padrão é válida no documento: " + DATA.validate_entity(row))
	var bad := row.duplicate(true)
	bad.size = [2.6, 20.0]
	check(DATA.validate_entity(bad) != "", "Comprimento curto demais é recusado")
	var bridge: Node3D = PROPS.create(row)
	world.add_child(bridge)
	for i in 3: await physics_frame
	var space := world.get_world_3d().direct_space_state
	var span: float = BRIDGE.span_for(34.6)
	var half_deck: float = span * 0.5 + BRIDGE.LANDING
	print("FOOTBRIDGE vão=%.2f m escada=%.2f m" % [span, BRIDGE.run_length()])
	# Rua de 7,5 m + calçadas de 2,625 m: 12,75 m precisam ficar livres.
	check(span >= 12.75, "Vão cobre rua e calçadas da market_street")
	var deck := ray(space, Vector3(0, 10, 0), Vector3(0, 0, 0))
	check(not deck.is_empty() and absf(deck.position.y - BRIDGE.DECK_HEIGHT) < 0.05, "Piso do tabuleiro a %.1f m" % BRIDGE.DECK_HEIGHT)
	# Nada sólido na faixa da rua abaixo de 4,4 m (ônibus e caminhões passam).
	for z in [-6.3, -3.0, 0.0, 3.0, 6.3]:
		for x in [-1.2, 0.0, 1.2]:
			var hit := ray(space, Vector3(x, 0.05, z), Vector3(x, 4.4, z))
			check(hit.is_empty(), "Livre sob a passarela em x=%.1f z=%.1f" % [x, z])
	# Pilares ficam além da calçada (6,375 m do eixo da rua).
	var pillar := ray(space, Vector3(1.05, 1.0, -20), Vector3(1.05, 1.0, 20))
	check(not pillar.is_empty() and absf(pillar.position.z) > 6.5, "Pilar fora da calçada (z=%.2f)" % (pillar.position.z if not pillar.is_empty() else 0.0))
	# Escada: altura do piso cresce do chão ao tabuleiro.
	var last := -1.0
	var monotonic := true
	for i in 9:
		var z: float = half_deck + BRIDGE.run_length() * (1.0 - i / 8.0)
		var hit := ray(space, Vector3(0, 8, z), Vector3(0, -1, z))
		var y: float = hit.position.y if not hit.is_empty() else -1.0
		if y < last - 0.01: monotonic = false
		last = y
	check(monotonic and last > BRIDGE.DECK_HEIGHT - 0.3, "Escada sobe continuamente até o tabuleiro")
	# Cápsula de personagem sobe a escada sul, atravessa e desce a norte.
	var walker := CharacterBody3D.new()
	walker.collision_layer = 2
	walker.collision_mask = 1
	var capsule := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = 0.3
	capsule_shape.height = 1.8
	capsule.shape = capsule_shape
	capsule.position.y = 0.9
	walker.add_child(capsule)
	world.add_child(walker)
	walker.global_position = Vector3(0, 0.05, half_deck + BRIDGE.run_length() + 2.0)
	var peak := 0.0
	for frame in 900:
		walker.velocity = Vector3(0, walker.velocity.y - 20.0 / 60.0, -3.5)
		if walker.is_on_floor(): walker.velocity.y = -1.0
		walker.move_and_slide()
		await physics_frame
		peak = maxf(peak, walker.global_position.y)
		if walker.global_position.z < -(half_deck + BRIDGE.run_length() + 1.0): break
	print("FOOTBRIDGE travessia z=%.1f pico=%.2f" % [walker.global_position.z, peak])
	check(peak > BRIDGE.DECK_HEIGHT - 0.1, "Personagem sobe até o tabuleiro")
	check(walker.global_position.z < -(half_deck + BRIDGE.run_length()), "Personagem atravessa e desce do outro lado")
	check(walker.global_position.y < 0.5, "Termina no chão")
	# Guarda-corpo: andando de lado no tabuleiro, não cai.
	walker.global_position = Vector3(0, BRIDGE.DECK_HEIGHT + 0.05, 0)
	for frame in 120:
		walker.velocity = Vector3(3.5, walker.velocity.y - 20.0 / 60.0, 0)
		if walker.is_on_floor(): walker.velocity.y = -1.0
		walker.move_and_slide()
		await physics_frame
	check(walker.global_position.y > BRIDGE.DECK_HEIGHT - 0.2 and absf(walker.global_position.x) < 1.3, "Guarda-corpo segura quem anda para o lado")
	var batches := bridge.find_children("*", "MultiMeshInstance3D", true, false).size()
	check(batches <= 6, "Poucos lotes de desenho (%d)" % batches)
	check(bridge.find_children("*", "Light3D", true, false).is_empty(), "Sem luzes")
	print("FOOTBRIDGE lotes=%d failures=%s" % [batches, failures])
	quit(0 if failures.is_empty() else 1)
