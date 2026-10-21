extends SceneTree
## Revisão dos materiais da blitz (BlitzLook): as mesmas tomadas antes/depois, na câmera da cena e em
## closes fixos de asfalto, faixa, cavalete, mato, guarda-corpo, porta do caminhão, papelão, muralha da
## prisão e quarto. Grava em evidence/prologue-materials-20261021/<rótulo>/.
##
##     tools/run_godot_locked.sh --path . --script res://tests/capture/qa_prologue_materials.gd -- --label=depois
##     GETECO_BLITZ_LOOK=0 tools/run_godot_locked.sh ... -- --label=antes     (materiais lisos, mesmo código)
##
## Só revisão visual: precisa de janela (sem --headless) e não mede desempenho.
const BLITZ := preload("res://runtime/prologue/BlitzScene.gd")
const DANTE_ORDER := ["dante_open", "dante_walk", "dante_ask", "dante_ambush", "dante_fight", "dante_flee", "dante_wounded",
	"dante_cuff", "dante_cuffed", "dante_escort", "dante_drive", "dante_prison", "dante_black", "dante_after"]
const VICENTE_ORDER := ["vicente_drive", "vicente_stop", "vicente_wait", "vicente_face", "vicente_black"]
var folder := "res://evidence/prologue-materials-20261021/"
var scene
var done := false
var cam: Camera3D

func _initialize() -> void:
	var label := "depois"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	folder += label + "/"
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await _dante()
	await _vicente()
	quit(0)

func _dante() -> void:
	await _start("dante")
	var prison: Vector3 = BLITZ.PRISON
	var room: Vector3 = BLITZ.ROOM
	if await _wait("dante_open", 3.0, DANTE_ORDER):
		await _scene_shot("01_estrada_alto")
		# Pista, faixas e cavaletes de perto, contra o farol do caminhão que vem.
		await _shot("02_asfalto_cavaletes", Vector3(-1.6, 1.5, -21.0), Vector3(2.4, .2, -12.0), 50.0)
		await _shot("03_asfalto_rasante", Vector3(-.8, .55, -9.0), Vector3(.6, 0, -16.0), 55.0)
		await _shot("04_mato_guarda_corpo", Vector3(3.5, 2.6, -36.0), Vector3(9.0, .4, -24.0), 55.0)
		await _shot("05_beira_alto", Vector3(5.0, 14.0, -4.0), Vector3(12.0, 0, -22.0), 50.0)
	if await _wait("dante_ask", 5.0, DANTE_ORDER):
		await _scene_shot("06_cabine")
		await _shot("07_porta_caminhao", scene.truck.to_global(Vector3(-3.2, 2.1, -2.0)), scene.truck.to_global(Vector3(-1.1, 1.6, -3.5)), 45.0)
	if await _wait("dante_escort", 9.0, DANTE_ORDER):
		await _scene_shot("08_bau")
		await _shot("09_papelao", scene.truck.to_global(Vector3(2.6, 2.6, 8.5)), scene.truck.to_global(Vector3(0, 1.6, 3.0)), 45.0)
	if await _wait("dante_prison", 4.0, DANTE_ORDER):
		await _scene_shot("10_prisao")
		await _shot("11_muralha", prison + Vector3(8.0, 1.8, 2.0), prison + Vector3(-12.0, 3.0, -10.0), 50.0)
	if await _wait("dante_after", 3.5, DANTE_ORDER):
		await _scene_shot("12_quarto")
		await _shot("13_cama", room + Vector3(.9, 1.15, .7), room + Vector3(-.4, .45, -1.0), 50.0)
		await _shot("14_parede_piso", room + Vector3(1.6, 1.5, 1.8), room + Vector3(-1.2, .6, -1.5), 60.0)
	if is_instance_valid(scene): scene.pace = 6.0
	while not done: await process_frame

func _vicente() -> void:
	await _start("vicente")
	if await _wait("vicente_drive", 3.0, VICENTE_ORDER): await _scene_shot("21_estrada_motorista")
	if await _wait("vicente_drive", 16.0, VICENTE_ORDER): await _scene_shot("22_giroflex")
	if is_instance_valid(scene): scene.pace = 6.0
	while not done: await process_frame

func _start(pov: String) -> void:
	done = false
	scene = BLITZ.start(null, pov, func(): done = true)
	scene.autoplay = true
	while not done and (scene.stage in ["build", "warm"] or scene.curtain.color.a > .01):
		await process_frame
	cam = Camera3D.new()
	cam.near = .03
	cam.far = 260.0
	scene._set.add_child(cam)
	_shader_report()

## Conjuntos de recursos dos materiais da cena (o StandardMaterial3D gera um shader por conjunto): o
## BlitzLook promete só duas variantes vestidas novas (mundo e objeto); emissivos e vidros não mudam.
func _shader_report() -> void:
	var sets := {}
	for held in BLITZ._retained:
		if not held is StandardMaterial3D: continue
		var material: StandardMaterial3D = held
		var key := "tex=%s normal=%s ao=%s tri=%s mundo=%s emiss=%s transp=%d" % [material.albedo_texture != null, material.normal_enabled,
			material.ao_enabled, material.uv1_triplanar, material.uv1_world_triplanar, material.emission_enabled, material.transparency]
		if not sets.has(key): sets[key] = []
		sets[key].append(material.resource_name)
	for key in sets: print("MATERIAL_SET %s chaves=%s" % [key, ",".join(sets[key])])
	print("MATERIAL_SETS distintos=%d" % sets.size())

func _reached(stage: String, t: float, order: Array) -> bool:
	if done or not is_instance_valid(scene): return true
	var now: int = order.find(scene.stage)
	var want: int = order.find(stage)
	if now > want: return true
	return now == want and scene.stage_time >= t and scene.curtain.color.a < .02

func _wait(stage: String, t: float, order: Array) -> bool:
	while not _reached(stage, t, order): await process_frame
	return not done and is_instance_valid(scene) and scene.stage == stage

func _shot(label: String, from: Vector3, to: Vector3, fov: float) -> void:
	if done or not is_instance_valid(scene): return
	var pace: float = scene.pace
	# Parado durante a tomada: o relógio da cena não anda enquanto a câmera extra desenha.
	scene.pace = .0001
	cam.fov = fov
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.current = true
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	_save(label)
	scene.camera.current = true
	scene.pace = pace

func _scene_shot(label: String) -> void:
	if done or not is_instance_valid(scene): return
	scene.camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	_save(label)

func _save(label: String) -> void:
	var path := folder + label + ".png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("MATERIAL_SHOT %s stage=%s t=%.2f" % [label, scene.stage, scene.stage_time])
