extends Node3D
## Bootstraps the race: builds the environment, places the car on the grid,
## snaps the chase camera and starts the countdown.

const CAR_SCENE := preload("res://scenes/car.tscn")
const AI_DRIVER_SCRIPT := preload("res://scripts/ai_driver.gd")

@onready var _world_environment: WorldEnvironment = $WorldEnvironment

var _track: Node
var _car: Node
var _camera: Node
var _lap_manager: Node
var _ai_cars: Array[Node] = []


func _ready() -> void:
	_track = $Track
	_car = $Car
	_camera = $ChaseCamera
	_lap_manager = $LapManager

	_setup_environment()

	_car.collision_mask = 15
	_car.global_transform = _track.get_grid_transform(0)
	_car.linear_velocity = Vector3.ZERO
	_car.angular_velocity = Vector3.ZERO

	_spawn_opponents()

	_camera.snap_to_target()
	_lap_manager.begin_race()


func _spawn_opponents() -> void:
	var opponents := [
		{"name": "BLAZE", "color": Color(0.12, 0.48, 0.95), "skill": 0.96, "lane": 2.0, "delay": 0.05},
		{"name": "VIPER", "color": Color(0.95, 0.76, 0.12), "skill": 0.9, "lane": -2.0, "delay": 0.15},
		{"name": "NOVA", "color": Color(0.22, 0.82, 0.48), "skill": 0.84, "lane": 2.0, "delay": 0.28},
		{"name": "RIVAL", "color": Color(0.68, 0.32, 0.92), "skill": 0.78, "lane": -2.0, "delay": 0.4},
	]

	for i in opponents.size():
		var data: Dictionary = opponents[i]
		var ai_car = CAR_SCENE.instantiate()
		ai_car.name = "AI_%s" % String(data["name"])
		ai_car.is_ai = true
		ai_car.driver_name = String(data["name"])
		ai_car.body_color = data["color"]
		ai_car.collision_mask = 15
		ai_car.remove_from_group("player_car")
		ai_car.transform = _track.get_grid_transform(i + 1)
		add_child(ai_car)
		ai_car.linear_velocity = Vector3.ZERO
		ai_car.angular_velocity = Vector3.ZERO

		var driver = AI_DRIVER_SCRIPT.new()
		driver.name = "AIDriver"
		driver.car = ai_car
		driver.track = _track
		driver.lane_offset = float(data["lane"])
		driver.skill = float(data["skill"])
		driver.start_delay = float(data["delay"])
		ai_car.add_child(driver)
		_ai_cars.append(ai_car)


func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.2, 0.4, 0.72)
	sky_material.sky_horizon_color = Color(0.72, 0.84, 0.96)
	sky_material.sky_curve = 0.18
	sky_material.ground_horizon_color = Color(0.45, 0.58, 0.5)
	sky_material.ground_bottom_color = Color(0.12, 0.18, 0.14)
	sky_material.sun_angle_max = 26.0
	sky_material.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky

	_world_environment.environment = environment
