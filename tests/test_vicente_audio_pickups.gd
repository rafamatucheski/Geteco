extends SceneTree
## Gravações 01–03 do Arquivo de Vicente (31/10/2026): contrato sem mundo. Confere que cada ponto
## está dentro do túnel e longe dos consoles, que a coleta registra uma vez só, que o save da rede
## secreta (snapshot/restore por JSON, o mesmo caminho do jogo) guarda as três e que o Arquivo passa
## a contar as quatro. Não prova que o jogador alcança o ponto a pé nem que a cenografia não o
## cobre: isso pede a sessão real (como tests/test_secret_vault.gd).
## Uso: "$GODOT" --headless --path . --script res://tests/test_vicente_audio_pickups.gd
const PASSAGE := preload("res://gameplay/urban_v1/TruckersVillageSecretPassage.gd")
const TUNNEL := preload("res://gameplay/urban_v1/SecretTunnel3D.gd")
const PROGRESSION := preload("res://runtime/SecretNetworkProgression.gd")
const PANEL := preload("res://ui/SecretFilePanel.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var expected := ["audio_vicente_field", "audio_maintenance_shift", "audio_blackout"]
	check(PASSAGE.AUDIO_PICKUPS.map(func(entry): return entry.id) == expected, "pontos das gravações 01–03 na ordem")
	var hq: Vector3 = TUNNEL.HQ_CENTER
	var consoles := [hq + Vector3(0, .04, -5.85), hq + Vector3(5.15, .04, -2.1), hq + Vector3(.9, .04, -12.5)]
	for index in PASSAGE.AUDIO_PICKUPS.size():
		var entry: Dictionary = PASSAGE.AUDIO_PICKUPS[index]
		check(_inside_tunnel(entry.local), "%s dentro do túnel" % entry.id)
		for console in consoles: check(entry.local.distance_to(console) > 2.0, "%s longe dos consoles" % entry.id)
		for digit in PASSAGE.VAULT_DIGITS: check(entry.local.distance_to(hq + digit.local) > 1.3, "%s longe dos dígitos do cofre" % entry.id)

	var progression := PROGRESSION.new()
	check(PASSAGE.audio_pickup_at(progression, Vector3(30, .04, -12)) == -1, "longe de tudo não oferece fita")
	var index := PASSAGE.audio_pickup_at(progression, PASSAGE.AUDIO_PICKUPS[1].local + Vector3(.4, 0, .3))
	check(index == 1, "perto do quadro de turnos oferece a 02")
	check(PASSAGE.collect_audio_pickup(progression, index), "coleta a 02")
	check(not PASSAGE.collect_audio_pickup(progression, index), "a 02 não entra duas vezes")
	check(PASSAGE.audio_pickup_at(progression, PASSAGE.AUDIO_PICKUPS[1].local) == -1, "a 02 coletada some da ação")
	check(not PASSAGE.collect_audio_pickup(progression, 7), "índice inválido recusado")

	var restored := PROGRESSION.new()
	check(restored.restore_snapshot(JSON.parse_string(JSON.stringify(progression.snapshot()))), "save com a 02 restaura")
	check(restored.has_audio_log("audio_maintenance_shift") and restored.data.audio_logs.size() == 1, "a 02 sobrevive ao save")
	check(not PASSAGE.collect_audio_pickup(restored, 1), "a 02 não conta de novo depois do load")
	check(PASSAGE.collect_audio_pickup(restored, 0) and PASSAGE.collect_audio_pickup(restored, 2), "coleta a 01 e a 03 depois do load")
	restored.discover_audio_log("audio_sealed_sector")
	var reloaded := PROGRESSION.new()
	check(reloaded.restore_snapshot(JSON.parse_string(JSON.stringify(restored.snapshot()))), "save com as quatro restaura")
	check(reloaded.progress_summary().audio_logs_found == 4, "resumo conta as quatro gravações")
	for id in PROGRESSION.AUDIO_IDS: check(reloaded.has_audio_log(id), "%s no Arquivo" % id)
	check(PANEL.EVIDENCE_ORDER.has("audio_vicente_field") and PANEL.EVIDENCE_ORDER.has("audio_blackout"), "Arquivo lista as gravações")
	print("VICENTE_AUDIO failures=%s" % [failures])
	quit(0 if failures.is_empty() else 1)

## Mesmos retângulos de SecretTunnel3D.contains (nível de baixo), sem instanciar o túnel.
func _inside_tunnel(point: Vector3) -> bool:
	var xz := Vector2(point.x, point.z)
	for rect in [Rect2(-2.0, -2.0, 4.0, 10.35), Rect2(-2.95, -12.5, 5.9, 11.2), Rect2(-.5, -15.15, 37.0, 6.3),
			Rect2(32.85, -12.5, 6.3, 15.0), Rect2(35.5, -1.15, 21.2, 6.3), Rect2(50.2, -5.8, 15.8, 15.6),
			Rect2(55.55, -13.0, 4.9, 7.4)]:
		if rect.has_point(xz): return true
	return false

func check(value: bool, label: String) -> void:
	print("VICENTE_AUDIO ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
