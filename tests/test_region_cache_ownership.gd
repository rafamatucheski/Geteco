extends SceneTree
## Ciclo real de nÃ³s/recursos, fora da Ã¡rvore; nÃ£o mede arte, colisÃ£o ou FPS.
const REGION := preload("res://world/regions/NativeRegion.gd")
const ART_PATH := "res://world/regions/NativeLake.gd"
var checks := 0
var failures := 0


func _initialize() -> void:
	_node_lifecycle()
	_resource_lifecycle()
	print("%s REGION_CACHE_OWNERSHIP checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("REGION_CACHE_OWNERSHIP: " + label)


func _node_lifecycle() -> void:
	var holder := Node3D.new()
	var owner := REGION.new()
	holder.add_child(owner) # Holder tambÃ©m fora da Ã¡rvore: nenhum _ready.
	var record := {"kind": "harbor_public_realm", "zone_id": "union_plaza", "position": Vector3.ZERO}
	var chunk := Node3D.new()
	owner.add_child(chunk)
	owner._build_record_cached(chunk, record)
	_check(chunk.get_child_count() == 1 and owner._record_cache.size() == 1, "mÃ©todo produtivo criou uma raiz real")
	var original: WeakRef = weakref(chunk.get_child(0))
	var key: String = chunk.get_child(0).get_meta("record_cache_key")
	for cycle in 8:
		owner._retire_chunk(chunk)
		_check(is_instance_valid(original.get_ref()) and original.get_ref().get_parent() == null, "retire preserva raiz detached/%d" % cycle)
		# Exercita diretamente a rotina existente de unmount, sem montar mundo.
		owner._exit_tree()
		_check(owner._record_cache.size() == 1 and is_instance_valid(original.get_ref()), "exit mantÃ©m cache/%d" % cycle)
		holder.remove_child(owner)
		holder.add_child(owner)
		chunk = Node3D.new()
		owner.add_child(chunk)
		owner._build_record_cached(chunk, record)
		_check(is_same(chunk.get_child(0), original.get_ref()), "remount reutiliza identidade/%d" % cycle)
		_check(owner._record_cache.size() == 1, "ciclos nÃ£o ampliam cardinalidade/%d" % cycle)
	owner._detach_cached_records(chunk)
	var second := REGION.new()
	_check(second._record_cache.is_empty(), "novo owner comeÃ§a vazio")
	var second_chunk := Node3D.new()
	second.add_child(second_chunk)
	second._build_record_cached(second_chunk, record)
	var second_node: WeakRef = weakref(second_chunk.get_child(0))
	_check(not is_same(second_node.get_ref(), original.get_ref()), "novo owner nÃ£o rouba raiz antiga detached")
	_check(second._record_cache.has(key), "keys iguais pertencem a owners diferentes")
	# Cache tambÃ©m pode conter uma raiz ainda pertencente a outro pai.
	var record_b := {"kind": "harbor_public_realm", "zone_id": "foundry_courtyard", "position": Vector3(128, 0, 128)}
	owner._build_record_cached(chunk, record_b)
	var parented: WeakRef = weakref(chunk.get_child(0))
	chunk.remove_child(parented.get_ref())
	var external := Node3D.new()
	external.add_child(parented.get_ref())
	var cache: Dictionary = owner._record_cache
	owner.free() # NOTIFICATION_PREDELETE real, sem chamada manual ao handler.
	_check(original.get_ref() == null, "destruiÃ§Ã£o definitiva libera raiz parentless")
	_check(cache.is_empty(), "destruiÃ§Ã£o elimina referÃªncias do dicionÃ¡rio")
	_check(is_instance_valid(parented.get_ref()) and parented.get_ref().get_parent() == external, "cleanup nÃ£o libera raiz de outro pai")
	_check(is_instance_valid(second_node.get_ref()), "outro owner permanece vÃ¡lido")
	second.free()
	_check(second_node.get_ref() == null, "raiz attached Ã© destruÃ­da pelo pai normalmente")
	external.free()
	_check(parented.get_ref() == null, "pai externo mantÃ©m responsabilidade normal")
	holder.free()


func _resource_lifecycle() -> void:
	var first := REGION.new()
	var second := REGION.new()
	var loaded: Resource = first._held_load(ART_PATH)
	_check(loaded != null and first._held_resources.size() == 1, "held_load produtivo mantÃ©m script real")
	_check(is_same(first._held_load(ART_PATH), loaded) and first._held_resources.size() == 1, "prewarm repetido reutiliza recurso por path")
	_check(second._held_resources.is_empty(), "novo owner nÃ£o compartilha dicionÃ¡rio de recursos")
	var warmed: Node3D = (loaded as Script).new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	warmed.add_child(mesh)
	first._hold_file_resources(warmed)
	warmed.free() # Descarta chunk/art como prewarm, preservando recurso por path.
	_check(first._held_resources.size() == 1 and first._held_resources.has(ART_PATH), "traversal produtivo de prewarm retÃ©m script e ignora mesh procedural")
	var shared: Resource = second._held_load(ART_PATH)
	_check(is_same(shared, loaded), "ResourceLoader continua compartilhando recurso vivo")
	first._hold_resource(Resource.new())
	first._hold_resource("nÃ£o Ã© Resource")
	_check(first._held_resources.size() == 1, "retenÃ§Ã£o continua ignorando recurso procedural e outros tipos")
	# Recurso real com caminho virtual Ãºnico, sem escrever arquivo/salvar jogo.
	var temporary := Resource.new()
	temporary.take_over_path("res://tests/region_cache_virtual_%d.tres" % first.get_instance_id())
	var released: WeakRef = weakref(temporary)
	first._hold_resource(temporary)
	temporary = null
	_check(is_instance_valid(released.get_ref()), "referÃªncia do owner mantÃ©m recurso vivo")
	var retained := Resource.new()
	retained.take_over_path("res://tests/region_cache_external_%d.tres" % first.get_instance_id())
	var retained_weak: WeakRef = weakref(retained)
	first._hold_resource(retained)
	var cache: Dictionary = first._held_resources
	first._exit_tree()
	_check(cache.size() == 3 and is_instance_valid(released.get_ref()), "unmount preserva recursos aquecidos")
	first.free()
	_check(cache.is_empty() and released.get_ref() == null, "PREDELETE solta referÃªncias exclusivas")
	_check(is_instance_valid(retained_weak.get_ref()) and is_instance_valid(shared), "referÃªncias externas e segundo owner sobrevivem")
	_check(second._held_resources.size() == 1, "limpeza do primeiro nÃ£o esvazia o segundo")
	retained = null
	_check(retained_weak.get_ref() == null, "recurso externo libera quando Ãºltima referÃªncia termina")
	second.free()
