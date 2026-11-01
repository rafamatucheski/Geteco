extends RefCounted
## Moto: piloto embutido nas malhas da V1 (separação e troca pelo motociclista do trânsito),
## manoplas para a mão de quem pilota e o empinar manual por passo. Separado de scripts/Vehicle.gd em
## 01/11 (Onda 3) só para o dono caber na leitura. O estado (_motorcycle_rider_parts, _motorcycle_seat,
## _motorcycle_grips, manual_wheelie, _motorcycle_visual_rest, _motorcycle_rear_contact) continua no
## Vehicle, porque o setter de `traffic`, reset_motorcycle_wheelie, driver_seat_anchor e testes o leem lá;
## o dono mantém cada função antiga como delegação de uma linha com a mesma assinatura.
## `g` fica como CharacterBody3D, e não como o script do dono, para não criar preload cíclico.
## Caminho por quadro: só _tick_motorcycle_wheelie, e só em moto (o dono testa manual_wheelie antes);
## nada aqui aloca por passo.

const WHEELIE := preload("res://gameplay/MotorcycleWheelie.gd")

var g: CharacterBody3D

func _init(host: CharacterBody3D) -> void:
	g = host

func _tick_motorcycle_wheelie(delta: float) -> void:
	var eligible := g.controlled and not g.traffic and not g.external_input and not g.input_locked and not g.engine_disabled and g.health > 0 and not g.has_meta("crash_stun")
	var previous_pitch: float = g.manual_wheelie.pitch
	if not eligible and previous_pitch == 0: return
	var controls := g.get_node_or_null("/root/GameInput")
	eligible = eligible and (controls == null or not controls.remapping)
	g.manual_wheelie.step(delta,eligible and Input.is_action_pressed("motorcycle_wheelie"),eligible,g.is_on_floor(),g.speed,g.throttle_input,g.brake_input or g.is_on_wall())
	if g.manual_wheelie.pitch == previous_pitch: return
	g.visual.transform = Transform3D(Basis(Vector3.RIGHT,g.manual_wheelie.pitch),WHEELIE.rear_pivot_offset(g.manual_wheelie.pitch,g._motorcycle_rear_contact))*g._motorcycle_visual_rest

func _bind_motorcycle_rider() -> void:
	if not g.archetype.begins_with("bike_"): return
	g._motorcycle_seat = g.visual.get_meta("motorcycle_seat", g._motorcycle_seat)
	# As motos preparadas da V1 trazem o piloto embutido em malhas irmãs. Separa só a
	# paleta/acessórios escritos do piloto, uma vez, antes da pintura e da troca de pai das rodas.
	for child in g.visual.get_children():
		if not child is MeshInstance3D: continue
		var part := child as MeshInstance3D
		# A moto agrupada (RedesignedFleet) guarda o piloto numa malha própria marcada pelo bake:
		# as cores viram cor de vértice e a paleta original não aparece mais no material.
		if part.get_meta("motorcycle_rider", false):
			g._motorcycle_rider_parts.append(part)
			part.visible = g.traffic
			continue
		# Idem para as manoplas: uma malha por lado, com o lado em metadado; o wheel_center
		# que elas trazem as leva ao pivô de direção logo abaixo, em _ready.
		if part.has_meta("motorcycle_grip"):
			g._motorcycle_grips[str(part.get_meta("motorcycle_grip"))] = part
			continue
		var material: Material = part.material_override if part.material_override else part.mesh.surface_get_material(0)
		if not material is StandardMaterial3D: continue
		var color: String = material.albedo_color.to_html(false)
		var center: Vector3 = (part.transform * part.mesh.get_aabb()).get_center()
		if color == "161b20" and part.get_meta("wheel_spins", true) == false and center.y > .85 and absf(center.x) > .25:
			g._motorcycle_grips["Left" if center.x < 0 else "Right"] = part
		if part.has_meta("wheel_center"): continue
		var body := color in ["41454d", "253043", "181b20", "cf5058", "101d29"]
		var helmet_z := -.23 if g.archetype == "bike_sport" else .01
		var helmet_stud := color == "b5c4ce" and absf(center.x) < .14 and center.y > 1.3 and absf(center.z - helmet_z) < .03
		var stripe_z := .212 if g.archetype == "bike_sport" else .332
		var jacket_stripe := color in ["d4dce0", "b5c4ce", "f1ede5"] and absf(center.x) < .02 and center.y > .95 and absf(center.z - stripe_z) < .02
		if not body and not helmet_stud and not jacket_stripe: continue
		g._motorcycle_rider_parts.append(part)
		part.visible = g.traffic
		if color == "253043" and absf(center.x) < .01:
			g._motorcycle_seat = center - Vector3(0, .95, 0)
	# Mantém chassi/manoplas escritos, trocando só a pessoa embutida obsoleta.
	# O bake offline da frota ainda precisa da geometria escrita original.
	if not g.is_inside_tree(): return
	for part in g._motorcycle_rider_parts:
		part.get_parent().remove_child(part)
		part.queue_free()
	g._motorcycle_rider_parts.clear()
	# Appearance must not consume traffic/gameplay RNG (paint, routes, encounters).
	var identity := posmod(g.vehicle_id.hash() if not g.vehicle_id.is_empty() else str(g.get_instance_id()).hash(),100000)
	var rider := preload("res://assets/civilians/TrafficMotorcyclist.gd").create(g,identity)
	g.visual.add_child(rider)
	rider.visible = g.traffic
	g._motorcycle_rider_parts.append(rider)

func motorcycle_handholds() -> Dictionary:
	var holds := {}
	for side in g._motorcycle_grips:
		var part: MeshInstance3D = g._motorcycle_grips[side]
		if not is_instance_valid(part): continue
		# A malha já é filha do pivô de direção. Segue a apresentação real dela,
		# incluindo esterço e yaw do veículo, sem outra varredura da cena.
		var sign_side := -1.0 if side == "Left" else 1.0
		var palm_basis: Basis = part.get_parent().global_basis.orthonormalized() * Basis(Vector3.BACK, -sign_side * PI * .5)
		holds[side] = Transform3D(palm_basis, part.to_global(part.mesh.get_aabb().get_center()))
	if not holds.is_empty():
		if g.archetype == "bike_sport":
			holds["lean_multiplier"] = 1.8
			holds["lean_min"] = 0.5
		elif g.archetype == "bike_urban":
			holds["lean_multiplier"] = 0.5
			holds["lean_min"] = 0.1
		else: # cruiser or default
			holds["lean_multiplier"] = 0.5
			holds["lean_min"] = 0.2
	return holds
