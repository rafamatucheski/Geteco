extends RefCounted
## Primeira troca de tiros com o cache de pipeline frio (22/10), sob a cortina de carregamento.
##
## Motivo: com o cache do Vulkan e do driver vazios (primeira sessão depois de trocar D3D12 por Vulkan,
## atualização do driver), a rodada de estresse no oeste teve quadros de 653 ms (submetralhadora,
## faíscas e poeira de impacto em cena), 1 057 ms (fuzil, polícia atirando) e 107 ms (pistola), com
## `pipelines_delta` surface/specialization e sem nenhum span: o primeiro desenho de cada efeito
## compilava o pipeline no meio do jogo. `CombatEffects.prewarm` dispara alguns efeitos na posição do
## jogador logo no começo da carga, quando a câmera ainda não enquadra nada; as armas na mão, o clarão
## do cano, cápsulas, traçantes, manchas e marcas de queimado nem passavam por ali.
##
## Aqui cada pool do CombatEffects do jogo é usado uma vez diante da câmera (faíscas e poeira de cada
## material, sangue, fumaça do cano, explosão, chama, sopro, cápsulas das duas malhas, traçante,
## mancha e marca de queimado) junto com cada arma do catálogo no modelo da mão e o clarão do cano,
## desenhados alguns quadros e apagados (CombatEffects.clear) antes de a cortina sair. Os pools e os
## materiais são os do jogo: nada fica criado em dobro. Sem dano, física, som nem RNG de jogo.
## GETECO_COMBAT_PREWARM=0 desliga só esta etapa (A/B no mesmo export).
const GUARDS = preload("res://gameplay/emergency/EffectsPrewarm.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const CATALOG = preload("res://gameplay/WeaponCatalog.gd")
const EFFECTS = preload("res://gameplay/CombatEffects.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 40
const DISTANCE := 7.0
static var _drawn := false

static func enabled() -> bool:
	return OS.get_environment("GETECO_COMBAT_PREWARM") != "0"

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or not enabled() or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var gameplay: Variant = host.get("gameplay")
	if not is_instance_valid(gameplay): return
	var effects: Variant = gameplay.get("effects")
	if not is_instance_valid(effects) or not effects.is_inside_tree(): return
	var tree := host.get_tree()
	var basis := camera.global_basis.orthonormalized()
	var origin := camera.global_position - basis.z * DISTANCE
	var right := basis.x
	var up := basis.y
	var toward := basis.z
	# Efeitos do jogo, cada um num ponto da tela.
	var slot := 0
	for material in EFFECTS.IMPACT_COLORS.keys() + ["dirt", "sand", "snow"]:
		effects.impact(_spot(origin, right, up, slot), toward, str(material), 30.0)
		slot += 1
	effects.glass_shatter(_spot(origin,right,up,slot),toward)
	slot += 1
	effects.blood(_spot(origin, right, up, slot), toward, 30.0)
	slot += 1
	effects.muzzle_smoke(_spot(origin, right, up, slot), toward)
	slot += 1
	effects.backblast(_spot(origin, right, up, slot), -toward)
	slot += 1
	effects.flame(_spot(origin, right, up, slot) + right * .5, -right, 2.0)
	slot += 1
	effects.explosion(origin + up * -1.2 - basis.z * 3.0, 4.0)
	slot += 1
	var pooled: Array = []
	for pair in [[effects._shells, 0, effects._shell_mesh], [effects._shells, 1, effects._shotgun_shell_mesh]]:
		var node: MeshInstance3D = pair[0][pair[1]]
		node.mesh = pair[2]
		pooled.append(node)
	# As línguas de chama ficam sempre escondidas no jogo (CombatEffects.flame): não entram.
	for list in [effects._tracers, effects._stains, effects._scorches]:
		if not list.is_empty(): pooled.append(list[0])
	for node: Node3D in pooled:
		node.global_transform = Transform3D(basis.scaled(Vector3.ONE * (0.6 if node in effects._stains or node in effects._scorches else 3.0)), _spot(origin, right, up, slot))
		node.visible = true
		slot += 1
	if not effects._tracers.is_empty():
		var tracer_material: Variant = effects._tracers[0].mesh.material
		if tracer_material is StandardMaterial3D: (tracer_material as StandardMaterial3D).emission = Color(1.0, .9, .2)
	# Armas no modelo da mão e o clarão do cano, com o material de clarão do jogo.
	var weapons := Node3D.new()
	weapons.name = "CombatWeaponPrewarm"
	weapons.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	host.add_child(weapons)
	weapons.global_transform = Transform3D(basis, origin + up * 1.4)
	var index := 0
	var flash_mesh: Mesh = gameplay._directional_flash_mesh() if gameplay.has_method("_directional_flash_mesh") else null
	for id in CATALOG.WEAPONS.keys():
		if str(id) in ["", "fists"]: continue
		var data: Dictionary = CATALOG.WEAPONS[id]
		var holder := Node3D.new()
		holder.position = Vector3((float(index % 8) - 3.5) * .55, -float(index / 8) * .45, 0.0)
		holder.rotation.y = PI * .5
		weapons.add_child(holder)
		var tip: Vector3 = ARSENAL.build_cached(holder, str(id))
		if flash_mesh != null and not data.get("is_melee", false) and not data.get("is_grenade", false) and gameplay.get("_muzzle_material") != null:
			var flash := MeshInstance3D.new()
			flash.mesh = flash_mesh
			flash.material_override = gameplay._muzzle_material
			flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flash.position = tip
			holder.add_child(flash)
		index += 1
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	for frame in MAX_WAIT_FRAMES:
		await tree.process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if draws[0] >= DRAW_FRAMES:
			_drawn = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(weapons): weapons.free()
	# Apaga tudo o que foi disparado (cápsulas, manchas, emissores, luzes) antes do jogo, inclusive as
	# cópias de emissor da explosão (CombatEffects._burst), que não são do pool.
	if is_instance_valid(effects):
		var pool: Array = effects._all_emitters()
		for child in effects.get_children():
			# O temporizador de _burst libera a cópia sozinho; aqui só some.
			if child is CPUParticles3D and not child in pool:
				child.emitting = false
				child.visible = false
		effects.clear()

## Grade de 6 colunas no plano a DISTANCE m da câmera.
static func _spot(origin: Vector3, right: Vector3, up: Vector3, slot: int) -> Vector3:
	return origin + right * (float(slot % 6) - 2.5) * 1.1 + up * (0.9 - float(slot / 6) * 0.9)
