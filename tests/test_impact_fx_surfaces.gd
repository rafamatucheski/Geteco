extends SceneTree
## Impacto de bala por superfície (gameplay/fx/ImpactFx.gd, 29/10), com corpos de física reais:
##   - cada material dispara a receita certa (faíscas + clarão no metal, pedrinhas/lascas/poeira no concreto,
##     farpas na madeira, brilho no vidro, jato do material em terra/grama/areia/neve, respingo no lago);
##   - faíscas caem e quicam no chão sem atravessá-lo;
##   - nada cresce num tiroteio longo (emissores, vagas de faísca e de marca, filhos);
##   - marcas respeitam o orçamento, a mais velha cede a vaga, desvanecem e somem;
##   - marca no carro acompanha o carro e some quando ele some;
##   - posição/normal não finita não chega a nenhum nó (crash de 29/10);
##   - materiais retidos: os mesmos objetos depois de recriar o CombatEffects;
##   - o clarão passa pelo LightBudget e não acende longe do jogador.
## NÃO mede aparência nem custo de GPU; os microssegundos impressos são do binário de editor (indicativo).
## Rodar sem GETECO_IMPACT_FX=0. Uso: tools/run_godot_locked.sh --path . --script res://tests/test_impact_fx_surfaces.gd
const EFFECTS := preload("res://gameplay/CombatEffects.gd")
const IMPACT := preload("res://gameplay/fx/ImpactFx.gd")
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")

## Lago mínimo com o contrato de NativeLake/FishingSite: grupo native_water_surface e contains_water.
class FakeLake extends Node3D:
	var half := Vector2(3.0, 3.0)
	func _ready() -> void: add_to_group("native_water_surface")
	func contains_water(point: Vector3) -> bool:
		var local := point - global_position
		return absf(local.x) < half.x and absf(local.z) < half.y

var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print(("IMPACT_FX PASS " if ok else "IMPACT_FX FAIL ") + label)
	if not ok: failures += 1

func solid(parent: Node3D, center: Vector3, size: Vector3, material: String, layer: int, moving := false) -> CollisionObject3D:
	var node: CollisionObject3D = CharacterBody3D.new() if moving else StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	node.add_child(shape)
	node.collision_layer = layer
	if not material.is_empty(): node.set_meta("impact_material", material)
	parent.add_child(node)
	node.global_position = center
	return node

## Emissor que o último `_emit` do rodízio usou.
func last_emitter(impact: Node3D, pool: String) -> CPUParticles3D:
	var list: Array = impact._pools[pool]
	return list[(int(impact._next[pool]) - 1 + list.size()) % list.size()]

func last_mark(impact: Node3D) -> int:
	return (int(impact._next_mark) - 1 + IMPACT.MAX_MARKS) % IMPACT.MAX_MARKS

func run() -> void:
	seed(29102026)
	var scene := Node3D.new()
	root.add_child(scene)
	solid(scene, Vector3(0, -0.5, 0), Vector3(60, 1, 60), "concrete", 1)
	var wall := solid(scene, Vector3(-4.0, 1.5, 0), Vector3(0.4, 3, 6), "metal", 1)
	var shooter := Node3D.new()
	scene.add_child(shooter)
	shooter.global_position = Vector3(0, 0, 6)
	var fx: Node3D = EFFECTS.new()
	scene.add_child(fx)
	fx.carry_source = shooter
	for tick in 3: await physics_frame
	var impact: Node3D = fx._impact_fx
	check(is_instance_valid(impact) and impact.get_parent() == fx, "ImpactFx montado no _ready do CombatEffects")
	if not is_instance_valid(impact):
		quit(1)
		return

	# 1) Receita por superfície.
	var expected := {
		"metal": ["sparks", "flash", "dust", "mark_metal"],
		"concrete": ["debris", "flakes", "dust", "mark_concrete"],
		"wood": ["splinters", "debris", "dust", "mark_wood"],
		"glass": ["glints", "dust"],
		"dirt": ["debris", "dust", "mark_soil"],
		"grass": ["debris", "flakes", "dust", "mark_soil"],
		"sand": ["debris", "dust", "mark_soil"],
		"snow": ["debris", "dust", "mark_soil"],
	}
	for material: String in expected:
		await process_frame
		impact.clear()
		var point := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 1.0))
		fx.impact(point, Vector3.UP, material, 25.0)
		var recipe: PackedStringArray = impact.last_recipe
		var missing := (expected[material] as Array).filter(func(part): return not part in recipe)
		check(missing.is_empty(), "%s dispara %s (faltou %s; saiu %s)" % [material, expected[material], missing, recipe])
		check(("flash" in recipe) == (material == "metal"), material + ": clarão de luz só no metal")
		check(("glints" in recipe) == (material == "glass"), material + ": brilho de vidro só no vidro")
		if material == "glass": check(not Array(recipe).any(func(part): return str(part).begins_with("mark_")), "vidro sem marca (a rachadura é do VehicleGlassDamage)")
		check(("splinters" in recipe) == (material == "wood"), material + ": farpas só na madeira")
		check(not "sparks" in recipe or material in ["metal", "concrete"], material + ": chão mole e vidro sem faísca")
		var placed := true
		for part in recipe:
			if not impact._pools.has(part): continue
			var emitter := last_emitter(impact, part)
			placed = placed and emitter.emitting and emitter.global_position.distance_to(point) < 0.12
		check(placed, material + ": emissores disparados no ponto atingido")
		match material:
			"snow": check(last_emitter(impact, "dust").color.r > 0.9 and last_emitter(impact, "debris").color.b > 0.85, "neve levanta pó branco")
			"sand":
				var grain := last_emitter(impact, "debris").color
				check(grain.r > 0.55 and grain.r > grain.g and grain.g > grain.b, "areia levanta grão bege (%s)" % grain)
			"dirt": check(last_emitter(impact, "debris").color.r < 0.45, "terra solta torrão escuro")
			"concrete":
				var chip := last_emitter(impact, "debris").color
				check(absf(chip.r - chip.g) < 0.06 and absf(chip.g - chip.b) < 0.08, "concreto solta pedrinha cinza (%s)" % chip)
	check(not impact.impact(Vector3(0, 1, 0), Vector3.UP, "flesh", 20.0), "pessoa fica com o sangue antigo (ImpactFx recusa flesh)")

	# 2) Variação: dois impactos iguais não saem idênticos.
	impact.clear()
	fx.impact(Vector3(1, 0, 0), Vector3.UP, "concrete", 25.0)
	var first := last_emitter(impact, "debris")
	var spread_a := [first.spread, first.color, Transform3D(first.global_transform)]
	await process_frame
	fx.impact(Vector3(1, 0, 0), Vector3.UP, "concrete", 25.0)
	var second := last_emitter(impact, "debris")
	check(not is_equal_approx(second.spread, spread_a[0]) or second.color != spread_a[1] or not second.global_transform.basis.is_equal_approx(spread_a[2].basis), "cada impacto varia direção, abertura ou cor")

	# 3) Água: tiro que acerta o fundo do lago respinga na superfície, sem marca no fundo.
	var lake := FakeLake.new()
	scene.add_child(lake)
	lake.global_position = Vector3(15, 0.0, 0)
	await process_frame
	impact.clear()
	fx.impact(Vector3(15, -0.4, 0), Vector3.UP, "dirt", 25.0)
	var splash: PackedStringArray = impact.last_recipe
	check("drops" in splash and "crown" in splash and not "mark_soil" in splash and not "debris" in splash, "fundo do lago vira respingo (%s)" % splash)
	var drops := last_emitter(impact, "drops")
	check(absf(drops.global_position.y - 0.06) < 0.02, "respingo nasce no espelho d'água (y=%.3f)" % drops.global_position.y)
	check(drops.global_position.x < 15.0 and drops.global_position.x > 9.0, "respingo na entrada da bala vinda do jogador (x=%.2f)" % drops.global_position.x)
	await process_frame
	fx.impact(Vector3(15, -0.4, 5.0), Vector3.UP, "dirt", 25.0)
	check(not "drops" in impact.last_recipe, "fora do polígono do lago não respinga")
	await process_frame
	fx.impact(Vector3(15, 0.4, 0), Vector3.UP, "dirt", 25.0)
	check(not "drops" in impact.last_recipe, "acima do espelho d'água não respinga")
	await process_frame
	fx.impact(Vector3(15, -6.0, 0), Vector3.UP, "dirt", 25.0)
	check(not "drops" in impact.last_recipe, "fundo mais fundo que WATER_DEPTH não respinga")
	lake.free()
	await process_frame

	# 4) Queda do jogador (PlayerAirMovement chama impact "concrete" sob os pés): poeira sem furo de bala.
	impact.clear()
	fx.impact(shooter.global_position + Vector3.UP * 0.04, Vector3.UP, "concrete", 30.0)
	check("debris" in impact.last_recipe and not "mark_concrete" in impact.last_recipe and not "sparks" in impact.last_recipe, "queda do jogador sem marca nem faísca")

	# 5) Faíscas do metal na parede caem e quicam no chão (y = 0), sem atravessá-lo.
	await process_frame
	impact.clear()
	fx.impact(Vector3(-3.8, 1.2, 0), Vector3.RIGHT, "metal", 40.0)
	var floors := PackedFloat32Array()
	for index in IMPACT.MAX_SPARKS:
		if impact._spark_life[index] > 0.0: floors.append(impact._spark_floor[index])
	check(not floors.is_empty() and Array(floors).all(func(y): return absf(y) < 0.01), "chão das faíscas da parede achado pelo raio (%s)" % [floors])
	var lowest := INF
	var near_floor := false
	var bounced := false
	for step in 70:
		var falling := PackedFloat32Array()
		for index in IMPACT.MAX_SPARKS: falling.append(impact._spark_vel[index].y)
		impact._update_sparks(1.0 / 60.0)
		for index in IMPACT.MAX_SPARKS:
			if impact._spark_life[index] <= 0.0: continue
			lowest = minf(lowest, impact._spark_pos[index].y)
			if impact._spark_pos[index].y < 0.05: near_floor = true
			if falling[index] < -0.5 and impact._spark_vel[index].y > 0.1: bounced = true
	check(near_floor and bounced, "faíscas da parede chegam ao chão e quicam")
	check(lowest > -0.01, "faíscas não atravessam o chão (menor y=%.3f)" % lowest)

	# 6) Orçamento: tiroteio longo não cria nó nem vaga.
	impact.clear()
	var before: Dictionary = impact.budget_counts()
	var fx_children := fx.get_child_count()
	var materials := ["metal", "concrete", "wood", "glass", "dirt", "grass", "sand", "snow", "world", "vidro_inexistente"]
	for shot in 400:
		var normal := Vector3.UP if shot % 3 else Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1))
		fx.impact(Vector3(randf_range(-8, 8), randf_range(0, 2), randf_range(-8, 8)), normal, materials[shot % materials.size()], randf_range(6.0, 70.0))
		if shot % 7 == 0: fx.glass_shatter(Vector3(randf_range(-8, 8), 1.2, randf_range(-8, 8)), Vector3.FORWARD)
		if shot % 9 == 0: await process_frame
	impact._process(1.0 / 60.0)
	var after: Dictionary = impact.budget_counts()
	check(after.emitters == before.emitters and after.children == before.children and fx.get_child_count() == fx_children, "400 tiros não criam emissor nem nó (%s → %s)" % [before, after])
	check(impact._marks.size() == IMPACT.MAX_MARKS and after.visible_marks <= IMPACT.MAX_MARKS, "marcas dentro do orçamento (%d de %d)" % [after.visible_marks, IMPACT.MAX_MARKS])
	check(impact._spark_pos.size() == IMPACT.MAX_SPARKS and impact._spark_multimesh.instance_count == IMPACT.MAX_SPARKS and impact._spark_multimesh.visible_instance_count <= IMPACT.MAX_SPARKS, "faíscas dentro das %d vagas" % IMPACT.MAX_SPARKS)

	# 7) Posições finitas em tudo que ficou na tela depois do tiroteio, e entradas não finitas recusadas.
	for bad: Array in [[Vector3(NAN, 0, 0), Vector3.UP, 10.0], [Vector3(INF, 1, 1), Vector3.UP, 10.0], [Vector3.ZERO, Vector3(NAN, 1, 0), 10.0], [Vector3.ZERO, Vector3.UP, NAN]]:
		impact.impact(bad[0], bad[1], "metal", bad[2])
		check(impact.last_recipe.is_empty(), "entrada não finita não desenha nada (%s)" % [bad])
	fx.glass_shatter(Vector3(NAN, 0, 0), Vector3.UP)
	check(impact.last_recipe.is_empty(), "estilhaço não finito recusado")
	impact.impact(Vector3(0.5, 0, 0.5), Vector3.ZERO, "concrete", 20.0)
	check("mark_concrete" in impact.last_recipe, "normal nula cai para cima e ainda marca")
	for step in 90: impact._process(1.0 / 60.0)
	var finite := true
	for list in impact._pools.values():
		for emitter: CPUParticles3D in list: finite = finite and emitter.global_transform.origin.is_finite() and emitter.global_transform.basis.x.is_finite()
	for decal: Decal in impact._marks:
		if decal.visible: finite = finite and decal.global_transform.origin.is_finite() and decal.global_transform.basis.y.is_finite()
	for index in IMPACT.MAX_SPARKS:
		if impact._spark_life[index] > 0.0: finite = finite and impact._spark_pos[index].is_finite()
	finite = finite and impact._flash.global_position.is_finite()
	check(finite, "emissores, marcas, faíscas e clarão com posição finita")

	# 8) Marcas: a mais velha cede a vaga; desvanecem no fim e somem.
	impact.clear()
	var start: int = impact._next_mark
	for index in IMPACT.MAX_MARKS + 5:
		fx.impact(Vector3(float(index) * 0.25 - 6.0, 0.0, -2.0), Vector3.UP, "concrete", 20.0)
	check(impact._visible_marks == IMPACT.MAX_MARKS, "anel cheio: %d marcas visíveis" % impact._visible_marks)
	check(absf(impact._marks[start].global_position.x - (float(IMPACT.MAX_MARKS) * 0.25 - 6.0)) < 0.01, "a 41ª marca ocupou a vaga da primeira (a mais antiga)")
	impact._age_marks(IMPACT.MARK_LIFETIME - IMPACT.MARK_FADE * 0.5)
	var alpha: float = impact._marks[start].modulate.a
	check(alpha > 0.3 and alpha < 0.7 and impact._marks[start].visible, "marca desvanece no fim da vida (alfa %.2f)" % alpha)
	impact._age_marks(IMPACT.MARK_FADE)
	check(impact._visible_marks == 0 and not impact._marks.any(func(decal): return decal.visible), "marcas somem depois de MARK_LIFETIME")
	fx.impact(Vector3(0, 0, -3), Vector3.UP, "metal", 30.0)
	fx.clear()
	check(impact._visible_marks == 0 and not impact._flash.visible and impact._spark_multimesh.visible_instance_count == 0, "CombatEffects.clear apaga marcas, clarão e faíscas")
	var still := false
	for list in impact._pools.values():
		for emitter: CPUParticles3D in list: still = still or (emitter.emitting and emitter.visible)
	check(not still, "clear não redispara emissor no lugar antigo (sem restart)")

	# 9) Marca no carro acompanha o carro e some quando ele some.
	var car := solid(scene, Vector3(6, 0.8, 4), Vector3(2, 1.4, 4), "metal", 4, true)
	for tick in 3: await physics_frame
	await process_frame
	fx.impact(Vector3(6, 0.8, 6.0), Vector3.BACK, "metal", 30.0)
	var slot := last_mark(impact)
	check(impact._mark_anchor[slot] == car, "marca no carro presa ao corpo do carro")
	car.global_position += Vector3(1.5, 0, 0)
	for tick in 3: await physics_frame
	await process_frame
	impact._process(1.0 / 60.0)
	check(absf(impact._marks[slot].global_position.x - 7.5) < 0.2, "marca anda com o carro (x=%.2f)" % impact._marks[slot].global_position.x)
	car.queue_free()
	await process_frame
	await process_frame
	impact._process(1.0 / 60.0)
	check(not impact._marks[slot].visible, "carro que some leva a marca junto")
	var static_slot := -1
	fx.impact(Vector3(-3.8, 1.0, 1.0), Vector3.RIGHT, "metal", 30.0)
	static_slot = last_mark(impact)
	wall.queue_free()
	await process_frame
	await process_frame
	impact._age_marks(IMPACT.MARK_TICK)
	check(not impact._marks[static_slot].visible, "parede descarregada leva a marca junto")

	# 10) Clarão pelo LightBudget, sem sombra, só perto do jogador.
	impact.clear()
	if LIGHT_BUDGET.enabled: check(LIGHT_BUDGET._owners.has(impact.get_instance_id()), "ImpactFx registrado no LightBudget")
	await process_frame
	fx.impact(Vector3(0, 0, 2), Vector3.UP, "metal", 30.0)
	var request: Dictionary = impact._budget_request()
	check(request.wanted.size() == 1 and request.wanted[0].light == impact._flash and not request.wanted[0].headlight and bool(request.wanted[0].get("transient", false)), "clarão pedido ao orçamento como luz transitória (não apaga farol)")
	check(impact._flash.visible and not impact._flash.shadow_enabled and impact._flash.light_volumetric_fog_energy == 0.0, "clarão aceso, sem sombra e sem névoa volumétrica")
	for step in 10: impact._process(1.0 / 60.0)
	check(not impact._flash.visible and impact._budget_request().wanted.is_empty(), "clarão dura décimos de segundo e sai do orçamento")
	shooter.global_position = Vector3(0, 0, 200)
	await process_frame
	fx.impact(Vector3(0, 0, 2), Vector3.UP, "metal", 30.0)
	check(not "flash" in impact.last_recipe and "sparks" in impact.last_recipe, "a mais de 25 m do jogador: faíscas sem luz")
	shooter.global_position = Vector3(0, 0, 6)

	# 11) Materiais retidos: os pools usam os materiais estáticos, os mesmos num CombatEffects novo.
	var retained: Array = IMPACT.resources().materials
	var all_retained := true
	for list in impact._pools.values():
		for emitter: CPUParticles3D in list:
			var material: Material = emitter.material_override if emitter.material_override != null else (emitter.mesh as PrimitiveMesh).material
			all_retained = all_retained and material != null and retained.any(func(kept): return is_same(kept, material))
	all_retained = all_retained and retained.any(func(kept): return is_same(kept, (impact._spark_multimesh.mesh as PrimitiveMesh).material))
	check(all_retained, "todo emissor e a faísca usam material retido em resources()")
	var fx2: Node3D = EFFECTS.new()
	scene.add_child(fx2)
	await process_frame
	var same: bool = is_same((fx2._impact_fx._pools.debris[0].mesh as PrimitiveMesh).material, (impact._pools.debris[0].mesh as PrimitiveMesh).material) \
		and is_same(fx2._impact_fx._marks[0].texture_normal, impact._marks[0].texture_normal)
	check(same, "CombatEffects recriado reaproveita os mesmos materiais (nada recompila)")
	fx2.free()

	# 12) Custo indicativo (binário de editor; não é medição de release).
	impact.clear()
	var began := Time.get_ticks_usec()
	for shot in 200:
		impact._frame = -1
		impact.impact(Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), Vector3.UP, materials[shot % 8], 25.0)
	var per_impact := float(Time.get_ticks_usec() - began) / 200.0
	for shot in IMPACT.MAX_SPARKS: impact._sparks(Vector3(0, 1, 0), Vector3.UP, 1, 1.0)
	began = Time.get_ticks_usec()
	for step in 60: impact._process(1.0 / 240.0)
	var per_frame := float(Time.get_ticks_usec() - began) / 60.0
	print("IMPACT_FX COST editor: %.1f us/impacto (receita cheia), %.1f us/quadro com %d faíscas e %d marcas" % [per_impact, per_frame, IMPACT.MAX_SPARKS, impact._visible_marks])
	fx.clear()
	scene.queue_free()
	await process_frame
	print("IMPACT_FX RESULT checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
