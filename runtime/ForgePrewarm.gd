extends RefCounted
## Forja da Serra sob a cortina: desenha por alguns quadros a forja (tábua/pedra/metal do
## forge_surface, cascalho, peças agrupadas e a brasa), a espada e escudo do gelo e as três lâminas lendárias (aço
## escuro e fio aceso), para nenhuma variante de shader compilar no quadro em que o jogador
## chega na clareira ou compra a lendária. Mesma receita de WildlifePrewarm/BridgeLookPrewarm.
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const FORGE := preload("res://world/mountain_detail/forge/MountainForge.gd")
const VISUALS := preload("res://gameplay/WeaponAttachmentVisuals.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
static var _done := false
static var last_summary: Dictionary = {}

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _done or DisplayServer.get_name() == "headless": return
	if "--no-prewarm" in OS.get_cmdline_user_args() or not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var began := Time.get_ticks_usec()
	var stage := Node3D.new()
	stage.name = "ForgePrewarm"
	host.add_child(stage)
	var forge := FORGE.new()
	forge.scale = Vector3.ONE * .12
	stage.add_child(forge)
	forge.smith.process_mode = Node.PROCESS_MODE_DISABLED
	for i in 3:
		var id: String = ["knife", "axe", "katana"][i]
		var blade := Node3D.new()
		blade.position = Vector3(-.5 + float(i) * .5, .4, 1.0)
		stage.add_child(blade)
		if id == "katana": preload("res://gameplay/KatanaModel.gd").build(blade, false)
		else: preload("res://gameplay/ArsenalWeapon3D.gd").build(blade, id)
		VISUALS.legendary(blade, id)
	# Espada e escudo do gelo (Meshy): materiais PBR próprios, que não existem em nenhum outro lugar do mundo.
	var ice := Node3D.new()
	ice.position = Vector3(1.0, .4, 1.0)
	stage.add_child(ice)
	preload("res://gameplay/SwordShieldModel.gd").build_sword(ice)
	var shield := Node3D.new()
	shield.position = Vector3(1.5, .4, 1.0)
	stage.add_child(shield)
	preload("res://gameplay/SwordShieldModel.gd").build_shield(shield)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	# Peças escondidas primeiro: os trabalhadores do motor compilam em paralelo (runtime/HiddenCompile.gd).
	await preload("res://runtime/HiddenCompile.gd").prepare(stage, host.get_tree())
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in MAX_WAIT_FRAMES:
		stage.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 6.0)
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not is_instance_valid(stage): break
		if draws[0] >= DRAW_FRAMES:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(stage): stage.free()
	_done = completed
	last_summary = {"completed": completed, "draws": draws[0], "usec": Time.get_ticks_usec() - began}
	print("Forja preparada: ", JSON.stringify(last_summary))
