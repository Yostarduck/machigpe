class_name PuzzleKey
extends Node3D
## Base of every key (misc/Interactables.md): levers, pressure plates, buttons, torches,
## key groups. A key has a state, `on`, and tells when it changes (I1). Activables list
## their keys and read `on`; keys don't know who listens (I3).
##
## Subclasses change the state with set_on() and draw it in _update_visuals().

## Emitted when `on` changes, except while a rewind places recorded states: activables
## record their own state, and read the keys' `on` again when the rewind ends.
signal on_changed(on: bool)

## Starting state; then the key's current state.
@export var on : bool = false

func _ready() -> void:
	_update_visuals()

## Sets the state, updating visuals and notifying listeners if it changed.
func set_on(value: bool) -> void:
	if value == on:
		return
	on = value
	_update_visuals()
	if not RecordManager.is_rewinding():
		on_changed.emit(on)

## True if `actor` (the player or the phantom) passes the accepts_* filters.
static func accepts_actor(actor: Node, accepts_player: bool, accepts_phantom: bool) -> bool:
	if actor.is_in_group(&"phantom"):
		return accepts_phantom
	if actor.is_in_group(&"player"):
		return accepts_player
	return false

# Rewind hooks (see Recordable), for keys with a Recordable child. Applying a state
# doesn't emit on_changed. Subclasses with more state extend both.
func _record_state() -> Dictionary:
	return {"on": on}

func _apply_state(state: Dictionary) -> void:
	on = state.on
	_update_visuals()

## Shows the current state. Override in subclasses.
func _update_visuals() -> void:
	pass
