extends SceneTree
## Lixeira/caixa atropelada vira corpo rígido: não atravessa parede, a tampa
## solta, o lixo espalha e tudo repousa no chão.
class Director extends Node3D:
	var litter := 0
	var glass := 0
	func spawn_litter(_p: Vector3, _d: Vector3) -> void: litter += 1
	func spawn_glass(_p: Vector3, _d: Vector3) -> void: glass += 1
	func spawn_geyser(_p: Vector3) -> void: pass
	func play_prop_hit(_p: Vector3, _f: String, _s: float) -> void: pass
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func verify(value: bool, label: String) -> void:
	if not value: failures.append(label); push_error(label)
func _static_box(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)
	body.global_position = at
func run() -> void:
	var fragile = load("res://gameplay/street_physics/FragileProps3D.gd")
	var kit = load("res://world/city_look/CityPropKit.gd")
	_static_box(Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	# Parede a 4 m à frente do choque (+X).
	_static_box(Vector3(0.4, 6, 20), Vector3(4.2, 3, 0))
	var director := Director.new()
	root.add_child(director)
	var chunk := Node3D.new()
	root.add_child(chunk)
	for kind in ["trash_can", "news_box", "mailbox", "hydrant"]:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = kit.mesh(kind)
		multimesh.instance_count = 1
		multimesh.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
		fragile.register_instance(kind, multimesh, 0, chunk)
		var items: Array = fragile.query(Vector3.ZERO, 1.0)
		verify(items.size() == 1, kind + ": registrado")
		if items.is_empty(): continue
		verify(fragile.hit(items[0], 16.0, Vector3.RIGHT, director), kind + ": cedeu a 16 m/s")
		# Instância original some por escala zero; o RenderingServer dummy do headless
		# não guarda transformações de MultiMesh, então aqui só o estado é conferível.
		verify(items[0].state == "down", kind + ": marcado como derrubado")
		var bodies: Array = director.find_children("*", "RigidBody3D", true, false)
		verify(bodies.size() >= (2 if kind == "trash_can" else 1), kind + ": destroço físico (" + str(bodies.size()) + ")")
		for body in bodies:
			for visual: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
				for surface in visual.mesh.get_surface_count():
					var material := visual.get_active_material(surface) as StandardMaterial3D
					verify(material != null, kind + ": destroço mantém material")
					if material == null: continue
					if kind == "trash_can":
						verify(material.albedo_color != Color.WHITE, kind + ": lata e tampa mantêm cor")
					else:
						verify(material.vertex_color_use_as_albedo and material.vertex_color_is_srgb, kind + ": preserva cores por vértice em sRGB")
		var max_x := -INF
		for i in 240:
			await physics_frame
			for b in bodies: if is_instance_valid(b): max_x = maxf(max_x, b.global_position.x)
		for b in bodies:
			verify(b.global_position.x < 4.0, kind + ": atravessou a parede x=" + str(b.global_position.x))
			verify(b.global_position.y > -0.2 and b.global_position.y < 1.5, kind + ": repousa no chão y=" + str(b.global_position.y))
			verify(b.linear_velocity.length() < 1.5, kind + ": parou v=" + str(b.linear_velocity.length()))
		verify(max_x > 2.0, kind + ": foi lançado até a parede (max x=" + str(max_x) + ")")
		for b in bodies: b.free()
		fragile.cells.clear()
	verify(director.litter >= 2, "lixo espalhado (" + str(director.litter) + ")")
	verify(director.glass >= 1, "vidro do jornaleiro")
	print("FRAGILE_DEBRIS_PHYSICS failures=", failures)
	quit(0 if failures.is_empty() else 1)
