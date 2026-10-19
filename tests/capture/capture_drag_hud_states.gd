extends SceneTree
## Capturas da HUD da arrancada em estados escolhidos, sobre fundo de duas cores
## parecido com o pátio ao anoitecer. Não é o Main nem medição de desempenho:
## a cena real fica com test_desert_drag_runtime.gd --capture-out.
## --hud=<caminho> desenha outra cópia da HUD (comparação antes/depois no mesmo
## executável); --out=res://evidence/<pasta> escolhe a pasta.
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const CHALLENGE := preload("res://activities/desert_drag/DragRivalChallengeController.gd")
const TELEMETRY := preload("res://activities/desert_drag/DragRivalChallengeTelemetry.gd")
# 1720×720 é 21:9 na mesma escala lógica de 3440×1440.
const RESOLUTIONS := [Vector2i(1280,720),Vector2i(960,540),Vector2i(1720,720)]
const CASES := [
	{"id":"01_staging_3","staging":true,"headline":"3","ratio":.30,"gear":1,"speed":0.0,"remaining":800.0,"elapsed":0.0,"gap":0.0},
	{"id":"02_staging_1","staging":true,"headline":"1","ratio":.55,"gear":1,"speed":0.0,"remaining":800.0,"elapsed":0.0,"gap":0.0},
	{"id":"03_green","feedback":"LARGADA IDEAL","ratio":.47,"gear":1,"speed":14.0,"remaining":797.0,"elapsed":.3,"gap":.4},
	{"id":"04_shift_due_after_verdict","feedback":"TROCA IDEAL","ratio":.93,"gear":2,"speed":96.0,"remaining":712.0,"elapsed":4.1,"gap":3.2},
	{"id":"05_early_shift","feedback":"ADIANTOU","ratio":.55,"gear":3,"speed":121.0,"remaining":640.0,"elapsed":6.0,"gap":-6.5},
	{"id":"06_no_nitro_behind","nitro":false,"ratio":.80,"gear":4,"speed":168.0,"remaining":310.0,"elapsed":12.4,"gap":-31.0},
	{"id":"07_challenge_livia","challenge":"livia","ratio":.88,"gear":4,"speed":119.0,"remaining":216.0,"elapsed":9.15,"gap":-67.6,"feedback":"BOA TROCA"},
]
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("DRAG_HUD_STATES timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		print("DRAG_HUD_STATES FAIL ",message)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Capturas exigem janela renderizada e --no-save.")
		quit(2)
		return
	var hud_path := "res://activities/desert_drag/DesertDragHUD.gd"
	var output := "res://evidence/drag-hud-states-%d"%Time.get_unix_time_from_system()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--hud="): hud_path=argument.trim_prefix("--hud=")
		if argument.begins_with("--out="): output=argument.trim_prefix("--out=")
	if not output.begins_with("res://evidence/") or DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))!=OK:
		push_error("Pasta de saída inválida: "+output)
		quit(2)
		return
	preload("res://runtime/Localization.gd").install()
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.min_size=Vector2i(640,360)
	# Céu e areia do pátio às 21 h, para julgar contraste como na corrida.
	var sky := ColorRect.new()
	sky.color=Color("2a3340")
	root.add_child(sky)
	sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sand := ColorRect.new()
	sand.color=Color("6e5a45")
	root.add_child(sand)
	sand.set_anchors_preset(Control.PRESET_FULL_RECT)
	sand.anchor_top=.42
	var asphalt := ColorRect.new()
	asphalt.color=Color("1d2228")
	root.add_child(asphalt)
	asphalt.set_anchors_preset(Control.PRESET_FULL_RECT)
	asphalt.anchor_top=.5
	asphalt.anchor_bottom=.72
	var hud: Control = load(hud_path).new()
	root.add_child(hud)
	var challenge := CHALLENGE.new()
	var telemetry := TELEMETRY.new()
	challenge._telemetry=telemetry
	telemetry.launch="BOA LARGADA"
	telemetry.limiter_seconds=.2
	telemetry.nitro_seconds=.8
	var count := 0
	for locale in ["en","pt_BR"]:
		TranslationServer.set_locale(locale)
		for resolution in RESOLUTIONS:
			root.size=resolution
			for frame in 4: await process_frame
			for row in CASES:
				var drive := DRIVE.new()
				drive.configure("desert_faisca",{"nitro":"nitro_race"} if row.get("nitro",true) else {})
				drive.race_mode=true
				drive.rpm=drive.redline*float(row.ratio)
				drive.speed_mps=float(row.speed)/3.6
				drive.gear=int(row.gear)
				drive.nitro=.68 if row.get("nitro",true) else 0.0
				var staging: bool=row.get("staging",false)
				hud.race_distance=800.0
				hud.show_start_lights=staging
				hud.racing=not staging
				hud.feedback=str(row.get("feedback",""))
				hud.rival_offscreen=1 if float(row.gap)<-50.0 else 0
				hud.event_title=""
				hud.challenge_status=""
				if row.has("challenge"):
					challenge._armed={"rival_id":row.challenge,"step":1}
					hud.event_title="DESAFIO · LÍVIA"
					hud.challenge_status=challenge.live_status()
				hud.update_state(drive,float(row.remaining),float(row.elapsed),float(row.gap),str(row.get("headline","")),"Digo" if not row.has("challenge") else "Lívia")
				hud.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var name := "%s-%dx%d-%s.png"%[locale.left(2),resolution.x,resolution.y,row.id]
				check(root.get_texture().get_image().save_png(output.path_join(name))==OK,"gravar "+name)
				count+=1
	challenge.free()
	print("DRAG_HUD_STATES output=",ProjectSettings.globalize_path(output)," captures=",count," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
