extends SceneTree
const MEET := preload("res://gameplay/classic_meet/ClassicMeetController.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var nights := 0
	for day in 7:
		var expected := day in [1,3,5]
		check(MEET.is_event_time(day,20.0/24.0) == expected,"Evening schedule day %d" % day)
		check(not MEET.is_event_time(day,12.0/24.0),"No daytime meet day %d" % day)
		check(not MEET.is_event_time(day,18.999/24.0),"No early start day %d" % day)
		check(MEET.is_event_time(day,19.0/24.0) == expected,"Exact opening day %d" % day)
		check(MEET.is_event_time(day+1,.5/24.0) == expected,"Midnight belongs to previous evening %d" % day)
		check(not MEET.is_event_time(day+1,1.0/24.0),"Exact closing day %d" % day)
		if MEET.is_event_time(day,20.0/24.0): nights += 1
	check(nights == 3,"Exactly three evenings per calendar week")
	check(MEET.is_event_time(8,20.0/24.0),"Calendar repeats following Tuesday")
	check(MEET.event_day(6,.5/24.0) == 5,"Sunday after midnight preserves Saturday identity")
	check(MEET.event_day(5,23.5/24.0) == 5,"Before and after midnight share event identity")
	for invalid in [-.01,1.0,INF,NAN]: check(not MEET.is_event_time(1,invalid),"Reject invalid clock %s" % invalid)
	print("CLASSIC_MEET_SCHEDULE failures=",failures)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
