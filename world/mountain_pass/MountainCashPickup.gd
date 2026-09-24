extends "res://world/mountain_pass/MountainWeaponPickup.gd"

var amount := 250

func install_model(parent: Node3D, point: Vector3) -> void:
	model = Node3D.new()
	model.name = name + "Model"
	model.position = point
	_floor_height = point.y
	parent.add_child(model)
	var bundle := Node3D.new()
	bundle.name = "FloorWeapon"
	bundle.position.y = hover_height
	model.add_child(bundle)
	for i in 5:
		var note := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.34, 0.024, 0.18)
		note.mesh = box
		note.position = Vector3(0, i * 0.026, 0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("77946b") if i % 2 == 0 else Color("c9d3a6")
		material.roughness = 0.9
		note.material_override = material
		bundle.add_child(note)
	var band := MeshInstance3D.new()
	var band_mesh := BoxMesh.new()
	band_mesh.size = Vector3(0.075, 0.136, 0.187)
	band.mesh = band_mesh
	band.position.y = 0.054
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("eee5c9")
	band.material_override = paper
	bundle.add_child(band)
	_install_halo()
	var halo: MeshInstance3D = model.get_node("FloorHalo")
	halo.mesh.inner_radius = 0.30
	halo.mesh.outer_radius = 0.325
	halo.material_override.albedo_color = Color("a6e889")

func _collect(body: Node2D) -> void:
	if collected or not body.is_in_group("player") or not body.is_visible_in_tree() or body.get("is_dead") == true or body.get("is_in_dialogue") == true or body.get("is_control_disabled") == true:
		return
	if is_instance_valid(render_host) and not render_host.contains_actor(body): return
	if body.world_pickups_collected.has(pickup_id):
		_hide_collected()
		return
	body.world_pickups_collected.append(pickup_id)
	body.money += amount
	var hud := get_tree().get_first_node_in_group("hud")
	if is_instance_valid(hud): hud.set_money(body.money)
	_hide_collected()
	body._show_weapon_notice("+$ %s" % amount)
	get_node("/root/SaveManager").request_autosave("Dinheiro encontrado")
