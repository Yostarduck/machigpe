class_name KeyGroup
extends PuzzleKey
## A group of keys, usually buttons or torches, that works as one key (I9):
##
##   stay_on = false   on while all members are on at the same time
##   stay_on = true    once all members are on together, the members stay on for good
##                     (their timers stop) and so does the group
##
## Activables list the group as one of their keys. Its state is recorded (Recordable
## child), and so is each member's lock, so a rewind undoes a completed group (I10).

## Members; all must be on.
@export var members : Array[PuzzleKey] = []
## Once complete, stay on for good and keep the members on.
@export var stay_on : bool = false

## Stay-on group that has been completed.
var completed : bool = false

func _physics_process(_delta: float) -> void:
	if completed:
		return
	var all_on := not members.is_empty()
	for member in members:
		if member == null or not member.on:
			all_on = false
			break
	if all_on and stay_on:
		completed = true
		for member in members:
			if member is TimedKey:
				member.lock()
	set_on(all_on)

func _record_state() -> Dictionary:
	var state := super()
	state.completed = completed
	return state

func _apply_state(state: Dictionary) -> void:
	completed = state.completed
	super(state)
