@tool
extends EditorPlugin
## Registers the Mover pose B gizmo and keeps it in sync with the selection (the phantom is
## only drawn for selected movers) and with edits made in the inspector (Mover is not a
## @tool script, so its setters don't refresh the gizmo themselves).

const GizmoPlugin := preload("res://addons/mover_preview/mover_gizmo.gd")

var _gizmo_plugin : EditorNode3DGizmoPlugin
var _shown : Array[Node3D] = []

func _enter_tree() -> void:
	_gizmo_plugin = GizmoPlugin.new(get_undo_redo())
	add_node_3d_gizmo_plugin(_gizmo_plugin)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	EditorInterface.get_inspector().property_edited.connect(_on_property_edited)

func _exit_tree() -> void:
	EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)
	EditorInterface.get_inspector().property_edited.disconnect(_on_property_edited)
	remove_node_3d_gizmo_plugin(_gizmo_plugin)
	_gizmo_plugin = null
	_shown.clear()

func _on_selection_changed() -> void:
	# Redraw the movers that lost the selection (hides their phantom) and the new ones
	for node in _shown:
		if is_instance_valid(node):
			node.update_gizmos()
	_shown.clear()
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is Node3D and GizmoPlugin.is_mover(node):
			_shown.append(node)
			node.update_gizmos()

func _on_property_edited(_property: String) -> void:
	var edited := EditorInterface.get_inspector().get_edited_object()
	if edited is Node3D and GizmoPlugin.is_mover(edited):
		edited.update_gizmos()
