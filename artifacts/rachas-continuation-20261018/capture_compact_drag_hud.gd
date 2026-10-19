extends SceneTree
## Directed visual fixture: production HUD, drivetrain and live-status formatter.
## This is not Main, a driving test, a performance test, or input-device certification.
const HUD := preload("res://activities/desert_drag/DesertDragHUD.gd")
const DRIVE := preload("res://gameplay/desert_cars/DesertDrivetrain.gd")
const CHALLENGE := preload("res://activities/desert_drag/DragRivalChallengeController.gd")
const TELEMETRY := preload("res://activities/desert_drag/DragRivalChallengeTelemetry.gd")
const RESOLUTIONS := [Vector2i(960,540),Vector2i(1280,720)]
const CASES := [
	{"id":"livia_long_status","rival":"Lívia","rival_id":"livia","step":1,"staging":false,"launch":"GIRO BAIXO","remaining":216.0,"elapsed":9.15,"gap":-67.6,"speed":119.0,"gear":4,"ratio":.88},
	{"id":"rauhz_live_status","rival":"Rauhz","rival_id":"rauhz","step":1,"staging":false,"launch":"BOA LARGADA","remaining":143.0,"elapsed":14.73,"gap":12.8,"speed":218.0,"gear":5,"ratio":.92},
	{"id":"rauhz_staging","rival":"Rauhz","rival_id":"rauhz","step":0,"staging":true,"launch":"","remaining":800.0,"elapsed":0.0,"gap":0.0,"speed":0.0,"gear":1,"ratio":.52},
]
var output := ""
var failures: Array[String] = []
var captures: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(45).timeout.connect(func(): push_error("COMPACT_HUD timeout"); quit(3))
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("COMPACT_HUD ","PASS " if ok else "FAIL ",message)
	if not ok: failures.append(message)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args():
		push_error("Render fixture requires the .NET executable, a rendered window and --no-save.")
		quit(2)
		return
	TranslationServer.set_locale("pt_BR")
	output="res://evidence/drag-hud-compact-%d-%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))!=OK:
		quit(2)
		return
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	root.min_size=Vector2i(640,360)
	var background := ColorRect.new()
	background.color=Color("e6d6ae")
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text="HUD real · captura isolada sobre fundo claro"
	label.position=Vector2(20,155)
	label.add_theme_color_override("font_color",Color("423d33"))
	label.add_theme_font_size_override("font_size",14)
	root.add_child(label)
	var hud := HUD.new()
	root.add_child(hud)
	var drive := DRIVE.new()
	drive.configure("desert_faisca",{"nitro":"nitro_race"})
	drive.race_mode=true
	var challenge := CHALLENGE.new()
	var telemetry := TELEMETRY.new()
	challenge._telemetry=telemetry
	var hint_review := "--hint-review" in OS.get_cmdline_user_args()
	var resolutions: Array=[Vector2i(960,540)] if hint_review else RESOLUTIONS
	var cases: Array=[CASES[0]] if hint_review else CASES
	for resolution in resolutions:
		root.size=resolution
		root.content_scale_size=resolution
		for frame in 4: await process_frame
		check(Vector2i(hud.size)==resolution,"HUD canvas matches %s"%resolution)
		for row in cases:
			challenge._armed={"rival_id":row.rival_id,"step":row.step}
			telemetry.launch=row.launch
			telemetry.nitro_seconds=0.0
			telemetry.limiter_seconds=.4 if row.id=="rauhz_live_status" else 0.0
			telemetry.good_shifts=3 if row.id=="rauhz_live_status" else 0
			telemetry.bad_shifts=0
			drive.rpm=drive.redline*float(row.ratio)
			drive.speed_mps=float(row.speed)/3.6
			drive.gear=int(row.gear)
			drive.nitro=.68
			drive.nitro_active=false
			hud.race_distance=800.0 if row.rival_id=="rauhz" else 402.0
			hud.racing=not row.staging
			hud.show_start_lights=row.staging
			hud.feedback="" if row.staging else "Troca ideal"
			hud.rival_offscreen=1 if float(row.gap)<-50.0 else 0
			hud.event_title="DESAFIO · "+str(row.rival).to_upper()
			hud.challenge_status=challenge.live_status()
			hud.update_state(drive,float(row.remaining),float(row.elapsed),float(row.gap),"2" if row.staging else "",row.rival)
			var status_width: float=HUD.BODY.get_string_size(hud.challenge_status,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x
			check(status_width<=496.0,"live status fits logical width: "+str(row.id))
			for gamepad in [false,true]:
				var device := "gamepad" if gamepad else "keyboard"
				# Send the device-selection event to the real HUD, without injecting OS input.
				if gamepad:
					var event := InputEventJoypadButton.new()
					event.button_index=JOY_BUTTON_A
					hud._input(event)
				else:
					var event := InputEventKey.new()
					event.keycode=KEY_W
					hud._input(event)
				check(hud.input_gamepad==gamepad,"device legends select "+device)
				hud.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var screenshot := root.get_texture().get_image()
				var name := "%dx%d-%s-%s.png"%[resolution.x,resolution.y,row.id,device]
				check(screenshot.get_size()==resolution,"capture pixel dimensions "+name)
				check(screenshot.save_png(output.path_join(name))==OK,"write "+name)
				captures.append({"file":name,"width":resolution.x,"height":resolution.y,"scenario":row.id,"device":device,
					"live_status":hud.challenge_status,"status_logical_width":status_width,"status_available_width":496,
					"scope":"Real production HUD and text formatter over a neutral bright fixture, not Main gameplay."})
	var report := FileAccess.open(output.path_join("capture.json"),FileAccess.WRITE)
	if report!=null:
		report.store_string(JSON.stringify({"captures":captures,"failures":failures,"visual_review_required":true},"\t"))
		report.close()
	else: failures.append("Cannot write capture manifest")
	challenge.free()
	print("COMPACT_HUD_DONE output=",ProjectSettings.globalize_path(output)," captures=",captures.size()," failures=",failures)
	quit(0 if failures.is_empty() else 1)
