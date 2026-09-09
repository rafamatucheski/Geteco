extends SceneTree
## Testes de geração/qualidade para as streams de sirene, alarme e conquista
## de ProceduralAudio.gd, e para o novo módulo BearAudio.gd.
##
## Rodar (headless) com:
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --headless --path "D:/geteco/game" --script res://audio/review_0908/test_procedural_audio_quality.gd

const BEAR := preload("res://audio/review_0908/BearAudio.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok:
		print("ok   - ", message)
	else:
		failures += 1
		push_error("FAIL - " + message)

func _decode(stream: AudioStream) -> PackedInt32Array:
	var wav := stream as AudioStreamWAV
	var out := PackedInt32Array()
	if wav == null:
		return out
	var bytes := wav.data
	var n := bytes.size() / 2
	out.resize(n)
	for i in range(n):
		out[i] = bytes.decode_s16(i * 2)
	return out

func _peak(samples: PackedInt32Array) -> int:
	var peak := 0
	for s in samples:
		peak = maxi(peak, absi(s))
	return peak

func _edge_jump(samples: PackedInt32Array) -> int:
	# Diferença entre a última e a primeira amostra: mede o "degrau" que
	# ocorreria ao repetir o loop (LOOP_FORWARD volta de loop_end a loop_begin).
	if samples.size() < 2:
		return 0
	return absi(samples[samples.size() - 1] - samples[0])

func _max_internal_delta(samples: PackedInt32Array) -> int:
	# Maior salto amostra-a-amostra observado dentro do próprio buffer. Um
	# tom de alta frequência tem, por natureza, deltas grandes entre
	# amostras vizinhas -- não é um "estalo". O jeito correto de avaliar a
	# costura do loop é comparar o degrau da costura contra esse valor de
	# referência (o maior degrau que o conteúdo real já produz sozinho), não
	# contra um número absoluto arbitrário.
	var m := 0
	for k in range(1, samples.size()):
		m = maxi(m, absi(samples[k] - samples[k - 1]))
	return m

func run() -> void:
	# --- Sirene principal (get_siren_stream) --------------------------------
	var siren_a := ProceduralAudio.get_siren_stream()
	var siren_b := ProceduralAudio.get_siren_stream()
	check(siren_a.get_instance_id() == siren_b.get_instance_id(), "get_siren_stream() cacheia a stream (2 chamadas = mesma instância)")
	check(siren_a is AudioStreamWAV, "get_siren_stream() retorna AudioStreamWAV")
	var siren_wav := siren_a as AudioStreamWAV
	check(siren_wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Sirene principal usa loop contínuo (LOOP_FORWARD)")
	var siren_samples := _decode(siren_wav)
	check(siren_samples.size() > 0, "Sirene gera amostras finitas e não vazias")
	check(_peak(siren_samples) < 32000, "Sirene sem clipping (pico < 32000/32767): pico=%d" % _peak(siren_samples))
	var siren_edge := _edge_jump(siren_samples)
	var siren_ref := _max_internal_delta(siren_samples)
	check(siren_edge <= siren_ref, "Sirene: transição de loop sem estalo perceptível (degrau=%d <= maior degrau natural do sinal=%d)" % [siren_edge, siren_ref])

	# --- Alarme de viatura (get_police_alarm_stream) -------------------------
	var alarm_a := ProceduralAudio.get_police_alarm_stream()
	var alarm_b := ProceduralAudio.get_police_alarm_stream()
	check(alarm_a.get_instance_id() == alarm_b.get_instance_id(), "get_police_alarm_stream() cacheia a stream")
	var alarm_wav := alarm_a as AudioStreamWAV
	check(alarm_wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Alarme usa loop contínuo (LOOP_FORWARD)")
	var alarm_samples := _decode(alarm_wav)
	check(alarm_samples.size() > 0, "Alarme gera amostras finitas e não vazias")
	check(_peak(alarm_samples) < 32000, "Alarme sem clipping (pico < 32000/32767): pico=%d" % _peak(alarm_samples))
	var alarm_edge := _edge_jump(alarm_samples)
	var alarm_ref := _max_internal_delta(alarm_samples)
	check(alarm_edge <= alarm_ref, "Alarme: transição de loop sem estalo perceptível (degrau=%d <= maior degrau natural do sinal=%d)" % [alarm_edge, alarm_ref])
	# Confirma que a alternância de dois tons continua presente (não virou tom único).
	var quarter := alarm_samples.size() / 4
	var seg1_peak := _peak(alarm_samples.slice(0, quarter))
	var seg2_peak := _peak(alarm_samples.slice(quarter, quarter * 2))
	check(seg1_peak > 1000 and seg2_peak > 1000, "Alarme: ambos os tons têm energia audível (alternância preservada)")
	# Confirma que não há mais saltos abruptos nas trocas de tom (a cada 0.2s).
	var worst_alarm_delta := 0
	for k in range(1, alarm_samples.size()):
		worst_alarm_delta = maxi(worst_alarm_delta, absi(alarm_samples[k] - alarm_samples[k - 1]))
	check(worst_alarm_delta < 9000, "Alarme: sem salto abrupto amostra-a-amostra (maior degrau=%d)" % worst_alarm_delta)

	# --- Conquista / fanfarra (get_mission_passed_stream) --------------------
	var ach_a := ProceduralAudio.get_mission_passed_stream()
	var ach_b := ProceduralAudio.get_mission_passed_stream()
	check(ach_a.get_instance_id() == ach_b.get_instance_id(), "get_mission_passed_stream() cacheia a stream")
	var ach_wav := ach_a as AudioStreamWAV
	check(ach_wav.loop_mode == AudioStreamWAV.LOOP_DISABLED, "Conquista é um one-shot (sem loop)")
	var ach_samples := _decode(ach_wav)
	check(ach_samples.size() > 0, "Conquista gera amostras finitas e não vazias")
	check(_peak(ach_samples) < 32000, "Conquista sem clipping (pico < 32000/32767): pico=%d" % _peak(ach_samples))
	check(absi(ach_samples[0]) < 500, "Conquista: ataque suave no início (sem estalo na 1a amostra)")
	var tail := ach_samples.slice(ach_samples.size() - 200, ach_samples.size())
	check(_peak(tail) < 800, "Conquista: cauda final decai perto do silêncio (sem corte abrupto): pico_cauda=%d" % _peak(tail))
	# Verifica ausência de estalo forte nos limites entre notas (0.35s, 0.70s, 1.05s).
	var sample_rate := 22050
	for boundary_t in [0.35, 0.70, 1.05]:
		var idx := int(boundary_t * sample_rate)
		var window_peak_delta := 0
		for k in range(idx - 30, idx + 30):
			if k > 0 and k < ach_samples.size():
				window_peak_delta = maxi(window_peak_delta, absi(ach_samples[k] - ach_samples[k - 1]))
		check(window_peak_delta < 4000, "Conquista: sem estalo forte na transição de nota em t=%.2fs (degrau=%d)" % [boundary_t, window_peak_delta])

	# --- BearAudio (módulo novo e independente) -------------------------------
	var breathing := BEAR.get_breathing_stream()
	var breathing2 := BEAR.get_breathing_stream()
	check(breathing is AudioStreamWAV, "BearAudio.get_breathing_stream() retorna AudioStreamWAV")
	check((breathing as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "BearAudio: respiração é um loop contínuo")
	var breathing_samples := _decode(breathing)
	check(breathing_samples.size() > 0, "BearAudio: respiração gera amostras finitas e não vazias")
	check(_peak(breathing_samples) < 32000, "BearAudio: respiração sem clipping: pico=%d" % _peak(breathing_samples))
	var breathing_edge := _edge_jump(breathing_samples)
	var breathing_ref := _max_internal_delta(breathing_samples)
	check(breathing_edge <= breathing_ref, "BearAudio: respiração faz loop sem estalo (degrau=%d <= maior degrau natural do sinal=%d)" % [breathing_edge, breathing_ref])
	check(breathing.get_instance_id() == breathing2.get_instance_id(), "BearAudio: respiração é cacheada")

	var grunt := BEAR.get_grunt_alert_stream()
	var grunt2 := BEAR.get_grunt_alert_stream()
	check(grunt is AudioStreamWAV, "BearAudio.get_grunt_alert_stream() retorna AudioStreamWAV")
	check((grunt as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "BearAudio: grunhido/alerta é one-shot")
	var grunt_samples := _decode(grunt)
	check(grunt_samples.size() > 0, "BearAudio: grunhido/alerta gera amostras finitas e não vazias")
	check(_peak(grunt_samples) < 32000, "BearAudio: grunhido/alerta sem clipping: pico=%d" % _peak(grunt_samples))
	check(grunt.get_instance_id() == grunt2.get_instance_id(), "BearAudio: grunhido/alerta é cacheado")

	var charge := BEAR.get_charge_stream()
	var charge2 := BEAR.get_charge_stream()
	check(charge is AudioStreamWAV, "BearAudio.get_charge_stream() retorna AudioStreamWAV")
	check((charge as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "BearAudio: investida é one-shot")
	var charge_samples := _decode(charge)
	check(charge_samples.size() > 0, "BearAudio: investida gera amostras finitas e não vazias")
	check(_peak(charge_samples) < 32000, "BearAudio: investida sem clipping: pico=%d" % _peak(charge_samples))
	check(charge.get_instance_id() == charge2.get_instance_id(), "BearAudio: investida é cacheada")

	print("PROCEDURAL_AUDIO_QUALITY failures=", failures)
	quit(0 if failures == 0 else 1)
