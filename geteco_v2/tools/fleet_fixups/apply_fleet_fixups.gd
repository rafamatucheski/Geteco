extends SceneTree
## Correções de arte sobre os veículos baked de res://assets/fleet/.
##
## Os .scn são fotografias achatadas dos modelos V1 (tools/bake_vehicles.gd roda contra
## a raiz do repositório). Os scripts-fonte V1 estão com trabalho não commitado de outras
## sessões e a V1 virou histórico, então a correção vive aqui, na V2, como passo depois
## do bake. Cada .scn corrigido ganha a meta "fleet_fixups" com a versão, e o passo é
## pulado se ela já existir — rodar duas vezes não empilha peças.
##
## Uso: --script res://tools/fleet_fixups/apply_fleet_fixups.gd -- [id ...]
## Depois de um novo bake, rode de novo.
const VERSION := 1
const GEOMETRY := preload("res://tools/fleet_fixups/FleetGeometry.gd")
const FLEET_DIR := "res://assets/fleet/"
## Folga entre lanterna e carroceria acima da qual ela é encostada. Acima do teto a
## lanterna está em outro plano (ex.: coluna sem lataria) e precisa de correção própria.
const LAMP_GAP_MIN := .03
const LAMP_GAP_MAX := .45
var report: Array[String] = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var ids: Array = Array(OS.get_cmdline_user_args())
	if ids.is_empty(): ids = preload("res://runtime/FleetCatalog.gd").all().keys()
	var failures := 0
	for id in ids:
		var path: String = FLEET_DIR + id + ".scn"
		var model: Node3D = (load(path) as PackedScene).instantiate()
		if int(model.get_meta("fleet_fixups", 0)) >= VERSION:
			model.free()
			continue
		var geo = GEOMETRY.new(model)
		var before := report.size()
		if id.begins_with("bike_"): _fix_bike_rider(id, geo)
		if id in ["ranch_single", "ranch_pickup", "lumber_pickup_4x4"]: _fix_ranch_cab_glass(id, geo)
		if id == "metro_hatch": _fix_metro_c_pillars(id, geo)
		_snap_tail_lamps(id, geo)
		model.set_meta("fleet_fixups", VERSION)
		var packed := PackedScene.new()
		var result := packed.pack(model)
		if result == OK: result = ResourceSaver.save(packed, path, ResourceSaver.FLAG_BUNDLE_RESOURCES)
		if result != OK:
			failures += 1
			report.append("%s: falha ao salvar (%d)" % [id, result])
		elif report.size() == before:
			report.append("%s: nada a corrigir" % id)
		model.free()
	for line in report: print("FIXUP ", line)
	quit(1 if failures else 0)

func _add(model: Node3D, mesh: Mesh, transform: Transform3D, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.transform = transform
	part.material_override = material
	part.set_meta("fleet_fixup", VERSION)
	model.add_child(part)
	part.owner = model
	return part

## Cilindro entre dois pontos, para membros do piloto.
func _limb(model: Node3D, from: Vector3, to: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * .9
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 8
	mesh.rings = 1
	var up := (to - from).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < .95 else Vector3.RIGHT).normalized()
	var basis := Basis(side, up, side.cross(up).normalized() * -1.0)
	return _add(model, mesh, Transform3D(basis.orthonormalized(), (from + to) * .5), material)

func _joint(model: Node3D, at: Vector3, radius: float, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 10
	mesh.rings = 5
	return _add(model, mesh, Transform3D(Basis.IDENTITY, at), material)

func _box(model: Node3D, center: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(model, mesh, Transform3D(Basis.from_euler(rotation), center), material)

## Moto: o piloto V1 é posado em runtime por pivôs que o bake achatou. Braços e pernas
## (cilindros de 1 m sem escala) ficaram empilhados na origem, dentro do motor, e o
## piloto aparecia sem braços com um "poste" sob a moto. Remove os membros órfãos e
## monta braços até as manoplas e pernas até as pedaleiras a partir das peças reais.
func _fix_bike_rider(id: String, geo) -> void:
	var torso: MeshInstance3D
	var pants: MeshInstance3D
	var neck: MeshInstance3D
	var pegs: Array = []
	var grips: Array = []
	var orphans: Array = []
	for part in geo.parts():
		var box: AABB = geo.bounds(part)
		var center := box.get_center()
		var color := GEOMETRY.color_of(part).to_html(false)
		if not part.has_meta("wheel_center") and absf(center.x) < .01 and absf(center.z) < .05 and center.y < .55 and color in ["41454d", "253043", "181b20"]:
			orphans.append(part)
			continue
		if color == "41454d" and center.y > .9 and (torso == null or box.get_volume() > geo.bounds(torso).get_volume()): torso = part
		elif color == "253043" and center.y > .6: pants = part
		elif color == "181b20" and center.y > 1.1: neck = part
		elif color == "161b20" and part.get_meta("wheel_spins", true) == false and center.y > .85 and absf(center.x) > .25: grips.append(part)
		elif color == "161b20" and not part.has_meta("wheel_center") and absf(center.x) > .25 and center.y > .38 and center.y < .55 and box.size.x > .1: pegs.append(part)
	if torso == null or pants == null or neck == null or grips.size() != 2:
		report.append("%s: piloto não reconhecido (torso=%s calça=%s pescoço=%s manoplas=%d)" % [id, torso != null, pants != null, neck != null, grips.size()])
		return
	for part in orphans:
		geo.forget(part)
		part.get_parent().remove_child(part)
		part.free()
	var jacket: Material = GEOMETRY.material_of(torso)
	var trousers: Material = GEOMETRY.material_of(pants)
	var glove: Material = GEOMETRY.material_of(neck)
	var torso_box: AABB = geo.bounds(torso)
	var neck_center: Vector3 = geo.bounds(neck).get_center()
	var hip_center: Vector3 = geo.bounds(pants).get_center()
	for side in [-1.0, 1.0]:
		var grip: MeshInstance3D = grips[0] if signf(geo.bounds(grips[0]).get_center().x) == side else grips[1]
		var grip_center: Vector3 = geo.bounds(grip).get_center()
		var hand := Vector3(grip_center.x - side * .05, grip_center.y + .015, grip_center.z)
		var shoulder := Vector3(side * (torso_box.size.x * .5 - .04), neck_center.y - .13, neck_center.z + .07)
		# Cotovelo aberto para fora e um pouco abaixo da reta ombro-mão: postura de guidão.
		var elbow := shoulder.lerp(hand, .5) + Vector3(side * .08, -.07, .05)
		_joint(geo.model, shoulder, .075, jacket)
		_limb(geo.model, shoulder, elbow, .062, jacket)
		_joint(geo.model, elbow, .058, jacket)
		_limb(geo.model, elbow, hand, .052, jacket)
		_joint(geo.model, hand, .05, glove)
		var peg: Vector3 = Vector3(side * .27, .45, .12)
		for candidate in pegs:
			var at: Vector3 = geo.bounds(candidate).get_center()
			if signf(at.x) == side: peg = at
		var hip := Vector3(side * .1, hip_center.y - .02, hip_center.z)
		var foot := Vector3(side * (absf(peg.x) - .04), peg.y + .07, peg.z + .02)
		var knee := hip.lerp(foot, .5) + Vector3(side * .07, .12, -.2)
		_joint(geo.model, hip, .09, trousers)
		_limb(geo.model, hip, knee, .082, trousers)
		_joint(geo.model, knee, .075, trousers)
		_limb(geo.model, knee, foot, .066, trousers)
		_box(geo.model, foot + Vector3(0, -.01, -.05), Vector3(.1, .1, .22), glove)
	report.append("%s: %d membros órfãos removidos; braços até as manoplas e pernas até as pedaleiras" % [id, orphans.size()])

## Picape Ranch: os vidros laterais da cabine (x=±0,795) ficaram meio centímetro para
## dentro da parede da cabine (x=±0,80), então a cabine parecia um bloco roxo sem
## janela. Mede a parede com raio e cola a vidraça, com moldura, na face externa.
func _fix_ranch_cab_glass(id: String, geo) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color("2c3e50")
	glass.metallic = .35
	glass.roughness = .15
	glass.resource_name = "glass"
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("1e272e")
	trim.roughness = .6
	var added := 0
	for side in [-1.0, 1.0]:
		var hit: Dictionary = geo.ray(Vector3(side * 5.0, 1.24, -.42), Vector3(-side, 0, 0))
		if hit.is_empty(): continue
		var face: float = hit.point.x
		# Janela da porta com moldura escura e coluna B, como nas outras picapes.
		_box(geo.model, Vector3(face + side * .006, 1.25, -.44), Vector3(.012, .42, .82), glass)
		_box(geo.model, Vector3(face + side * .004, 1.25, -.44), Vector3(.012, .48, .9), trim)
		_box(geo.model, Vector3(face + side * .01, 1.25, -.05), Vector3(.012, .46, .06), trim)
		added += 1
	var rear: Dictionary = geo.ray(Vector3(0, 1.25, 5.0), Vector3.FORWARD, [], func(part): return geo.bounds(part).get_center().z < 1.0 or geo.bounds(part).size.z > 3.0)
	report.append("%s: vidraças laterais da cabine na lataria (%d lados)%s" % [id, added, "" if rear.is_empty() else ", vidro traseiro atingido em z=%.2f" % rear.point.z])

## Metro Hatch: as lanternas verticais de coluna ficavam no ar ao lado do vidro
## traseiro, porque o modelo não tem coluna C. Adiciona a coluna em cor de lataria.
func _fix_metro_c_pillars(id: String, geo) -> void:
	var paint: Material
	for part in geo.parts():
		var box: AABB = geo.bounds(part)
		if absf(box.get_center().y - 1.34) < .02 and box.size.x > 1.2 and box.size.z > 1.9: paint = GEOMETRY.material_of(part)
	if paint == null:
		report.append("%s: teto não encontrado, coluna C não adicionada" % id)
		return
	for side in [-1.0, 1.0]:
		_box(geo.model, Vector3(side * .64, 1.05, 1.39), Vector3(.07, .56, .14), paint, Vector3(deg_to_rad(-12.0), 0, 0))
	report.append("%s: colunas C atrás das lanternas verticais" % id)

## Lanterna traseira descolada: encosta a face dianteira dela na lataria medida por
## raio vindo de trás no mesmo (x, y).
func _snap_tail_lamps(id: String, geo) -> void:
	var body_only := func(part): return not GEOMETRY.is_lamp(part) and not part.has_meta("wheel_center") and not part.has_meta("fleet_fixup_lamp")
	var moved := []
	for part in geo.parts():
		if not GEOMETRY.is_tail_lamp(part): continue
		var box: AABB = geo.bounds(part)
		if box.get_center().z < 0 or box.size.z > .12: continue
		var center := box.get_center()
		var hit: Dictionary = geo.ray(Vector3(center.x, center.y, 30.0), Vector3.FORWARD, [part], body_only)
		if hit.is_empty(): continue
		var gap: float = box.position.z - hit.point.z
		if gap > LAMP_GAP_MIN and gap <= LAMP_GAP_MAX:
			part.position.z -= gap - .004
			geo.forget(part)
			moved.append("%.2f" % gap)
			box = geo.bounds(part)
		# Lanterna de canto mais larga que a lataria afinada naquele ponto: puxa para dentro.
		var side := signf(center.x)
		if side == 0: continue
		var flank: Dictionary = geo.ray(Vector3(side * 5.0, center.y, box.position.z - .02), Vector3(-side, 0, 0), [part], body_only)
		if flank.is_empty(): continue
		var outer: float = box.end.x if side > 0 else -box.position.x
		var overhang: float = outer - absf(flank.point.x)
		if overhang > .015 and overhang < .2:
			part.position.x -= side * (overhang + .004)
			geo.forget(part)
			moved.append("lateral %.2f" % overhang)
	if not moved.is_empty(): report.append("%s: lanternas encostadas na lataria (%s m)" % [id, ", ".join(moved)])
