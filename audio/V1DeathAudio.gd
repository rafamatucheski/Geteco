class_name V1DeathAudio
extends RefCounted
## Vinheta de morte da V1, portada sem depender do autoload antigo.

static func stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 1.8
	var sample_count := int(sample_rate*duration)
	var data := PackedByteArray()
	data.resize(sample_count*2)
	for index in sample_count:
		var time := float(index)/float(sample_rate)
		var envelope := exp(-time*2.2)
		var bass := sin(TAU*55.0*time)*.6
		var minor_third := sin(TAU*65.41*time)*.4
		var fifth := sin(TAU*82.41*time)*.3
		var sample := (bass+minor_third+fifth)*envelope*.65
		data.encode_s16(index*2,clampi(int(sample*32767.0),-32768,32767))
	var result := AudioStreamWAV.new()
	result.format = AudioStreamWAV.FORMAT_16_BITS
	result.mix_rate = sample_rate
	result.stereo = false
	result.loop_mode = AudioStreamWAV.LOOP_DISABLED
	result.data = data
	return result
