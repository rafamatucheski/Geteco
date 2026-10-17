extends RefCounted
## Pré-aquecimento da PRIMEIRA aparição da gangue Cobra e da polícia, sob a cortina de carregamento.
##
## Motivo (release de 17/10, log 20261017-023031-664): ao atirar, três quadros de 588–646 ms aos 85,7 s,
## 102,5 s e 141,8 s, quase todo o tempo na fase de desenho (render_bracket 551–579 ms; script e física
## pequenos; nenhum trecho nomeado), só na primeira vez que Cobra e polícia entravam no tiroteio. No cenário
## "caos 3 estrelas" os piores quadros eram 33–47 ms. É o padrão de pipeline compilado no primeiro desenho.
##
## O motor já pré-compila em segundo plano os pipelines de cada superfície quando ela é criada (commit
## d7965b4d), e PoliceVisualPrewarm/MeshyBodyPrewarm já desenham corpos, armas e silhuetas. Ficavam de fora
## as chaves que só existem no desenho ou que nascem no meio do tiroteio:
##   - `GeometryInstance3D.transparency` > 0 no sumiço do morto (DestroyedFade3D, 4 s depois da queda) e no
##     sumiço da arma no chão (LootPickup.advance): leva o material opaco para o passe alfa (outro pipeline);
##   - o clarão da Cobra (CobraModel: StandardMaterial3D sem luz e sem emissão, um por modelo; o da polícia
##     tem emissão e é outro shader);
##   - os itens que caem do morto (LootPickup: halo/disco aditivos, brilho por overlay, nota com textura);
##   - o giroflex da viatura (VehicleEquipment._refresh desliga `emission_enabled` das lentes a cada fase,
##     acende os brilhos Sprite3D e a luz do halo).
## Este passo desenha tudo isso alguns quadros na frente da câmera, primeiro opaco e depois com transparency
## 0,5, sem ator, colisão, grupo, áudio ou RNG global. Materiais criados por instância ficam retidos aqui:
## o shader de um StandardMaterial3D só continua vivo enquanto existir material com as mesmas flags.
##
## Hipótese a confirmar: não foi reproduzido nem medido depois desta mudança. A/B: GETECO_SPAWN_PREWARM=0
## desliga só esta etapa.
const GUARDS = preload("res://gameplay/emergency/EffectsPrewarm.gd")
const POLICE_MODEL = preload("res://gameplay/PoliceModel.gd")
const COBRA_MODEL = preload("res://gameplay/CobraModel.gd")
const LOOT = preload("res://gameplay/LootPickup.gd")
const ARSENAL = preload("res://gameplay/ArsenalWeapon3D.gd")
const FLEET = preload("res://runtime/FleetCatalog.gd")
const EQUIPMENT = preload("res://gameplay/VehicleEquipment.gd")
## Mesmas armas por escalão de PoliceVisualPrewarm (PoliceAgent.TIER_WEAPONS).
const POLICE_WEAPONS := ["pistol", "smg", "m4a1", "m4a1", "m4a1"]
## Armas que a Cobra (pistola, escopeta, submetralhadora) e a polícia largam ao morrer.
const LOOT_WEAPONS := ["pistol", "shotgun", "smg", "m4a1"]
## Qualquer valor entre 0 e 1 usa o mesmo pipeline alfa; o valor só precisa ser visível.
const FADE_TRANSPARENCY := 0.5
## Cores das lentes da barra da viatura (VehicleEquipment._bind_lens).
const BEACON_COLORS := [Color("e83c42"), Color("3689ef")]
const DRAW_FRAMES := 3
## Espera limitada: minimizar a janela não pode deixar o carregamento preso.
const MAX_WAIT_FRAMES := 40
const DISTANCE := 11.0
static var _drawn := false
static var _retained: Array[Material] = []

class ExteriorContext extends RefCounted:
	var state := {"place_id": ""}

class VisualHolder extends Node3D:
	var dead := false
	var controller: RefCounted

static func enabled() -> bool:
	return OS.get_environment("GETECO_SPAWN_PREWARM") != "0"

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or not enabled() or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var tree := host.get_tree()
	var visual := Node3D.new()
	visual.name = "SpawnVisualPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	host.add_child(visual)
	_position(visual, camera)
	# Tudo que no jogo some com `transparency`: corpos com arma (DestroyedFade3D) e armas no chão (LootPickup).
	var fading := Node3D.new()
	fading.name = "Fading"
	visual.add_child(fading)
	var context := ExteriorContext.new()
	var police: Array = []
	for tier in POLICE_WEAPONS.size():
		var owner := VisualHolder.new()
		owner.controller = context
		owner.position = Vector3((float(tier) - 2.0) * 1.8, 0.5, 0.0)
		fading.add_child(owner)
		var model = POLICE_MODEL.new()
		model.tier = tier
		# Não consome PoliceAppearance.next_model.
		model.appearance_index = tier
		owner.add_child(model)
		police.append(model)
	var cobras: Array = []
	for tier in 3:
		var owner := VisualHolder.new()
		owner.controller = context
		owner.position = Vector3((float(tier) - 1.0) * 1.8, -3.0, 0.0)
		fading.add_child(owner)
		# CobraModel monta corpo, uniforme, insígnia, clarão e arma no próprio _ready (como CobraAgent).
		var cobra = COBRA_MODEL.new()
		cobra.tier = tier
		owner.add_child(cobra)
		cobras.append(cobra)
	for index in LOOT_WEAPONS.size():
		var icon := Node3D.new()
		icon.name = "LootWeapon"
		icon.position = Vector3((float(index) - 1.5) * 1.6, 3.6, 0.0)
		icon.scale = Vector3.ONE * 2.4
		fading.add_child(icon)
		ARSENAL.build_cached(icon, str(LOOT_WEAPONS[index]))
		for node in icon.find_children("*", "GeometryInstance3D", true, false):
			(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var drops := Node3D.new()
	drops.name = "Drops"
	visual.add_child(drops)
	var drop_index := 0
	for kind in ["cash", "armor"]:
		var drop := _ground_pickup(str(kind))
		drop.position = Vector3(5.0 + float(drop_index) * 1.6, -3.0, 0.0)
		drops.add_child(drop)
		drop_index += 1
	_retain_materials(drops)
	var cruiser: Node3D = FLEET.create("police_cruiser")
	if cruiser != null:
		cruiser.process_mode = Node.PROCESS_MODE_DISABLED
		cruiser.position = Vector3(-6.5, -3.0, 0.0)
		visual.add_child(cruiser)
		_dim_lenses(cruiser)
		_beacon_presentation(cruiser)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	# 0: espera os corpos da polícia (instalados em call_deferred); 1: opaco; 2: sumindo.
	var stage := 0
	for frame in MAX_WAIT_FRAMES:
		await tree.process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if not is_instance_valid(visual) or visual.is_queued_for_deletion(): break
		_position(visual, camera)
		if stage == 0:
			var bodies_ready := true
			for model in police:
				if not is_instance_valid(model.body): bodies_ready = false
			if not bodies_ready: continue
			for tier in police.size():
				police[tier].equip(POLICE_WEAPONS[tier])
				police[tier].muzzle_flash_3d.show()
			for cobra in cobras:
				var flash: MeshInstance3D = cobra.muzzle_flash_3d
				if not is_instance_valid(flash): continue
				flash.show()
				# Um clarão vivo basta para o shader dele sobreviver aos modelos temporários.
				if flash.material_override != null and not _retained.has(flash.material_override):
					_retained.append(flash.material_override)
			stage = 1
			draws[0] = 0
			continue
		if draws[0] < DRAW_FRAMES: continue
		if stage == 1:
			_fade(fading)
			stage = 2
			draws[0] = 0
			continue
		_drawn = true
		break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	# Sai antes de ProductionWorld revelar a cena; nenhum quadro visível com isto.
	if is_instance_valid(visual): visual.free()

## Plano da tela a DISTANCE m: x para a direita e y para cima da câmera (ortográfica alta ou perspectiva).
static func _position(visual: Node3D, camera: Camera3D) -> void:
	var basis := camera.global_basis.orthonormalized()
	visual.global_transform = Transform3D(basis, camera.global_position - basis.z * DISTANCE)

## Mesmo que DestroyedFade3D.fade faz em cada GeometryInstance3D do morto.
static func _fade(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).transparency = FADE_TRANSPARENCY

## Item de dinheiro/colete com as receitas do próprio LootPickup, sem entrar na árvore como LootPickup:
## o _ready dele sorteia a fase com o randf global e o Gameplay não o registra.
static func _ground_pickup(kind: String) -> Node3D:
	var source = LOOT.new()
	source.setup(kind, "", 100 if kind == "cash" else 0)
	source._build_ground_effects()
	var holder := Node3D.new()
	holder.name = "LootGround"
	for child in source.get_children():
		source.remove_child(child)
		holder.add_child(child)
	var icon := Node3D.new()
	icon.name = "Icon"
	icon.position.y = LOOT.ICON_HEIGHT
	var model := Node3D.new()
	icon.add_child(model)
	if kind == "cash": source._build_cash(model)
	else: source._build_vest(model)
	var tint: Color = source.halo_color()
	source.free()
	# Mesmas flags do brilho por overlay de LootPickup._ready; a cor é uniform.
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(tint.r, tint.g, tint.b, 0.3)
	holder.add_child(icon)
	for node in icon.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		geometry.material_overlay = glow
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return holder

static func _retain_materials(root: Node) -> void:
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		for held in [geometry.material_override, geometry.material_overlay]:
			if held != null and not _retained.has(held): _retained.append(held)
		var instance := geometry as MeshInstance3D
		if instance == null or instance.mesh == null: continue
		for surface in instance.mesh.get_surface_count():
			var surface_material: Material = instance.mesh.surface_get_material(surface)
			if surface_material != null and not _retained.has(surface_material): _retained.append(surface_material)

## Lentes emissivas da viatura com `emission_enabled` desligado: é a variante que o giroflex e os faróis
## alternam em VehicleEquipment._refresh (cópia de material por lente, mesmas outras flags).
static func _dim_lenses(model: Node3D) -> void:
	var copies := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh == null: continue
		var count: int = 1 if part.material_override != null else part.mesh.get_surface_count()
		for surface in count:
			var original := part.get_active_material(surface) as StandardMaterial3D
			if original == null or not original.emission_enabled: continue
			var key: int = original.get_instance_id()
			if not copies.has(key):
				var dark := original.duplicate() as StandardMaterial3D
				dark.emission_enabled = false
				dark.emission_energy_multiplier = 0.0
				copies[key] = dark
				_retained.append(dark)
			if part.material_override != null: part.material_override = copies[key]
			else: part.set_surface_override_material(surface, copies[key])

## Brilhos do giroflex e luz do halo com os mesmos parâmetros de VehicleEquipment._ready/_glow.
static func _beacon_presentation(model: Node3D) -> void:
	var side := -1.0
	for color in BEACON_COLORS:
		var glow := Sprite3D.new()
		glow.name = "VehicleLensGlow"
		glow.texture = EQUIPMENT._lens_glow_texture()
		glow.pixel_size = 0.58 / 64.0
		glow.modulate = color
		glow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = Vector3(side * 0.35, 1.7, 0.0)
		model.add_child(glow)
		side = -side
	var halo := OmniLight3D.new()
	halo.omni_range = 7.0
	halo.light_energy = 2.2
	halo.light_color = BEACON_COLORS[0]
	halo.shadow_enabled = false
	halo.position = Vector3(0.0, 2.0, 0.0)
	model.add_child(halo)
