@tool
extends EditorPlugin

## Editor entry point for dot-objective. Registers inspector types only.
##
## No autoloads. An objective manager is a tempting singleton and it is the wrong shape
## twice over: a server that simulates and a client that mirrors are two of them in one
## process, and a suite that plays both halves of a capture is a third.

const _ICON := "res://addons/dot_objective/icon_placeholder.svg"

const _TYPES := [
	[
		"DotObjectiveManager",
		"Node",
		"res://addons/dot_objective/runtime/dot_objective_manager.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
