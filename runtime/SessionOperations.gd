extends RefCounted
## Diagnóstico de ciclo de vida de baixa frequência. As durações de relógio incluem awaits e filhos.
## Nunca deduz sucesso de um callback que retornou; quem chama pode relatar status explícito.
static func logger() -> Node:
	if OS.get_environment("HARBOR_SESSION_PROFILE") != "1": return null
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("SessionDiagnostics") if tree != null else null

static func begin(source: Node, system: String, operation: String, details: Dictionary = {}, parent_token: int = 0) -> int:
	var sink := logger()
	if sink == null: return 0
	var script_path := ""
	if is_instance_valid(source) and source.get_script() != null:
		script_path = _source_path(source)
	return int(sink.call("BeginOperationAt", system, operation, script_path, JSON.stringify(details), Time.get_ticks_usec(), Engine.get_process_frames(), parent_token))

static func finish(token: int, status := "returned") -> void:
	if token == 0: return
	var sink := logger()
	if sink != null: sink.call("EndOperation", token, status)

static func completed(source: Node, system: String, operation: String, began_usec: int, details: Dictionary = {}) -> void:
	if began_usec == 0: return
	var sink := logger()
	if sink == null: return
	var ended := Time.get_ticks_usec()
	sink.call("RecordProfile", JSON.stringify({"type":"operation_timing", "system":system,
		"operation":operation, "source":_source_path(source),
		"start_usec":began_usec, "end_usec":ended, "process_frame":Engine.get_process_frames(),
		"duration_ms":float(ended-began_usec)/1000.0,
		"timing":"wall_inclusive", "details":details}))

static func _source_path(source: Node) -> String:
	return str(source.get_script().resource_path) if is_instance_valid(source) and source.get_script() != null else ""

## Fronteiras síncronas. Um erro antes do finish deixa de propósito uma etapa pendente.
## Sem catch/rollback: o erro original do motor e o comportamento do jogo ficam intactos.
static func attach(parent: Node, child: Node, source: Node, parent_token: int = 0) -> void:
	var token := begin(source, "scene", "add_child_ready", {"node":str(child.name), "class":child.get_class(), "script":_source_path(child)}, parent_token)
	parent.add_child(child)
	finish(token)

static func load_resource(path: String, source: Node = null, parent_token: int = 0) -> Resource:
	var token := begin(source, "resource", "load", {"path":path, "cached_before":ResourceLoader.has_cached(path)}, parent_token)
	var resource := load(path)
	finish(token, "loaded" if resource != null else "missing")
	return resource

static func instantiate(resource: Resource, source: Node = null, parent_token: int = 0) -> Node:
	var token := begin(source, "resource", "instantiate", {"path":resource.resource_path}, parent_token)
	var node: Node = resource.instantiate() if resource is PackedScene else resource.new()
	finish(token, "created" if node != null else "missing")
	return node
