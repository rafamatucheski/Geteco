extends RefCounted
## Small attempt-owned accumulator; no nodes, timers, allocations or history per tick.
var course := 800.0
var launch := ""
var good_shifts := 0
var bad_shifts := 0
var shift_count := 0
var limiter_seconds := 0.0
var late_limiter_seconds := 0.0
var nitro_seconds := 0.0
var spin60_seconds := 0.0
var first60_seconds := 0.0
var tail_entry_speed := 0.0
var tail_min_speed := 0.0
var finish_speed := 0.0
var observed_seconds := 0.0
var max_offset := 0.0
var _serial := 0
var _gear := 1
var _offset := 0.0

func observe(drive: RefCounted, offset: float, delta: float) -> void:
	if delta<=0.0 or max_offset>=course: return
	var end := clampf(offset,0.0,course)
	var moved := maxf(.00001,offset-_offset)
	var dt := minf(delta,.25)*clampf((course-_offset)/moved,0.0,1.0)
	var covered := maxf(.00001,end-_offset)
	launch=str(drive.launch_quality)
	if int(drive.shift_serial)!=_serial:
		var target: int=int(drive.get("_shift_target_gear"))
		var count: int=int(drive.shift_serial)-_serial
		shift_count+=count
		if target>_gear and count==1 and str(drive.last_shift) in ["TROCA IDEAL","BOA TROCA"]: good_shifts+=1
		else: bad_shifts+=count
		_serial=int(drive.shift_serial)
		_gear=target
	observed_seconds+=dt
	if drive.limiter:
		limiter_seconds+=dt
		var late_fraction := 1.0 if end==_offset and end>=course-200.0 else clampf((end-maxf(_offset,course-200.0))/covered,0.0,1.0)
		late_limiter_seconds+=dt*late_fraction
	if drive.nitro_active: nitro_seconds+=dt
	var first_fraction := 1.0 if end==_offset and _offset<60.0 else clampf((minf(end,60.0)-minf(_offset,60.0))/covered,0.0,1.0)
	var first_dt := dt*first_fraction
	first60_seconds+=first_dt
	spin60_seconds+=first_dt*clampf(float(drive.wheelspin),0.0,1.0)
	finish_speed=maxf(0.0,float(drive.speed_mps))
	if end>=course-100.0:
		if tail_entry_speed<=0.0: tail_entry_speed=finish_speed; tail_min_speed=finish_speed
		else: tail_min_speed=minf(tail_min_speed,finish_speed)
	max_offset=maxf(max_offset,end)
	_offset=end

func snapshot() -> Dictionary:
	return {"launch":launch,"good_shifts":good_shifts,"bad_shifts":bad_shifts,"shift_count":shift_count,"limiter_seconds":limiter_seconds,"late_limiter_seconds":late_limiter_seconds,"nitro_seconds":nitro_seconds,"spin60_seconds":spin60_seconds,"first60_seconds":first60_seconds,"tail_entry_speed":tail_entry_speed,"tail_min_speed":tail_min_speed,"finish_speed":finish_speed,"observed_seconds":observed_seconds,"max_offset":max_offset}
