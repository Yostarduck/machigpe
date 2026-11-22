extends PuzzleKey
## Two-state switch, toggled by interacting with it (InteractSensor), by the player or
## the phantom. Stays on until toggled again. Its state is recorded (Recordable child),
## so a rewind undoes toggles made during the record.

@export var accepts_player : bool = true
@export var accepts_phantom : bool = true
## Handle tilt in each state, in degrees.
@export var handle_angle : float = 35.0
@export var color_off : Color = Color(0.8, 0.25, 0.2)
@export var color_on : Color = Color(0.3, 0.85, 0.3)

@onready var _handle : Node3D = $Handle
@onready var _handle_mesh : MeshInstance3D = $Handle/MeshInstance3D

var _material := StandardMaterial3D.new()

func _ready() -> void:
	_handle_mesh.material_override = _material
	super()

## Toggles the lever, if the actor (player or phantom) is accepted.
func interact(actor: Node3D) -> void:
	if accepts_actor(actor, accepts_player, accepts_phantom):
		set_on(not on)

func _update_visuals() -> void:
	_handle.rotation_degrees.x = handle_angle if on else -handle_angle
	_material.albedo_color = color_on if on else color_off
