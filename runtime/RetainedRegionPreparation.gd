extends RefCounted
## Keep only expensive models whose constructed nodes survive preparation.
## These indivisible constructors stay behind the curtain; the background queue
## reads resources only. Disposable surfaces and decoration are not generated.
static func run(region: Node3D) -> void:
	for key in region.records:
		if region.chunks.has(key): continue
		for record in region.records[key]:
			if str(record.kind) not in region.CACHED_RECORDS: continue
			var temporary := Node3D.new()
			temporary.name = "RetainedModelPreparation"
			region.add_child(temporary)
			region._build_record_cached(temporary,record)
			region._hold_file_resources(temporary)
			region._suspend_chunk_mechanisms(temporary)
			region._detach_cached_records(temporary)
			temporary.free()
			await region.get_tree().process_frame
			if not is_instance_valid(region) or not region.is_inside_tree() or region.is_queued_for_deletion(): return
