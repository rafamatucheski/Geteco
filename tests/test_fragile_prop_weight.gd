extends SceneTree
## Lixo, lixeira e mobília atropelados têm peso (playtest de 29/10: "voam como papel").
## Contrato do lançamento (momento limitado pela massa, sem decolar) e simulação real
## dos destroços num chão plano: altura máxima, distância e repouso por tipo.
class Director extends Node3D:
	func spawn_litter(_p: Vector3, _d: Vector3) -> void: pass
	func spawn_glass(_p: Vector3, _d: Vector3) -> void: pass
	func spawn_geyser(_p: Vector3) -> void: pass
	func play_prop_hit(_p: Vector3, _f: String, _s: float) -> void: pass

var failures: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("run")

func verify(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	var fragile = load("res://gameplay/street_physics/FragileProps3D.gd")
	var kit = load("res://world/city_look/CityPropKit.gd")
	# 1) Contrato do lançamento, sem física.
	var kinds := ["trash_bags", "trash_can", "wheelie_bins", "news_box", "planter", "dumpster"]
	for speed in [8.0, 16.0, 30.0]:
		var previous := INF
		for kind in kinds:
			var mass := float(fragile.MASSES[kind])
			var launch: Vector3 = fragile.launch_velocity(kind, speed, Vector3.RIGHT, 1.05, 0.12)
			var horizontal := Vector2(launch.x, launch.z).length()
			verify(horizontal <= speed, "%s a %d m/s: não sai mais rápido que o carro (%.1f)" % [kind, speed, horizontal])
			verify(horizontal * mass <= fragile.IMPULSE_CAP * 1.13, "%s a %d m/s: impulso limitado (%.0f N·s)" % [kind, speed, horizontal * mass])
			verify(launch.y <= fragile.MAX_LIFT + 0.001, "%s a %d m/s: não decola (sobe %.2f m/s)" % [kind, speed, launch.y])
			verify(horizontal <= previous + 0.001, "%s a %d m/s: mais pesado não sai mais rápido" % [kind, speed])
			previous = horizontal
			var spin: Vector3 = fragile.launch_spin(kind, launch, Vector3.FORWARD, 1.0)
			verify(spin.length() <= 8.0, "%s a %d m/s: giro contido (%.1f rad/s)" % [kind, speed, spin.length()])
	var dumpster: Vector3 = fragile.launch_velocity("dumpster", 20.0, Vector3.RIGHT)
	verify(dumpster.length() < 8.5, "caçamba a 72 km/h é empurrada, não arremessada (%.1f m/s)" % dumpster.length())
	# 2) Simulação: chão plano largo, choque a 20 m/s (72 km/h).
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 60)
	shape.shape = box
	floor_body.add_child(shape)
	root.add_child(floor_body)
	floor_body.global_position = Vector3(60, -0.5, 0)
	var director := Director.new()
	root.add_child(director)
	var chunk := Node3D.new()
	root.add_child(chunk)
	# Distância máxima de repouso por tipo a 20 m/s (antes: lata ~30 m, caçamba ~25 m).
	var limits := {"trash_can": 22.0, "trash_bags": 22.0, "dumpster": 7.0, "news_box": 20.0}
	for kind in limits:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = kit.mesh(kind)
		multimesh.instance_count = 1
		multimesh.set_instance_transform(0, Transform3D.IDENTITY)
		fragile.register_instance(kind, multimesh, 0, chunk)
		var items: Array = fragile.query(Vector3.ZERO, 1.0)
		verify(items.size() == 1, kind + ": registrado")
		if items.is_empty(): continue
		verify(fragile.hit(items[0], 20.0, Vector3.RIGHT, director), kind + ": cede a 20 m/s")
		var bodies: Array = director.find_children("*", "RigidBody3D", true, false)
		verify(not bodies.is_empty(), kind + ": vira destroço físico")
		# Subida do centro de cada forma de colisão acima de onde nasceu: a origem do
		# corpo fica na base e sobe sozinha quando o objeto tomba de lado.
		var start := {}
		for body in bodies:
			start[body] = _shape_center_y(body)
		var peak := 0.0
		for i in 300:
			await physics_frame
			for body in bodies:
				if is_instance_valid(body): peak = maxf(peak, _shape_center_y(body) - float(start[body]))
		var farthest := 0.0
		for body in bodies:
			if not is_instance_valid(body): continue
			farthest = maxf(farthest, Vector2(body.global_position.x, body.global_position.z).length())
			verify(body.linear_velocity.length() < 1.0, "%s: repousa em 5 s (v=%.2f)" % [kind, body.linear_velocity.length()])
		print("%s: sobe %.2f m, repouso a %.1f m" % [kind, peak, farthest])
		# Rolar de quina sobe o centro alguns decímetros; decolar seria passar de meio metro.
		verify(peak < 0.5, "%s: não decola (sobe %.2f m)" % [kind, peak])
		verify(farthest < float(limits[kind]), "%s: para perto (%.1f m, limite %.0f)" % [kind, farthest, limits[kind]])
		verify(farthest > 0.8, "%s: o choque ainda empurra (%.1f m)" % [kind, farthest])
		for body in bodies:
			if is_instance_valid(body): body.free()
		fragile.cells.clear()
	print("FRAGILE_PROP_WEIGHT checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _shape_center_y(body: RigidBody3D) -> float:
	for child in body.get_children():
		if child is CollisionShape3D: return (body.global_transform * (child as CollisionShape3D).position).y
	return body.global_position.y
