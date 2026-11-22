extends Area3D
## Sets the respawn point when the live player touches it. The phantom never triggers it
## (D13): the mask is the player layer and it checks the "player" group. It is persistent
## progress, so a rewind doesn't undo it (D19): no Recordable.

@export var color_inactive : Color = Color(0.5, 0.5, 0.55)
@export var color_active : Color = Color(0.3, 0.6, 1.0)

@onready var _flag : MeshInstance3D = $Flag

var _material := StandardMaterial3D.new()

func _ready() -> void:
	_flag.material_override = _material
	body_entered.connect(_on_body_entered)
	GameState.checkpoint_changed.connect(_on_checkpoint_changed)
	_on_checkpoint_changed(null)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not RecordManager.is_rewinding():
		GameState.set_checkpoint(self)

func _on_checkpoint_changed(checkpoint: Node3D) -> void:
	_material.albedo_color = color_active if checkpoint == self else color_inactive
