extends Node
## Race director: countdown, sequential checkpoints, lap timing, standings and
## the local best-lap record.

signal countdown_changed(text: String)
signal race_started
signal lap_completed(lap_number: int, lap_time: float, best_lap: float)
signal race_finished(total_time: float, best_lap: float)

const SAVE_PATH := "user://apex_oval_racer.cfg"
const SAVE_SECTION := "records"
const SAVE_KEY := "best_lap"


class RacerState:
	var car = null
	var driver_name := ""
	var is_player := false
	var lap := 1
	var next_checkpoint := 1
	var race_time := 0.0
	var lap_time := 0.0
	var last_lap_time := 0.0
	var last_respawn := Transform3D.IDENTITY
	var finished := false
	var finish_time := 0.0
	var finish_position := 0


@export var total_laps := 3
@export var checkpoint_spawn_height := 0.66

var is_racing := false
var is_finished := false
var current_lap := 1
var best_lap := 0.0

var _car: Node = null
var _touch_hud: Node = null
var _checkpoints: Array[Area3D] = []
var _racers: Array = []
var _race_time := 0.0
var _lap_time := 0.0
var _last_lap_time := 0.0
var _finish_count := 0
var _bound := false


func _ready() -> void:
	add_to_group("race_manager")
	_load_best_lap()


func _process(delta: float) -> void:
	if not is_racing or is_finished:
		return

	_race_time += delta
	for state in _racers:
		if state.finished:
			continue
		state.race_time += delta
		state.lap_time += delta
		if state.is_player:
			_lap_time = state.lap_time


func begin_race() -> void:
	_bind_scene_nodes()
	_reset_race_state()

	for state in _racers:
		if state.car != null and state.car.has_method("set_controls_enabled"):
			state.car.freeze = true
			state.car.set_controls_enabled(false)
			state.last_respawn = state.car.global_transform

	if _touch_hud != null and _touch_hud.has_method("set_controls_enabled"):
		_touch_hud.set_controls_enabled(false)

	await _run_countdown()


func _run_countdown() -> void:
	await get_tree().create_timer(0.4, false).timeout

	for number in [3, 2, 1]:
		countdown_changed.emit(str(number))
		await get_tree().create_timer(0.85, false).timeout

	countdown_changed.emit("GO!")
	_race_time = 0.0
	_lap_time = 0.0
	is_racing = true

	for state in _racers:
		if state.car == null:
			continue
		state.car.freeze = false
		if state.car.has_method("set_controls_enabled"):
			state.car.set_controls_enabled(true)

	if _touch_hud != null and _touch_hud.has_method("set_controls_enabled"):
		_touch_hud.set_controls_enabled(true)

	race_started.emit()
	await get_tree().create_timer(0.9, false).timeout
	countdown_changed.emit("")


func _bind_scene_nodes() -> void:
	if _bound:
		return
	_bound = true

	_car = get_tree().get_first_node_in_group("player_car")
	_touch_hud = get_tree().get_first_node_in_group("touch_hud")

	_checkpoints.clear()
	for node in get_tree().get_nodes_in_group("checkpoints"):
		if node is Area3D:
			_checkpoints.append(node as Area3D)
	_checkpoints.sort_custom(_compare_checkpoints)

	var racers := get_tree().get_nodes_in_group("race_racer")
	if racers.is_empty() and _car != null:
		racers = [_car]
	racers.sort_custom(_compare_racers)

	for node in racers:
		if not node is Node3D:
			continue
		var state := RacerState.new()
		state.car = node
		state.is_player = node == _car
		var configured_name = node.get("driver_name")
		if configured_name != null and String(configured_name) != "":
			state.driver_name = String(configured_name)
		else:
			state.driver_name = String(node.name)
		_racers.append(state)

	for area in _checkpoints:
		var index := int(area.get_meta("index", 0))
		area.body_entered.connect(_on_checkpoint_entered.bind(index))


func _reset_race_state() -> void:
	is_racing = false
	is_finished = false
	current_lap = 1
	_race_time = 0.0
	_lap_time = 0.0
	_last_lap_time = 0.0
	_finish_count = 0

	var first_checkpoint := 1 % maxi(_checkpoints.size(), 1)
	for state in _racers:
		state.lap = 1
		state.next_checkpoint = first_checkpoint
		state.race_time = 0.0
		state.lap_time = 0.0
		state.last_lap_time = 0.0
		state.last_respawn = state.car.global_transform
		state.finished = false
		state.finish_time = 0.0
		state.finish_position = 0


func _compare_checkpoints(a: Area3D, b: Area3D) -> bool:
	return int(a.get_meta("index", 0)) < int(b.get_meta("index", 0))


func _compare_racers(a: Node, b: Node) -> bool:
	if a == _car:
		return true
	if b == _car:
		return false
	return String(a.name) < String(b.name)


func _on_checkpoint_entered(body: Node3D, index: int) -> void:
	if not is_racing or is_finished:
		return

	var state = _find_state(body)
	if state == null or state.finished:
		return
	if index != state.next_checkpoint:
		return

	if index == 0:
		_complete_lap(state)
		return

	_remember_checkpoint(state, index)
	state.next_checkpoint = (index + 1) % _checkpoints.size()


func _remember_checkpoint(state, index: int) -> void:
	if index < 0 or index >= _checkpoints.size():
		return
	var area := _checkpoints[index]
	var spawn: Transform3D = area.global_transform
	if area.has_meta("spawn_transform"):
		spawn = area.get_meta("spawn_transform")
	else:
		spawn.origin += spawn.basis.y * checkpoint_spawn_height
	state.last_respawn = spawn


func _complete_lap(state) -> void:
	var lap_time: float = state.lap_time
	state.last_lap_time = lap_time

	if state.is_player:
		current_lap = state.lap
		if best_lap <= 0.0 or lap_time < best_lap:
			best_lap = lap_time
			_save_best_lap()
		lap_completed.emit(state.lap, lap_time, best_lap)

	if state.lap >= total_laps:
		_finish_racer(state)
	else:
		state.lap += 1
		state.lap_time = 0.0
		state.next_checkpoint = 1 % maxi(_checkpoints.size(), 1)
		if state.is_player:
			current_lap = state.lap
			_lap_time = 0.0


func _finish_racer(state) -> void:
	state.finished = true
	state.finish_time = state.race_time
	state.finish_position = _finish_count + 1
	_finish_count += 1

	if state.is_player:
		current_lap = total_laps
		_finish_race()
		return

	if state.car != null:
		state.car.collision_layer = 0
		state.car.collision_mask = 14


func _finish_race() -> void:
	is_finished = true
	var total_time := get_total_time()

	if _car != null and _car.has_method("set_controls_enabled"):
		_car.set_controls_enabled(false)
	if _touch_hud != null and _touch_hud.has_method("set_controls_enabled"):
		_touch_hud.set_controls_enabled(false)

	race_finished.emit(total_time, best_lap)


func _find_state(car: Node):
	if car == null:
		return null
	for state in _racers:
		if state.car == car:
			return state
	return null


func _player_state():
	for state in _racers:
		if state.is_player:
			return state
	return null


func get_standings() -> Array:
	var standings: Array = []
	for state in _racers:
		standings.append({
			"car": state.car,
			"name": state.driver_name,
			"lap": state.lap,
			"finished": state.finished,
			"finish_time": state.finish_time,
			"finish_position": state.finish_position,
			"is_player": state.is_player,
			"progress": _progress_for(state),
		})
	standings.sort_custom(_compare_standings)
	for i in standings.size():
		standings[i]["position"] = i + 1
	return standings


func _progress_for(state) -> float:
	var checkpoint_total := maxi(_checkpoints.size(), 1)
	var next_stage: int = state.next_checkpoint
	if next_stage == 0:
		next_stage = checkpoint_total
	var stage := float((state.lap - 1) * checkpoint_total + next_stage)
	var distance := 0.0
	if state.car != null and state.next_checkpoint < _checkpoints.size():
		distance = state.car.global_position.distance_to(_checkpoints[state.next_checkpoint].global_position)
	return stage - clampf(distance / 500.0, 0.0, 0.9)


func _compare_standings(a: Dictionary, b: Dictionary) -> bool:
	if a["finished"] and b["finished"]:
		if is_equal_approx(a["finish_time"], b["finish_time"]):
			return String(a["name"]) < String(b["name"])
		return a["finish_time"] < b["finish_time"]
	if a["finished"] != b["finished"]:
		return a["finished"]
	if is_equal_approx(a["progress"], b["progress"]):
		return String(a["name"]) < String(b["name"])
	return a["progress"] > b["progress"]


func get_current_lap_time() -> float:
	var state = _player_state()
	if state == null:
		return 0.0
	if state.finished:
		return state.last_lap_time
	if not is_racing:
		return 0.0
	return state.lap_time


func get_total_time() -> float:
	if not is_racing:
		return 0.0
	return _race_time


func get_player_finish_position() -> int:
	var state = _player_state()
	if state == null:
		return 0
	return state.finish_position


func get_respawn_transform_for(car: Node) -> Transform3D:
	var state = _find_state(car)
	if state != null:
		return state.last_respawn
	if car is Node3D:
		return car.global_transform
	return Transform3D.IDENTITY


func get_respawn_transform() -> Transform3D:
	if _car == null:
		return Transform3D.IDENTITY
	return get_respawn_transform_for(_car)


func _load_best_lap() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	best_lap = float(config.get_value(SAVE_SECTION, SAVE_KEY, 0.0))


func _save_best_lap() -> void:
	var config := ConfigFile.new()
	config.load(SAVE_PATH)
	config.set_value(SAVE_SECTION, SAVE_KEY, best_lap)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Could not save best lap record: %s" % error_string(error))
