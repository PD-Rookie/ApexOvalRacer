extends Node

var car = null
var track = null
var lane_offset := 0.0
var skill := 0.85
var start_delay := 0.0

var _elapsed := 0.0
var _stuck_time := 0.0


func _physics_process(delta: float) -> void:
	if car == null or track == null:
		return

	_elapsed += delta
	if not car.controls_enabled or _elapsed < start_delay:
		car.set_ai_inputs(0.0, 0.35, 0.0)
		return

	var position: Vector3 = car.global_position
	var speed: float = car.linear_velocity.length()
	if speed < 0.8:
		_stuck_time += delta
		if _stuck_time > 2.5:
			_stuck_time = 0.0
			car.reset_vehicle()
			return
	else:
		_stuck_time = 0.0
	var nearest: int = track.get_nearest_index(position)
	var curve: float = track.get_curvature(nearest, 8)
	var center_distance: float = position.distance_to(track.get_centerline_point(nearest))

	var lane := lane_offset
	if center_distance > track.get_track_width() * 0.58:
		lane = 0.0

	var base_speed := lerpf(25.0, 34.0, skill)
	var target_speed := base_speed * lerpf(1.0, 0.7, clampf(curve * 2.4, 0.0, 1.0))
	var lookahead := clampf(7.0 + speed * 0.55, 9.0, 26.0)
	var target: Vector3 = track.get_lookahead_point(position, lookahead, lane)

	var to_target := target - position
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		car.set_ai_inputs(0.0, 0.2, 0.0)
		return
	to_target = to_target.normalized()

	var forward: Vector3 = car.get_forward()
	var right := forward.cross(Vector3.UP).normalized()
	var lateral_error := to_target.dot(right)
	var angle_error := absf(forward.signed_angle_to(to_target, Vector3.UP))

	var steer := clampf(lateral_error * lerpf(2.1, 3.4, skill), -1.0, 1.0)
	var throttle := 0.0
	var brake := 0.0

	if speed < target_speed:
		throttle = clampf(0.55 + (target_speed - speed) * 0.08, 0.4, 1.0)
	elif speed > target_speed + 2.0:
		brake = clampf((speed - target_speed) * 0.08, 0.15, 0.8)

	if angle_error > 0.9:
		throttle *= 0.25
		brake = maxf(brake, 0.2)

	var use_nitrous := skill >= 0.9 and curve < 0.08 and speed > 10.0 \
		and float(car.nitrous_amount) > 0.3
	car.set_ai_inputs(throttle, brake, steer, absf(angle_error) > 1.2, use_nitrous)
