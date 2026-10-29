extends SceneTree
## Contrato da saída do telhado (playtest 29/10): a escada pintada do quartel sobra num
## módulo só da lateral leste, e a saída do telhado (patamar + casinha) fica no topo dela,
## dentro do telhado. Sem Main.tscn; não confere visual (isso é no jogo).
const KIT := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const ROOFS := preload("res://world/places/harbor_buildings/HarborServiceRoofCatalog.gd")
const CIRCULATION := preload("res://world/places/harbor_buildings/HarborRoofCirculation.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	var depth := 220.0/16.0
	var z := KIT.side_ladder_z("bombeiros", depth)
	check(is_finite(z), "bombeiros tem escada pintada na lateral")
	check(z > -depth*.5 and z < depth*.5, "escada dentro da lateral (z=%.2f)" % z)
	check(not is_finite(KIT.side_ladder_z("casa-patrol-b", 12.0)), "estilo sem escada não inventa uma")
	var fire := ROOFS.find("harbor_fire_station")
	if not fire.is_empty() and PaintedHarborHouses.style_for("NorthFireStation", "fire_station") != "":
		var stair := CIRCULATION.stair(fire)
		check(stair.x > 0.0, "saída do quartel no lado leste da escada")
		check(absf(stair.z - z*fire.size.y/depth) < .05, "patamar alinhado ao topo da escada")
		check(absf(stair.x) < fire.size.x*.5 - .9, "patamar dentro da platibanda")
		var house := stair + CIRCULATION.HOUSE_OFFSET
		check(absf(house.x) + CIRCULATION.HOUSE_SIZE.x*.5 < fire.size.x*.5 - .1, "casinha dentro do telhado")
	var bank := ROOFS.find("harbor_bank")
	if not bank.is_empty():
		check(CIRCULATION.stair(bank).is_equal_approx(Vector3(-bank.size.x*.5+1.45, 0, 1.45)), "outros telhados mantêm o canto oeste")
	print("ROOF_SINGLE_EXIT falhas=%d" % failures)
	quit(1 if failures > 0 else 0)
