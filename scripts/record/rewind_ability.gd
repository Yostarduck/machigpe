class_name RewindAbility
extends Node
## The player's record ability. Decides whether a record may start, and tells the
## RecordManager which Recordable becomes the phantom's tape and which phantom plays it.

## Whether the player has the ability (later it may be granted by an item).
@export var unlocked : bool = true
## Recordable whose recorded transforms become the phantom's tape.
@export var recordable : Recordable
## Scene spawned to play back the tape.
@export var phantom_scene : PackedScene = preload("res://prefabs/record/phantom.tscn")

func _enter_tree() -> void:
	RecordManager.set_tape_source(self)

func _ready() -> void:
	# A real death cancels a record, or ends the phantom and the cooldown (D14, D20)
	get_parent().died.connect(RecordManager.reset)
	_warm_up_phantom.call_deferred()

# Draws an invisible phantom on the player for a few frames, so its shaders are compiled
# at level start instead of when the first phantom appears (see Phantom.warm_up)
func _warm_up_phantom() -> void:
	if not phantom_scene:
		return
	var phantom := phantom_scene.instantiate()
	phantom.warm_up()
	get_tree().current_scene.add_child(phantom)
	phantom.global_transform = get_parent().global_transform

func _exit_tree() -> void:
	RecordManager.clear_tape_source(self)

func can_use() -> bool:
	return unlocked and RecordManager.state == RecordManager.State.IDLE

## Starts a record if the ability can be used, or ends the running record early.
## Returns whether a record started or was stopped.
func try_use() -> bool:
	if RecordManager.state == RecordManager.State.RECORDING:
		return RecordManager.stop_record()
	if not can_use():
		return false
	return RecordManager.start_record()
