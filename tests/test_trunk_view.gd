extends SceneTree
## Validador isolado para res://runtime/TrunkView.gd, a apresentação V2 do
## porta-malas do Monaliza (tampa 3D real + modelos de arma, sem precisar da ligação
## de PersonalCar/sessão para exercitá-lo).
class MockCar extends Node3D:
	var visual: Node3D
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var car := MockCar.new()
	root.add_child(car)
	var visual := Node3D.new()
	car.add_child(visual)
	car.visual = visual
	var pivot := Node3D.new()
	pivot.name = "MonalizaTrunkHinge"
	visual.add_child(pivot)
	var camera := preload("res://scripts/CameraRig.gd").new()
	root.add_child(camera)
	camera.target = car
	camera.locked = false
	camera.offset = Vector3(1, 2, 3)
	camera.target_size = 20.0

	var view = preload("res://runtime/TrunkView.gd").new()
	root.add_child(view)
	view.open(car, camera)
	check(view.pivot == pivot, "Trunk view did not find the MonalizaTrunkHinge pivot")
	# A câmera trava num foco que acompanha a bandeja do porta-malas, não o centro do carro.
	check(camera.locked and is_instance_valid(view.focus_anchor) and camera.target == view.focus_anchor, "Camera did not lock onto the trunk focus")
	for frame in 30: await process_frame
	check(pivot.rotation.x < -1.5, "Trunk lid never opened (rotation.x=%s)" % pivot.rotation.x)
	check(view.weapons.position.y > 0.15, "Loadout tray never rose (y=%s)" % view.weapons.position.y)
	var rect := root.get_visible_rect().size
	var centre := camera.unproject_position(view.tray_point())
	check(absf(centre.x / rect.x - 0.5) < 0.01 and absf(centre.y / rect.y - 0.5) < 0.01, "Without a side panel the tray should be at screen centre (screen=%s)" % centre)
	# Inventário ancorado à direita: a bandeja vai para o meio da área livre à esquerda.
	view.screen_focus = func(): return Vector2(0.25, 0.5)
	for frame in 2: await process_frame
	var left := camera.unproject_position(view.tray_point())
	check(absf(left.x / rect.x - 0.25) < 0.01 and absf(left.y / rect.y - 0.5) < 0.01, "Tray not framed in the free area left of the panel (screen=%s)" % left)
	# Painel ainda sem tamanho: não desloca para um ponto inválido.
	view.screen_focus = func(): return null
	for frame in 2: await process_frame
	var pending := camera.unproject_position(view.tray_point())
	check(absf(pending.x / rect.x - 0.5) < 0.01, "Pending panel should keep the tray centred (screen=%s)" % pending)

	view.update_loadout({"curta": "pistol", "longa": "", "corpo": "", "granada": ""})
	await process_frame
	check(view.slot_models.get("curta") != null and is_instance_valid(view.slot_models.curta), "Pistol slot has no model after update_loadout")
	check(view.slot_models.curta.get_child_count() > 0, "Pistol slot model has no built geometry")
	check(str(view.displayed.get("longa","x")) == "", "Empty slot should stay empty")

	view.update_loadout({"curta": "", "longa": "", "corpo": "", "granada": ""})
	await process_frame
	check(view.slot_models.curta.get_child_count() == 0, "Cleared slot still shows a weapon model")

	view.close()
	await process_frame
	check(pivot.rotation.x == 0.0, "Trunk lid did not close")
	check(not camera.locked and camera.target == car, "Camera framing was not restored after close")
	check(not is_instance_valid(view) or view.is_queued_for_deletion(), "TrunkView did not free itself on close")

	for failure in failures: push_error(failure)
	print("TRUNK_VIEW ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
