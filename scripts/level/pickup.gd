extends Area3D
## Collectible that adds to the score. Only the live player collects it: its mask is the
## player layer and it checks the "player" group, so the phantom can't (D13).
## The collected flag is recorded (Recordable child), so a rewind puts it back, and
## GameState restores the score.

@export var value : int = 1
## Visual spin, in radians per second.
@export var spin_speed : float = 2.0

var collected : bool = false

@onready var _mesh : Node3D = $MeshInstance3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_mesh.rotate_y(spin_speed * delta)

func _on_body_entered(body: Node3D) -> void:
	# During a rewind the player passes over pickups at recorded positions: not a collect
	if collected or not body.is_in_group("player") or RecordManager.is_rewinding():
		return
	collected = true
	_update()
	GameState.add_score(value)

# Rewind hooks (see Recordable)
func _record_state() -> Dictionary:
	return {"collected": collected}

func _apply_state(state: Dictionary) -> void:
	collected = state.collected
	_update()

func _update() -> void:
	visible = not collected
	# Deferred: collecting happens inside a physics callback
	set_deferred("monitoring", not collected)
