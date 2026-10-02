extends "res://tests/test_vehicle_crash_damage.gd"
## Reuse the existing physical crash scenario; do not inject an audio event.
var contact_audio_checks := 0

func check(condition: bool, label: String) -> void:
	super.check(condition, label)
	if label != "carros colidem e ambos recebem dano" or not condition: return
	var world: Node3D
	for child in root.get_children():
		if child is Node3D: world = child
	var pool = world.get_node_or_null("ContactAudio") if world != null else null
	var cars: Array[Node3D] = []
	if world != null:
		for child in world.get_children():
			if child is CharacterBody3D and "archetype" in child: cars.append(child)
	var pair := ""
	if cars.size() == 2:
		pair = "%d|%d" % [mini(cars[0].get_instance_id(),cars[1].get_instance_id()),maxi(cars[0].get_instance_id(),cars[1].get_instance_id())]
	var emitted: bool = pool != null and not pair.is_empty() and float(pool.contacts.get(pair,{}).get("played",-1000.0)) >= 0.0
	super.check(emitted, "colisao carro-carro real emite audio pelo hook produtivo")
	contact_audio_checks += 1
	print("VEHICLE_CONTACT_COLLISION audio_checks=",contact_audio_checks," emitted=",emitted," pair=",pair)
