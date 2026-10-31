extends RefCounted
## Aquece a família de texto/contorno medida no primeiro uso sob a cobertura existente.
## Usa a fábrica de rótulos definida sem disparar reações, áudio nem RNG.
const PRESENTER = preload("res://gameplay/civilian_reactions/CivilianReactionPresenter.gd")
const GUARDS = preload("res://gameplay/emergency/EffectsPrewarm.gd")
const DRAW_FRAMES := 3
const MAX_WAIT_FRAMES := 24
const REPRESENTATIVE_TEXT := "VOU LIGAR PARA A POLÍCIA!"
static var _drawn := false

static func run(host: Node3D, curtain: CanvasLayer) -> void:
	if _drawn or DisplayServer.get_name() == "headless" or "--no-prewarm" in OS.get_cmdline_user_args(): return
	if not GUARDS._covered_loading(host, curtain): return
	var camera := host.get("camera") as Camera3D
	if not GUARDS._current_camera(host, camera): return
	var tree := host.get_tree()
	var visual := Node3D.new()
	visual.name = "ReactionVisualPrewarm"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var label := PRESENTER.create_bubble_label()
	label.text = REPRESENTATIVE_TEXT
	visual.add_child(label)
	host.add_child(visual)
	visual.global_transform = Transform3D(Basis.IDENTITY, camera.global_position-camera.global_basis.z*9.0-label.position)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	# Peças escondidas primeiro: os trabalhadores do motor compilam em paralelo (runtime/HiddenCompile.gd).
	await preload("res://runtime/HiddenCompile.gd").prepare(visual, host.get_tree())
	RenderingServer.frame_post_draw.connect(count_draw)
	for frame in MAX_WAIT_FRAMES:
		await tree.process_frame
		if not GUARDS._covered_loading(host, curtain) or not GUARDS._current_camera(host, camera): break
		if not is_instance_valid(visual) or visual.is_queued_for_deletion(): break
		visual.global_transform = Transform3D(Basis.IDENTITY, camera.global_position-camera.global_basis.z*9.0-label.position)
		if draws[0] >= DRAW_FRAMES:
			_drawn = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw):
		RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(visual): visual.free()
