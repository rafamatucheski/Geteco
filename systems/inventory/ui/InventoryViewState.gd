extends Control
const GRID := preload("res://systems/inventory/GridInventory.gd")
const BOARD := preload("res://systems/inventory/ui/GridBoard.gd")
const ICONS := preload("res://systems/inventory/InventoryIcons.gd")
var adapter
var selected_container := ""
var selected_index := -1
var equipment_id := ""
var trunk_visible := false
var body: HBoxContainer
var details: VBoxContainer
var card: PanelContainer
var feedback: Label

