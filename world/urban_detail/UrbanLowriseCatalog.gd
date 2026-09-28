@tool
extends RefCounted
const TYPES := ["house_gable","house_duplex","warehouse_sawtooth","warehouse_loading"]
const LABELS := ["Casa com telhado inclinado","Sobrado geminado","Galpão com sheds","Galpão com docas"]
const PRESETS := [
	["Casa compacta","house_gable",[7,9],4.8,"c5b18f"],
	["Casa ampla","house_gable",[11,12],6,"a9b3a1"],
	["Sobrado geminado compacto","house_duplex",[10,10],7,"aa8064"],
	["Sobrado geminado largo","house_duplex",[16,12],9,"b8aa91"],
	["Galpão de sheds pequeno","warehouse_sawtooth",[14,18],6,"9d9987"],
	["Galpão de sheds grande","warehouse_sawtooth",[24,30],9,"869c96"],
	["Galpão com duas docas","warehouse_loading",[16,14],7,"8c9a9e"],
	["Galpão com quatro docas","warehouse_loading",[30,22],10,"a59880"],
]
