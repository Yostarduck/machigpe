class_name TimedKey
extends PuzzleKey
## A key that turns on for a while, then off: base of buttons and torches
## (misc/Interactables.md). Attacks turn it on for a time that depends on their strength:
##
##   weak attack     short_time
##   normal attack   normal_time
##   strong attack   long_time
##
## Turning it on again keeps the longer time (I6): the time left becomes
## max(time left, new duration). The time left is recorded with the state (Recordable child).

@export_group("On time")
## Seconds on after a weak attack (buttons: also after an interact).
@export var short_time : float = 3.0
## Seconds on after a normal attack.
@export var normal_time : float = 6.0
## Seconds on after a strong attack.
@export var long_time : float = 10.0
@export_group("")

## Seconds left before it turns off.
var time_left : float = 0.0
## Kept on for good by a stay-on KeyGroup: the time left doesn't run down.
var locked : bool = false

func _ready() -> void:
	# Shots are auto aimed at buttons and torches (PlayerAttack)
	add_to_group(PlayerAttack.AIM_GROUP)
	super()

func _physics_process(delta: float) -> void:
	if locked or time_left <= 0.0:
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		set_on(false)

## Hit by a projectile (I8).
func hit_by_attack(strength: int, _damage: int) -> void:
	match strength:
		PlayerAttack.Strength.STRONG:
			press(long_time)
		PlayerAttack.Strength.NORMAL:
			press(normal_time)
		_:
			press(short_time)

## Keeps it on for good (a stay-on KeyGroup was completed).
func lock() -> void:
	locked = true
	set_on(true)
	_update_visuals()

## On for `duration` seconds, unless more time is already left (I6).
func press(duration: float) -> void:
	time_left = maxf(time_left, duration)
	set_on(true)

func _record_state() -> Dictionary:
	var state := super()
	state.time_left = time_left
	state.locked = locked
	return state

func _apply_state(state: Dictionary) -> void:
	time_left = state.time_left
	locked = state.locked
	super(state)
