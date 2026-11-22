extends Area3D
## Takes the live player to another scene. The phantom can't use it (mask and "player"
## group). Changing scene cancels any record and removes the phantom (D16).

@export_file("*.tscn") var target_scene : String

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if target_scene.is_empty() or not body.is_in_group("player") or RecordManager.is_rewinding():
		return
	RecordManager.reset()
	# Checkpoints belong to the level being left
	GameState.clear_checkpoint()
	get_tree().change_scene_to_file.call_deferred(target_scene)
