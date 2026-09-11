extends SceneTree
## Verifica contato físico e continuidade entre quadros, inclusive em seek regressivo.
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func run() -> void:
	var opening: Control=load("res://cutscenes/opening/OpeningCutscene.tscn").instantiate()
	opening.auto_start=false; root.add_child(opening); await process_frame
	var stage: Node3D=opening.stage
	var max_error:=0.0; var worst_time:=0.0; var worst_hand:=0
	var max_step:=0.0; var step_time:=0.0
	var previous_photo:=Vector3.ZERO; var previous_phone:=Vector3.ZERO
	for interval in [Vector2(0,12.9),Vector2(17,41.9),Vector2(53,60.9)]:
		var first:=true
		for frame in range(int(interval.x*60),int(interval.y*60)):
			var t:=float(frame)/60
			stage.set_time(t)
			for i in 2:
				if stage.performance.weights[i]>.999:
					var tip: Vector3=stage.hands[i].thumb_tip.global_position
					var error: float=tip.distance_to(stage.performance.contacts[i])
					if error>max_error: max_error=error; worst_time=t; worst_hand=i
			if not first:
				var distance: float=maxf(stage.loose_photo.position.distance_to(previous_photo),stage.phone.position.distance_to(previous_phone))
				if distance>max_step: max_step=distance; step_time=t
			first=false; previous_photo=stage.loose_photo.position; previous_phone=stage.phone.position
	check(max_error<.008,"Contato polegar/objeto: máximo %.4f m em %.3f s mão %d" % [max_error,worst_time,worst_hand])
	check(max_step<.04,"Objetos sem salto dentro do plano: máximo %.4f m em %.3f s" % [max_step,step_time])
	stage.set_time(57); var bus_photo: Transform3D=stage.loose_photo.transform
	stage.set_time(33); stage.set_time(57)
	check(stage.loose_photo.transform.is_equal_approx(bus_photo),"Seek não depende de quadros anteriores")
	for t in [33.69,33.70,37.49,37.51,53.99,54.01,60.39,60.41]:
		stage.set_time(t)
		check(stage.loose_photo.visible and stage.frame_photo.visible,"Papel permanece presente em %.2f s" % t)
	stage.set_time(33.65)
	check(stage.frame_photo.get_parent()==stage.loose_photo,"Um único papel sai do quadro")
	opening.queue_free(); await process_frame; await create_timer(.25).timeout
	print("OPENING_CONTACTS_V3 failures=",failures)
	quit(1 if failures else 0)
