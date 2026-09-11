extends RefCounted
## Uma única cronologia alimenta montagem, atuação, legendas e stems offline.
const TOTAL_DURATION_SECONDS := 68.0
const DESTINATION_BEAT := &"bus_terminal_arrival"
const SHOTS := [
	{"id": &"morning_coffee", "start": 0.0, "duration": 6.0},
	{"id": &"family_photos", "start": 6.0, "duration": 7.0},
	{"id": &"phone_hesitation", "start": 13.0, "duration": 5.0},
	{"id": &"call_reaction", "start": 18.0, "duration": 13.0},
	{"id": &"quiet_decision", "start": 31.0, "duration": 7.0},
	{"id": &"backpack_departure", "start": 38.0, "duration": 4.0},
	{"id": &"empty_frame", "start": 42.0, "duration": 4.0},
	{"id": &"bus_highway", "start": 46.0, "duration": 7.0},
	{"id": &"dante_bus_interior", "start": 53.0, "duration": 8.0},
	{"id": &"bus_terminal_arrival", "start": 61.0, "duration": 7.0},
]
const CUES := [
	[1.3, &"coffee_pour"], [8.4, &"photo_frame"], [11.1, &"uniform_box"],
	[16.0, &"phone_ring_old"], [18.2, &"phone_answer_click"],
	[19.0, &"voice_caller_release"], [23.0, &"voice_caller_harbor"],
	[27.0, &"voice_dante_who_are_you"], [29.45, &"phone_disconnect"],
	[33.7, &"photo_paper"], [36.0, &"jacket_fabric"], [38.0, &"music_travel"],
	[38.4, &"backpack_buckle"], [42.2, &"floor_steps"], [44.5, &"door_close"],
	[46.0, &"bus_diesel_exterior"], [53.0, &"bus_diesel_interior"],
	[61.0, &"terminal_ambience"], [64.8, &"bus_air_brake"], [66.45, &"bus_door"],
]

static func shot_at(time: float) -> int:
	for i in range(SHOTS.size() - 1, -1, -1):
		if time >= float(SHOTS[i].start): return i
	return 0
