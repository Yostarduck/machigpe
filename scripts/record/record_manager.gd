extends Node
## Record & rewind state machine (autoload: RecordManager).
## See misc/RecordMechanic.md for the design.

## Emitted on every state change.
signal state_changed(old_state: State, new_state: State)
## Emitted on the tick that applies frame 0. Recordables release their targets here, so
## they simulate again from the next tick, which is the first REPLAY tick.
signal rewind_finished

enum State { IDLE, RECORDING, REWINDING, REPLAY, COOLDOWN }

## Maximum length of a record, in physics ticks (600 = 10 s at 60 ticks per second).
## A record can be stopped earlier with stop_record().
const RECORD_FRAMES := 600

## Length of the cooldown that starts when the phantom finishes, in physics ticks.
var cooldown_frames : int = 300
## Recorded frames rewound per physics tick (1.0 = same speed as the record).
var rewind_speed : float = 3

var state : State = State.IDLE
## Ticks spent in the current state (used by REPLAY and COOLDOWN).
var tick : int = 0
## Frames captured by the current record.
var frames_recorded : int = 0
## Frame being applied while rewinding. A float so rewind_speed can be fractional.
## -1 once frame 0 has been applied.
var playhead : float = 0.0

var _record_requested : bool = false
var _stop_requested : bool = false
var _recordables : Array[Recordable] = []
var _tape_source : RewindAbility
# The player's recorded transforms, played back by the phantom during REPLAY
var _tape : Array[Transform3D] = []
# The player's recorded states, for the phantom's animation
var _tape_states : Array[Dictionary] = []
var _phantom : Node3D
# Frame 0 has been applied once as an approach (see _rewind_tick)
var _approached : bool = false
# Discrete actions of the player (interact, shoot), by frame: {frame: [event, ...]}.
# The phantom performs them on the same replay tick.
var _events : Dictionary = {}

func _ready() -> void:
	# Run before every gameplay script, so a capture sees the end of the previous tick
	# for every object (characters and rigid bodies alike)
	process_physics_priority = -1000
	add_child(preload("res://scripts/record/record_debug_overlay.gd").new())
	add_child(preload("res://prefabs/record/record_hud.tscn").instantiate())

## Asks to start a record. It begins at the start of the next physics tick, so frame 0
## is captured before any gameplay code of that tick runs.
## Returns false if a record can't start now.
func start_record() -> bool:
	if state != State.IDLE:
		return false
	_record_requested = true
	return true

## Asks to end the current record early. The frame of this tick, already captured, is the
## last one: the rewind starts at the next physics tick, and the phantom plays only the
## recorded frames. Returns false if no record is running.
func stop_record() -> bool:
	if state != State.RECORDING:
		return false
	_stop_requested = true
	return true

func is_rewinding() -> bool:
	return state == State.REWINDING

## Cancels a record, dismisses the phantom and clears the cooldown. Used on death and
## level transitions; nothing is rewound.
func reset() -> void:
	_record_requested = false
	_stop_requested = false
	_approached = false
	_dismiss_phantom(false)
	_tape.clear()
	_tape_states.clear()
	_events.clear()
	frames_recorded = 0
	playhead = 0.0
	_change_state(State.IDLE)

## Adds a recordable to the per-tick capture and apply loops. Called by Recordable.
func register(recordable: Recordable) -> void:
	if not _recordables.has(recordable):
		_recordables.append(recordable)

## Removes a recordable from the loops. Called by Recordable.
func unregister(recordable: Recordable) -> void:
	_recordables.erase(recordable)

## Records a discrete action of the player on the tape, for the phantom to perform on
## the same tick: {"type": &"interact"} or {"type": &"shoot", "shot": ...}.
## Ignored outside a record.
func record_event(event: Dictionary) -> void:
	if state != State.RECORDING:
		return
	# The manager runs first in the tick, so the frame of this tick is already captured
	var frame := frames_recorded - 1
	if not _events.has(frame):
		_events[frame] = []
	_events[frame].append(event)

func get_event_count() -> int:
	var count := 0
	for frame_events in _events.values():
		count += frame_events.size()
	return count

## Sets the ability whose Recordable becomes the tape and whose phantom plays it.
func set_tape_source(ability: RewindAbility) -> void:
	_tape_source = ability

func clear_tape_source(ability: RewindAbility) -> void:
	if _tape_source == ability:
		_tape_source = null

func get_recordable_count() -> int:
	return _recordables.size()

func _physics_process(_delta: float) -> void:
	match state:
		State.IDLE:
			if _record_requested:
				_record_requested = false
				frames_recorded = 0
				_events.clear()
				_change_state(State.RECORDING)
				_record_tick()
		State.RECORDING:
			if frames_recorded >= RECORD_FRAMES or _stop_requested:
				_stop_requested = false
				playhead = frames_recorded - 1
				_change_state(State.REWINDING)
				_rewind_tick()
			else:
				_record_tick()
		State.REWINDING:
			if playhead < 0.0:
				# Frame 0 was applied last tick and the world was released: from this tick on
				# it simulates again, and the phantom plays the tape
				_change_state(State.REPLAY)
				_spawn_phantom()
				_replay_tick()
			else:
				_rewind_tick()
		State.REPLAY:
			if tick >= frames_recorded:
				_dismiss_phantom(true)
				_tape.clear()
				_tape_states.clear()
				_events.clear()
				_change_state(State.COOLDOWN)
			else:
				_replay_tick()
		State.COOLDOWN:
			tick += 1
			if tick >= cooldown_frames:
				_change_state(State.IDLE)

func _record_tick() -> void:
	for recordable in _recordables:
		recordable.capture(frames_recorded)
	frames_recorded += 1

func _rewind_tick() -> void:
	var frame := roundi(playhead)
	# Frame 0 is applied on two ticks, the first one as an approach: moving platforms are
	# placed one tick before frame 0, so their final move into frame 0 has their frame 0
	# velocity, which is what the physics engine (and anyone standing on them) reads
	# when the world is released. See Recordable.apply().
	var approach := frame <= 0 and not _approached
	for recordable in _recordables:
		recordable.apply(frame, approach)
	if frame > 0:
		playhead = maxf(playhead - rewind_speed, 0.0)
	elif approach:
		_approached = true
	else:
		_approached = false
		# Keep the player's frames for the phantom before the recordables drop their buffers
		_tape = _tape_source.recordable.get_transforms() if _tape_source else []
		_tape_states = _tape_source.recordable.get_states() if _tape_source else []
		# Nodes re-enabled during a tick only process from the next one, so the world is
		# released now and REPLAY starts at the top of the next tick
		playhead = -1.0
		rewind_finished.emit()

# Replay tick k shows frame k, the state at the start of record tick k. Measured with a
# pressure plate: this makes the phantom trigger areas on the same ticks the player did
# (the player's body overlaps are reported one tick after its move, a placed area's
# aren't, so showing frame k + 1 triggered one tick early).
func _replay_tick() -> void:
	if is_instance_valid(_phantom):
		_phantom.show_frame(_tape[tick], _tape_states[tick] if tick < _tape_states.size() else {})
		for event in _events.get(tick, []):
			_phantom.perform(event)
	tick += 1

func _spawn_phantom() -> void:
	if _tape.is_empty() or not _tape_source.phantom_scene:
		return
	_phantom = _tape_source.phantom_scene.instantiate()
	get_tree().current_scene.add_child(_phantom)

# fade: play the exit effect (end of the tape), or remove it at once (reset)
func _dismiss_phantom(fade: bool) -> void:
	if is_instance_valid(_phantom):
		if fade:
			_phantom.finish()
		else:
			_phantom.queue_free()
	_phantom = null

func _change_state(new_state: State) -> void:
	var old_state := state
	state = new_state
	tick = 0
	if old_state != new_state:
		state_changed.emit(old_state, new_state)
