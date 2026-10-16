extends RefCounted
## Primeiro urso da serra sob a cortina: monta um modelo adulto na frente da câmera por
## alguns quadros (compila as variantes de material com brilho de borda, transparência e
## sem sombreamento) e gera os sons procedurais do urso, que ficam em cache estático.
## Sem isto o primeiro urso custava ~53 ms de modelo + 26 ms de respiração gerada no
## quadro em que aparecia (auditoria de desempenho de 16/10, serra/travessia).
## Mesma receita de BridgeLookPrewarm.
const GUARDS := preload("res://gameplay/emergency/EffectsPrewarm.gd")
const MODEL := preload("res://gameplay/wildlife/MountainBearModel.gd")
const AUDIO := preload("res://audio/wildlife/BearAudio.gd")
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
	AUDIO.get_breathing_stream()
	AUDIO.get_grunt_alert_stream()
	AUDIO.get_charge_stream()
	var bear: Node3D = MODEL.new()
	bear.name = "WildlifePrewarm"
	bear.set_process(false)
	host.add_child(bear)
	var draws: Array[int] = [0]
	var count_draw := func() -> void: draws[0] += 1
	RenderingServer.frame_post_draw.connect(count_draw)
	var completed := false
	for frame in MAX_WAIT_FRAMES:
		bear.global_transform = Transform3D(camera.global_basis, camera.global_position - camera.global_basis.z * 9.0)
		await host.get_tree().process_frame
		if not GUARDS._covered_loading(host, curtain) or not is_instance_valid(bear): break
		if draws[0] >= DRAW_FRAMES:
			completed = true
			break
	if RenderingServer.frame_post_draw.is_connected(count_draw): RenderingServer.frame_post_draw.disconnect(count_draw)
	if is_instance_valid(bear): bear.free()
	_done = completed
	last_summary = {"completed": completed, "draws": draws[0], "usec": Time.get_ticks_usec() - began}
	print("Fauna preparada: ", JSON.stringify(last_summary))
