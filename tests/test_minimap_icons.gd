extends SceneTree
## Ícones de lugar do minimapa não piscam: o jogador anda por um grupo de lugares próximos (alguns a
## menos de 17 px um do outro, mais lugares que as 8 vagas), em zigue-zague e com o zoom mudando como
## no jogo. Entrar e sair do mapa é normal; piscar é sumir e voltar (ou o contrário) em menos de
## BLINK_METRES de caminho. Compara com a regra antiga (ordem só pela distância a cada redesenho),
## que é a que piscava no playtest de 26/10. Não abre o jogo.
const MINIMAP := preload("res://ui/v1/HarborMinimap3D.gd")
const STEP := .5
const BLINK_METRES := 4.0
var checks := 0
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	checks += 1
	print("MINIMAP_ICONS ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func _initialize() -> void:
	var places: Array[Dictionary] = []
	var spots := [Vector2(0,20), Vector2(8,22), Vector2(-6,17), Vector2(5,14), Vector2(40,-10), Vector2(43,-4), Vector2(-35,-12),
		Vector2(-30,-8), Vector2(70,25), Vector2(75,30), Vector2(-70,28), Vector2(-66,33), Vector2(20,-30), Vector2(26,-33)]
	for i in spots.size(): places.append({"id":"p%d" % i, "region":"harbor", "kind":"shop", "title":"Lugar %d" % i, "point":spots[i]})
	var fresh := {"name": "nova", "shown": {}, "changed": {}, "blinks": 0}
	var old := {"name": "antiga", "shown": {}, "changed": {}, "blinks": 0}
	var labels := {"name": "etiqueta", "shown": {}, "changed": {}, "blinks": 0}
	var step := 0
	var x := -160.0
	while x <= 160.0:
		# Zigue-zague de quem anda e zoom que muda com a velocidade.
		var center := Vector2(x, 2.0 + sin(x * 2.3) * 2.0)
		var scale := lerpf(MINIMAP.SCALE, .85, .5 + .5 * sin(x * .15))
		var view := MINIMAP.MAP_SIZE / scale
		var area := Rect2(center - view * .5, view)
		var nearby: Array[Dictionary] = []
		var icons: Array[Vector2] = []
		var keep := area.grow(MINIMAP.KEEP_MARGIN / scale)
		for place in places:
			if not area.has_point(place.point) and not (fresh.shown.has(MINIMAP.place_key(place)) and keep.has_point(place.point)): continue
			nearby.append(place)
			icons.append(MINIMAP.MAP_SIZE * .5 + (place.point - center) * scale)
		var picked: Dictionary = MINIMAP.choose_places(nearby, icons, center, fresh.shown, labels.shown)
		var now := {}
		var now_labels := {}
		for index: int in picked.shown: now[MINIMAP.place_key(nearby[index])] = true
		for index: int in picked.labels: now_labels[MINIMAP.place_key(nearby[index])] = true
		_advance(fresh, now, step)
		_advance(labels, now_labels, step)
		_advance(old, _old_rule(places, area, center, scale), step)
		step += 1
		x += STEP
	print("MINIMAP_ICONS piscadas: regra nova %d, regra antiga %d, etiquetas %d" % [fresh.blinks, old.blinks, labels.blinks])
	check(old.blinks > 0, "a regra antiga pisca neste percurso (%d), então o teste reproduz o defeito" % old.blinks)
	check(fresh.blinks == 0, "regra nova não pisca nenhum ícone (%d)" % fresh.blinks)
	check(labels.blinks <= 2, "etiquetas não ficam pulando (%d)" % labels.blinks)
	print("MINIMAP_ICONS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)

## Conta como piscada a troca de um ícone que já tinha trocado há menos de BLINK_METRES.
static func _advance(track: Dictionary, now: Dictionary, step: int) -> void:
	var keys: Array = now.keys()
	for key in track.shown: if not now.has(key): keys.append(key)
	for key in keys:
		if now.has(key) == track.shown.has(key): continue
		if track.changed.has(key) and float(step - int(track.changed[key])) * STEP < BLINK_METRES: track.blinks += 1
		track.changed[key] = step
	track.shown = now

## Regra de antes de 26/10: ordem por distância a cada redesenho, sem preferência por quem já estava.
static func _old_rule(places: Array[Dictionary], area: Rect2, center: Vector2, scale: float) -> Dictionary:
	var nearby := places.filter(func(place): return area.has_point(place.point))
	nearby.sort_custom(func(a, b): return center.distance_squared_to(a.point) < center.distance_squared_to(b.point))
	var occupied: Array[Vector2] = []
	var result := {}
	for place in nearby:
		var icon: Vector2 = MINIMAP.MAP_SIZE * .5 + (place.point - center) * scale
		if icon.distance_to(MINIMAP.MAP_SIZE * .5) < 12 or occupied.any(func(point): return point.distance_to(icon) < 17): continue
		occupied.append(icon)
		result[MINIMAP.place_key(place)] = true
		if result.size() >= 8: break
	return result
