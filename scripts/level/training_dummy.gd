extends StaticBody3D
## Target for the attack. Its health is recorded (Recordable child), so a rewind brings it
## back. At 0 health it is deactivated (hidden, no collision) instead of freed, so the
## rewind has something to bring back.

signal died

@export var max_health : int = 5
@export var color_full : Color = Color(0.85, 0.75, 0.55)
@export var color_hurt : Color = Color(0.9, 0.2, 0.15)

var health : int

@onready var _shape : CollisionShape3D = $CollisionShape3D
@onready var _mesh : MeshInstance3D = $MeshInstance3D

var _material := StandardMaterial3D.new()

func _ready() -> void:
	health = max_health
	_mesh.material_override = _material
	_update()

func take_damage(amount: int) -> void:
	if health <= 0:
		return
	health = maxi(health - amount, 0)
	_update()
	if health == 0:
		died.emit()

# Rewind hooks (see Recordable)
func _record_state() -> Dictionary:
	return {"health": health}

func _apply_state(state: Dictionary) -> void:
	health = state.health
	_update()

func _update() -> void:
	var alive := health > 0
	visible = alive
	# Deferred: take_damage() runs inside a physics callback
	_shape.set_deferred("disabled", not alive)
	_material.albedo_color = color_hurt.lerp(color_full, float(health) / max_health)
