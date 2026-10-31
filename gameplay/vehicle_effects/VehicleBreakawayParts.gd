extends Node
## Apresentação de colisão compartilhada entre jogador e trânsito, apoiada em geometria de painel preparada offline.
## Os originais ficam no veículo para deformação/reparo; as cópias soltas moram no mundo.
const DEBRIS := preload("res://gameplay/vehicle_effects/VehiclePanelDebris.gd")
const PART_IDS := ["hood","bumper_front","bumper_rear"]
const MIN_CLOSING_SPEED := 5.0
var vehicle: CharacterBody3D
var panels: Dictionary = {}
var spawned_count := 0
var _debris: Array[WeakRef] = []

func configure(car: CharacterBody3D) -> void:
	vehicle = car
	set_process(false)
	set_physics_process(false)
	for part: MeshInstance3D in car.visual.find_children("*","MeshInstance3D",true,false):
		var id := str(part.get_meta("breakaway_part_id",""))
		if id in PART_IDS:
			panels[id] = {"node":part,"damage":0.0,"rest":part.transform,"visible":part.visible}

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true # Saves predating detachable panels.
	if value.get("version") != 1 or not value.get("parts") is Dictionary or value.parts.size()>PART_IDS.size(): return false
	for id in value.parts:
		if id not in PART_IDS: return false
		var amount: Variant = value.parts[id]
		if typeof(amount) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(amount)) or float(amount)<0.0 or float(amount)>1.0: return false
	return true

func snapshot() -> Dictionary:
	var state := {}
	for id in panels:
		if float(panels[id].damage)>0.0: state[id] = float(panels[id].damage)
	return {} if state.is_empty() else {"version":1,"parts":state}

func restore_state(state: Dictionary) -> void:
	if not valid_state(state): return
	repair()
	for id in state.get("parts",{}):
		if not panels.has(id): continue
		panels[id].damage = float(state.parts[id])
		var part: MeshInstance3D = panels[id].node
		if is_instance_valid(part): part.visible = bool(panels[id].visible) and float(panels[id].damage)<1.0

func detached_count() -> int:
	var count := 0
	for entry in panels.values():
		if float(entry.damage)>=1.0: count += 1
	return count

func impact(point: Vector3, closing_speed: float, inward: Vector3, presentation_velocity := Vector3.INF) -> void:
	if not is_finite(closing_speed) or closing_speed<MIN_CLOSING_SPEED or not point.is_finite() or not inward.is_finite(): return
	# Só o contato real na frente/traseira pode arrancar as fixações. Raspões laterais ainda amassam a casca.
	var longitudinal := absf(point.z)/maxf(vehicle.half_length,.1)
	var lateral := absf(point.x)/maxf(vehicle.half_width,.1)
	if longitudinal<.62 or longitudinal<lateral*.80: return
	var frontal := point.z<0.0
	var strength := clampf((closing_speed-MIN_CLOSING_SPEED)/20.0,0.0,1.65)
	var ids := ["bumper_front","hood"] if frontal else ["bumper_rear"]
	for id in ids:
		if not panels.has(id): continue
		if id=="hood" and absf(inward.z)<.45: continue
		var entry: Dictionary = panels[id]
		if float(entry.damage)>=1.0: continue
		# A grazing corner transfers less force to the hood than a central frontal hit.
		var axis_weight := clampf(absf(inward.z),.35,1.0)
		var factor := lerpf(.78,.42,clampf(lateral,0,1))*axis_weight if id=="hood" else axis_weight
		entry.damage = minf(1.0,float(entry.damage)+strength*factor*vehicle.damage_resistance)
		if float(entry.damage)>=1.0: _detach(id,entry,closing_speed,inward,point,presentation_velocity)

func _detach(id: String, entry: Dictionary, closing_speed: float, inward: Vector3, point: Vector3, presentation_velocity: Vector3) -> void:
	var original: MeshInstance3D = entry.node
	if not is_instance_valid(original) or original.mesh==null: return
	# A deformação de malha aloca substitutas, então esta malha atual fica imutável dali em diante.
	var copy := MeshInstance3D.new()
	copy.name = "DetachedPanel"
	copy.mesh = original.mesh
	copy.cast_shadow = original.cast_shadow
	copy.layers = original.layers
	if original.material_overlay != null: copy.material_overlay = original.material_overlay.duplicate()
	if original.material_override != null: copy.material_override = original.material_override.duplicate()
	else:
		for surface in original.mesh.get_surface_count():
			var material := original.get_active_material(surface)
			if material != null: copy.set_surface_override_material(surface,material.duplicate())
	var body := DEBRIS.new()
	body.name = "PanelDebris_"+id
	body.panel_id = id
	body.source_vehicle_id = vehicle.vehicle_id
	body.panel_mesh = copy
	body.mass = 12.0 if id=="hood" else 8.0
	body.collision_layer = 0
	body.collision_mask = 1 # Só o mundo. Sem colisão com trânsito, pedestres ou o dono.
	body.continuous_cd = true
	body.linear_damp = .35
	body.angular_damp = .8
	var contact := PhysicsMaterial.new()
	contact.friction = .85
	contact.bounce = .12
	body.physics_material_override = contact
	var pose := original.global_transform
	var scale := pose.basis.get_scale().abs()
	var rotation := pose.basis.orthonormalized()
	var local_bounds := original.mesh.get_aabb()
	var scaled_bounds := AABB(local_bounds.position*scale,local_bounds.size*scale)
	var center := scaled_bounds.get_center()
	copy.transform = Transform3D(Basis.from_scale(scale),-center)
	body.add_child(copy)
	var collider := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = scaled_bounds.size.max(Vector3(.08,.045,.08))
	collider.shape = hull
	body.add_child(collider)
	var world := vehicle.get_parent()
	if not is_instance_valid(world): body.free(); return
	world.add_child(body)
	body.global_transform = Transform3D(rotation,pose.origin+rotation*center+Vector3.UP*.05)
	var launch := vehicle.global_basis*inward
	launch.y = 0
	if launch.length_squared()<.01: launch = vehicle.global_basis.z if id!="bumper_rear" else -vehicle.global_basis.z
	launch = launch.normalized()
	var inherited: Vector3 = presentation_velocity if presentation_velocity.is_finite() else vehicle.horizontal_velocity
	if id=="hood":
		# O deslocamento relativo passa da cabine antes da descida; a borda traseira vira para cima.
		# A folga inclui a meia largura do painel porque só o centro dele pode passar de um teto.
		var side := 1.0 if point.x>=0 else -1.0
		var lateral := clampf((vehicle.half_width+scaled_bounds.size.x*.5+.20)/.60,3.0,4.0)
		body.linear_velocity = inherited + launch*clampf(closing_speed*.12,1.0,4.0) + vehicle.global_basis.x*side*lateral + Vector3.UP*5.0
		body.angular_velocity = vehicle.global_basis*Vector3(-.6,0,.2*side)
	else:
		# Para-choques quebrados caem da fixação, para longe do corpo do dono.
		var outward := -vehicle.global_basis.z if id=="bumper_front" else vehicle.global_basis.z
		body.linear_velocity = inherited + outward*(.5 if id=="bumper_front" else 2.0) + Vector3.DOWN*.8
		body.angular_velocity = vehicle.global_basis*Vector3(1.4,signf(original.position.x)*.6,.7)
	body.reset_physics_interpolation()
	original.hide()
	_debris.append(weakref(body))
	spawned_count += 1

func repair() -> void:
	for entry in panels.values():
		entry.damage = 0.0
		var part: MeshInstance3D = entry.node
		if is_instance_valid(part):
			part.transform = entry.rest
			part.visible = entry.visible
	for reference in _debris:
		var body: Variant = reference.get_ref()
		if is_instance_valid(body):
			body.hide()
			body.collision_mask = 0
			body.queue_free()
	_debris.clear()
