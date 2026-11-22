extends Node
## Game rules and progress (autoload: GameState). See misc/RecordMechanic.md §4.4.
##
## Run state (score) rewinds: it is saved when a record starts and restored when the
## rewind reaches frame 0. Persistent progress (checkpoints) never rewinds (D19, D23).

signal score_changed(score: int)
## The checkpoint node that became active, or null when cleared.
signal checkpoint_changed(checkpoint: Node3D)

# Run state: rewinds
var score : int = 0

# Persistent progress: never rewinds
var has_checkpoint : bool = false
var checkpoint_transform : Transform3D

var _snapshot : Dictionary = {}

func _ready() -> void:
	RecordManager.state_changed.connect(_on_record_state_changed)
	RecordManager.rewind_finished.connect(_restore_snapshot)

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func set_checkpoint(checkpoint: Node3D) -> void:
	has_checkpoint = true
	checkpoint_transform = checkpoint.global_transform
	checkpoint_changed.emit(checkpoint)

func clear_checkpoint() -> void:
	has_checkpoint = false
	checkpoint_changed.emit(null)

func _on_record_state_changed(_old_state: RecordManager.State, new_state: RecordManager.State) -> void:
	match new_state:
		RecordManager.State.RECORDING:
			_snapshot = {"score": score}
		RecordManager.State.IDLE:
			# Cancelled record (death, transition): nothing is restored (D14)
			_snapshot.clear()

func _restore_snapshot() -> void:
	if _snapshot.is_empty():
		return
	score = _snapshot.score
	_snapshot.clear()
	score_changed.emit(score)
