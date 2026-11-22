extends Control
## Ring showing the record ability's timer, with the seconds left in the middle and the
## current phase below: REC (time left to record), REWIND (time left to rewind),
## PHANTOM (time left of the phantom), COOLDOWN (filling up until ready), READY.

@export var radius : float = 30.0
@export var thickness : float = 6.0
@export var color_back : Color = Color(1, 1, 1, 0.15)
@export var color_ready : Color = Color(1, 1, 1, 0.7)
@export var color_record : Color = Color(1.0, 0.25, 0.2)
@export var color_rewind : Color = Color(0.45, 0.7, 1.0)
@export var color_phantom : Color = Color(0.45, 0.85, 1.0)
@export var color_cooldown : Color = Color(0.6, 0.6, 0.65)

@onready var _seconds : Label = $Seconds
@onready var _caption : Label = $Caption

var _fraction : float = 0.0
var _color : Color

func _process(_delta: float) -> void:
	var rm := RecordManager
	var frames_left := 0
	var caption := ""
	_color = color_ready
	match rm.state:
		rm.State.IDLE:
			var ability := _find_ability()
			visible = ability != null and ability.unlocked
			_fraction = 1.0
			caption = "READY"
		rm.State.RECORDING:
			frames_left = rm.RECORD_FRAMES - rm.frames_recorded
			_fraction = float(frames_left) / rm.RECORD_FRAMES
			_color = color_record
			caption = "REC"
		rm.State.REWINDING:
			frames_left = maxi(ceili(rm.playhead / rm.rewind_speed), 0)
			_fraction = maxf(rm.playhead, 0.0) / maxi(rm.frames_recorded, 1)
			_color = color_rewind
			caption = "REWIND"
		rm.State.REPLAY:
			frames_left = rm.frames_recorded - rm.tick
			_fraction = float(frames_left) / maxi(rm.frames_recorded, 1)
			_color = color_phantom
			caption = "PHANTOM"
		rm.State.COOLDOWN:
			frames_left = rm.cooldown_frames - rm.tick
			_fraction = float(rm.tick) / maxi(rm.cooldown_frames, 1)
			_color = color_cooldown
			caption = "COOLDOWN"
	if rm.state != rm.State.IDLE:
		visible = true

	_seconds.text = "%d" % ceili(frames_left / float(Engine.physics_ticks_per_second)) if frames_left > 0 else ""
	_seconds.modulate = _color
	_caption.text = caption
	_caption.modulate = _color
	queue_redraw()

func _draw() -> void:
	var center := Vector2(size.x / 2.0, radius + thickness)
	draw_arc(center, radius, 0.0, TAU, 64, color_back, thickness, true)
	if _fraction > 0.0:
		draw_arc(center, radius, -PI / 2.0, -PI / 2.0 + TAU * _fraction, 64, _color, thickness, true)

func _find_ability() -> RewindAbility:
	var player := get_tree().get_first_node_in_group("player")
	return player.get_node_or_null("RewindAbility") if player else null
