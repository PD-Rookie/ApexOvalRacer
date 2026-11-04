extends Camera3D
## Smooth third-person chase camera.
##
## The follow position is based on the car's heading, blended with its velocity
## direction at speed. Exponential smoothing keeps sudden heading changes from
## snapping the camera, and the FOV widens with speed for an arcade sense of
## pace. Runs in _process so camera motion stays smooth even if the physics
## tick differs from the render rate.

@export var target: VehicleBody3D
@export var follow_distance := 6.2
@export var follow_height := 2.25
@export var look_ahead := 4.0
@export var look_height := 0.9
@export var position_smoothing := 5.5
@export var look_smoothing := 7.0
@export var velocity_heading_blend := 0.35
@export var min_velocity_heading := 3.0
@export var base_fov := 68.0
@export var max_fov := 82.0
@export var fov_max_speed := 38.0
@export var fov_smoothing := 2.5
@export var nitrous_fov_boost := 7.0

var _look_target := Vector3.ZERO


func _ready() -> void:
	current = true
	if target == null:
		var car := get_tree().get_first_node_in_group("player_car")
		if car is VehicleBody3D:
			target = car as VehicleBody3D
	snap_to_target()


func _process(delta: float) -> void:
	if target == null:
		return

	var car_position := target.global_position
	var forward := target.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, 1.0)
	forward = forward.normalized()

	var flat_velocity := Vector3(target.linear_velocity.x, 0.0, target.linear_velocity.z)
	var speed := flat_velocity.length()
	var heading := forward

	if speed > min_velocity_heading:
		var velocity_direction := flat_velocity / speed
		if forward.dot(velocity_direction) > 0.0:
			var blend := velocity_heading_blend * clampf(speed / 28.0, 0.0, 1.0)
			heading = forward.lerp(velocity_direction, blend).normalized()

	var desired_position := car_position - heading * follow_distance + Vector3.UP * follow_height
	var position_weight := 1.0 - exp(-position_smoothing * delta)
	global_position = global_position.lerp(desired_position, position_weight)
	if global_position.y < 0.55:
		global_position.y = 0.55

	var desired_look := car_position + Vector3.UP * look_height + heading * look_ahead
	desired_look += flat_velocity * 0.03
	_look_target = _look_target.lerp(desired_look, 1.0 - exp(-look_smoothing * delta))

	if global_position.distance_squared_to(_look_target) > 0.01:
		look_at(_look_target, Vector3.UP)

	var speed_ratio := clampf(speed / fov_max_speed, 0.0, 1.0)
	var desired_fov := lerpf(base_fov, max_fov, speed_ratio)
	if bool(target.get("nitrous_active")):
		desired_fov += nitrous_fov_boost
	fov = lerpf(fov, desired_fov, 1.0 - exp(-fov_smoothing * delta))


## Instantly place the camera behind the car (used after spawning/respawning).
func snap_to_target() -> void:
	if target == null:
		return

	var car_position := target.global_position
	var forward := target.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, 1.0)
	forward = forward.normalized()

	global_position = car_position - forward * follow_distance + Vector3.UP * follow_height
	_look_target = car_position + Vector3.UP * look_height + forward * look_ahead
	fov = base_fov
	if global_position.distance_squared_to(_look_target) > 0.01:
		look_at(_look_target, Vector3.UP)
