extends Node3D
## Reusable, genuinely volumetric fish. Forward is -Z; Y is up.
## configure() leaves the caller's transform alone. animate() is caller driven.
## Four draw surfaces per fish, five with barbels; no per-frame mesh generation.

const RULES := preload("res://activities/fishing/FishingRules.gd")
const RINGS := 42
const SIDES := 28
const BODY_STATIONS := [0.0, .10, .24, .40, .58, .76, .91, 1.0]
const BODY_WIDTHS := [.13, .74, 1.0, 1.0, .86, .53, .22, .12]
const BODY_HEIGHTS := [.13, .62, .92, 1.0, .88, .56, .23, .12]
const PROFILES := {
	"tilapia": {"length":.57,"width":.105,"depth":.195,"head":.60,"dorsal":.13,"fin":"6a7861","back":"445c53","body":"9aa890","belly":"d6cfad","pattern":"bars","tail":"fan"},
	"piau": {"length":.54,"width":.085,"depth":.135,"head":.52,"dorsal":.12,"fin":"9a7939","back":"69684a","body":"bdaf72","belly":"ded1a1","pattern":"piau","tail":"fork"},
	"pacu": {"length":.75,"width":.12,"depth":.285,"head":.62,"dorsal":.13,"fin":"434f4d","back":"4c5d60","body":"a2b0af","belly":"cc965c","pattern":"silver","tail":"fan"},
	"carpa": {"length":.83,"width":.125,"depth":.20,"head":.72,"dorsal":.10,"fin":"a3712f","back":"78602d","body":"c8a64d","belly":"e2c680","pattern":"scales","tail":"fork","barbels":2},
	"traira": {"length":.77,"width":.115,"depth":.12,"head":1.12,"dorsal":.08,"fin":"6c6744","back":"414c2d","body":"8c8950","belly":"c4c08b","pattern":"mottle","tail":"round"},
	"matrinxa": {"length":.68,"width":.09,"depth":.16,"head":.52,"dorsal":.13,"fin":"b95b40","back":"4c6467","body":"b7c3bd","belly":"e3d5b2","pattern":"silver","tail":"fork"},
	"tambacu": {"length":.96,"width":.15,"depth":.28,"head":.72,"dorsal":.14,"fin":"3c4546","back":"354647","body":"687673","belly":"a79770","pattern":"dark","tail":"fan"},
	"pintado": {"length":1.18,"width":.14,"depth":.115,"head":1.28,"dorsal":.16,"fin":"8e8b76","back":"646e64","body":"a7ac92","belly":"e1dcc3","pattern":"spots","tail":"fork","barbels":6},
	"tucunare": {"length":.83,"width":.11,"depth":.185,"head":.94,"dorsal":.13,"fin":"ae872f","back":"566b2e","body":"bca749","belly":"e1c762","pattern":"peacock","tail":"fan"},
	"dourado": {"length":.99,"width":.10,"depth":.155,"head":.84,"dorsal":.13,"fin":"bd8823","back":"878032","body":"d6b33f","belly":"ebd478","pattern":"gold","tail":"fork"},
	"pirarara": {"length":1.19,"width":.16,"depth":.14,"head":1.30,"dorsal":.16,"fin":"c36a3c","back":"283e42","body":"465b56","belly":"e3d6a9","pattern":"cream_band","tail":"round","barbels":6},
}

static var _cache: Dictionary = {}
static var _skin: StandardMaterial3D
var _rig: Node3D
var _body: MeshInstance3D
var _tail: Node3D
var _left: Node3D
var _right: Node3D
var _barbels: Node3D
var _mouth: Marker3D
var _tail_mesh: MeshInstance3D
var _left_mesh: MeshInstance3D
var _right_mesh: MeshInstance3D
var _barbel_mesh: MeshInstance3D
var _species := ""
var _grams := -1
var _age := 0.0
var _strength := .5

func configure(definition: Dictionary, grams: int = 2500) -> void:
	var id := str(definition.get("id", "tilapia"))
	if not PROFILES.has(id): id = "tilapia"
	if _rig == null: _build_rig()
	if id == _species and grams == _grams: return
	_grams = grams
	_strength = clampf(float(definition.get("strength", .5)), 0.0, 1.0)
	if not _cache.has(id): _cache[id] = _load_species(id)
	var art: Dictionary = _cache[id]
	if id != _species:
		_species = id
		_body.mesh = art.body
		_tail_mesh.mesh = art.tail
		_left_mesh.mesh = art.left
		_right_mesh.mesh = art.right
		_barbel_mesh.mesh = art.barbels
		_barbels.visible = art.barbels != null
		_tail.position = Vector3(0, 0, .39)
		_left.position = Vector3(-float(PROFILES[id].width) * .88, -.025, -.17)
		_right.position = Vector3(float(PROFILES[id].width) * .88, -.025, -.17)
		_mouth.position = Vector3(0, float(art.mouth_y), -.505)
	var canonical := RULES.definition(id)
	var average := (float(canonical.min) + float(canonical.max)) * .5
	# Cube root maintains a plausible relationship between volume and weight.
	var size := float(PROFILES[id].length) * clampf(pow(maxf(float(grams), 1.0) / average, 1.0 / 3.0), .58, 1.28)
	_rig.scale = Vector3.ONE * size

func animate(delta: float, intensity: float = .5) -> void:
	if _rig == null: return
	_age = fmod(_age + maxf(delta, 0.0), 600.0)
	var effort := clampf(intensity, 0.0, 2.0)
	var beat := _age * (4.5 + effort * 7.0 + _strength * 1.4)
	_body.rotation.y = sin(beat - .8) * (.018 + effort * .034)
	_body.rotation.z = sin(beat * .48) * effort * .018
	_tail.rotation.y = sin(beat) * (.12 + effort * .23)
	_tail.rotation.z = sin(beat * .7) * effort * .025
	_left.rotation.z = -.12 - sin(beat * .55) * (.12 + effort * .15)
	_right.rotation.z = .12 + sin(beat * .55 + .45) * (.12 + effort * .15)
	_left.rotation.y = sin(beat * .55) * .08
	_right.rotation.y = -sin(beat * .55 + .45) * .08
	_barbels.rotation.y = sin(beat * .55 - .7) * (.025 + effort * .04)

func mouth_local_position() -> Vector3:
	if _mouth == null: return Vector3.ZERO
	return _rig.transform * _body.transform * _mouth.position

func mouth_global_position() -> Vector3:
	return to_global(mouth_local_position())

func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "FishAnatomy"
	add_child(_rig)
	_body = _instance("FishBody", _rig)
	_tail = _pivot("FishTail", _body)
	_tail_mesh = _instance("CaudalFin", _tail)
	_left = _pivot("LeftPectoral", _body)
	_right = _pivot("RightPectoral", _body)
	_left_mesh = _instance("LeftFin", _left)
	_right_mesh = _instance("RightFin", _right)
	_barbels = _pivot("Barbels", _body)
	_barbel_mesh = _instance("SensoryBarbels", _barbels)
	_mouth = Marker3D.new()
	_mouth.name = "Mouth"
	_body.add_child(_mouth)

static func _pivot(label: String, parent: Node3D) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	return node

static func _instance(label: String, parent: Node3D) -> MeshInstance3D:
	if _skin == null:
		_skin = StandardMaterial3D.new()
		_skin.vertex_color_use_as_albedo = true
		_skin.vertex_color_is_srgb = true
		_skin.roughness = .47
		_skin.metallic = .08
		_skin.metallic_specular = .38
		_skin.cull_mode = BaseMaterial3D.CULL_DISABLED
	var node := MeshInstance3D.new()
	node.name = label
	node.material_override = _skin
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func _load_species(id: String) -> Dictionary:
	# Authored meshes are baked once, so a first bite never triangulates a fish.
	var path := "res://assets/fishing/models/" + id + ".res"
	if ResourceLoader.exists(path):
		var bundle := load(path) as Resource
		if bundle != null:
			var art: Dictionary = bundle.get_meta("art", {})
			if art.has_all(["body", "tail", "left", "right", "barbels", "mouth_y"]): return art
	# Keep the authoring path available for new species and resource regeneration.
	return _build_species(id)

static func _build_species(id: String) -> Dictionary:
	var profile: Dictionary = PROFILES[id]
	var body := FishMesh.new()
	for ring in RINGS:
		var t0 := float(ring) / RINGS
		var t1 := float(ring + 1) / RINGS
		for side in SIDES:
			var a0 := TAU * float(side) / SIDES
			var a1 := TAU * float(side + 1) / SIDES
			var p0 := _surface(profile, t0, a0)
			var p1 := _surface(profile, t1, a0)
			var p2 := _surface(profile, t1, a1)
			var p3 := _surface(profile, t0, a1)
			body.smooth_triangle(p0, p1, p2, _normal(profile, t0, a0), _normal(profile, t1, a0), _normal(profile, t1, a1), _skin_color(profile, t0, a0), _skin_color(profile, t1, a0), _skin_color(profile, t1, a1))
			body.smooth_triangle(p0, p2, p3, _normal(profile, t0, a0), _normal(profile, t1, a1), _normal(profile, t0, a1), _skin_color(profile, t0, a0), _skin_color(profile, t1, a1), _skin_color(profile, t0, a1))
	# Close both ends: the lips sit over the snout cap, the tail covers the peduncle.
	for side in SIDES:
		var a0 := TAU * float(side) / SIDES
		var a1 := TAU * float(side + 1) / SIDES
		body.triangle(Vector3(0, 0, -.5), _surface(profile, 0, a1), _surface(profile, 0, a0), Color(profile.body))
		body.triangle(Vector3(0, 0, .4), _surface(profile, 1, a0), _surface(profile, 1, a1), Color(profile.fin))
	if id == "pintado": _add_spots(body, profile)
	_add_fixed_fins(body, profile, id)
	_add_face(body, profile, id)
	var tail := FishMesh.new()
	_add_tail(tail, profile, id)
	var left := FishMesh.new()
	var right := FishMesh.new()
	_add_pectoral(left, profile, -1.0)
	_add_pectoral(right, profile, 1.0)
	var barbels := FishMesh.new()
	_add_barbels(barbels, profile)
	return {"body":body.mesh(), "tail":tail.mesh(), "left":left.mesh(), "right":right.mesh(), "barbels":barbels.mesh() if int(profile.get("barbels", 0)) > 0 else null, "mouth_y":-.018 if id in ["pintado", "pirarara", "carpa"] else 0.0}

static func _radii(profile: Dictionary, t: float) -> Vector2:
	# Authored snout, shoulder, deep belly and narrowing caudal peduncle.
	for i in BODY_STATIONS.size() - 1:
		if t <= float(BODY_STATIONS[i + 1]):
			var u := inverse_lerp(float(BODY_STATIONS[i]), float(BODY_STATIONS[i + 1]), t)
			var before := maxi(i - 1, 0)
			var after := mini(i + 2, BODY_STATIONS.size() - 1)
			var p0 := _station_radius(profile, i)
			var p1 := _station_radius(profile, i + 1)
			var span := float(BODY_STATIONS[i + 1]) - float(BODY_STATIONS[i])
			var m0 := (p1 - _station_radius(profile, before)) * span / (float(BODY_STATIONS[i + 1]) - float(BODY_STATIONS[before]))
			var m1 := (_station_radius(profile, after) - p0) * span / (float(BODY_STATIONS[after]) - float(BODY_STATIONS[i]))
			# Shared tangents avoid artificial ridges between authoring stations.
			var u2 := u * u
			var u3 := u2 * u
			return p0 * (2.0 * u3 - 3.0 * u2 + 1.0) + m0 * (u3 - 2.0 * u2 + u) + p1 * (-2.0 * u3 + 3.0 * u2) + m1 * (u3 - u2)
	return _station_radius(profile, BODY_STATIONS.size() - 1)

static func _station_radius(profile: Dictionary, index: int) -> Vector2:
	var width := float(BODY_WIDTHS[index]) * (float(profile.head) if index < 2 else 1.0)
	var height := float(BODY_HEIGHTS[index])
	if int(profile.get("barbels", 0)) == 6:
		if index == 0: width = .42; height = .25
		elif index == 1: width = 1.05; height = .65
	return Vector2(width * float(profile.width), height * float(profile.depth))

static func _surface(profile: Dictionary, t: float, angle: float) -> Vector3:
	var radii := _radii(profile, t)
	var y := sin(angle) * radii.y
	# Flatter ventral surface and a gentle dorsal shoulder, especially in deep fish.
	if y < 0: y *= .86
	return Vector3(cos(angle) * radii.x, y, -.5 + .9 * t)

static func _normal(profile: Dictionary, t: float, angle: float) -> Vector3:
	var tangent := _surface(profile, minf(t + .002, 1.0), angle) - _surface(profile, maxf(t - .002, 0.0), angle)
	var around := _surface(profile, t, angle + .002) - _surface(profile, t, angle - .002)
	return around.cross(tangent).normalized()

static func _skin_color(profile: Dictionary, t: float, angle: float) -> Color:
	var vertical := sin(angle)
	var side := absf(cos(angle))
	var color := Color(profile.body)
	if vertical > .15: color = color.lerp(Color(profile.back), smoothstep(.15, 1.0, vertical) * .93)
	if vertical < -.15: color = color.lerp(Color(profile.belly), smoothstep(.15, .85, -vertical))
	var pattern := str(profile.pattern)
	var marking := 0.0
	if t > .22 and t < .92 and side > .28:
		match pattern:
			"bars": marking = smoothstep(.63, .9, sin(t * 49.0 + vertical * 1.3)) * .58
			"piau": marking = smoothstep(.75, .95, sin(t * 32.0 + vertical * .5)) * smoothstep(.92, .45, absf(vertical)) * .66
			"peacock": marking = smoothstep(.42, .76, sin(t * 25.0 + vertical * 1.5)) * .83
			"mottle": marking = smoothstep(.2, .75, sin(t * 47.0 + vertical * 11.0) * sin(t * 27.0 - vertical * 19.0)) * .68
			"cream_band":
				color = color.lerp(Color(profile.belly), (1.0 - smoothstep(.09, .26, absf(vertical + .27))) * .92)
	if marking > 0: color = color.lerp(Color("25382b"), marking)
	# Small, staggered scale facets are baked into vertices, never separate objects.
	if pattern not in ["spots", "cream_band", "mottle"] and t > .18:
		var scale_row := floorf(angle * 12.0)
		var scale_wave := sin(t * 210.0 + scale_row * PI) * sin(angle * 24.0)
		color = color.lightened(maxf(scale_wave, 0.0) * (.12 if pattern in ["scales", "gold"] else .065))
	return color

static func _add_spots(builder: FishMesh, profile: Dictionary) -> void:
	# Distinct irregular spots follow the skin surface; baked into the same draw.
	# A coarse vertex noise pattern aliases into stripes on a slender catfish.
	for sign_value in [-1.0, 1.0]:
		for row in 5:
			for column in 9:
				var t := .23 + column * .075 + fposmod(row * .037, .071)
				var angle := -.45 + row * .35
				if sign_value < 0: angle = PI - angle
				var radius := .008 + .004 * (.5 + .5 * sin(column * 5.7 + row * 9.3))
				var center := _surface(profile, t, angle) + _normal(profile, t, angle) * .0018
				for segment in 9:
					var a0 := TAU * float(segment) / 9.0
					var a1 := TAU * float(segment + 1) / 9.0
					var t0 := t + cos(a0) * radius
					var t1 := t + cos(a1) * radius
					var v0 := angle + sin(a0) * .10
					var v1 := angle + sin(a1) * .10
					var p0 := _surface(profile, t0, v0) + _normal(profile, t0, v0) * .0018
					var p1 := _surface(profile, t1, v1) + _normal(profile, t1, v1) * .0018
					builder.smooth_triangle(center, p0, p1, _normal(profile, t, angle), _normal(profile, t0, v0), _normal(profile, t1, v1), Color("2c3930"), Color("2c3930"), Color("2c3930"))

static func _add_fixed_fins(builder: FishMesh, profile: Dictionary, id: String) -> void:
	var depth := float(profile.depth)
	var fin := Color(profile.fin)
	var is_catfish := int(profile.get("barbels", 0)) == 6
	var long_dorsal := id in ["tilapia", "carpa", "tucunare"]
	var start := -.22 if long_dorsal else -.12
	var finish := .25 if long_dorsal else .13
	if id == "traira": start = .07; finish = .28
	if is_catfish: start = -.18; finish = .06
	var rays := 18 if long_dorsal else 12
	var previous_base := Vector3.ZERO
	var previous_tip := Vector3.ZERO
	for index in rays + 1:
		var u := float(index) / rays
		var z := lerpf(start, finish, u)
		var radius := _radii(profile, (z + .5) / .9).y
		var height := sin(PI * pow(u, .7)) * float(profile.dorsal)
		if id in ["tilapia", "tucunare"]: height *= 1.0 if index % 2 == 0 else .84
		var base := Vector3(0, radius * .9, z)
		var tip := Vector3(0, radius + height, z + .025 * sin(PI * u))
		if index > 0:
			builder.triangle(previous_base, previous_tip, tip, fin.lightened(.10))
			builder.triangle(previous_base, tip, base, fin)
		builder.tube(base, tip, .0021, fin.darkened(.20), 4)
		previous_base = base
		previous_tip = tip
	# Anal and paired pelvic fins remain attached to the anatomical body surface.
	var anal_start := Vector3(0, -depth * .65, .12)
	var anal_tip := Vector3(0, -depth * .72 - .09, .23)
	var anal_end := Vector3(0, -depth * .26, .30)
	if id in ["pacu", "tambacu"]: anal_tip.y -= .045
	_membrane(builder, anal_start, anal_tip, anal_end, fin, 7)
	for sign_value in [-1.0, 1.0]:
		var root := Vector3(sign_value * float(profile.width) * .4, -depth * .8, .015)
		_membrane(builder, root, root + Vector3(sign_value * .07, -.075, .11), root + Vector3(0, .025, .12), fin, 6)
	# Characins and catfish have a small adipose fin behind the dorsal fin.
	if id in ["pacu", "tambacu", "pintado", "pirarara", "matrinxa", "dourado"]:
		_membrane(builder, Vector3(0, depth * .43, .25), Vector3(0, depth * .43 + .055, .28), Vector3(0, depth * .19, .33), fin, 5)

static func _add_tail(builder: FishMesh, profile: Dictionary, id: String) -> void:
	var fin := Color(profile.fin)
	var shape := str(profile.tail)
	var height := .14 if float(profile.depth) < .15 else .17
	var previous := Vector3.ZERO
	for index in 21:
		var u := float(index) / 20.0
		var y := lerpf(-height, height, u)
		var edge := .18
		if shape == "fork": edge = .08 + .15 * pow(absf(u * 2.0 - 1.0), .7)
		elif shape == "round": edge = .14 + .07 * sin(PI * u)
		else: edge = .18 + .025 * sin(PI * u)
		var point := Vector3(sin(u * PI) * .006, y, edge)
		var shade := fin.lightened(.12 if index % 2 == 0 else 0.0)
		if id == "pirarara": shade = Color("d96b3e").lerp(Color("f1b678"), absf(y) / height * .25)
		if index > 0: builder.triangle(Vector3.ZERO, previous, point, shade)
		builder.tube(Vector3(0, y * .11, 0), point, .0018, fin.darkened(.2), 4)
		previous = point
	if id == "tucunare":
		# Diagnostic ocellus at the caudal peduncle, visible from either side.
		for sign_value in [-1.0, 1.0]:
			builder.ellipsoid(Vector3(sign_value * .011, .035, .047), Vector3(.006, .029, .023), Color("e0c74d"), 12, 8)
			builder.ellipsoid(Vector3(sign_value * .016, .035, .047), Vector3(.003, .019, .015), Color("29382b"), 12, 8)

static func _add_pectoral(builder: FishMesh, profile: Dictionary, sign_value: float) -> void:
	var fin := Color(profile.fin)
	var catfish := int(profile.get("barbels", 0)) == 6
	var reach := .19 if catfish else .14
	_membrane(builder, Vector3.ZERO, Vector3(sign_value * reach, -.035, .10), Vector3(sign_value * .035, -.025, .18), fin, 11)

static func _membrane(builder: FishMesh, root: Vector3, outer: Vector3, end: Vector3, color: Color, rays: int) -> void:
	var previous := outer
	for index in rays + 1:
		var u := float(index) / rays
		var tip := outer.lerp(end, u)
		tip += (outer - root).normalized() * sin(PI * u) * .016
		if index > 0: builder.triangle(root, previous, tip, color.lightened(.08 if index % 2 == 0 else 0.0))
		builder.tube(root, tip, .0018, color.darkened(.22), 4)
		previous = tip

static func _add_face(builder: FishMesh, profile: Dictionary, id: String) -> void:
	var eye_t := .16 if id not in ["pintado", "pirarara"] else .20
	var eye_radius := .018 if id not in ["pacu", "tambacu"] else .023
	var radii := _radii(profile, eye_t)
	for sign_value in [-1.0, 1.0]:
		var eye := Vector3(sign_value * radii.x * .94, radii.y * .31, -.5 + .9 * eye_t)
		builder.ellipsoid(eye, Vector3(.009, eye_radius, eye_radius), Color("c1a763"), 14, 8)
		builder.ellipsoid(eye + Vector3(sign_value * .006, .001, -.002), Vector3(.006, eye_radius * .68, eye_radius * .68), Color("12272a"), 14, 8)
		builder.ellipsoid(eye + Vector3(sign_value * .011, eye_radius * .30, -eye_radius * .24), Vector3(.002, eye_radius * .18, eye_radius * .18), Color("eee9d8"), 8, 6)
		var prior := Vector3.ZERO
		for index in 9:
			var u := float(index) / 8.0
			var angle := lerpf(-.95, 1.10, u)
			var t := .27 + sin(PI * u) * .045
			var point := _surface(profile, t, angle if sign_value > 0 else PI - angle)
			point.x += sign_value * .0014
			if index > 0: builder.tube(prior, point, .0023, Color(profile.back).darkened(.23), 4)
			prior = point
	var mouth_y := -.018 if id in ["pintado", "pirarara", "carpa"] else 0.0
	var mouth_width := .032 if int(profile.get("barbels", 0)) == 6 else .014
	if id in ["traira", "tucunare", "dourado"]: mouth_width = .022
	builder.ellipsoid(Vector3(0, mouth_y, -.500), Vector3(mouth_width, .010, .008), Color(profile.belly).darkened(.25), 16, 8)
	builder.ellipsoid(Vector3(0, mouth_y, -.506), Vector3(mouth_width * .78, .006, .004), Color("283532"), 16, 8)

static func _add_barbels(builder: FishMesh, profile: Dictionary) -> void:
	var count := int(profile.get("barbels", 0))
	if count == 0: return
	for sign_value in [-1.0, 1.0]:
		for pair in range(count >> 1):
			var base := Vector3(sign_value * (.025 + pair * .009), -.020 - pair * .012, -.465)
			var previous := base
			for segment in 7:
				var u := float(segment + 1) / 7.0
				var length := .22 if count == 6 else .075
				var point := base + Vector3(sign_value * length * u * (.6 + pair * .17), -length * u * u * (.5 + pair * .23), -length * sin(u * PI * .7))
				builder.tube(previous, point, lerpf(.0034, .0010, u), Color(profile.belly).darkened(.12), 5)
				previous = point

class FishMesh:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
		var normal := (b - a).cross(c - a).normalized()
		smooth_triangle(a, b, c, normal, normal, normal, color, color, color)

	func smooth_triangle(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		vertices.append(a); vertices.append(b); vertices.append(c)
		normals.append(na); normals.append(nb); normals.append(nc)
		colors.append(ca); colors.append(cb); colors.append(cc)

	func ellipsoid(center: Vector3, size: Vector3, color: Color, sides: int = 12, rows: int = 8) -> void:
		for row in rows:
			var v0 := PI * float(row) / rows
			var v1 := PI * float(row + 1) / rows
			for side in sides:
				var a0 := TAU * float(side) / sides
				var a1 := TAU * float(side + 1) / sides
				var n0 := Vector3(sin(v0) * cos(a0), cos(v0), sin(v0) * sin(a0))
				var n1 := Vector3(sin(v1) * cos(a0), cos(v1), sin(v1) * sin(a0))
				var n2 := Vector3(sin(v1) * cos(a1), cos(v1), sin(v1) * sin(a1))
				var n3 := Vector3(sin(v0) * cos(a1), cos(v0), sin(v0) * sin(a1))
				smooth_triangle(center + n0 * size, center + n1 * size, center + n2 * size, (n0 / size).normalized(), (n1 / size).normalized(), (n2 / size).normalized(), color, color, color)
				smooth_triangle(center + n0 * size, center + n2 * size, center + n3 * size, (n0 / size).normalized(), (n2 / size).normalized(), (n3 / size).normalized(), color, color, color)

	func tube(start: Vector3, finish: Vector3, radius: float, color: Color, sides: int = 5) -> void:
		var axis := finish - start
		if axis.length_squared() < .00000001: return
		axis = axis.normalized()
		var tangent := axis.cross(Vector3.UP if absf(axis.y) < .9 else Vector3.RIGHT).normalized()
		var bitangent := axis.cross(tangent).normalized()
		for side in sides:
			var a0 := TAU * float(side) / sides
			var a1 := TAU * float(side + 1) / sides
			var n0 := tangent * cos(a0) + bitangent * sin(a0)
			var n1 := tangent * cos(a1) + bitangent * sin(a1)
			smooth_triangle(start + n0 * radius, finish + n0 * radius, finish + n1 * radius, n0, n0, n1, color, color, color)
			smooth_triangle(start + n0 * radius, finish + n1 * radius, start + n1 * radius, n0, n1, n1, color, color, color)

	func mesh() -> ArrayMesh:
		var output := ArrayMesh.new()
		if vertices.is_empty(): return output
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return output
