extends Node
## Cemetery ambience. The permanent resident now belongs to KeeperHouse.
var wind: AudioStreamPlayer2D

func _ready() -> void:
	wind = AudioStreamPlayer2D.new()
	wind.name = "CemeteryWind"
	wind.stream = _wind_stream()
	wind.bus = "Ambient"
	wind.max_distance = 650
	wind.volume_db = -15
	get_parent().add_child.call_deferred(wind)
	wind.play.call_deferred()

static func _wind_stream() -> AudioStreamWAV:
	var rate := 22050
	var count := rate * 12
	var data := PackedByteArray()
	data.resize(count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 7341
	var filtered := 0.0
	for i in count:
		var t := float(i) / rate
		filtered += (noise.randf_range(-1,1) - filtered) * 0.065
		var fade := minf(1.0, minf(t,12.0-t) / 0.8)
		var gust := 0.55 + 0.30 * sin(TAU*t/6.0) + 0.15*sin(TAU*t/4.0)
		var sample := (filtered*1.5 + sin(TAU*173*t+0.8*sin(TAU*t/12.0))*0.035) * gust * fade
		data.encode_s16(i*2,clampi(int(sample*32767),-32768,32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream
