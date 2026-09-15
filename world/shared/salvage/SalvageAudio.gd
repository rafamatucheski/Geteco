extends RefCounted
static var _hydraulics: AudioStreamWAV

static func hydraulics() -> AudioStreamWAV:
	if _hydraulics != null: return _hydraulics
	var bytes:=PackedByteArray()
	bytes.resize(22050*2)
	for i in 22050:
		var t:=float(i)/22050.0
		var motor:=sin(TAU*92*t)*.28+sin(TAU*184*t)*.10
		var pump:=sin(TAU*371*t+sin(TAU*3*t)*.5)*.055
		bytes.encode_s16(i*2,roundi((motor+pump)*19000))
	_hydraulics=AudioStreamWAV.new()
	_hydraulics.format=AudioStreamWAV.FORMAT_16_BITS
	_hydraulics.mix_rate=22050
	_hydraulics.data=bytes
	_hydraulics.loop_mode=AudioStreamWAV.LOOP_FORWARD
	_hydraulics.loop_end=22050
	return _hydraulics
