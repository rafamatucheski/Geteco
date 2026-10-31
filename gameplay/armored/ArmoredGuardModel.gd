extends "res://gameplay/PoliceModel.gd"
## Private armored security: shared articulated body, ballistic vest and radio.
var carrying := false
var cash_case: Node3D
var case_dropped := false

func _ready() -> void:
	tier = UnitTier.SWAT
	super._ready()
	_uniform_base_color = Color("394840")
	_build_case.call_deferred()

func _body_look() -> Dictionary:
	var look := super._body_look()
	look.merge({"top": 8, "hat": 4, "top_color": Color("394840"), "bottom_color": Color("262e2b"), "accent": Color("1e2522"), "inner": Color("c5c4ad"), "shoe_color": Color("171b19")}, true)
	return look

func _build_case() -> void:
	if not is_inside_tree(): return
	cash_case = Node3D.new()
	cash_case.name = "CashCase"
	add_child(cash_case)
	_piece(Vector3(.39, .29, .14), Vector3.ZERO, Color("4a514b"))
	for side in [-1, 1]:
		_piece(Vector3(.018, .29, .15), Vector3(side * .177, 0, 0), Color("80877f"))
		_piece(Vector3(.035, .038, .015), Vector3(side * .11, .105, -.077), Color("b5b8aa"))
		_piece(Vector3(.014, .055, .024), Vector3(side * .057, .168, 0), Color("1c221e"))
	_piece(Vector3(.128, .018, .024), Vector3(0, .194, 0), Color("1c221e"))
	cash_case.hide()

func _piece(size: Vector3, point: Vector3, color: Color) -> void:
	var piece := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	piece.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .72
	piece.material_override = material
	piece.position = point
	cash_case.add_child(piece)

func _body_weapon_targets() -> Array:
	var hands := super._body_weapon_targets()
	if not is_instance_valid(cash_case) or case_dropped: return hands
	cash_case.visible = carrying
	weapon.visible = not carrying
	if not carrying or not is_instance_valid(body): return hands
	var grip := Vector3(.30, .76, .04)
	cash_case.global_transform = Transform3D(body.global_basis, body.to_global(grip - Vector3.UP * .194))
	return [null, body.to_global(grip)]

func drop_case() -> void:
	if case_dropped or not is_instance_valid(cash_case) or not cash_case.visible: return
	case_dropped = true
	carrying = false
	# Larga no escopo do ator atual para que a limpeza do comboio também remova a maleta.
	var actor := get_parent() as Node3D
	if actor == null or actor.get_parent() == null: return
	if actor.get("dead") != true: weapon.show()
	cash_case.reparent(actor.get_parent(), true)
	cash_case.set_meta("armored_dropped_case", true)
	var ray := PhysicsRayQueryParameters3D.create(cash_case.global_position + Vector3.UP * .2, cash_case.global_position + Vector3.DOWN * 2.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var floor_y := float(hit.position.y) if not hit.is_empty() else actor.global_position.y
	var tween := cash_case.create_tween()
	tween.tween_property(cash_case, "global_position:y", floor_y + .075, .24)
	tween.parallel().tween_property(cash_case, "rotation:x", PI * .5, .24)
