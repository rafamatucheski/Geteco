extends SceneTree
## Produz imagens finais com o elenco nativo. O jogo só reproduz os arquivos exportados.
const Timeline=preload("res://cutscenes/opening/v3/opening_timeline.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	root.size=Vector2i(1920,1080)
	var view:=SubViewport.new(); view.size=root.size; view.own_world_3d=true
	view.msaa_3d=Viewport.MSAA_4X; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var stage: Node3D=load("res://cutscenes/opening/v3/opening_stage.gd").new(); view.add_child(stage)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://cutscenes/opening/v3/assets/stills"))
	for index in Timeline.SHOTS.size():
		var shot: Dictionary=Timeline.SHOTS[index]
		stage.set_time(float(shot.pose))
		if shot.id==&"phone_on_table": stage.phone_label.text=""
		# Enquadramentos próprios para fotografias, sem fases intermediárias da pegada.
		match String(shot.id):
			"morning_coffee": stage._camera(Vector3(-1.45,1.52,-2.65),Vector3(0,.87,-.04),43)
			"coffee_detail": stage._camera(Vector3(.04,1.15,-1.07),Vector3(.24,.94,-.31),38)
			"cup_on_table": stage._camera(Vector3(-.02,.96,-.95),Vector3(.17,.77,-.35),29)
			"dante_at_home": stage._camera(Vector3(-.60,1.22,-1.58),Vector3(0,1.01,-.06),33)
			"brother_released": stage._camera(Vector3(-.16,1.115,-.81),Vector3(0,1.07,-.015),31)
			"harbor_clue": stage._camera(Vector3(-.66,1.17,-.94),Vector3(0,1.06,-.015),33)
			"line_disconnected": stage._camera(Vector3(-.46,1.20,-1.55),Vector3(0,1.02,-.03),34)
			"phone_on_table", "anonymous_call", "phone_put_down": stage._camera(Vector3(.85,1.15,-.42),Vector3(.34,.76,-.20),28)
			"weighing_decision": stage._camera(Vector3(-.74,1.22,-1.76),Vector3(-.03,.96,-.07),34)
			"opens_gallery": stage._camera(stage.actor.to_global(Vector3(.30,1.30,.06)),stage.phone.position,34)
			"road_to_harbor": stage._camera(stage.bus.position+Vector3(-13,6,6),stage.bus.position+Vector3(0,1,0),43)
		for i in 8: await process_frame
		await RenderingServer.frame_post_draw
		var result:=view.get_texture().get_image().save_jpg(Timeline.image_path(index),.96)
		if result!=OK: push_error("Falha ao exportar "+String(shot.id)); quit(1); return
		print("STILL ",index+1," ",shot.id)
		if shot.id==&"anonymous_call":
			stage.phone_label.text="UNKNOWN"
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_jpg(Timeline.image_path(index).replace(".jpg","_en.jpg"),.96)
	print("OPENING_STILLS_RENDER PASS: ",Timeline.SHOTS.size()," imagens")
	quit()
