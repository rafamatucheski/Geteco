extends RefCounted
## Fotografias fixas: o palco 3D serve somente para produzir os arquivos offline.
const VoiceTiming=preload("res://cutscenes/opening/v3/voice_timing.gd")
const E := VoiceTiming.CALL_EXTENSION_SECONDS
const TOTAL_DURATION_SECONDS := 77.0+E
const DESTINATION_BEAT := &"bus_terminal_arrival"
# Relogio de poses do palco de autoria, independente do tempo de exibicao.
const REFLECTION_START := 35.0
const REFLECTION_END := 44.0
const SHOTS := [
	{"id": &"morning_coffee", "start": 0, "duration": (1.3)-(0), "pose": 5.6},
	{"id": &"coffee_detail", "start": 1.3, "duration": (4.2)-(1.3), "pose": 2.4},
	{"id": &"cup_on_table", "start": 4.2, "duration": (6)-(4.2), "pose": 5.6},
	{"id": &"family_photos", "start": 6, "duration": (10)-(6), "pose": 7.8},
	{"id": &"dante_at_home", "start": 10, "duration": (13)-(10), "pose": 11.7},
	{"id": &"phone_on_table", "start": 13, "duration": (16)-(13), "pose": 14.5},
	{"id": &"anonymous_call", "start": 16, "duration": (18.2)-(16), "pose": 16.7},
	{"id": &"listening", "start": 18.2, "duration": (24)-(18.2), "pose": 21.0},
	{"id": &"brother_released", "start": 24, "duration": (27.58)-(24), "pose": 24.8},
	{"id": &"harbor_clue", "start": 27.58, "duration": (27.0+E)-(27.58), "pose": 26.5},
	{"id": &"who_is_calling", "start": 27.0+E, "duration": (29.45+E)-(27.0+E), "pose": 29.3},
	{"id": &"line_disconnected", "start": 29.45+E, "duration": (32.1+E)-(29.45+E), "pose": 30.5},
	{"id": &"phone_put_down", "start": 32.1+E, "duration": (33.0+E)-(32.1+E), "pose": 34.3},
	{"id": &"absorbing_news", "start": 33.0+E, "duration": (37.0+E)-(33.0+E), "pose": 37.0},
	{"id": &"weighing_decision", "start": 37.0+E, "duration": (42.2+E)-(37.0+E), "pose": 42.3},
	{"id": &"opens_gallery", "start": 42.2+E, "duration": (44.45+E)-(42.2+E), "pose": 47.5},
	{"id": &"brothers_on_phone", "start": 44.45+E, "duration": (47.0+E)-(44.45+E), "pose": 48.2},
	{"id": &"backpack_departure", "start": 47.0+E, "duration": (51.0+E)-(47.0+E), "pose": 50.5},
	{"id": &"apartment_after_departure", "start": 51.0+E, "duration": (55.0+E)-(51.0+E), "pose": 55.5},
	{"id": &"bus_highway", "start": 55.0+E, "duration": (59.0+E)-(55.0+E), "pose": 59.0},
	{"id": &"road_to_harbor", "start": 59.0+E, "duration": (62.0+E)-(59.0+E), "pose": 62.0},
	{"id": &"gallery_on_bus", "start": 62.0+E, "duration": (65.0+E)-(62.0+E), "pose": 64.5},
	{"id": &"dante_at_window", "start": 65.0+E, "duration": (70.0+E)-(65.0+E), "pose": 69.5},
	{"id": &"bus_terminal_arrival", "start": 70.0+E, "duration": (75.45+E)-(70.0+E), "pose": 74.0},
	{"id": &"terminal_door", "start": 75.45+E, "duration": (77.0+E)-(75.45+E), "pose": 78.7},
 ]
const CUES := [
 [1.3, &"coffee_pour"], [16.0, &"phone_ring_old"], [18.2, &"phone_answer_click"],
 [19.0, &"voice_caller_release"], [VoiceTiming.CALLER_HARBOR_START, &"voice_caller_harbor"],
 [27.0+E, &"voice_dante_who_are_you"], [29.45+E, &"phone_disconnect"],
 [42.2+E, &"phone_gallery_tap"], [45.0+E, &"music_travel"],
 [47.0+E, &"jacket_fabric"], [47.55+E, &"floor_steps"], [51.0+E, &"door_close"],
 [55.0+E, &"bus_diesel_exterior"], [62.0+E, &"bus_diesel_interior"],
 [70.0+E, &"terminal_ambience"], [73.8+E, &"bus_air_brake"], [75.45+E, &"bus_door"],
]
static func shot_at(time: float) -> int:
	for i in range(SHOTS.size()-1,-1,-1):
		if time>=float(SHOTS[i].start): return i
	return 0
static func image_path(index: int) -> String:
	return "res://cutscenes/opening/v3/assets/stills/%02d_%s.jpg" % [index+1,SHOTS[index].id]
static func stage_time(time: float) -> float:
	var acting:=time if time<27 else (27.0 if time<29 else time-2)
	return acting if acting<33.0 else (33.0 if acting<42.0 else acting-9.0)
