extends "res://scripts/Vehicle.gd"
const AUDIO := preload("res://gameplay/digo/DigoAmarokAudio.gd")
func _init() -> void:
	archetype = "digo_amarok_2014"
	vehicle_id = archetype
	paint_color = Color("f0f1ef")
	set_meta("owner_id","digo")
	set_meta("personal_vehicle",true)
func _ready() -> void:
	super._ready()
	install_audio(self)
static func install_audio(car: CharacterBody3D) -> Node:
	car.add_to_group("digo_amarok")
	car.set_meta("owner_id","digo")
	car.set_meta("personal_vehicle",true)
	if car.has_node("DigoAmarokExhaust"): return car.get_node("DigoAmarokExhaust")
	var sound := AUDIO.new()
	sound.name = "DigoAmarokExhaust"
	car.add_child(sound)
	return sound
