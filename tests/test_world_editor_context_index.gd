extends SceneTree
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
const INDEX := preload("res://addons/geteco_world_editor/WorldMapContextIndex.gd")
var checks := 0
var failures := 0
var subject: Variant
var progress_calls := 0
var saw_complete_old_index := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func fixture() -> Dictionary:
	var parts: Array = []
	for i in 8000: parts.append([float(i%100)*2,float(i/100)*2,1.0,1.0,float(i%3),"859591"])
	return {"id":"piece/new","type":"piece","position":[100,80],"size":[200,160],"rotation":0.0,"parts":parts}

func report(done: int, total: int) -> void:
	progress_calls += 1
	if done < total and total > 0 and subject.context_owners == ["piece/old"]: saw_complete_old_index = true

func close_during_index(done: int, total: int) -> void:
	if done > 0 and done < total and is_instance_valid(subject): subject.free()

func run() -> void:
	subject = CANVAS.new()
	root.add_child(subject)
	subject.objects = {"piece/old":{"id":"piece/old","type":"piece","position":[0,0],"size":[1,1],"rotation":0.0,"parts":[[0,0,1,1,0,"ffffff"]]}}
	subject.rebuild_context()
	var row := fixture()
	subject.objects = {row.id:row}
	check(await INDEX.build(weakref(subject),self,500,report), "Context selection index completes in finite slices")
	check(progress_calls > 2 and saw_complete_old_index, "Progress is observable while the previous complete index stays active")
	check(is_equal_approx(subject.context_index_progress,1.0) and subject.context_parts.size() == 8000, "Only the complete new context index is published")
	var synchronous := CANVAS.new()
	root.add_child(synchronous)
	synchronous.objects = subject.objects
	synchronous.rebuild_context()
	check(subject.context_parts == synchronous.context_parts and subject.context_owners == synchronous.context_owners, "Async and synchronous indexing preserve the same geometry and identities")
	check(subject.context_cells == synchronous.context_cells and subject.context_part_cells == synchronous.context_part_cells and subject.context_owner_parts == synchronous.context_owner_parts, "Async cell and owner indices exactly match the synchronous reference")
	synchronous.free()
	check(not await INDEX.build(weakref(subject),self,500,close_during_index), "Closing during context indexing cancels without resuming a destroyed canvas")
	check(not is_instance_valid(subject), "A cancelled job does not retain the closed editor canvas")
	print("WORLD_EDITOR_CONTEXT_INDEX checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
