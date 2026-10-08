extends RefCounted
## Integer grams keep rankings and ties exact through a JSON save.
const SPECIES := [
	{"id":"tilapia", "name":"Tilápia", "min":400, "max":2600, "strength":0.22, "color":Color("94a99a"), "pattern":"stripes", "tail_shape":"fan", "body_shape":"deep", "weight":20.0, "cast_bonus":0.55},
	{"id":"piau", "name":"Piau", "min":300, "max":2400, "strength":0.30, "color":Color("9eaaa3"), "pattern":"stripes", "tail_shape":"fan", "body_shape":"slender", "weight":15.0, "cast_bonus":0.65},
	{"id":"pacu", "name":"Pacu", "min":1200, "max":6500, "strength":0.48, "color":Color("a3a89a"), "pattern":"plain", "tail_shape":"rounded", "body_shape":"deep", "weight":15.0, "cast_bonus":0.8},
	{"id":"carpa", "name":"Carpa", "min":900, "max":7500, "strength":0.52, "color":Color("c59652"), "pattern":"spots", "tail_shape":"rounded", "body_shape":"deep", "weight":13.0, "cast_bonus":0.85},
	{"id":"traira", "name":"Traíra", "min":700, "max":4200, "strength":0.64, "color":Color("697b53"), "pattern":"stripes", "tail_shape":"forked", "body_shape":"long", "weight":12.0, "cast_bonus":1.05},
	{"id":"matrinxa", "name":"Matrinxã", "min":600, "max":5200, "strength":0.69, "color":Color("a6b4aa"), "pattern":"plain", "tail_shape":"forked", "body_shape":"slender", "weight":9.0, "cast_bonus":1.25},
	{"id":"tambacu", "name":"Tambacu", "min":2000, "max":11500, "strength":0.82, "color":Color("717d7c"), "pattern":"plain", "tail_shape":"fan", "body_shape":"deep", "weight":6.0, "cast_bonus":1.45},
	{"id":"pintado", "name":"Pintado", "min":1800, "max":14000, "strength":0.91, "color":Color("9b987f"), "pattern":"spots", "tail_shape":"forked", "body_shape":"long", "weight":4.0, "cast_bonus":1.8},
	{"id":"tucunare", "name":"Tucunaré", "min":900, "max":9000, "strength":0.88, "color":Color("897d4d"), "pattern":"spots", "tail_shape":"fan", "body_shape":"deep", "weight":3.0, "cast_bonus":1.95},
	{"id":"dourado", "name":"Dourado", "min":1600, "max":9800, "strength":1.0, "color":Color("d4b551"), "pattern":"stripes", "tail_shape":"forked", "body_shape":"slender", "weight":2.0, "cast_bonus":2.1},
	{"id":"pirarara", "name":"Pirarara", "min":2500, "max":14000, "strength":0.96, "color":Color("c78355"), "pattern":"stripes", "tail_shape":"rounded", "body_shape":"long", "weight":1.0, "cast_bonus":2.4},
]
const TIERS := [
	{"name":"Torneio da lagoa", "prize":100, "seconds":90.0, "skill":0.15},
	{"name":"Copa dos pescadores", "prize":200, "seconds":120.0, "skill":0.45},
	{"name":"Grande campeonato", "prize":300, "seconds":150.0, "skill":0.75},
]
const RIVALS := ["Lia", "Rui", "Nina", "Beto", "Celso"]

static func definition(id: String) -> Dictionary:
	for fish in SPECIES:
		if fish.id == id: return fish
	return {}

static func valid_catch(fish: Dictionary) -> bool:
	var spec := definition(str(fish.get("id", "")))
	if spec.is_empty() or typeof(fish.get("grams")) not in [TYPE_INT, TYPE_FLOAT]: return false
	var grams: float = float(fish.grams)
	return is_finite(grams) and grams == floorf(grams) and grams >= spec.min and grams <= spec.max

static func roll(rng: RandomNumberGenerator, cast_quality := 0.5) -> Dictionary:
	# Good casts tilt the table toward stronger species and larger specimens,
	# while every species remains possible from the shore.
	var quality := clampf(cast_quality, 0.0, 1.0)
	var total := 0.0
	for entry in SPECIES:
		total += float(entry.weight) * lerpf(1.0, float(entry.cast_bonus), quality)
	var pick := rng.randf() * total
	var spec: Dictionary = SPECIES[0]
	for entry in SPECIES:
		pick -= float(entry.weight) * lerpf(1.0, float(entry.cast_bonus), quality)
		if pick <= 0.0:
			spec = entry
			break
	var size_roll := pow(rng.randf(), lerpf(1.35, 1.08, quality))
	return {"id":spec.id, "grams":roundi(lerpf(spec.min, spec.max, size_roll))}

static func ranking(player_grams: int, rivals: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = [{"name":"Dante", "grams":player_grams, "player":true}]
	for rival in rivals:
		rows.append({"name":str(rival.name), "grams":int(rival.get("grams", 0)), "player":false})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.grams == b.grams: return a.name.naturalnocasecmp_to(b.name) < 0
		return a.grams > b.grams)
	return rows

static func winner(player_grams: int, rivals: Array) -> bool:
	if player_grams <= 0: return false
	for rival in rivals:
		if player_grams <= int(rival.get("grams", 0)): return false
	return true

static func kg(grams: int) -> String:
	return ("%.3f kg" % (float(grams) / 1000.0)).replace(".", ",")

class Fight:
	extends RefCounted
	var tension := 0.38
	var progress := 0.0
	var elapsed := 0.0
	var slack := 0.0
	var strength := 0.5
	var outcome := ""

	func begin(value: float) -> void:
		strength = clampf(value, 0, 1)
		tension = 0.38
		progress = 0.0
		elapsed = 0.0
		slack = 0.0
		outcome = ""

	func update(delta: float, reeling: bool) -> String:
		if not outcome.is_empty() or delta <= 0 or not is_finite(delta): return outcome
		var remaining := minf(delta, .25)
		while remaining > 0.00001:
			var step := minf(remaining, 1.0 / 60.0)
			remaining -= step
			elapsed += step
			var surge := maxf(0.0, sin(elapsed * (1.7 + strength) + .4)) * (.11 + strength * .10)
			tension = clampf(tension + step * ((.22 + strength * .10 + surge) if reeling else (-.36 + surge)), 0, 1)
			progress = clampf(progress + step * ((.19 - strength * .035) if reeling and tension > .12 else -.022), 0, 1)
			slack = slack + step if tension < .045 else 0.0
			if tension >= 1.0: outcome = "line_broke"
			elif slack >= 2.0 or elapsed >= 38.0: outcome = "escaped"
			elif progress >= 1.0: outcome = "caught"
			if not outcome.is_empty(): break
		return outcome
