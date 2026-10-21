extends "res://gameplay/desert_heist/DesertCargoTruckVisual.gd"
## O caminhão da blitz: o de carga do deserto com a cabine oca do lado do motorista. No original a
## cabine é um bloco maciço com vidro escuro (no jogo ninguém olha para dentro); aqui a porta abre e
## Vicente tem que aparecer ao volante. O bloco vira piso, paredes, painel e bancos, e o vidro lateral
## do motorista sai (quem fecha o vão é a porta da cena). Montado uma vez, sob a cortina, e guardado
## como cena para o flashback do ato 2 não montar de novo.
const CAB_BLOCK := Vector3(0, 1.47, -3.23)
const DRIVER_GLASS := Vector3(-1.12, 2.53, -3.37)
static var _open_template: PackedScene

static func create_open() -> Node3D:
	if _open_template == null:
		# Malhas base (caixa e cilindro) do caminhão original.
		prewarm()
		var builder = new()
		var root: Node3D = builder._build()
		root.name = "BlitzTruck"
		_assign_owner(root, root)
		_open_template = PackedScene.new()
		_open_template.pack(root)
		root.free()
	return _open_template.instantiate() as Node3D

func box(at: Vector3, size: Vector3, finish: String, rotation := Vector3.ZERO) -> void:
	if finish == "glass" and at.is_equal_approx(DRIVER_GLASS): return
	if finish == "paint" and at.is_equal_approx(CAB_BLOCK):
		_open_cab()
		return
	super(at, size, finish, rotation)

func _open_cab() -> void:
	# Mesmo volume externo do bloco (2,22 x 1,32 x 1,75), agora oco: o vão da porta vai de z -3,96 a -2,85.
	super.box(Vector3(0, .98, -3.23), Vector3(2.22, .34, 1.75), "paint")
	super.box(Vector3(0, 1.165, -3.23), Vector3(2.1, .03, 1.65), "rubber")
	super.box(Vector3(1.06, 1.64, -3.23), Vector3(.1, .98, 1.75), "paint")
	super.box(Vector3(-1.06, 1.64, -4.03), Vector3(.1, .98, .15), "paint")
	super.box(Vector3(-1.06, 1.64, -2.6), Vector3(.1, .98, .49), "paint")
	super.box(Vector3(0, 1.64, -4.06), Vector3(2.22, .98, .09), "paint")
	super.box(Vector3(0, 1.64, -2.4), Vector3(2.22, .98, .09), "paint")
	# Painel, coluna de direção e os dois bancos (assento na altura do quadril de quem senta: piso + 0,45).
	super.box(Vector3(0, 1.88, -3.9), Vector3(2.0, .3, .3), "chassis")
	super.box(Vector3(-.55, 1.97, -3.78), Vector3(.07, .07, .3), "chassis", Vector3(-.55, 0, 0))
	for x in [-.55, .55]:
		super.box(Vector3(x, 1.53, -3.3), Vector3(.56, .14, .52), "rubber")
		super.box(Vector3(x, 1.96, -3.0), Vector3(.56, .74, .12), "rubber", Vector3(.12, 0, 0))
