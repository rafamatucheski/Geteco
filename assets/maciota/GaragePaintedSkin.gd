extends RefCounted
## Fachada pintada (PaintedFacadeKit) da garagem "Piston & Co" e do anexo ao lado.
##
## As caixas antigas continuam na cena: MaciotaPlace deriva a colisão do AABB das malhas
## com `interior_solid_id`, então só o visual delas (e o letreiro MACIOTA, o neon e o totem)
## é escondido. A pintura traz o letreiro novo, o portão de 6 m sem folha (a entrada continua
## sendo o ponto de interação em frente ao vão) e a porta de serviço do fundo.
## Interruptor: GETECO_PAINTED_GARAGE=0 (ou GETECO_PAINTED_FACADES=0) volta ao 3D antigo.

const MAIN_STYLE := "garagem-piston"
const ANNEX_STYLE := "anexo-piston"
const MAIN := Vector3(7.8, 4.4, 6.25)
const ANNEX := Vector3(5.6, 3.8, 6.25)
const MAIN_X := -2.0
const ANNEX_X := 6.1


static func enabled() -> bool:
	return PaintedFacadeKit.enabled() and OS.get_environment("GETECO_PAINTED_GARAGE") != "0"


static func apply(facade: Node3D, center_z: float) -> void:
	for node in facade.get_children():
		if node is MeshInstance3D or node is Label3D: (node as Node3D).visible = false
	_place(facade, MAIN_STYLE, MAIN, Vector3(MAIN_X, 0, center_z))
	_place(facade, ANNEX_STYLE, ANNEX, Vector3(ANNEX_X, 0, center_z))


static func _place(facade: Node3D, style: String, size: Vector3, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.name = "Painted_" + style
	holder.position = at
	facade.add_child(holder)
	PaintedFacadeKit.build(holder, style, size, null, NAN, {"snow": false})
