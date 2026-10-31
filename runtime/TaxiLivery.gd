extends Node3D
## Carroceria de táxi compartilhada; estado do luminoso e placa por carro, sem fonte de luz extra.
var sign_material: StandardMaterial3D
var plates: Array[Label3D] = []
var available := true

static func decorate(model: Node3D) -> void:
	if model.has_node("TaxiLivery"): return
	var art = load("res://runtime/TaxiLivery.gd").new()
	art.name = "TaxiLivery"
	model.add_child(art)
	art.build(model)

static func _new_sign_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("fff0b0")
	material.emission_enabled = true
	material.emission = Color("ffe49b")
	material.emission_energy_multiplier = .65
	return material

func build(model: Node3D) -> void:
	sign_material = _new_sign_material()
	for part in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var bounds: AABB = part.transform*part.get_aabb()
		if bounds.position.y > 1.41 and bounds.size.y > .2 and bounds.size.x < 1.1:
			part.material_override = sign_material
	for back in [false,true]:
		var label := _label("TAXI",Vector3(0,1.57,.277 if back else -.077),.005,Color("181b1d"))
		label.rotation.y = 0.0 if back else PI
		var plate := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.48,.15,.016)
		plate.mesh = box
		plate.position = Vector3(0,.39,2.37 if back else -2.37)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("edece7")
		material.roughness = .35
		plate.material_override = material
		add_child(plate)
		var local_registration := _label("HBR-0000",plate.position+Vector3(0,-.016,.012 if back else -.012),.0015,Color("17212a"))
		local_registration.rotation.y = 0.0 if back else PI
		plates.append(local_registration)
		var band := MeshInstance3D.new()
		var strip := BoxMesh.new(); strip.size = Vector3(.48,.025,.02)
		band.mesh = strip; band.position = plate.position+Vector3.UP*.056
		var blue := StandardMaterial3D.new(); blue.albedo_color = Color("2151a1")
		band.material_override = blue; add_child(band)

func _label(text: String, point: Vector3, pixel: float, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text; label.position = point; label.pixel_size = pixel
	label.font_size = 48; label.outline_size = 0; label.modulate = color
	label.no_depth_test = false
	add_child(label)
	return label

func _ready() -> void:
	if sign_material == null or plates.is_empty(): _recover_state()
	var vehicle = get_parent().get_parent()
	if vehicle != null and "vehicle_id" in vehicle: registration(vehicle.vehicle_id)

func registration(id: String) -> void:
	var text := "HBR-%04d" % (absi(id.hash())%10000)
	for plate in plates: plate.text = text

func set_available(value: bool) -> void:
	available = value
	# Táxi vindo da cena assada chega sem `sign_material` (veja _recover_state).
	if sign_material == null: _recover_state()
	if sign_material == null: return
	sign_material.emission_energy_multiplier = .65 if value else 0.0
	sign_material.albedo_color = Color("fff0b0") if value else Color("575249")


## O táxi do jogo vem de `assets/fleet/redesigned/taxi_yellow.scn` (RedesignedFleet), assado
## por tools/fleet_fixups/build_passenger_batch.gd DEPOIS de decorate(): o nó TaxiLivery volta
## da cena com o script, mas sem as variáveis (não são exportadas), e o assado fundiu o
## letreiro numa superfície da malha única "Body" (medido em 16/10: superfície 11, emissiva,
## albedo fff0b0). Por isso a busca por peça/geometria de build() não acha nada aqui, e
## `sign_material` nulo dava os 3 erros em TaxiRank._close_slot do log de 16/10 e travava
## tests/test_taxi_service.gd. Reencontra placas e letreiro e dá a cada carro um material
## próprio: o da cena é sub-recurso compartilhado, apagaria o letreiro de todos os táxis juntos.
func _recover_state() -> void:
	for child in get_children():
		if child is Label3D and str(child.text).begins_with("HBR-") and not plates.has(child): plates.append(child)
	var model := get_parent()
	if model == null or sign_material != null: return
	var reference := _new_sign_material()
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or is_ancestor_of(part): continue
		for index in part.mesh.get_surface_count():
			var material := part.get_active_material(index) as StandardMaterial3D
			if material == null or not material.emission_enabled: continue
			if not material.albedo_color.is_equal_approx(reference.albedo_color): continue
			if not material.emission.is_equal_approx(reference.emission): continue
			# Cópia do material assado (mantém o acabamento da cena), uma por carro.
			if sign_material == null: sign_material = material.duplicate() as StandardMaterial3D
			part.set_surface_override_material(index, sign_material)
