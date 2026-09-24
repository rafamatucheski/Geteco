extends SceneTree
## Dano do veículo: desgaste sem mudar o matiz, fogo no motor que leva à explosão,
## carcaça carbonizada (não marrom) e reparo que devolve tudo.

const VEHICLE := preload("res://scripts/Vehicle.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

## Marrom = canal vermelho claramente acima do azul num tom escuro. Carvão é neutro/frio.
func warm_dark(color: Color) -> bool:
	return color.v < .4 and color.r - color.b > .05

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	for archetype: String in ["", "sport_coupe"]:
		var car := VEHICLE.new()
		car.archetype = archetype
		car.paint_color = Color("d5a544")
		world.add_child(car)
		car.place(Vector3(0, .12, 0), 0)
		await physics_frame
		car.set_physics_process(false)
		var label := archetype if not archetype.is_empty() else "coupe"
		var paint: StandardMaterial3D = car._paint.materials[0]
		var gloss := paint.roughness
		var exploded := [0]
		car.destroyed.connect(func(): exploded[0] += 1)

		car.receive_damage(car.max_health * .55)
		check(paint.albedo_color.is_equal_approx(Color("d5a544")), label + ": desgaste não escurece a pintura")
		check(paint.roughness > gloss, label + ": desgaste tira o brilho")
		check(paint.detail_enabled and paint.detail_albedo != null, label + ": desgaste mostra riscos")
		check(not car.damage_look.burning, label + ": 45% de vida ainda não pega fogo")

		car.receive_damage(car.max_health * .3)
		check(car.damage_look.burning and car.health > 0, label + ": abaixo de 20% o motor pega fogo")
		var seconds := 0.0
		while car.health > 0 and seconds < 6.0:
			await physics_frame
			seconds += 1.0 / Engine.physics_ticks_per_second
		check(car.health <= 0 and exploded[0] == 1, label + ": o fogo leva à explosão (%.1fs)" % seconds)
		check(seconds < 4.5, label + ": explosão sai em poucos segundos")
		check(car.damage_look.wrecked, label + ": carcaça ativa")
		for i in 40: await process_frame
		var warm := 0
		var parts := 0
		for part: MeshInstance3D in car.visual.find_children("*", "MeshInstance3D", true, false):
			for index in part.mesh.get_surface_count():
				var material := part.get_active_material(index) as StandardMaterial3D
				if material == null or material.albedo_color.a < .01: continue
				parts += 1
				if warm_dark(material.albedo_color): warm += 1
				check(not material.albedo_color.is_equal_approx(Color("292728")), label + ": material chapado antigo não volta")
		check(parts > 0 and warm == 0, label + ": nenhuma superfície da carcaça é marrom (%d/%d)" % [warm, parts])
		check(car.visual.position.y < 0, label + ": carcaça assenta sobre os aros")

		car.repair()
		check(car.health == car.max_health and not car.damage_look.wrecked, label + ": reparo zera o dano")
		check(paint.roughness == gloss and not paint.detail_enabled, label + ": reparo devolve a pintura")
		check(car.visual.position == Vector3.ZERO, label + ": reparo endireita a lataria")
		var restored := car.visual.find_children("*", "MeshInstance3D", true, false).any(func(part): return part.get_active_material(0) == paint or part.material_override == paint)
		check(restored, label + ": pintura original volta às peças")
		car.damage_look.ignite(null)
		check(car.damage_look.burning and car.damage_look._fire.emitting, label + ": impacto de lança-chamas acende o motor na hora")
		car.repair()
		car.queue_free()
	print("VEHICLE_DAMAGE_LOOK checks=%d failures=%d" % [checks, failures.size()])
	for failure in failures: print("  FAIL ", failure)
	quit(0 if failures.is_empty() else 1)
