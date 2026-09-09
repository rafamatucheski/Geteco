extends "res://district/harbor_preview/events/WorldEventResident.gd"

const STOPS := [Vector2(-90,-225), Vector2(-90,-65), Vector2(90,35), Vector2(90,215)]
const STORIES_PT := [
	"Dona Alzira consertava as redes do cais. Nos dias de tempestade, deixava uma vela acesa para quem ainda estava no mar.",
	"Bento era maquinista. Reconhecia cada passageiro pelo passo na plataforma. No último dia, ninguém veio se despedir.",
	"Rosa plantava flores nas janelas da rua inteira. Esta aqui aparece todo inverno. Eu nunca vi quem traz.",
	"Samuel guardava cartas que nunca enviou. Dizia que algumas verdades precisavam esperar. Uma delas desapareceu."
]
const STORIES_EN := [
	"Alzira mended the harbor nets. On stormy nights, she kept a candle burning for those still at sea.",
	"Bento drove the train. He knew every passenger by their footsteps. On his last day, nobody came to say goodbye.",
	"Rosa planted flowers in every window on her street. This one appears each winter. I've never seen who brings it.",
	"Samuel kept letters he never sent. Some truths needed to wait, he said. One of those letters vanished."
]
var stop_index := 0
var waiting := 0.0
var told := false

func _ready() -> void:
	resident_name = "ELIAS"
	coat_color = Color("514b43")
	lines.clear()
	travel_speed = 20
	super._ready()
	add_to_group("cemetery_storyteller")
	speech.add_theme_font_size_override("font_size", 13)
	speech.size.x = 320
	speech.position = Vector2(-160,-100)
	_go_to_stop()

func _go_to_stop() -> void:
	var origin: Vector2 = get_parent().global_position
	set_route(PackedVector2Array([Vector2(origin.x,global_position.y), origin+Vector2(0,STOPS[stop_index].y), origin+STOPS[stop_index]]))
	waiting = 0
	told = false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_dead: return
	if not finished: return
	waiting += delta
	var viewer := get_tree().get_first_node_in_group("player") as Node2D
	var nearby: bool = is_instance_valid(viewer) and viewer.visible and viewer.global_position.distance_to(global_position) < 135 and not viewer.get_meta("mountain_interior",false)
	if nearby and not told:
		speech.text = resident_name + ": " + (STORIES_PT[stop_index] if TranslationServer.get_locale().begins_with("pt") else STORIES_EN[stop_index])
		told = true
		waiting = 0
	if not nearby or waiting > 12: speech.text = ""
	if waiting > 18:
		stop_index = (stop_index + 1) % STOPS.size()
		speech.text = ""
		_go_to_stop()
