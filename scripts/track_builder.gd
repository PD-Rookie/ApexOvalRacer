extends Node3D
## Builds the whole test circuit at runtime so the project stays asset-free.
##
## Layout:
##   - Asphalt ribbon (StaticBody3D on layer 2) with a trimesh collider
##   - Grass plane (StaticBody3D on layer 4) with different friction
##   - Solid barrier walls (StaticBody3D on layer 8)
##   - Six sequential Area3D checkpoints (layer 0 / mask 1)
##   - Start line, lane markings and light scenery
##
## The car raycasts against layers 2 and 4 to detect road vs. off-road.

const ROAD_LAYER := 2
const GRASS_LAYER := 4
const WALL_LAYER := 8
const CAR_LAYER := 1

@export var segment_count := 200
@export var radius_x := 66.0
@export var radius_z := 40.0
## Superellipse exponent. Lower values square off the oval into long straights.
@export_range(0.35, 1.0, 0.01) var straightness := 0.58
@export var track_width := 16.0
@export var wall_height := 1.1
@export var wall_thickness := 0.6
@export var wall_offset := 0.4
@export var checkpoint_count := 6
@export var spawn_height := 0.66
@export_group("Elevation & Banking")
@export var elevation_base := 2.1
@export var hill_height := 1.1
@export var hill_height_2 := 0.55
@export var bank_strength := 7.5
@export var max_bank := 0.22
@export_range(0, 4) var bank_smoothing_passes := 2
@export_group("")
@export var road_color := Color(0.145, 0.155, 0.17)
@export var grass_color := Color(0.2, 0.42, 0.16)
@export var wall_color := Color(0.94, 0.94, 0.9)
@export var wall_accent := Color(0.83, 0.13, 0.11)

var _centerline := PackedVector3Array()
var _tangents := PackedVector3Array()
var _sides := PackedVector3Array()
var _normals := PackedVector3Array()
var _cumulative := PackedFloat32Array()
var _checkpoint_indices: Array[int] = []
var _spawn_transform := Transform3D.IDENTITY
var _checkpoints: Array[Area3D] = []


func _ready() -> void:
	_sample_curve()
	_build_grass()
	_build_road()
	_build_markings()
	_build_walls()
	_build_checkpoints()
	_build_start_line()
	_build_gantry()
	_build_scenery()
	_spawn_transform = _make_spawn_transform()


## Used by main.gd to place the car on the grid.
func get_spawn_transform() -> Transform3D:
	return _spawn_transform


func get_checkpoints() -> Array[Area3D]:
	return _checkpoints


func get_track_width() -> float:
	return track_width


func get_total_length() -> float:
	if _cumulative.is_empty():
		return 0.0
	return _cumulative[_cumulative.size() - 1]


func get_grid_transform(slot: int) -> Transform3D:
	var safe_slot := maxi(slot, 0)
	var row := safe_slot / 2
	var column := safe_slot % 2
	var index := _wrap_index(segment_count - 10 - row * 4)
	var lateral := -2.15 if column == 0 else 2.15
	return _transform_at(index, lateral, spawn_height)


func get_centerline_point(index: int) -> Vector3:
	return _centerline[_wrap_index(index)]


func get_tangent(index: int) -> Vector3:
	return _tangents[_wrap_index(index)]


func get_side(index: int) -> Vector3:
	return _sides[_wrap_index(index)]


func get_normal(index: int) -> Vector3:
	return _normals[_wrap_index(index)]


func get_nearest_index(position: Vector3) -> int:
	var best_index := 0
	var best_distance := INF
	for i in segment_count:
		var distance := position.distance_squared_to(_centerline[i])
		if distance < best_distance:
			best_distance = distance
			best_index = i
	return best_index


func get_lookahead_point(position: Vector3, lookahead: float, lateral: float = 0.0) -> Vector3:
	var index := get_nearest_index(position)
	var traveled := 0.0
	var start_index := index
	while traveled < lookahead:
		var next := _wrap_index(index + 1)
		traveled += _centerline[index].distance_to(_centerline[next])
		index = next
		if index == start_index:
			break
	return _centerline[index] + _sides[index] * lateral


func get_curvature(index: int, lookahead_segments: int = 6) -> float:
	var before := _horizontal(_tangents[_wrap_index(index)])
	var after := _horizontal(_tangents[_wrap_index(index + lookahead_segments)])
	return absf(before.signed_angle_to(after, Vector3.UP))


func _transform_at(index: int, lateral: float, height: float) -> Transform3D:
	var wrapped := _wrap_index(index)
	var basis := Basis.looking_at(_tangents[wrapped], _normals[wrapped], true)
	var origin := _centerline[wrapped] + _sides[wrapped] * lateral + _normals[wrapped] * height
	return Transform3D(basis, origin)


func _wrap_index(index: int) -> int:
	return (index % segment_count + segment_count) % segment_count


# ---------------------------------------------------------------------------
# Curve sampling
# ---------------------------------------------------------------------------
func _sample_curve() -> void:
	_centerline.resize(segment_count)
	_tangents.resize(segment_count)
	_sides.resize(segment_count)
	_normals.resize(segment_count)

	for i in segment_count:
		var angle := TAU * float(i) / float(segment_count)
		var cos_a := cos(angle)
		var sin_a := sin(angle)
		var x := radius_x * signf(cos_a) * pow(absf(cos_a), straightness)
		var z := radius_z * signf(sin_a) * pow(absf(sin_a), straightness)
		z *= 1.0 + 0.025 * sin(angle * 4.0 + 0.7)
		var y := elevation_base \
			+ hill_height * sin(angle * 3.0 + 0.35) \
			+ hill_height_2 * sin(angle * 5.0 + 1.1)
		_centerline[i] = Vector3(x, y, z)

	for i in segment_count:
		var previous := _centerline[(i - 1 + segment_count) % segment_count]
		var next := _centerline[(i + 1) % segment_count]
		_tangents[i] = (next - previous).normalized()

	var bank_angles := PackedFloat32Array()
	bank_angles.resize(segment_count)
	for i in segment_count:
		var before := _horizontal(_tangents[(i - 1 + segment_count) % segment_count])
		var after := _horizontal(_tangents[(i + 1) % segment_count])
		var turn := before.cross(after).y
		bank_angles[i] = clampf(turn * bank_strength, -max_bank, max_bank)

	for _pass in bank_smoothing_passes:
		var smoothed := bank_angles.duplicate()
		for i in segment_count:
			var prev := bank_angles[(i - 1 + segment_count) % segment_count]
			var next := bank_angles[(i + 1) % segment_count]
			smoothed[i] = (prev + bank_angles[i] * 2.0 + next) * 0.25
		bank_angles = smoothed

	# Keep the low edge of every banked section above the flat grass plane.
	var bank_clearance := track_width * 0.5
	for i in segment_count:
		_centerline[i].y += bank_clearance * absf(sin(bank_angles[i])) + 0.08
	for i in segment_count:
		var previous := _centerline[(i - 1 + segment_count) % segment_count]
		var next := _centerline[(i + 1) % segment_count]
		_tangents[i] = (next - previous).normalized()

	for i in segment_count:
		var tangent := _tangents[i]
		var flat_side := tangent.cross(Vector3.UP).normalized()
		var bank := bank_angles[i]
		var side := flat_side.rotated(tangent, -bank).normalized()
		_sides[i] = side
		_normals[i] = side.cross(tangent).normalized()

	_compute_checkpoint_indices()


func _horizontal(vector: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	if flat.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	return flat.normalized()


func _compute_checkpoint_indices() -> void:
	_cumulative.resize(segment_count + 1)
	var total := 0.0
	for i in segment_count:
		total += _centerline[i].distance_to(_centerline[(i + 1) % segment_count])
		_cumulative[i + 1] = total

	_checkpoint_indices.clear()
	for i in checkpoint_count:
		var target := total * float(i) / float(checkpoint_count)
		var index := 0
		while index < segment_count and _cumulative[index] < target:
			index += 1
		_checkpoint_indices.append(index % segment_count)


func _make_spawn_transform() -> Transform3D:
	var index := (segment_count - 10 + segment_count) % segment_count
	var basis := Basis.looking_at(_tangents[index], _normals[index], true)
	var origin := _centerline[index] + _normals[index] * spawn_height
	return Transform3D(basis, origin)


# ---------------------------------------------------------------------------
# Road + grass + walls
# ---------------------------------------------------------------------------
func _build_grass() -> void:
	var grass_material := StandardMaterial3D.new()
	grass_material.albedo_color = grass_color
	grass_material.roughness = 1.0

	var plane := PlaneMesh.new()
	plane.size = Vector2(620.0, 620.0)
	plane.material = grass_material

	var visual := MeshInstance3D.new()
	visual.name = "GrassMesh"
	visual.mesh = plane
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)

	var body := StaticBody3D.new()
	body.name = "Grass"
	body.collision_layer = GRASS_LAYER
	body.collision_mask = 0
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.55
	body.physics_material_override = physics_material

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(620.0, 0.2, 620.0)
	shape.shape = box
	shape.position = Vector3(0, -0.1, 0)
	body.add_child(shape)
	add_child(body)


func _build_road() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = road_color
	material.roughness = 0.92
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)

	var half := track_width * 0.5
	var distance := 0.0
	for i in segment_count:
		var j := (i + 1) % segment_count
		var p0 := _centerline[i]
		var p1 := _centerline[j]
		var s0 := _sides[i]
		var s1 := _sides[j]
		var normal := (_normals[i] + _normals[j]).normalized()
		var left0 := p0 - s0 * half
		var right0 := p0 + s0 * half
		var left1 := p1 - s1 * half
		var right1 := p1 + s1 * half
		var length := p0.distance_to(p1)
		var v0 := distance / 8.0
		var v1 := (distance + length) / 8.0
		distance += length
		_add_quad(tool, left0, right0, right1, left1, 0.0, 1.0, v0, v1, normal)
	tool.generate_tangents()

	var mesh := tool.commit()
	var visual := MeshInstance3D.new()
	visual.name = "RoadMesh"
	visual.mesh = mesh
	add_child(visual)

	var body := StaticBody3D.new()
	body.name = "Road"
	body.collision_layer = ROAD_LAYER
	body.collision_mask = 0
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 1.1
	body.physics_material_override = physics_material

	var shape := CollisionShape3D.new()
	var road_shape := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	road_shape.backface_collision = true
	shape.shape = road_shape
	body.add_child(shape)
	add_child(body)


func _build_markings() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.96, 0.96, 0.92)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var dashes := StandardMaterial3D.new()
	dashes.albedo_color = Color(0.95, 0.8, 0.25)
	dashes.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dashes.cull_mode = BaseMaterial3D.CULL_DISABLED

	var edge_tool := SurfaceTool.new()
	edge_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	edge_tool.set_material(material)

	var dash_tool := SurfaceTool.new()
	dash_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	dash_tool.set_material(dashes)

	var half := track_width * 0.5
	var edge_offset := half - 0.7
	var edge_width := 0.18

	for i in segment_count:
		var j := (i + 1) % segment_count
		var p0 := _centerline[i] + _normals[i] * 0.012
		var p1 := _centerline[j] + _normals[j] * 0.012
		var s0 := _sides[i]
		var s1 := _sides[j]
		var normal := (_normals[i] + _normals[j]).normalized()

		for side_index in 2:
			var sign_value := -1.0 if side_index == 0 else 1.0
			var a0 := p0 + s0 * (edge_offset * sign_value) - s0 * (edge_width * 0.5)
			var b0 := p0 + s0 * (edge_offset * sign_value) + s0 * (edge_width * 0.5)
			var a1 := p1 + s1 * (edge_offset * sign_value) - s1 * (edge_width * 0.5)
			var b1 := p1 + s1 * (edge_offset * sign_value) + s1 * (edge_width * 0.5)
			_add_quad(edge_tool, a0, b0, b1, a1, 0.0, 1.0, 0.0, 1.0, normal)

		if i % 6 < 3:
			var dash_width := 0.16
			var c0a := p0 - s0 * (dash_width * 0.5)
			var c0b := p0 + s0 * (dash_width * 0.5)
			var c1a := p1 - s1 * (dash_width * 0.5)
			var c1b := p1 + s1 * (dash_width * 0.5)
			_add_quad(dash_tool, c0a, c0b, c1b, c1a, 0.0, 1.0, 0.0, 1.0, normal)

	var edge_mesh := edge_tool.commit()
	var edge_visual := MeshInstance3D.new()
	edge_visual.name = "LaneEdges"
	edge_visual.mesh = edge_mesh
	edge_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(edge_visual)

	var dash_mesh := dash_tool.commit()
	var dash_visual := MeshInstance3D.new()
	dash_visual.name = "CenterDashes"
	dash_visual.mesh = dash_mesh
	dash_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dash_visual)


func _build_walls() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.75
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)

	var body := StaticBody3D.new()
	body.name = "Walls"
	body.collision_layer = WALL_LAYER
	body.collision_mask = 0
	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.4
	physics_material.bounce = 0.08
	body.physics_material_override = physics_material

	var offset := track_width * 0.5 + wall_offset
	for i in segment_count:
		var j := (i + 1) % segment_count
		var stripe := wall_accent if (i / 4) % 2 == 0 else wall_color
		for side_index in 2:
			var sign_value := -1.0 if side_index == 0 else 1.0
			var side0 := _sides[i] * offset * sign_value
			var side1 := _sides[j] * offset * sign_value
			var bottom0 := _centerline[i] + side0 + _normals[i] * 0.02
			var bottom1 := _centerline[j] + side1 + _normals[j] * 0.02
			var top0 := bottom0 + Vector3.UP * wall_height
			var top1 := bottom1 + Vector3.UP * wall_height
			var normal := -_sides[i] * sign_value
			_add_wall_quad(tool, bottom0, bottom1, top1, top0, normal, stripe)

			# Thick box segments prevent fast cars from tunnelling through the
			# zero-thickness visual wall.
			var segment := bottom1 - bottom0
			var segment_length := segment.length()
			var basis := Basis.looking_at(segment.normalized(), Vector3.UP, true)
			var midpoint := (bottom0 + bottom1) * 0.5 + Vector3.UP * (wall_height * 0.5)
			var box := BoxShape3D.new()
			box.size = Vector3(wall_thickness, wall_height + 0.2, segment_length + 0.3)
			var collision := CollisionShape3D.new()
			collision.shape = box
			collision.transform = Transform3D(basis, midpoint)
			body.add_child(collision)

	var mesh := tool.commit()
	var visual := MeshInstance3D.new()
	visual.name = "WallMesh"
	visual.mesh = mesh
	add_child(visual)
	add_child(body)


# ---------------------------------------------------------------------------
# Checkpoints, start line, scenery
# ---------------------------------------------------------------------------
func _build_checkpoints() -> void:
	var parent := Node3D.new()
	parent.name = "Checkpoints"
	add_child(parent)

	for i in checkpoint_count:
		var index := _checkpoint_indices[i]
		var area := Area3D.new()
		area.name = "Checkpoint%d" % i
		area.collision_layer = 0
		area.collision_mask = CAR_LAYER
		area.monitoring = true
		area.monitorable = false
		area.add_to_group("checkpoints")
		area.set_meta("index", i)
		area.transform = Transform3D(
			Basis.looking_at(_tangents[index], _normals[index], true),
			_centerline[index]
		)

		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(track_width + 2.0, 4.0, 3.0)
		shape.shape = box
		shape.position = Vector3(0, 2.0, 0)
		area.add_child(shape)
		parent.add_child(area)

		var respawn := area.global_transform
		respawn.origin += respawn.basis.y * spawn_height
		area.set_meta("spawn_transform", respawn)
		_checkpoints.append(area)


func _build_start_line() -> void:
	var image := Image.create(16, 4, false, Image.FORMAT_RGBA8)
	for x in 16:
		for y in 4:
			var color := Color(0.97, 0.97, 0.95) if (x + y) % 2 == 0 else Color(0.04, 0.04, 0.05)
			image.set_pixel(x, y, color)

	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var plane := PlaneMesh.new()
	plane.size = Vector2(track_width, 2.4)
	plane.material = material

	var line := MeshInstance3D.new()
	line.name = "StartLine"
	line.mesh = plane
	line.transform = Transform3D(
		Basis.looking_at(_tangents[0], _normals[0], true),
		_centerline[0] + _normals[0] * 0.03
	)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)


func _build_gantry() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.1, 0.12, 0.16)
	material.metallic = 0.4
	material.roughness = 0.45

	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.32, 4.8, 0.32)
	post_mesh.material = material

	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(track_width + 5.0, 0.35, 0.5)
	beam_mesh.material = material

	var half := track_width * 0.5
	var side := _sides[0]
	var post_tops: Array[Vector3] = []

	for side_index in 2:
		var sign_value := -1.0 if side_index == 0 else 1.0
		var base := _centerline[0] + side * (half + 2.2) * sign_value + _normals[0] * 0.02
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.transform = Transform3D(Basis.IDENTITY, base + Vector3.UP * 2.4)
		add_child(post)
		post_tops.append(base + Vector3.UP * 4.8)

	var beam_x := _horizontal(side)
	var beam_basis := Basis(beam_x, Vector3.UP, beam_x.cross(Vector3.UP))
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.transform = Transform3D(beam_basis, (post_tops[0] + post_tops[1]) * 0.5)
	add_child(beam)


func _build_scenery() -> void:
	var colors := [
		Color(0.28, 0.34, 0.42),
		Color(0.35, 0.3, 0.27),
		Color(0.22, 0.28, 0.26),
	]
	var materials: Array[StandardMaterial3D] = []
	for color in colors:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		materials.append(material)

	for i in 14:
		var angle := TAU * float(i) / 14.0 + 0.17
		var distance := 1.58 + 0.09 * sin(float(i) * 2.3)
		var height := 6.0 + fmod(float(i) * 3.7, 13.0)
		var width := 8.0 + fmod(float(i) * 5.1, 9.0)
		var depth := 7.0 + fmod(float(i) * 4.3, 8.0)

		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, height, depth)
		mesh.material = materials[i % materials.size()]

		var building := MeshInstance3D.new()
		building.mesh = mesh
		building.position = Vector3(
			cos(angle) * radius_x * distance,
			height * 0.5,
			sin(angle) * radius_z * distance
		)
		building.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var collider := StaticBody3D.new()
		collider.name = "BuildingCollider"
		collider.collision_layer = WALL_LAYER
		collider.collision_mask = 0
		var collider_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = mesh.size
		collider_shape.shape = box_shape
		collider.add_child(collider_shape)
		building.add_child(collider)

		add_child(building)


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------
func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		u0: float, u1: float, v0: float, v1: float, normal: Vector3) -> void:
	# a/b are the left/right of the near edge, d/c the left/right of the far edge.
	_vertex(tool, a, normal, Vector2(u0, v0))
	_vertex(tool, b, normal, Vector2(u1, v0))
	_vertex(tool, c, normal, Vector2(u1, v1))
	_vertex(tool, a, normal, Vector2(u0, v0))
	_vertex(tool, c, normal, Vector2(u1, v1))
	_vertex(tool, d, normal, Vector2(u0, v1))


func _add_wall_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		normal: Vector3, color: Color) -> void:
	tool.set_color(color)
	_vertex(tool, a, normal, Vector2(0, 1))
	_vertex(tool, b, normal, Vector2(1, 1))
	_vertex(tool, c, normal, Vector2(1, 0))
	_vertex(tool, a, normal, Vector2(0, 1))
	_vertex(tool, c, normal, Vector2(1, 0))
	_vertex(tool, d, normal, Vector2(0, 0))


func _vertex(tool: SurfaceTool, position: Vector3, normal: Vector3, uv: Vector2) -> void:
	tool.set_normal(normal)
	tool.set_uv(uv)
	tool.add_vertex(position)
