extends SceneTree
## Carro molhado pela chuva: pintura escurece/brilha com gotas e volta exatamente ao seco.
const RAIN := preload("res://gameplay/vehicle_effects/VehicleRain.gd")
const DAMAGE := preload("res://gameplay/vehicle_effects/VehicleDamage.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("ok   " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _init() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(.6, .2, .1)
	paint.roughness = .5
	paint.clearcoat_enabled = true
	paint.clearcoat = .4
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	check(paint.roughness < .5 and paint.roughness >= .05, "molhada fica mais brilhante")
	check(paint.clearcoat > .4, "verniz aumenta")
	check(paint.albedo_color.r < .6 and paint.albedo_color.a == 1.0, "cor escurece sem mudar alfa")
	check(RAIN.has_beads(paint) and not paint.normal_enabled and not paint.uv1_triplanar, "gotas independentes não alteram normal nem UV da pintura")
	var drops := paint.next_pass as ShaderMaterial
	RAIN.apply_material_for_test(paint, .5, .5, 1.0)
	check(paint.roughness > .05 and paint.roughness < .5 and is_equal_approx(float(drops.get_shader_parameter("wet")), .5), "meio molhada fica no meio")
	check(paint.next_pass == drops, "atualizar umidade reutiliza a camada de gotas")
	RAIN.apply_material_for_test(paint, 0.0, 0.0, 1.0)
	check(is_equal_approx(paint.roughness, .5) and is_equal_approx(paint.clearcoat, .4), "seca devolve rugosidade e verniz")
	check(paint.albedo_color.is_equal_approx(Color(.6, .2, .1)) and not RAIN.has_beads(paint) and paint.next_pass == null, "seca devolve cor e remove gotas")
	check(not paint.has_meta("rain_base") and not paint.has_meta("rain_drops"), "sem resíduo de estado quando seco")

	# Repintura no meio da chuva: a nova cor vira a base, não é desfeita.
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	paint.albedo_color = Color(.1, .3, .7)
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	RAIN.apply_material_for_test(paint, 0.0, 0.0, 1.0)
	check(paint.albedo_color.is_equal_approx(Color(.1, .3, .7)), "repintura durante a chuva sobrevive à secagem")
	check(is_equal_approx(paint.roughness, .5) and is_equal_approx(paint.clearcoat, .4), "repintar não transforma o brilho molhado em base permanente")
	# Alterar só o acabamento não autoriza multiplicar outra vez a cor molhada.
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	var wet_color := paint.albedo_color
	paint.roughness = .72
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	check(paint.albedo_color.is_equal_approx(wet_color), "mudança de rugosidade preserva o tom molhado")
	for update in 4: RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	check(paint.albedo_color.is_equal_approx(wet_color), "atualizações repetidas não acumulam escurecimento")
	RAIN.apply_material_for_test(paint, 0.0, 0.0, 1.0)
	check(is_equal_approx(paint.roughness, .72) and paint.albedo_color.is_equal_approx(Color(.1, .3, .7)), "secar mantém apenas o acabamento externo novo")

	# Amassado manda na normal: gotas não a substituem nem a apagam ao secar.
	var dented := StandardMaterial3D.new()
	dented.normal_enabled = true
	dented.normal_texture = DAMAGE._dents()
	dented.normal_scale = .55
	dented.uv1_triplanar = true
	dented.uv1_scale = Vector3(.55, .55, .55)
	RAIN.apply_material_for_test(dented, 1.0, 1.0, 1.0)
	check(dented.normal_texture == DAMAGE._dents() and RAIN.has_beads(dented), "amassado e gotas coexistem")
	check(is_equal_approx(dented.normal_scale, .55) and dented.uv1_triplanar and dented.uv1_scale.is_equal_approx(Vector3(.55, .55, .55)), "chuva preserva escala e mapeamento do amassado")
	RAIN.apply_material_for_test(dented, 0.0, 0.0, 1.0)
	check(dented.normal_texture == DAMAGE._dents() and dented.normal_enabled, "secar não apaga o amassado")

	# Gotas não ocupam UV1: pintura texturizada também pode molhar sem distorcer.
	var textured := StandardMaterial3D.new()
	var texture := ImageTexture.create_from_image(Image.create_empty(4, 4, false, Image.FORMAT_RGBA8))
	textured.albedo_texture = texture
	textured.uv1_scale = Vector3(2, 3, 1)
	textured.uv1_offset = Vector3(.2, .3, 0)
	RAIN.apply_material_for_test(textured, 1.0, 1.0, 1.0)
	check(RAIN.has_beads(textured) and not textured.normal_enabled and not textured.uv1_triplanar, "pintura texturizada ganha gotas independentes")
	RAIN.apply_material_for_test(textured, 0.0, 0.0, 1.0)
	check(textured.albedo_texture == texture and textured.uv1_scale == Vector3(2, 3, 1) and textured.uv1_offset == Vector3(.2, .3, 0), "molhar e secar preserva textura, escala e posição dos UVs")

	var finish := StandardMaterial3D.new()
	paint.next_pass = finish
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	drops = paint.next_pass
	check(drops.next_pass == finish, "chuva preserva acabamento adicional existente")
	RAIN.apply_material_for_test(paint, 0.0, 0.0, 1.0)
	check(paint.next_pass == finish, "secagem restaura acabamento adicional")
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	var new_finish := StandardMaterial3D.new()
	paint.next_pass = new_finish
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	check(RAIN.has_beads(paint), "trocar acabamento adicional não perde gotas permanentemente")
	RAIN.apply_material_for_test(paint, 0.0, 0.0, 1.0)
	check(paint.next_pass == new_finish, "secar preserva acabamento adicional trocado durante a chuva")

	# O mesmo carro encharcado precisa distinguir garoa de tempestade.
	RAIN._apply_material(paint, 1.0, 1.0, 1.0, .1, 17.0)
	drops = paint.next_pass
	check(is_equal_approx(float(drops.get_shader_parameter("wet")), 1.0) and is_equal_approx(float(drops.get_shader_parameter("falling")), .1), "garoa usa intensidade atual separada da água acumulada")
	RAIN._apply_material(paint, 1.0, 1.0, 1.0, .9, 29.0)
	check(paint.next_pass == drops and is_equal_approx(float(drops.get_shader_parameter("falling")), .9), "intensificar chuva atualiza gotas mesmo já encharcado")
	check(is_equal_approx(float(drops.get_shader_parameter("pattern_seed")), 29.0), "padrão recebe identidade própria do veículo")
	quit(1 if failures > 0 else 0)
