extends "res://tools/building_bake/test_baked_commercial.gd"
## Paridade das sombras no marco real de fusão, nas quatro combinações P5/P6.
func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var initial_detail: bool = CATALOG.detail_enabled()
	var initial_baked: bool = FACTORY.baked_enabled
	for detail_enabled in [false, true]:
		CATALOG.set_detail_enabled(detail_enabled)
		for record in BAKE.records():
			var original := mount(record, false)
			var baked := mount(record, true)
			var id := str(record.id) + " P5=" + str(detail_enabled)
			check(baked.get_meta("baked_commercial", false), id + " usa o bake")
			var before := BAKE.counts(baked)
			FACTORY.BUILDING_BATCH._optimize_building(original)
			FACTORY.BUILDING_BATCH._optimize_building(baked)
			check(same_geometry(geometry(original), geometry(baked)), id + " conserva geometria, materiais e sombras após fusão")
			check(boxes(original) == boxes(baked), id + " conserva colisão após fusão")
			check(BAKE.counts(baked) == before, id + " marco não reconstrói nem funde o arquivo")
			original.free()
			baked.free()
	CATALOG.set_detail_enabled(initial_detail)
	FACTORY.baked_enabled = initial_baked
	var file := FileAccess.open("res://tools/building_bake/validation_batch.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "variants": 15, "detail_modes": [false, true]}, "\t"))
	file.close()
	print("P6_CONTRATO_SOMBRAS_FUSAO verificações=", checks, " falhas=", failures.size())
	quit(0 if failures.is_empty() else 1)
