extends "res://tests/test_vehicle_glass_damage.gd"
## Carro parado em cima da borda de um canteiro levando tiros (vídeo de 26/10/2026: o Monaliza meio em cima
## do canteiro afundou no chão depois dos tiros). Chão fino como o da cidade (malha de colisão só com a face
## de cima), canteiro elevado 18 cm; o carro assenta com uma roda no canteiro, leva uma rajada e não pode
## atravessar o chão.
## Uso: "$GODOT" --headless --path . --script res://tests/test_vehicle_curb_rest.gd -- --no-save [arquétipo]
func _floor(y: float, rect: Rect2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new()
	var a := Vector3(rect.position.x, y, rect.position.y)
	var b := Vector3(rect.end.x, y, rect.position.y)
	var c := Vector3(rect.end.x, y, rect.end.y)
	var d := Vector3(rect.position.x, y, rect.end.y)
	shape.set_faces(PackedVector3Array([a, b, c, a, c, d]))
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	root.add_child(body)
	return body

func run() -> void:
	var id := "monaliza"
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"): id = arg
	var combat := Combat.new()
	root.add_child(combat)
	_floor(0.0, Rect2(-40, -40, 80, 80))
	# Canteiro: tampo elevado e as laterais (meio-fio) como caixa sólida, igual aos lotes da cidade.
	var planter := StaticBody3D.new()
	planter.collision_layer = 1
	var box := CollisionShape3D.new()
	box.shape = BoxShape3D.new()
	box.shape.size = Vector3(6, .18, 20)
	box.position = Vector3(3.0 + .9, .09, 0)
	planter.add_child(box)
	root.add_child(planter)
	var car := car_at(id, Vector3(0, .6, 0))
	car.rotation.y = PI * .5
	car.set_physics_process(true)
	var lowest := INF
	for tick in 120:
		await physics_frame
	var rest_y := car.global_position.y
	print("CURB_REST assentou em y=%.3f" % rest_y)
	check(rest_y > -.2, id + " assenta sobre o chão e a borda do canteiro (y=%.2f)" % rest_y)
	# Rajada de 20 tiros pela lateral, como no vídeo, e mais 3 s de física.
	for shot in 20:
		var from := car.global_position + Vector3(-6, 1.0, randf_range(-1.5, 1.5))
		combat._damage_bullet(car, 25.0, null, from, from + Vector3(12, -.4, 0))
		await physics_frame
		lowest = minf(lowest, car.global_position.y)
	for tick in 180:
		await physics_frame
		lowest = minf(lowest, car.global_position.y)
	print("CURB_REST mais baixo y=%.3f, saúde %.0f" % [lowest, car.health])
	check(lowest > -.5, id + " não atravessa o chão depois dos tiros (mais baixo y=%.2f)" % lowest)
	car.free()
	combat.free()
	print("VEHICLE_CURB_REST checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
