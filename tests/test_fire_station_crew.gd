extends SceneTree
## Contrato do playtest de 29/10: quem atende dentro do quartel veste farda de bombeiro
## (corpo de função "firefighter"), não um civil sorteado. A arte do quartel mantém a
## equipe de plantão. Sem Main.tscn; não confere visual (isso é no jogo).
const RESIDENTS := preload("res://world/places/OriginalResidents.gd")
const ART := "res://assets/regions/source/world/harbor/interiors/FireStationArt3D.gd"
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	var crew := RESIDENTS.for_place("harbor_fire_station")
	check(not crew.is_empty(), "quartel tem atendente")
	for resident in crew:
		var model: Node3D = RESIDENTS.create_model(resident)
		check(model.get("body_role") == "firefighter", "%s com corpo de bombeiro" % resident.name)
		if model.has_method("_body_look"): check(model._body_look().get("role", "") == "firefighter", "%s veste a farda" % resident.name)
		model.free()
	var source := FileAccess.get_file_as_string(ART)
	check(source.contains("OnDutyFirefighter"), "arte do quartel mantém a equipe de plantão")
	print("FIRE_STATION_CREW falhas=%d" % failures)
	quit(1 if failures > 0 else 0)
