extends CanvasLayer
## On-screen readout of the RecordManager state. Toggle with F3.

var _manager : Node
var _label : Label

func _ready() -> void:
	_manager = get_parent()
	layer = 100

	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_constant_override("outline_size", 6)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_label)

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F3:
		visible = not visible

func _process(_delta: float) -> void:
	var State = _manager.State
	var lines : PackedStringArray = []
	lines.append("Record: %s" % State.keys()[_manager.state])

	match _manager.state:
		State.IDLE:
			lines.append("ready")
		State.RECORDING:
			lines.append(_progress(_manager.frames_recorded, _manager.RECORD_FRAMES))
		State.REWINDING:
			lines.append("frame %d  (x%.1f)" % [maxi(roundi(_manager.playhead), 0), _manager.rewind_speed])
		State.REPLAY:
			lines.append(_progress(_manager.tick, _manager.frames_recorded))
		State.COOLDOWN:
			lines.append(_progress(_manager.tick, _manager.cooldown_frames))

	lines.append("recordables: %d  events: %d" % [_manager.get_recordable_count(), _manager.get_event_count()])
	var player := get_tree().get_first_node_in_group("player")
	lines.append("score: %d  health: %s  checkpoint: %s" % [
		GameState.score, player.health if player else "-", "yes" if GameState.has_checkpoint else "no"])
	lines.append("physics: %d ticks/s" % Engine.physics_ticks_per_second)
	_label.text = "\n".join(lines)

func _progress(current: int, total: int) -> String:
	var ticks_per_second := float(Engine.physics_ticks_per_second)
	return "%d / %d frames  (%.1f s / %.1f s)" % [
		current, total, current / ticks_per_second, total / ticks_per_second]
