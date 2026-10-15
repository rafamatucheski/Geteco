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
	check(paint.normal_enabled and paint.normal_texture == RAIN.beads() and paint.uv1_triplanar, "gotas aplicadas")
	RAIN.apply_material_for_test(paint, .5, .5, 1.0)
	check(paint.roughness > .05 and paint.roughness < .5 and paint.normal_scale < .9, "meio molhada fica no meio")
	RAIN.apply_material_for_test(paint, 0.0, 0.0, 1.0)
	check(is_equal_approx(paint.roughness, .5) and is_equal_approx(paint.clearcoat, .4), "seca devolve rugosidade e verniz")
	check(paint.albedo_color.is_equal_approx(Color(.6, .2, .1)) and not paint.normal_enabled and paint.normal_texture == null and not paint.uv1_triplanar, "seca devolve cor e remove gotas")
	check(not paint.has_meta("rain_base"), "sem resíduo de estado quando seco")

	# Repintura no meio da chuva: a nova cor vira a base, não é desfeita.
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	paint.albedo_color = Color(.1, .3, .7)
	RAIN.apply_material_for_test(paint, 1.0, 1.0, 1.0)
	RAIN.apply_material_for_test(paint, 0.0, 0.0, 1.0)
	check(paint.albedo_color.is_equal_approx(Color(.1, .3, .7)), "repintura durante a chuva sobrevive à secagem")

	# Amassado manda na normal: gotas não a substituem nem a apagam ao secar.
	var dented := StandardMaterial3D.new()
	dented.normal_enabled = true
	dented.normal_texture = DAMAGE._dents()
	RAIN.apply_material_for_test(dented, 1.0, 1.0, 1.0)
	check(dented.normal_texture == DAMAGE._dents(), "amassado mantém a normal")
	RAIN.apply_material_for_test(dented, 0.0, 0.0, 1.0)
	check(dented.normal_texture == DAMAGE._dents() and dented.normal_enabled, "secar não apaga o amassado")

	# Pintura texturizada não leva gotas triplanares (o triplanar distorceria a textura).
	var textured := StandardMaterial3D.new()
	textured.albedo_texture = RAIN.beads()
	RAIN.apply_material_for_test(textured, 1.0, 1.0, 1.0)
	check(not textured.normal_enabled and not textured.uv1_triplanar, "textura própria não ganha gotas")
	quit(1 if failures > 0 else 0)
