@tool
extends EditorPlugin

const GizmoPlugin := preload("res://addons/prototype_platform/prototype_platform_gizmo.gd")

var _gizmo_plugin : EditorNode3DGizmoPlugin

func _enter_tree() -> void:
	_gizmo_plugin = GizmoPlugin.new(get_undo_redo())
	add_node_3d_gizmo_plugin(_gizmo_plugin)

func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(_gizmo_plugin)
	_gizmo_plugin = null
