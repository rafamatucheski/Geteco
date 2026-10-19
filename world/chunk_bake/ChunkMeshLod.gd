extends RefCounted
## LOD das malhas fundidas por célula (auditoria Godot 4.7, §4): o motor só gera LOD na importação, e os lotes
## do ChunkCellMerge nascem em runtime sem nenhum. Aqui o lote passa por `ImporterMesh.generate_lods` (o mesmo
## simplificador da importação) **num trabalhador**, e o thread principal só monta a ArrayMesh com os índices
## de cada nível (`add_surface_from_arrays(..., lods)`), no mesmo commit que já existia.
##
## Desligado por padrão até o A/B: GETECO_PROC_LOD=1 liga.
##
## Câmera ortográfica: em projeção ortogonal o motor não usa a distância até a câmera para escolher o nível;
## a escolha depende só do tamanho da caixa da malha, do `size` da câmera (zoom) e de
## `mesh_lod_threshold` do viewport. Com o zoom do jogo quase fixo, cada lote tende a ficar sempre no
## mesmo nível, perto ou longe do jogador (inferência pelo código do motor, não está na doc). Ou seja: o
## ganho, se houver, é igual na tela toda, e o risco visual também. Não depende de distância.
##
## Cache só em memória, por sessão: o mesmo trecho volta muitas vezes (ida e volta da ponte) e o lote sai igual.
## A chave é o conteúdo do lote (hash das arrays de posição e índice, calculado no trabalhador). Cache em disco
## ficou de fora: a chave teria de cobrir versão do gerador, do motor e do simplificador para não servir índice
## de outro lote, e um índice errado vira triângulo voando — não é "simples e seguro".
static var enabled := OS.get_environment("GETECO_PROC_LOD") == "1"
## Abaixo disto o lote não ganha nada (caixas e peças simples não simplificam) e o trabalhador só custa.
const MIN_INDICES := 3000
## Ângulo de fusão de normais do importador (graus), o padrão da importação de cena.
const NORMAL_MERGE_ANGLE := 60.0
const MAX_CACHE := 512

static var _cache := {}
static var _cache_mutex := Mutex.new()

## O lote vale a ida ao trabalhador? Só em jogo (orçamento > 0): testes e censo montam no principal, e a regra
## é nunca simplificar no thread principal.
static func wanted(index_count: int, budget_usec: int) -> bool:
	return enabled and budget_usec > 0 and index_count >= MIN_INDICES

## Conta no trabalhador. Recebe as arrays prontas do lote e grava em `out`:
## - "lods": Dictionary {tamanho (float): PackedInt32Array} para add_surface_from_arrays;
## - "arrays": as arrays a usar (as de entrada, ou as que o importador devolveu se ele mexeu nos vértices).
## Sem "lods" (ou vazio), o chamador segue como antes, sem LOD.
static func generate(arrays: Array, out: Dictionary) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var key := hash([vertices.size(), indices.size(), hash(vertices.to_byte_array()), hash(indices.to_byte_array())])
	_cache_mutex.lock()
	var cached: Variant = _cache.get(key)
	_cache_mutex.unlock()
	if cached != null:
		out.lods = cached
		out.arrays = arrays
		out.cached = true
		return
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# O segundo argumento (normal_split_angle) não é mais usado pelo motor; fica só pela assinatura.
	importer.generate_lods(NORMAL_MERGE_ANGLE, 0.0, [])
	var lods := {}
	for lod in importer.get_surface_lod_count(0):
		var lod_indices := importer.get_surface_lod_indices(0, lod)
		# Nível que não tira nada (peça que já é mínima) só ocupa memória de índice.
		if lod_indices.is_empty() or lod_indices.size() >= indices.size(): continue
		lods[importer.get_surface_lod_size(0, lod)] = lod_indices
	# Os índices dos níveis apontam para os vértices que o importador guardou. Se ele mudou os vértices
	# (versões antigas separavam normais), usa as arrays dele e não guarda no cache, que só tem índices.
	var final_arrays := importer.get_surface_arrays(0)
	var final_vertices: PackedVector3Array = final_arrays[Mesh.ARRAY_VERTEX]
	var same := final_vertices == vertices
	out.arrays = arrays if same else final_arrays
	out.lods = lods
	out.cached = false
	if not same: return
	_cache_mutex.lock()
	if _cache.size() >= MAX_CACHE: _cache.clear()
	_cache[key] = lods
	_cache_mutex.unlock()

static func clear_cache() -> void:
	_cache_mutex.lock()
	_cache.clear()
	_cache_mutex.unlock()
