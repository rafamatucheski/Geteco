extends SceneTree
## Contatos das poses selecionadas para as fotografias, sem simular transições.
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1

func run() -> void:
	var stage: Node3D=load("res://cutscenes/opening/v3/opening_stage.gd").new()
	root.add_child(stage); await process_frame
	var max_error:=0.0; var worst_time:=0.0
	var highest_elbow:=-10.0; var torso_hits:=0; var bag_hits:=0; var finger_away:=0
	var torso:=AABB(Vector3(-.155,.74,-.128),Vector3(.31,.33,.228))
	var bag_box:=AABB(Vector3(-.23,-.035,-.15),Vector3(.46,.455,.30))
	for shot in preload("res://cutscenes/opening/v3/opening_timeline.gd").SHOTS:
		var t:=float(shot.pose)
		stage.set_time(t)
		for i in 2:
			if stage.performance.weights[i]>.999:
				var tip: Vector3=stage.hands[i].thumb_tip.global_position
				var error: float=tip.distance_to(stage.performance.contacts[i])
				if error>max_error: max_error=error; worst_time=t
				var finger: Node3D=stage.hands[i].fingers[1].get_child(1).get_child(1).get_child(0)
				if stage.hands[i].to_local(finger.global_position).z>0: finger_away+=1
			var upper: Node3D=stage.host.left_upper_arm if i==0 else stage.host.right_upper_arm
			var lower: Node3D=stage.host.left_lower_arm if i==0 else stage.host.right_lower_arm
			var elbow: Vector3=lower.global_position
			if i==1 and t>=19.05 and t<33:
				highest_elbow=maxf(highest_elbow,elbow.y-upper.global_position.y)
			for sample in 13:
				var point: Vector3=elbow.lerp(stage.palms[i].global_position,float(sample)/12)
				if stage.backpack.visible and bag_box.has_point(stage.backpack.to_local(point)): bag_hits+=1
				if t>=17.25 and t<34.8 and i==1 and torso.has_point(stage.actor.to_local(point)): torso_hits+=1
	check(max_error<.008,"Contato: max %.4f m em %.3f s" % [max_error,worst_time])
	check(highest_elbow<-.05,"Cotovelo fica abaixo do ombro na ligacao: %.3f m" % highest_elbow)
	check(torso_hits==0,"Antebraco do telefone fora do volume do tronco: %d" % torso_hits)
	check(bag_hits==0,"Antebracos fora da mochila, com margem de espessura: %d" % bag_hits)
	check(finger_away==0,"Dedos fecham na direcao do polegar e do objeto")
	stage.set_time(2.4)
	var points: PackedVector3Array=stage.coffee.stream_points
	check(points[0].distance_to(stage.coffee.tip.global_position)<.0001,"Cafe nasce na boca do bico")
	check(points[-1].distance_to(stage.mug.position+Vector3(0,.118,0))<.001,"Fluxo termina dentro da xicara")
	var penetrations:=0
	for point in points:
		var local: Vector3=stage.pot.to_local(point)
		if absf(local.y)<.074 and Vector2(local.x,local.z).length()<.065: penetrations+=1
	check(penetrations==0,"Fluxo nao atravessa o corpo do bule")
	check(points[12].distance_to(points[0].lerp(points[-1],.5))>.01,"Queda curva, sem cilindro reto")
	stage.set_time(35.1)
	var held_photo: Transform3D=stage.loose_photo.transform
	var resting_phone: Transform3D=stage.phone.transform
	var still_objects:=true
	for at in [37.0,39.0,41.0,43.9]:
		stage.set_time(at)
		still_objects=still_objects and stage.loose_photo.transform.is_equal_approx(held_photo) and stage.phone.transform.is_equal_approx(resting_phone)
	check(still_objects,"Nove segundos de reflexao sem pegar foto ou telefone")
	stage.set_time(68); var bus_photo: Transform3D=stage.loose_photo.transform
	stage.set_time(35); stage.set_time(68)
	check(stage.loose_photo.transform.is_equal_approx(bus_photo),"Seek deterministico")
	check(stage.frame_photo.get_parent()==stage.loose_photo,"Uma unica fotografia")
	stage.queue_free(); await process_frame; await create_timer(.25).timeout
	print("OPENING_CONTACTS_V3 failures=",failures)
	quit(1 if failures else 0)
