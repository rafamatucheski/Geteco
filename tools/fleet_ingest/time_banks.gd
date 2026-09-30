extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var cache := preload("res://audio/EngineBankCache.gd")
	var t := Time.get_ticks_usec()
	var worst := 0.0
	cache.prewarm(self)
	var frames := 0
	while frames < 900:
		var began := Time.get_ticks_usec()
		await process_frame
		worst = maxf(worst, float(Time.get_ticks_usec()-began)/1000.0)
		frames += 1
		if cache._banks.size() >= cache.all_families().size(): break
	var bad := 0
	for fam in cache.all_families():
		var bank: Array = cache.bank(fam)
		if bank.size() != 7 or (bank[0] as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_FORWARD: bad += 1
	print("BANKS families=", cache.all_families().size(), " loaded=", cache._banks.size(), " ruins=", bad, " frames=", frames, " pior_quadro_ms=", snappedf(worst,0.1), " total_ms=", snappedf(float(Time.get_ticks_usec()-t)/1000.0,1))
	quit(0 if bad == 0 else 1)
