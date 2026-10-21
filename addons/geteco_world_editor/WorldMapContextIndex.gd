@tool
extends RefCounted
## Initial map selection index, built in private state with a finite frame budget.
## A closed editor or a newer edit cancels the job without publishing partial cells.
static func build(reference: WeakRef, tree: SceneTree, budget_usec := 3000, progress := Callable()) -> bool:
	var canvas: Variant = reference.get_ref()
	if not is_instance_valid(canvas) or not canvas.is_inside_tree(): return false
	canvas.context_index_revision += 1
	var request: int = canvas.context_index_revision
	canvas.context_index_progress = 0.0
	var rows: Array = canvas.objects.values()
	var total := 0
	var began := Time.get_ticks_usec()
	for row: Dictionary in rows:
		if row.get("type","") in ["context","piece"]: total += row.get("parts",[]).size()
		if Time.get_ticks_usec()-began >= budget_usec:
			if progress.is_valid(): progress.call(0,0)
			await tree.process_frame
			canvas = reference.get_ref()
			if not is_instance_valid(canvas) or not canvas.is_inside_tree(): return false
			if canvas.context_index_revision != request: return false
			began = Time.get_ticks_usec()
	var parts: Array = []
	var owners: Array[String] = []
	var owner_parts := {}
	var part_cells := {}
	var cells := {}
	var overview_items := {}
	var done := 0
	if progress.is_valid(): progress.call(0,total)
	for row: Dictionary in rows:
		if Time.get_ticks_usec()-began >= budget_usec:
			canvas.context_index_progress = float(done)/maxi(1,total)
			if progress.is_valid(): progress.call(done,total)
			await tree.process_frame
			canvas = reference.get_ref()
			if not is_instance_valid(canvas) or not canvas.is_inside_tree(): return false
			if canvas.context_index_revision != request: return false
			began = Time.get_ticks_usec()
		if row.get("type","") not in ["context","piece"]: continue
		var owner := str(row.id)
		var overview: Dictionary = canvas.overview_footprint(row)
		if not overview.is_empty(): overview_items[owner] = overview
		if not owner_parts.has(owner): owner_parts[owner] = []
		for part: Array in row.get("parts",[]):
			var index := parts.size()
			parts.append(part)
			owners.append(owner)
			owner_parts[owner].append(index)
			var touched: Array[Vector2i] = []
			for x in range(floori(part[0]/64),floori((part[0]+part[2])/64)+1):
				for z in range(floori(part[1]/64),floori((part[1]+part[3])/64)+1):
					var key := Vector2i(x,z)
					if not cells.has(key): cells[key] = []
					cells[key].append(index)
					touched.append(key)
					if Time.get_ticks_usec()-began >= budget_usec:
						canvas.context_index_progress = float(done)/maxi(1,total)
						if progress.is_valid(): progress.call(done,total)
						await tree.process_frame
						canvas = reference.get_ref()
						if not is_instance_valid(canvas) or not canvas.is_inside_tree(): return false
						if canvas.context_index_revision != request: return false
						began = Time.get_ticks_usec()
			part_cells[index] = touched
			done += 1
			# Empty/off-grid parts still need a yield boundary, even without cells.
			if Time.get_ticks_usec()-began >= budget_usec:
				canvas.context_index_progress = float(done)/maxi(1,total)
				if progress.is_valid(): progress.call(done,total)
				await tree.process_frame
				canvas = reference.get_ref()
				if not is_instance_valid(canvas) or not canvas.is_inside_tree(): return false
				if canvas.context_index_revision != request: return false
				began = Time.get_ticks_usec()
	canvas = reference.get_ref()
	if not is_instance_valid(canvas) or not canvas.is_inside_tree(): return false
	if canvas.context_index_revision != request: return false
	canvas.context_parts = parts
	canvas.context_owners = owners
	canvas.context_owner_parts = owner_parts
	canvas.context_part_cells = part_cells
	canvas.context_free_parts.clear()
	canvas.context_cells = cells
	canvas.context_overview_items = overview_items
	canvas.invalidate_overview()
	canvas.context_overview_dirty = true
	canvas.context_triangles.clear()
	canvas.mesh_key = []
	canvas.road_ready = false
	canvas.cached_cells = Rect2i(-999999,-999999,0,0)
	canvas.context_mesh = null
	canvas.context_index_progress = 1.0
	canvas.queue_redraw()
	if progress.is_valid(): progress.call(done,total)
	return true
