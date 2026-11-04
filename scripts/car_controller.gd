extends VehicleBody3D
## Arcade car controller.
##
## Uses a rear-wheel-drive VehicleBody3D setup:
##   - Front wheels: use_as_steering
##   - Rear wheels:  use_as_traction
##
## All driving input is read from the InputMap, so keyboard, gamepad and the
## on-screen touch overlay all feed the exact same code path.
##
## Important Godot convention: a VehicleBody3D drives towards its local +Z
## (Vector3.MODEL_FRONT), and a positive `steering` value turns left.

@export_group("Power")
## Force applied to each driven wheel. Godot's vehicle units are small
## compared to real-world Newtons; keep this in the low hundreds for a 300 kg
## arcade car and adjust together with mass.
@export var engine_power: float = 1250.0
@export_range(0.0, 1.0, 0.01) var reverse_engine_scale: float = 0.55
## Extra force multiplier at low speed so launches feel punchy.
@export var low_speed_boost: float = 2.0
@export var brake_force: float = 35.0
## Light drag while drifting; the handbrake mostly cuts rear grip.
@export var handbrake_force: float = 2.0

@export_group("Steering")
@export var low_speed_steer: float = 0.52
@export var high_speed_steer: float = 0.15
## Speed (m/s) at which the high-speed steering limit is reached.
@export var high_speed_reference: float = 32.0
@export var steer_response: float = 5.0
@export var steer_return: float = 7.0
@export var drift_steer_boost: float = 1.4

@export_group("Grip")
@export var handbrake_grip: float = 0.18
@export var offroad_grip: float = 0.45
@export var offroad_engine: float = 0.55
@export var grip_response: float = 9.0

@export_group("Aero & Safety")
@export var air_drag: float = 0.6
@export var offroad_drag: float = 18.0
@export var downforce: float = 0.6
## How long the car may sit upside down before it is automatically respawned.
@export var flip_reset_delay: float = 2.0
@export var reset_cooldown: float = 1.0

@export_group("Racer")
@export var is_ai := false
@export var driver_name := "YOU"
@export var body_color := Color(0.89, 0.13, 0.16)

@export_group("Nitrous")
## Engine force multiplier while the nitrous button is held.
@export var nitrous_force_multiplier: float = 1.9
## Throttle floor while boosting, so NOS accelerates even without GAS.
@export_range(0.0, 1.0, 0.01) var nitrous_min_throttle: float = 0.55
## Fraction of a full tank drained per second while boosting.
@export var nitrous_drain: float = 0.42
## Fraction of a full tank refilled per second after the recharge delay.
@export var nitrous_recharge: float = 0.14
@export var nitrous_recharge_delay: float = 1.2

## Set by the race manager. While false, throttle and steering are ignored and
## the car gently brakes.
var controls_enabled := false
## True when the wheels are on grass instead of asphalt.
var is_offroad := false
## Cached for the HUD.
var current_speed_kmh := 0.0
## True while the car is braking/reversing at low speed; shown on the HUD.
var reverse_gear := false
## Remaining nitrous, 0.0 to 1.0.
var nitrous_amount := 1.0
var nitrous_active := false

var ai_throttle := 0.0
var ai_brake := 0.0
var ai_steer := 0.0
var ai_handbrake := false
var ai_nitrous := false

var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _front_grip: Array[float] = []
var _rear_grip: Array[float] = []
var _upside_down_time := 0.0
var _reset_timer := 0.0
var _nitrous_idle_time := 0.0
var _lap_manager: Node = null

@onready var _ground_ray: RayCast3D = $GroundRay

const ROAD_LAYER := 2
const GRASS_LAYER := 4


func _ready() -> void:
	add_to_group("race_racer")
	if is_ai:
		remove_from_group("player_car")
		add_to_group("ai_car")
	else:
		add_to_group("player_car")

	_apply_body_color()

	_front_wheels = [$WheelFL, $WheelFR]
	_rear_wheels = [$WheelRL, $WheelRR]
	for wheel in _front_wheels:
		_front_grip.append(wheel.wheel_friction_slip)
	for wheel in _rear_wheels:
		_rear_grip.append(wheel.wheel_friction_slip)

	_ground_ray.collision_mask = ROAD_LAYER | GRASS_LAYER
	_ground_ray.enabled = true
	_ground_ray.force_raycast_update()

	freeze = true
	controls_enabled = false


func _apply_body_color() -> void:
	var body := get_node_or_null("BodyMesh") as MeshInstance3D
	if body == null:
		return
	var source := body.get_active_material(0)
	if source == null:
		return
	var material := source.duplicate() as StandardMaterial3D
	if material == null:
		return
	material.albedo_color = body_color
	body.set_surface_override_material(0, material)


func _physics_process(delta: float) -> void:
	if freeze:
		return

	_reset_timer = maxf(_reset_timer - delta, 0.0)
	current_speed_kmh = linear_velocity.length() * 3.6

	var forward := global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3(0.0, 0.0, 1.0)
	forward = forward.normalized()

	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(forward)

	var throttle := 0.0
	var brake_input := 0.0
	var handbrake := false
	var steer_raw := 0.0

	if controls_enabled:
		if is_ai:
			throttle = ai_throttle
			brake_input = ai_brake
			handbrake = ai_handbrake
			steer_raw = ai_steer
		else:
			throttle = Input.get_action_strength(&"accelerate")
			brake_input = Input.get_action_strength(&"brake")
			handbrake = Input.is_action_pressed(&"handbrake")
			steer_raw = Input.get_action_strength(&"steer_right") - Input.get_action_strength(&"steer_left")
			if Input.is_action_just_pressed(&"reset"):
				reset_vehicle()

	# --- Longitudinal control -------------------------------------------------
	var drive := 0.0
	var braking := 0.0
	reverse_gear = false

	if not controls_enabled:
		braking = brake_force * 0.55
	else:
		if brake_input > 0.05:
			if forward_speed > 0.8:
				braking = brake_force * brake_input
			else:
				drive = -engine_power * reverse_engine_scale * brake_input
				reverse_gear = true
		elif throttle > 0.01:
			var speed_factor := clampf(speed / 8.0, 0.0, 1.0)
			var launch_multiplier := lerpf(low_speed_boost, 1.0, speed_factor)
			drive = engine_power * throttle * launch_multiplier

	var nitrous_pressed := ai_nitrous if is_ai else Input.is_action_pressed(&"nitrous")
	var wants_nitrous := controls_enabled and not reverse_gear and brake_input <= 0.05 \
		and nitrous_pressed and nitrous_amount > 0.01
	nitrous_active = wants_nitrous
	if wants_nitrous:
		var boost_throttle := maxf(throttle, nitrous_min_throttle)
		var boost_speed_factor := clampf(speed / 8.0, 0.0, 1.0)
		var boost_launch := lerpf(low_speed_boost, 1.0, boost_speed_factor)
		drive = engine_power * boost_throttle * boost_launch * nitrous_force_multiplier
		nitrous_amount = maxf(nitrous_amount - nitrous_drain * delta, 0.0)
		_nitrous_idle_time = 0.0
	else:
		_nitrous_idle_time += delta
		if _nitrous_idle_time >= nitrous_recharge_delay:
			nitrous_amount = minf(nitrous_amount + nitrous_recharge * delta, 1.0)

	if handbrake:
		braking += handbrake_force
		drive *= 0.7

	_update_surface()
	if is_offroad:
		drive *= offroad_engine

	engine_force = drive
	brake = braking

	# --- Steering -------------------------------------------------------------
	# Positive steering in Godot turns left, while steer_raw is +1 for right.
	var steer_limit := lerpf(low_speed_steer, high_speed_steer, clampf(speed / high_speed_reference, 0.0, 1.0))
	var steer_target := -steer_raw * steer_limit
	if handbrake:
		steer_target *= drift_steer_boost

	var rate := steer_response
	if absf(steer_target) < absf(steering):
		rate = steer_return
	steering = move_toward(steering, steer_target, rate * delta)

	# --- Grip, drag, downforce, safety ---------------------------------------
	var rear_grip_factor := offroad_grip if is_offroad else 1.0
	if handbrake:
		rear_grip_factor *= handbrake_grip
	_set_wheel_grip(_front_wheels, _front_grip, offroad_grip if is_offroad else 1.0, delta)
	_set_wheel_grip(_rear_wheels, _rear_grip, rear_grip_factor, delta)

	_apply_aero(speed)
	_check_flip(delta, speed)


func _set_wheel_grip(wheels: Array[VehicleWheel3D], base_grip: Array[float], factor: float, delta: float) -> void:
	for i in wheels.size():
		var target := base_grip[i] * factor
		wheels[i].wheel_friction_slip = move_toward(wheels[i].wheel_friction_slip, target, grip_response * delta)


func _update_surface() -> void:
	is_offroad = false
	_ground_ray.force_raycast_update()
	if not _ground_ray.is_colliding():
		return
	var collider: Object = _ground_ray.get_collider()
	if collider is CollisionObject3D and (collider.collision_layer & GRASS_LAYER) != 0:
		is_offroad = true


func _apply_aero(speed: float) -> void:
	if speed > 0.5:
		var drag := air_drag
		if is_offroad:
			drag += offroad_drag
		apply_central_force(-linear_velocity.normalized() * drag * speed * speed)

	var forward := global_transform.basis.z.normalized()
	var forward_speed := maxf(linear_velocity.dot(forward), 0.0)
	if forward_speed > 1.0:
		apply_central_force(-global_transform.basis.y * downforce * forward_speed * forward_speed)


func _check_flip(delta: float, speed: float) -> void:
	var upright := global_transform.basis.y.dot(Vector3.UP)
	if upright < 0.2 and speed < 4.0:
		_upside_down_time += delta
		if _upside_down_time >= flip_reset_delay:
			reset_vehicle()
	else:
		_upside_down_time = 0.0


## Teleports the car to the last checkpoint (or the starting grid) and clears
## all velocity. Also used by the HUD Reset button and the R key.
func reset_vehicle() -> void:
	if _reset_timer > 0.0:
		return

	_reset_timer = reset_cooldown
	if _lap_manager == null:
		_lap_manager = get_tree().get_first_node_in_group("race_manager")

	var target := global_transform
	if _lap_manager != null and _lap_manager.has_method("get_respawn_transform_for"):
		target = _lap_manager.get_respawn_transform_for(self)
	elif _lap_manager != null and _lap_manager.has_method("get_respawn_transform"):
		target = _lap_manager.get_respawn_transform()

	global_transform = target
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	engine_force = 0.0
	brake = brake_force
	steering = 0.0
	_upside_down_time = 0.0
	reverse_gear = false
	nitrous_active = false
	_nitrous_idle_time = 0.0


func set_ai_inputs(throttle: float, brake_input: float, steer_raw: float,
		handbrake: bool = false, nitrous: bool = false) -> void:
	ai_throttle = clampf(throttle, 0.0, 1.0)
	ai_brake = clampf(brake_input, 0.0, 1.0)
	ai_steer = clampf(steer_raw, -1.0, 1.0)
	ai_handbrake = handbrake
	ai_nitrous = nitrous


## Called by the race manager while the countdown is running / after the race.
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		engine_force = 0.0
		brake = brake_force * 0.55
		nitrous_active = false
		reverse_gear = false


## Camera and HUD helper: +Z heading of the chassis, flattened.
func get_forward() -> Vector3:
	var forward := global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return forward.normalized()
