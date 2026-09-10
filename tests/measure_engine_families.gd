extends SceneTree

## Caracteriza as camadas sintetizadas de cada família de motor e o custo de
## construí-las. Serve para responder "caminhão soa como caminhão?" com número
## em vez de opinião: centróide espectral (brilho), energia abaixo de 120 Hz
## (peso), profundidade de modulação por ignição (batida) e a razão de giro
## marcha-lenta/corte (o quanto a família estica antes de acabar).
##
## Exporta um relatório em res://docs/measurements/ e WAVs das camadas em
## res://docs/measurements/engine_layers/ para escuta direta.

const ENGINE := preload("res://audio/VehicleEngineSound.gd")
const FAMILIES := [
	"street", "sport", "muscle", "suv", "diesel",
	"truck", "bus", "fire_diesel", "ambulance", "police",
]
const OUT_DIR := "res://docs/measurements/engine_layers"

func _initialize() -> void:
	call_deferred("_run")

func _samples(stream: AudioStreamWAV) -> PackedFloat32Array:
	var data := stream.data
	var frames: int = stream.loop_end
	var out := PackedFloat32Array()
	out.resize(frames)
	for i in frames:
		out[i] = float(data.decode_s16(i * 2)) / 32768.0
	return out

## Centróide espectral aproximado pela razão entre energia da derivada e energia
## do sinal: proporcional à frequência média do conteúdo. Barato e suficiente
## para ordenar famílias por brilho.
func _brightness(samples: PackedFloat32Array) -> float:
	var energy := 0.0
	var diff_energy := 0.0
	var previous := samples[samples.size() - 1]
	for i in samples.size():
		var value := samples[i]
		energy += value * value
		var d := value - previous
		diff_energy += d * d
		previous = value
	if energy <= 0.0:
		return 0.0
	return sqrt(diff_energy / energy) * float(ENGINE.RATE) / TAU

## Energia abaixo de ~120 Hz, via média móvel circular de 1/120 s.
func _low_energy(samples: PackedFloat32Array) -> float:
	var n := samples.size()
	var window := int(float(ENGINE.RATE) / 120.0)
	var running := 0.0
	for i in window:
		running += samples[i]
	var total := 0.0
	var low := 0.0
	for i in n:
		var mean := running / float(window)
		low += mean * mean
		total += samples[i] * samples[i]
		running += samples[(i + window) % n] - samples[i]
	if total <= 0.0:
		return 0.0
	return low / total

## Profundidade da batida: variação do envelope entre picos e vales dentro de um
## ciclo do motor. Motor de verdade pulsa; drone sintético não.
func _pulse_depth(samples: PackedFloat32Array, cycles: int) -> float:
	var n := samples.size()
	var window := maxi(int(float(n) / float(cycles) / 12.0), 8)
	var peak := 0.0
	var valley := 1e9
	var i := 0
	while i < n:
		var local := 0.0
		for k in window:
			local = maxf(local, absf(samples[(i + k) % n]))
		peak = maxf(peak, local)
		valley = minf(valley, local)
		i += window
	if peak <= 0.0:
		return 0.0
	return (peak - valley) / peak

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var lines: Array[String] = []
	lines.append("Familias de motor — camadas sintetizadas (%s)" % Time.get_datetime_string_from_system())
	lines.append("")
	lines.append("familia      camada  ciclos/s  brilho_Hz  grave%%  batida  ms_gerar")
	var total_ms := 0.0
	for family in FAMILIES:
		ENGINE._layer_sets.clear()
		ENGINE._streams.clear()
		var started := Time.get_ticks_usec()
		var layers: Array = ENGINE.get_layer_streams(family)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		total_ms += elapsed
		var profile: Dictionary = ENGINE._PROFILES[family]
		for index in layers.size():
			var stream: AudioStreamWAV = layers[index]
			var samples := _samples(stream)
			var cycles := int(profile.cycles[index])
			lines.append("%-12s %-6d %-9d %-10.0f %-7.2f %-7.2f %.1f" % [
				family, index, cycles, _brightness(samples),
				_low_energy(samples) * 100.0, _pulse_depth(samples, cycles),
				elapsed / float(layers.size()),
			])
			var wav_path := "%s/%s_%d.wav" % [OUT_DIR, family, index]
			var file := FileAccess.open(wav_path, FileAccess.WRITE)
			if file != null:
				file.store_buffer(_wav_bytes(stream))
				file.close()
		lines.append("             faixa de giro (marcha lenta -> corte): %.1fx  cilindros: %d  marchas: %d" % [
			float(profile.redline) / float(profile.idle), int(profile.cyl),
			ENGINE._GEARBOX[family].size(),
		])
	lines.append("")
	lines.append("Tempo total de sintese das %d familias: %.0f ms" % [FAMILIES.size(), total_ms])
	# Limpa o cache poluido pela medicao para nao deixar estado estranho ao sair.
	ENGINE._layer_sets.clear()
	ENGINE._streams.clear()

	var report := "\n".join(lines) + "\n"
	print(report)
	var report_path := "res://docs/measurements/engine_families.txt"
	var out := FileAccess.open(report_path, FileAccess.WRITE)
	if out != null:
		out.store_string(report)
		out.close()
		print("Relatorio: ", ProjectSettings.globalize_path(report_path))
		print("WAVs: ", ProjectSettings.globalize_path(OUT_DIR))
	quit(0)

## Empacota o PCM do laço (sem as amostras de guarda) em um WAV mono para poder
## abrir em qualquer player e escutar a camada isolada.
func _wav_bytes(stream: AudioStreamWAV) -> PackedByteArray:
	var frames: int = stream.loop_end
	var pcm := stream.data.slice(0, frames * 2)
	var out := PackedByteArray()
	out.append_array("RIFF".to_ascii_buffer())
	var header_tail := PackedByteArray()
	header_tail.append_array("WAVEfmt ".to_ascii_buffer())
	var chunk := PackedByteArray()
	chunk.resize(16)
	chunk.encode_u32(0, 16)
	var fmt := PackedByteArray()
	fmt.resize(16)
	fmt.encode_u16(0, 1)
	fmt.encode_u16(2, 1)
	fmt.encode_u32(4, stream.mix_rate)
	fmt.encode_u32(8, stream.mix_rate * 2)
	fmt.encode_u16(12, 2)
	fmt.encode_u16(14, 16)
	var size_field := PackedByteArray()
	size_field.resize(4)
	size_field.encode_u32(0, 36 + pcm.size())
	out.append_array(size_field)
	out.append_array(header_tail)
	var fmt_size := PackedByteArray()
	fmt_size.resize(4)
	fmt_size.encode_u32(0, 16)
	out.append_array(fmt_size)
	out.append_array(fmt)
	out.append_array("data".to_ascii_buffer())
	var data_size := PackedByteArray()
	data_size.resize(4)
	data_size.encode_u32(0, pcm.size())
	out.append_array(data_size)
	out.append_array(pcm)
	return out
