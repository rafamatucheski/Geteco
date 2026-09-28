@tool
extends RefCounted
## Dimensions are metres: width, depth, total body height. Stable model IDs
## are shared by the editor library, saved documents and production factory.
const TYPES := ["urban_setback","urban_twin","urban_slab","urban_deco","urban_infill","urban_podium"]
const LABELS := ["Torre escalonada","Torres gêmeas","Residencial com varandas","Torre art déco","Prédio estreito","Torre sobre base comercial"]
const PRESETS := [
	["Torre escalonada média","urban_setback",[14,12],22,"b9ac94"],
	["Torre escalonada alta","urban_setback",[18,16],32,"9baba8"],
	["Torres gêmeas compactas","urban_twin",[18,14],24,"81999e"],
	["Torres gêmeas altas","urban_twin",[24,18],36,"8c9f9c"],
	["Residencial com varandas compacto","urban_slab",[16,10],12,"b9a58c"],
	["Residencial com varandas largo","urban_slab",[24,12],20,"a7aea0"],
	["Torre art déco média","urban_deco",[10,12],20,"c0ab88"],
	["Torre art déco alta","urban_deco",[14,14],30,"b5b5a5"],
	["Prédio estreito de tijolos","urban_infill",[6,9],12,"91634e"],
	["Prédio estreito alto","urban_infill",[8,12],18,"aa8065"],
	["Torre de vidro compacta","urban_podium",[18,16],26,"839b9d"],
	["Torre de vidro alta","urban_podium",[26,22],38,"819496"],
]
