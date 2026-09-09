extends SceneTree

## Script de gravação de vídeo frame a frame em velocidade normal (1.0x) para as 3 entregas.
## Salva sequências de imagens JPG em:
##   captures/video_frames/funeral/
##   captures/video_frames/shovel/
##   captures/video_frames/police/

const DEMO_FUNERAL_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/DemoFuneralScene.gd")
const DEMO_ELIAS_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/DemoEliasShovelScene.gd")
const DEMO_POLICE_SCRIPT := preload("res://prototypes/gameplay_repair_art_0909/DemoPoliceExtractionScene.gd")

const FPS := 20
const FRAME_TIME := 1.0 / float(FPS)

var frame_index := 0
var recording_dir := ""

func _initialize() -> void:
	call_deferred("_run_recording")

func _run_recording() -> void:
	print("\n=======================================================")
	print("INICIANDO GRAVAÇÃO DE VÍDEOS EM VELOCIDADE NORMAL (1.0x)")
	print("=======================================================\n")

	DirAccess.make_dir_recursive_absolute("d:/geteco/game/prototypes/gameplay_repair_art_0909/captures/video_frames/funeral")
	DirAccess.make_dir_recursive_absolute("d:/geteco/game/prototypes/gameplay_repair_art_0909/captures/video_frames/shovel")
	DirAccess.make_dir_recursive_absolute("d:/geteco/game/prototypes/gameplay_repair_art_0909/captures/video_frames/police")

	await _record_funeral()
	await _record_shovel_and_elias()
	await _record_police_extraction()

	print("\n=======================================================")
	print("GRAVAÇÃO CONCLUÍDA! Pronta para codificação MP4.")
	print("=======================================================\n")
	quit(0)

func _record_frames(duration_sec: float) -> void:
	var total_frames := int(duration_sec * FPS)
	for i in total_frames:
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := recording_dir + "/frame_%05d.jpg" % frame_index
		img.save_jpg(p, 0.88)
		frame_index += 1
		await process_frame

# -------------------------------------------------------------
# 1. FUNERAL COMPLETO (VELOCIDADE NORMAL 1.0x)
# -------------------------------------------------------------
func _record_funeral() -> void:
	print(">>> [VÍDEO 1] Gravando Ciclo Completo do Funeral...")
	recording_dir = "d:/geteco/game/prototypes/gameplay_repair_art_0909/captures/video_frames/funeral"
	frame_index = 0

	var scene: Node3D = DEMO_FUNERAL_SCRIPT.new()
	root.add_child(scene)
	for i in 15: await process_frame

	var ctrl: Node3D = scene.get("controller") as Node3D
	ctrl.set("speed_multiplier", 1.0)
	ctrl.set("ceremony_wait_time", 2.5)

	# Inicia em visão de gameplay para ver o cortejo avançando pelo cemitério
	ctrl.call("start_sequence")
	await _record_frames(4.5) # Cortejo no corredor central

	# Alterna para close-up na sepultura quando chegam ao lote
	scene.call("_toggle_camera")
	await _record_frames(14.5) # Chegada, espera, descida, aterramento e flores

	# Retorna à câmera de gameplay para ver a dispersão
	scene.call("_toggle_camera")
	await _record_frames(4.0)

	scene.queue_free()
	for i in 15: await process_frame
	print("  [OK] Funeral gravado: ", frame_index, " frames.")

# -------------------------------------------------------------
# 2. ELIAS & COVEIRO COM PÁ (VELOCIDADE NORMAL 1.0x)
# -------------------------------------------------------------
func _record_shovel_and_elias() -> void:
	print(">>> [VÍDEO 2] Gravando Elias e Poses da Pá 3D...")
	recording_dir = "d:/geteco/game/prototypes/gameplay_repair_art_0909/captures/video_frames/shovel"
	frame_index = 0

	var scene: Node3D = DEMO_ELIAS_SCRIPT.new()
	root.add_child(scene)
	for i in 15: await process_frame

	var elias: Node3D = scene.get("elias") as Node3D
	var worker: Node3D = scene.get("worker") as Node3D

	# 1. Elias em espera e Coveiro com pá em HOLD
	elias.call("set_pose", 0) # WAIT
	worker.call("set_worker_pose", 0) # HOLD
	await _record_frames(2.5)

	# 2. Elias narrando (TALK) e Coveiro com pá em CARRY caminhando
	elias.call("set_pose", 1) # TALK
	worker.call("set_worker_pose", 1) # CARRY
	scene.set("is_walking", true)
	await _record_frames(3.5)

	# 3. Coveiro em pose de escavação (DIG) e Elias inspecionando
	scene.set("is_walking", false)
	elias.call("set_pose", 3) # INSPECT
	worker.call("set_worker_pose", 2) # DIG
	await _record_frames(3.5)

	# 4. Visão de gameplay geral
	scene.call("_toggle_camera")
	await _record_frames(3.0)

	scene.queue_free()
	for i in 15: await process_frame
	print("  [OK] Elias e Pá gravados: ", frame_index, " frames.")

# -------------------------------------------------------------
# 3. RETIRADA POLICIAL DO MOTORISTA (VELOCIDADE NORMAL 1.0x)
# -------------------------------------------------------------
func _record_police_extraction() -> void:
	print(">>> [VÍDEO 3] Gravando Retirada Policial do Motorista...")
	recording_dir = "d:/geteco/game/prototypes/gameplay_repair_art_0909/captures/video_frames/police"
	frame_index = 0

	var scene: Node3D = DEMO_POLICE_SCRIPT.new()
	root.add_child(scene)
	for i in 15: await process_frame

	var ext: Node3D = scene.get("extraction") as Node3D
	ext.set("speed_multiplier", 1.0)

	# 1. Extração completa pela porta do motorista (Esquerda) em Close-up
	ext.call("start_extraction", -1.0)
	await _record_frames(7.2) # Abordagem, abertura, extração ao solo e algemas

	# 2. Demonstração de Interrupção com Rollback
	ext.call("reset_poses")
	for i in 10: await process_frame
	ext.call("start_extraction", -1.0)
	await _record_frames(1.6) # Interrompe no meio da aproximação
	ext.call("interrupt_extraction")
	await _record_frames(2.0) # Rollback: porta fecha, policial recua e Dante permanece seguro

	# 3. Extração da porta direita (Passageiro) em visão Gameplay
	scene.call("_toggle_camera")
	ext.call("start_extraction", 1.0)
	await _record_frames(6.5)

	scene.queue_free()
	for i in 15: await process_frame
	print("  [OK] Retirada Policial gravada: ", frame_index, " frames.")
