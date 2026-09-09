extends SceneTree
## Testes dos sons originais da Monaliza (primeiro carro pessoal do Dante):
## existência dos arquivos, duração, amplitude (sem clipping), continuidade
## das emendas de loop e fade dos one-shots.
##
## Rodar (headless, só analisa PCM -- não precisa de renderer):
##   "D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" ^
##     --headless --path "D:/geteco/game" --script res://tests/test_monaliza_audio.gd

const KIT := preload("res://audio/monaliza_review/MonalizaAudioKit.gd")
const AUDIO_DIR := "D:/geteco/game/audio/monaliza_review/"

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok:
		print("ok   - ", message)
	else:
		failures += 1
		push_error("FAIL - " + message)

# ==========================================
# HELPERS DE ANÁLISE DE PCM
# ==========================================
func _load_wav(path: String) -> AudioStreamWAV:
	if not FileAccess.file_exists(path):
		return null
	# Estes .wav ficam fora do pipeline de import do editor (nunca foram
	# abertos no editor, não têm .import) -- load_from_file() lê o WAV
	# diretamente do disco, sem depender de metadados de import.
	return AudioStreamWAV.load_from_file(path)

func _decode(stream: AudioStreamWAV) -> PackedInt32Array:
	var out := PackedInt32Array()
	if stream == null:
		return out
	var bytes := stream.data
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

func _rms(samples: PackedInt32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum := 0.0
	for s in samples:
		sum += float(s) * float(s)
	return sqrt(sum / float(samples.size()))

func _max_internal_delta(samples: PackedInt32Array) -> int:
	var m := 0
	for k in range(1, samples.size()):
		m = maxi(m, absi(samples[k] - samples[k - 1]))
	return m

func _edge_jump(samples: PackedInt32Array) -> int:
	if samples.size() < 2:
		return 0
	return absi(samples[samples.size() - 1] - samples[0])

func _peak_in_range(samples: PackedInt32Array, from_idx: int, to_idx: int) -> int:
	var peak := 0
	for i in range(maxi(0, from_idx), mini(samples.size(), to_idx)):
		peak = maxi(peak, absi(samples[i]))
	return peak

# ==========================================
# EXECUÇÃO
# ==========================================
func run() -> void:
	_test_files_exist_and_are_valid_finite_wavs()
	_test_engine()
	_test_turbo_spool()
	_test_turbo_release()
	_test_ignition_if_present()
	_test_demo()

	print("MONALIZA_AUDIO_TEST failures=", failures)
	quit(0 if failures == 0 else 1)

# ==========================================
# ARQUIVOS: existem, carregam, são finitos
# ==========================================
func _test_files_exist_and_are_valid_finite_wavs() -> void:
	for file_name in ["engine.wav", "turbo_spool.wav", "turbo_release.wav"]:
		check(FileAccess.file_exists(AUDIO_DIR + file_name), "%s existe em audio/monaliza_review/" % file_name)
		var stream := _load_wav(AUDIO_DIR + file_name)
		check(stream != null, "%s carrega como AudioStreamWAV válido" % file_name)
		if stream != null:
			check(stream.data.size() > 0, "%s tem PCM finito e não vazio" % file_name)
			check(stream.mix_rate == KIT.SAMPLE_RATE, "%s usa o sample rate documentado (%d Hz)" % [file_name, KIT.SAMPLE_RATE])
	# ignition.wav é opcional no pedido, mas foi entregue -- se existir, também precisa ser válido.
	if FileAccess.file_exists(AUDIO_DIR + "ignition.wav"):
		var ignition := _load_wav(AUDIO_DIR + "ignition.wav")
		check(ignition != null and ignition.data.size() > 0, "ignition.wav (opcional, entregue) é um AudioStreamWAV válido e não vazio")
	check(FileAccess.file_exists(AUDIO_DIR + "demo_start_accelerate_release.wav"), "demonstração composta (partida/aceleração/alívio) existe para audição")

# ==========================================
# engine.wav: loop de motor
# ==========================================
func _test_engine() -> void:
	# save_to_wav() grava um .wav puro (fmt/data), sem o chunk "smpl" que
	# carregaria loop_begin/loop_end de volta -- então o AudioStreamWAV
	# recarregado do arquivo sempre volta com loop_mode = DISABLED, mesmo
	# quando o stream gerado em memória tinha LOOP_FORWARD. Isso é uma
	# limitação da própria API save_to_wav()/load_from_file() do Godot, não
	# um defeito do áudio -- documentado em audio/monaliza_review/README.md.
	# Por isso verificamos loop_mode no stream gerado em memória (a fonte),
	# e continuidade real de PCM (abaixo) no arquivo gravado.
	check(KIT.generate_engine_stream().loop_mode == AudioStreamWAV.LOOP_FORWARD, "MonalizaAudioKit.generate_engine_stream() marca loop contínuo (LOOP_FORWARD) no stream em memória")
	var stream := _load_wav(AUDIO_DIR + "engine.wav")
	if stream == null:
		check(false, "engine.wav não pôde ser analisado (não carregou)")
		return
	var duration := float(stream.data.size() / 2) / float(stream.mix_rate)
	check(absf(duration - KIT.ENGINE_DURATION) < 0.01, "engine.wav tem a duração documentada (~%.2fs, medido %.3fs)" % [KIT.ENGINE_DURATION, duration])

	var samples := _decode(stream)
	var peak := _peak(samples)
	check(peak < 32000, "engine.wav sem clipping (pico=%d < 32000/32767)" % peak)
	check(peak > 4000, "engine.wav tem corpo audível (pico=%d, não é silêncio quase total)" % peak)
	var rms := _rms(samples)
	check(rms > 500.0 and rms < 20000.0, "engine.wav tem RMS num intervalo saudável (%.0f), nem quase mudo nem esmagado" % rms)

	var edge := _edge_jump(samples)
	var ref := _max_internal_delta(samples)
	check(edge <= ref, "engine.wav: emenda do loop sem estalo perceptível (degrau=%d <= maior degrau natural do sinal=%d)" % [edge, ref])

# ==========================================
# turbo_spool.wav: loop de assobio discreto
# ==========================================
func _test_turbo_spool() -> void:
	# Ver o comentário equivalente em _test_engine() sobre por que loop_mode
	# é verificado no stream em memória, não no arquivo recarregado.
	check(KIT.generate_turbo_spool_stream().loop_mode == AudioStreamWAV.LOOP_FORWARD, "MonalizaAudioKit.generate_turbo_spool_stream() marca loop contínuo (LOOP_FORWARD) no stream em memória")
	var stream := _load_wav(AUDIO_DIR + "turbo_spool.wav")
	if stream == null:
		check(false, "turbo_spool.wav não pôde ser analisado (não carregou)")
		return
	var duration := float(stream.data.size() / 2) / float(stream.mix_rate)
	check(absf(duration - KIT.TURBO_SPOOL_DURATION) < 0.01, "turbo_spool.wav tem a duração documentada (~%.2fs, medido %.3fs)" % [KIT.TURBO_SPOOL_DURATION, duration])

	var samples := _decode(stream)
	var peak := _peak(samples)
	check(peak < 32000, "turbo_spool.wav sem clipping (pico=%d < 32000/32767)" % peak)

	var engine_stream := _load_wav(AUDIO_DIR + "engine.wav")
	if engine_stream != null:
		var engine_peak := _peak(_decode(engine_stream))
		check(peak < engine_peak, "turbo_spool.wav é mais discreto que engine.wav (pico=%d < pico do motor=%d), como pedido" % [peak, engine_peak])

	var edge := _edge_jump(samples)
	var ref := _max_internal_delta(samples)
	check(edge <= ref, "turbo_spool.wav: emenda do loop sem estalo perceptível (degrau=%d <= maior degrau natural do sinal=%d)" % [edge, ref])

# ==========================================
# turbo_release.wav: one-shot com fade
# ==========================================
func _test_turbo_release() -> void:
	var stream := _load_wav(AUDIO_DIR + "turbo_release.wav")
	if stream == null:
		check(false, "turbo_release.wav não pôde ser analisado (não carregou)")
		return
	check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "turbo_release.wav é um one-shot (sem loop)")
	var duration := float(stream.data.size() / 2) / float(stream.mix_rate)
	check(duration > 0.15 and duration < 1.2, "turbo_release.wav é 'curto' como pedido (%.3fs, entre 0.15s e 1.2s)" % duration)

	var samples := _decode(stream)
	var peak := _peak(samples)
	check(peak < 32000, "turbo_release.wav sem clipping (pico=%d < 32000/32767)" % peak)
	check(absi(samples[0]) < 400, "turbo_release.wav começa com ataque suave (1a amostra=%d, sem estalo)" % samples[0])

	var tail_n := mini(400, samples.size())
	var tail_peak := _peak_in_range(samples, samples.size() - tail_n, samples.size())
	check(tail_peak < peak / 8, "turbo_release.wav esvanece (fade) até perto do silêncio no final (pico da cauda=%d << pico geral=%d)" % [tail_peak, peak])

# ==========================================
# ignition.wav (opcional): também precisa de fade se foi entregue
# ==========================================
func _test_ignition_if_present() -> void:
	var path := AUDIO_DIR + "ignition.wav"
	if not FileAccess.file_exists(path):
		print("ok   - ignition.wav é opcional e não foi entregue (nada a verificar)")
		return
	var stream := _load_wav(path)
	if stream == null:
		check(false, "ignition.wav existe mas não pôde ser analisado")
		return
	check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "ignition.wav é um one-shot (sem loop)")
	var samples := _decode(stream)
	var peak := _peak(samples)
	check(peak < 32000, "ignition.wav sem clipping (pico=%d < 32000/32767)" % peak)
	check(absi(samples[0]) < 400, "ignition.wav começa com ataque suave (1a amostra=%d, sem estalo)" % samples[0])
	var tail_n := mini(400, samples.size())
	var tail_peak := _peak_in_range(samples, samples.size() - tail_n, samples.size())
	check(tail_peak < peak / 6, "ignition.wav esvanece perto do silêncio no final (pico da cauda=%d << pico geral=%d)" % [tail_peak, peak])

# ==========================================
# Demonstração composta: partida + aceleração + alívio
# ==========================================
func _test_demo() -> void:
	var path := AUDIO_DIR + "demo_start_accelerate_release.wav"
	var stream := _load_wav(path)
	if stream == null:
		check(false, "demo_start_accelerate_release.wav não pôde ser analisado")
		return
	check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "demonstração é um one-shot (não um loop)")
	var duration := float(stream.data.size() / 2) / float(stream.mix_rate)
	check(duration > 3.0, "demonstração é longa o bastante para conter partida, aceleração e alívio (%.2fs)" % duration)

	var samples := _decode(stream)
	var peak := _peak(samples)
	check(peak < 32000, "demonstração sem clipping (pico=%d < 32000/32767)" % peak)

	# Tem que haver som real nos três momentos descritos: partida (início),
	# aceleração (por volta de 2/3 do percurso da subida de RPM) e alívio
	# (logo após o pico, quando o turbo solta).
	var sr := stream.mix_rate
	check(_peak_in_range(samples, 0, int(0.3 * sr)) > 200, "demonstração tem som audível na partida (primeiros 0.3s)")
	check(_peak_in_range(samples, int(2.0 * sr), int(2.4 * sr)) > 1500, "demonstração tem som audível durante a aceleração (~2.0-2.4s)")
	check(_peak_in_range(samples, int(3.05 * sr), int(3.35 * sr)) > 500, "demonstração tem som audível no instante do alívio do turbo (~3.05-3.35s)")

	# Final da demonstração precisa fechar em silêncio (fade), não cortar seco.
	var tail_n := mini(800, samples.size())
	var tail_peak := _peak_in_range(samples, samples.size() - tail_n, samples.size())
	check(tail_peak < peak / 10, "demonstração fecha com fade até perto do silêncio (pico da cauda=%d << pico geral=%d)" % [tail_peak, peak])
