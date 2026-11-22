extends CanvasLayer
## The record ability's presentation: the screen effect, the timer ring, and a sound on
## each state change. Added by RecordManager, so it is present in every scene.

## Played when a record starts.
@export var record_sound : AudioStream
## Played when the rewind starts.
@export var rewind_sound : AudioStream
## Played when the phantom appears.
@export var phantom_sound : AudioStream
## Played when the phantom has finished.
@export var phantom_end_sound : AudioStream
## Played when the cooldown is over and the ability can be used again.
@export var ready_sound : AudioStream

## Seconds to fade the screen effect in and out.
@export var effect_fade_time : float = 0.2

@onready var _effect : ColorRect = $ScreenEffect
@onready var _sound : AudioStreamPlayer = $Sound

var _effect_material : ShaderMaterial
var _record_amount : float = 0.0
var _rewind_amount : float = 0.0

func _ready() -> void:
	_effect_material = _effect.material
	RecordManager.state_changed.connect(_on_state_changed)

func _process(delta: float) -> void:
	var recording := RecordManager.state == RecordManager.State.RECORDING
	var rewinding := RecordManager.state == RecordManager.State.REWINDING
	var step := delta / effect_fade_time
	_record_amount = move_toward(_record_amount, 1.0 if recording else 0.0, step)
	_rewind_amount = move_toward(_rewind_amount, 1.0 if rewinding else 0.0, step)

	_effect_material.set_shader_parameter("record_amount", _record_amount)
	_effect_material.set_shader_parameter("rewind_amount", _rewind_amount)
	# The effect reads the whole screen: skip it when it shows nothing
	_effect.visible = _record_amount > 0.0 or _rewind_amount > 0.0

func _on_state_changed(old_state: RecordManager.State, new_state: RecordManager.State) -> void:
	match new_state:
		RecordManager.State.RECORDING:
			_play(record_sound)
		RecordManager.State.REWINDING:
			_play(rewind_sound)
		RecordManager.State.REPLAY:
			_play(phantom_sound)
		RecordManager.State.COOLDOWN:
			_play(phantom_end_sound)
		RecordManager.State.IDLE:
			if old_state == RecordManager.State.COOLDOWN:
				_play(ready_sound)

func _play(stream: AudioStream) -> void:
	if stream:
		_sound.stream = stream
		_sound.play()
