extends SceneTree
## Onde Dante acorda depois de morrer ou ser preso, sem carregar o mundo (RecoveryDestination é pura).
## Relato de 31/10: "quando a pessoa morre e renasce às vezes sai na ponte". O spawn_position da serra
## fica no tabuleiro da ponte e o do deserto na cabeça da ponte norte; este teste trava que nenhum
## destino de resgate cai em ponte/conexão e que a ponte decide pela ponta mais próxima.
## Não prova que o ponto está livre de colisão no jogo: isso só o resgate de verdade (position_clear) mede.
## Uso: "$GODOT" --headless --path . --script res://tests/test_recovery_destination.gd
const DEST := preload("res://runtime/RecoveryDestination.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
const DESERT := preload("res://world/desert/DesertLayout.gd")
const NORTH_ANCHOR := Vector3(342.5, 2.4, -373.5)

var failures := 0

func check(ok: bool, label: String) -> void:
	print(("OK   " if ok else "FALHA ") + label)
	if not ok: failures += 1

func _planar(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func expect(point: Vector3, current: String, arrested: bool, region: String, place_id: String, label: String) -> void:
	var got: Dictionary = DEST.choose(point, current, arrested)
	check(got.region == region and got.place_id == place_id, "%s → %s/%s (veio %s/%s)" % [label, region, place_id, got.region, got.place_id])

func _initialize() -> void:
	var mountain_spawn := Vector3(3260 + 4300, 0, 400 - 4960) / 16.0
	var desert_spawn := DESERT.BRIDGE_END + Vector3(0, .08, -6)
	# Pontos de morte em cada região.
	expect(Vector3(100, 0, 100), "harbor", false, "harbor", "harbor_hospital", "Harbor, centro")
	expect(Vector3(100, 0, 100), "harbor", true, "harbor", "harbor_police", "Harbor, centro, preso")
	expect(Vector3(700, 0, -300), "mountain", false, "mountain", DEST.MOUNTAIN_HOSPITAL, "serra, estrada")
	expect(Vector3(700, 0, -300), "mountain", true, "mountain", DEST.MOUNTAIN_PRECINCT, "serra, estrada, preso")
	expect(Vector3(-180, 0, -560), "desert", false, "desert", "", "deserto, cidade")
	expect(Vector3(-180, 0, -560), "desert", true, "desert", "", "deserto, cidade, preso")
	# Ponte e túnel: ponta mais próxima, não a região lógica da emenda.
	var mid := (DEST.CORRIDOR_WEST_X + DEST.CORRIDOR_EAST_X) * .5
	expect(Vector3(DEST.CORRIDOR_WEST_X + 10, 0, CONNECTION.CENTER_Z), "harbor", false, "harbor", "harbor_hospital", "ponte, ponta oeste")
	expect(Vector3(CONNECTION.SEAM.x + 10, 0, CONNECTION.CENTER_Z), "mountain", false, "harbor", "harbor_hospital", "ponte logo depois da emenda (lógica serra)")
	expect(mountain_spawn, "mountain", false, "harbor", "harbor_hospital", "antigo ponto de resgate da serra, no tabuleiro")
	expect(Vector3(mid - 1, 0, CONNECTION.CENTER_Z), "mountain", true, "harbor", "harbor_police", "meio da ponte, lado oeste, preso")
	expect(Vector3(mid + 1, 0, CONNECTION.CENTER_Z), "harbor", false, "mountain", DEST.MOUNTAIN_HOSPITAL, "meio da ponte, lado leste")
	expect(Vector3(DEST.CORRIDOR_EAST_X - 5, 0, CONNECTION.CENTER_Z), "mountain", true, "mountain", DEST.MOUNTAIN_PRECINCT, "túnel, boca leste, preso")
	# Interior (sem ponto): fica a região atual.
	expect(Vector3.INF, "mountain", false, "mountain", DEST.MOUNTAIN_HOSPITAL, "dentro de interior na serra")
	expect(Vector3.INF, "desert", true, "desert", "", "dentro de interior no deserto")
	# Nenhum destino na ponte, na emenda, na cabeça norte ou nos spawns antigos; e cada um na própria região.
	for region in ["harbor", "mountain", "desert"]:
		for arrested in [false, true]:
			var target: Dictionary = DEST.for_region(region, arrested)
			var p: Vector3 = target.position
			var label := "%s%s" % [region, " (preso)" if arrested else ""]
			check(p.is_finite(), label + ": destino existe")
			if not p.is_finite(): continue
			check(not DEST.on_bridge(p), label + ": fora da ponte/túnel")
			check(_planar(p, CONNECTION.SEAM) > 60.0 and _planar(p, NORTH_ANCHOR) > 60.0, label + ": longe da emenda e da cabeça norte (%.0f m / %.0f m)" % [_planar(p, CONNECTION.SEAM), _planar(p, NORTH_ANCHOR)])
			check(_planar(p, mountain_spawn) > 60.0 and _planar(p, desert_spawn) > 60.0, label + ": não é o spawn antigo na ponte")
			check(CONNECTION.logical_region(p) == region, label + ": ponto pertence à região (%s)" % CONNECTION.logical_region(p))
	print("RecoveryDestination: %s" % ("PASSOU" if failures == 0 else "%d falha(s)" % failures))
	quit(0 if failures == 0 else 1)
