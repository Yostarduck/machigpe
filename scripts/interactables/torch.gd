extends TimedKey
## Torch (misc/Interactables.md, I7). Lit only by attacks, for a time that depends on
## their strength (see TimedKey); hitting it again keeps the longer time.
##
## Two parts react to shots. The pillar (Body) is solid: a shot that hits it lights the
## torch and is destroyed. The flame zone above it (FlameZone, a shot trigger) is not: a
## shot passing over the pillar, through the bowl or just above it, lights the torch and
## keeps flying.
##
## In its last warning_time seconds the flame and its light shrink, so the player can
## see it is about to go out. Locked by a stay-on KeyGroup, it burns at full size.

@export_group("Look")
## Seconds before going out during which the flame shrinks.
@export var warning_time : float = 2.0
## Flame size just before going out, relative to its full size.
@export var min_flame_scale : float = 0.25

@onready var _flame : Node3D = $Flame
@onready var _light : OmniLight3D = $Flame/OmniLight3D

var _light_energy : float

func _ready() -> void:
	_light_energy = _light.light_energy
	super()

# Every frame: the time left changes every tick, and is also set by the rewind
func _process(_delta: float) -> void:
	_update_flame()

func _update_visuals() -> void:
	_update_flame()

func _update_flame() -> void:
	_flame.visible = on
	if not on:
		return
	var size := 1.0
	if not locked and warning_time > 0.0 and time_left < warning_time:
		size = lerpf(min_flame_scale, 1.0, time_left / warning_time)
	_flame.scale = Vector3.ONE * size
	_light.light_energy = _light_energy * size
