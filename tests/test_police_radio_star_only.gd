extends SceneTree

var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	create_timer(15).timeout.connect(func():
		printerr("TIMEOUT in test_police_radio_star_only")
		quit(2)
	)

	var wanted = root.get_node("WantedManager")
	check(wanted != null, "WantedManager autoload exists")
	wanted.reset()

	var radio_calls: Array[Dictionary] = []
	wanted.radio_message.connect(func(event: StringName, level: int):
		radio_calls.append({"event": event, "level": level})
	)

	# 1. Ganhar 1 estrela deve disparar rádio policial
	wanted.report_crime(15) # STAR_THRESHOLDS[1] = 12
	check(wanted.current_stars == 1, "Crime reported sets 1 star")
	check(radio_calls.size() == 1, "Radio message emitted once on 1st star")
	if radio_calls.size() == 1:
		check(radio_calls[0].event == &"suspect_spotted", "1st star event is suspect_spotted")
		check(radio_calls[0].level == 1, "Level is 1")
	check(is_instance_valid(wanted._radio_player), "Radio player instance created")
	var initial_player = wanted._radio_player

	# 2. Crime adicional que NÃO sobe de estrela não deve tocar rádio
	wanted.report_crime(5) # Total 20 < STAR_THRESHOLDS[2] = 30
	check(wanted.current_stars == 1, "Stars remain 1")
	check(radio_calls.size() == 1, "No extra radio call when stars do not increase")

	# 3. Ganhar 2ª estrela deve disparar rádio e REAPROVEITAR o mesmo nó de áudio
	wanted.report_crime(15) # Total 35 >= STAR_THRESHOLDS[2] = 30
	check(wanted.current_stars == 2, "Crime brings wanted level to 2 stars")
	check(radio_calls.size() == 2, "Radio message emitted once on 2nd star")
	if radio_calls.size() == 2:
		check(radio_calls[1].event == &"reinforcements", "2nd star event is reinforcements")
		check(radio_calls[1].level == 2, "Level is 2")
	check(wanted._radio_player == initial_player, "Audio player node reused without churn")

	# 4. Despacho de viatura não deve tocar rádio
	var dummy_unit = Node.new()
	wanted._configure_dispatch(dummy_unit)
	check(radio_calls.size() == 2, "Dispatching unit does not trigger radio")
	dummy_unit.free()

	# 5. Crime intermediário em 2 estrelas que não alcança 3 estrelas (60 pts) não toca rádio
	wanted.report_crime(5) # Total 40 < STAR_THRESHOLDS[3] = 60
	check(wanted.current_stars == 2, "Stars remain 2")
	check(radio_calls.size() == 2, "Intermediate crime without star gain does not trigger radio")

	# 6. Escapar da busca (reset) não dispara rádio
	wanted.reset_crime()
	check(wanted.current_stars == 0, "Crime reset to 0 stars")
	check(radio_calls.size() == 2, "Escape/reset does not trigger radio")

	# 7. Furto de viatura policial (roubar cruiser) ganha estrela e toca rádio
	wanted.report_police_car_theft()
	check(wanted.current_stars == 1, "Car theft gives 1 star")
	check(radio_calls.size() == 3, "Car theft star gain triggers radio")
	check(wanted._radio_player == initial_player, "Audio player node still reused")

	# 8. Morte de oficial eleva para 3 estrelas (STAR_THRESHOLDS[3]=60), disparando rádio da nova estrela
	wanted.report_officer_killed()
	check(wanted.current_stars >= 3, "Officer killed promoted wanted level")
	check(radio_calls.size() == 4, "Officer killed star promotion triggered radio for new star")

	# 9. Segundo policial morto sem subir de estrela (crime points 90 < STAR_THRESHOLDS[4] = 100) NÃO dispara rádio
	wanted.report_officer_killed()
	check(wanted.current_stars == 3, "Second officer death kept wanted level at 3")
	check(radio_calls.size() == 4, "No radio triggered when officer death does not gain a star")

	wanted.reset()
	print("POLICE RADIO STAR ONLY: %d failures" % failures)
	quit(1 if failures else 0)
