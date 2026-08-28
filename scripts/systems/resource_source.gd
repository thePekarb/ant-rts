class_name ResourceSource
extends StaticBody3D


signal amount_changed(current_amount: int, max_amount: int)

@export var resource_id: String = "food"
@export var display_name: String = "Хлеб"
@export var sync_amount_to_pieces: bool = true
@export var remaining_amount: int = 81
@export var max_amount: int = 81
@export var units_per_trip: int = 1
@export var gather_duration: float = 1.2
@export var carry_visual_scene: PackedScene

# Настройки маски выкусывания V9
@export var mask_resolution: int = 128
@export var bite_radius_world: float = 0.42
@export var bite_soft_edge_world: float = 0.08
@export var invert_mask_v: bool = false

# Настройки эффекта крошек
@export var gather_fx_enabled: bool = true
@export var gather_tick_particles: int = 3
@export var gather_take_particles: int = 8
@export var particle_lifetime: float = 0.52
@export var particle_size: float = 0.075

# Размеры препятствия и безопасных слотов
@export var obstacle_half_size: Vector2 = Vector2(2.70, 3.35)
@export var gather_surface_reach: float = 0.72
@export var gather_clearance: float = 0.68
@export var waiting_extra_clearance: float = 0.95

@export var gather_slot_count: int = 10
@export var waiting_slot_count: int = 16

@onready var gather_slots: SafeInteractionSlots = $GatherSlots
@onready var waiting_slots: SafeInteractionSlots = $WaitingSlots
@onready var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")

var available_cells: Array[Node3D] = []
var active_take_count: int = 0

# Процедурная текстура маски
var mask_image: Image
var mask_texture: ImageTexture
var bread_top_mesh_instance: MeshInstance3D = null

var crumb_particle_material: StandardMaterial3D


func _ready() -> void:
	# V9: Хлеб блокирует физически (Layer 1 = World) и детектируется мышью (Layer 4 = Resource)
	# 1 | 8 = 9
	collision_layer = 1 | 8
	collision_mask = 0

	crumb_particle_material = StandardMaterial3D.new()
	crumb_particle_material.albedo_color = Color(0.90, 0.83, 0.65)
	crumb_particle_material.roughness = 0.85

	if obstacle != null:
		obstacle.affect_navigation_mesh = true
		obstacle.avoidance_enabled = true
		obstacle.use_3d_avoidance = false
		obstacle.vertices = PackedVector3Array([
			Vector3(-obstacle_half_size.x, 0.0, -obstacle_half_size.y),
			Vector3( obstacle_half_size.x, 0.0, -obstacle_half_size.y),
			Vector3( obstacle_half_size.x, 0.0,  obstacle_half_size.y),
			Vector3(-obstacle_half_size.x, 0.0,  obstacle_half_size.y)
		])

	if gather_slots != null:
		gather_slots.shape = SafeInteractionSlots.SlotShape.RECTANGLE
		gather_slots.rect_half_size = obstacle_half_size + Vector2(gather_clearance, gather_clearance)
		gather_slots.slot_count = gather_slot_count
		gather_slots.reach_distance = 0.40
		gather_slots.rebuild_slots()

	if waiting_slots != null:
		waiting_slots.shape = SafeInteractionSlots.SlotShape.RECTANGLE
		var total_waiting_clearance: float = gather_clearance + waiting_extra_clearance
		waiting_slots.rect_half_size = obstacle_half_size + Vector2(total_waiting_clearance, total_waiting_clearance)
		waiting_slots.slot_count = waiting_slot_count
		waiting_slots.reach_distance = 0.40
		waiting_slots.rebuild_slots()

	collect_logical_cells(self)
	find_bread_top(self)
	init_mask_shader()

	if sync_amount_to_pieces and not available_cells.is_empty():
		remaining_amount = available_cells.size()
		max_amount = remaining_amount

	amount_changed.emit(remaining_amount, max_amount)
	print("[Ресурс V9: ", name, "] Инициализирован: логических ячеек=", available_cells.size(), ", запас=", remaining_amount, "/", max_amount)


func collect_logical_cells(node: Node) -> void:
	for child in node.get_children():
		if child.name.begins_with("BreadCell_") and child is Node3D:
			available_cells.append(child)
		collect_logical_cells(child)


func find_bread_top(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and child.name == "BreadTop":
			bread_top_mesh_instance = child
			return
		find_bread_top(child)


func init_mask_shader() -> void:
	if bread_top_mesh_instance == null:
		return

	# Создаем белую текстуру маски 128x128
	mask_image = Image.create(mask_resolution, mask_resolution, false, Image.FORMAT_R8)
	mask_image.fill(Color(1.0, 1.0, 1.0, 1.0))
	mask_texture = ImageTexture.create_from_image(mask_image)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D mask_texture : hint_default_white, filter_linear;
uniform vec4 crumb_color : source_color = vec4(0.90, 0.83, 0.65, 1.0);
uniform vec4 crust_color : source_color = vec4(0.66, 0.47, 0.25, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.86;

void fragment() {
	float mask = texture(mask_texture, UV).r;
	if (mask < 0.5) {
		discard;
	}
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	float d = length(centered);
	vec3 col = mix(crumb_color.rgb, crust_color.rgb, smoothstep(0.72, 0.88, d));
	ALBEDO = col;
	ROUGHNESS = roughness;
}
"""

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("mask_texture", mask_texture)
	mat.set_shader_parameter("crumb_color", Color(0.90, 0.83, 0.65, 1.0))
	mat.set_shader_parameter("crust_color", Color(0.66, 0.47, 0.25, 1.0))
	mat.set_shader_parameter("roughness", 0.86)

	bread_top_mesh_instance.material_override = mat


func spawn_gather_tick(worker_pos: Vector3) -> void:
	if not gather_fx_enabled:
		return

	var dir_to_bread: Vector3 = (global_position - worker_pos).normalized()
	var spawn_pos: Vector3 = worker_pos + dir_to_bread * 0.38
	spawn_pos.y = 0.22
	spawn_crumbs(spawn_pos, gather_tick_particles, 0.04, 0.6)


func take_from(worker_pos: Vector3, amount: int = 1) -> int:
	if available_cells.is_empty() or remaining_amount <= 0:
		return 0

	var actual_take: int = min(amount, remaining_amount)

	var to_worker_2d := Vector2(worker_pos.x - global_position.x, worker_pos.z - global_position.z)
	var dir_to_worker: Vector2 = to_worker_2d.normalized() if to_worker_2d.length_squared() > 0.001 else Vector2.RIGHT

	for _i in range(actual_take):
		if available_cells.is_empty():
			break

		var best_idx: int = -1
		var best_score: float = INF

		for j in range(available_cells.size()):
			var cell: Node3D = available_cells[j]
			if not is_instance_valid(cell):
				continue

			var cell_vec := Vector2(cell.global_position.x - global_position.x, cell.global_position.z - global_position.z)
			var cell_dist_from_center: float = cell_vec.length()
			var cell_dir: Vector2 = cell_vec.normalized() if cell_dist_from_center > 0.001 else dir_to_worker

			var alignment: float = dir_to_worker.dot(cell_dir)
			var dist_to_worker: float = worker_pos.distance_to(cell.global_position)

			var score: float = dist_to_worker * 1.2 - (alignment * 2.2) - (cell_dist_from_center * 0.40)

			if score < best_score:
				best_score = score
				best_idx = j

		if best_idx != -1:
			var target_cell: Node3D = available_cells[best_idx]
			available_cells.remove_at(best_idx)
			remaining_amount -= 1

			# Выкусываем область на маске BreadTop
			apply_bite_to_mask(target_cell.global_position)

			if gather_fx_enabled:
				var cell_pos: Vector3 = target_cell.global_position
				cell_pos.y = max(0.22, cell_pos.y)
				spawn_crumbs(cell_pos, gather_take_particles, particle_size, 1.2)

	amount_changed.emit(remaining_amount, max_amount)
	print("[Ресурс V9: ", name, "] Выкусан кусочек! Осталось ячеек: ", remaining_amount, "/", max_amount)

	if remaining_amount <= 0 or available_cells.is_empty():
		on_fully_depleted()

	return actual_take


func apply_bite_to_mask(world_pos: Vector3) -> void:
	if mask_image == null or mask_texture == null:
		return

	var local_x: float = world_pos.x - global_position.x
	var local_z: float = world_pos.z - global_position.z

	var hw: float = obstacle_half_size.x
	var hh: float = obstacle_half_size.y

	var u: float = clampf((local_x + hw) / (hw * 2.0), 0.0, 1.0)
	var v: float = clampf((local_z + hh) / (hh * 2.0), 0.0, 1.0)
	if invert_mask_v:
		v = 1.0 - v

	var center_px: int = int(u * float(mask_resolution))
	var center_py: int = int(v * float(mask_resolution))

	var rad_px: float = (bite_radius_world / (hw * 2.0)) * float(mask_resolution)
	var rad_int: int = int(ceil(rad_px + 2.0))

	for dy in range(-rad_int, rad_int + 1):
		for dx in range(-rad_int, rad_int + 1):
			var px: int = center_px + dx
			var py: int = center_py + dy
			if px >= 0 and px < mask_resolution and py >= 0 and py < mask_resolution:
				var dist: float = sqrt(float(dx * dx + dy * dy))
				if dist <= rad_px:
					mask_image.set_pixel(px, py, Color(0.0, 0.0, 0.0, 1.0))

	mask_texture.update(mask_image)


func spawn_crumbs(pos: Vector3, count: int, cube_size: float, speed: float) -> void:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.amount = max(1, count)
	particles.lifetime = particle_lifetime
	particles.direction = Vector3(0.0, 1.0, 0.0)
	particles.spread = 60.0
	particles.initial_velocity_min = speed * 0.7
	particles.initial_velocity_max = speed * 1.3
	particles.gravity = Vector3(0.0, -6.5, 0.0)

	var p_mesh := BoxMesh.new()
	p_mesh.size = Vector3(cube_size, cube_size, cube_size)
	p_mesh.material = crumb_particle_material
	particles.mesh = p_mesh

	add_child(particles)
	particles.global_position = pos
	particles.emitting = true

	get_tree().create_timer(particle_lifetime + 0.1).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


func on_fully_depleted() -> void:
	print("[Ресурс V9: ", name, "] Полностью истощён и съеден!")
	collision_layer = 0
	if obstacle != null:
		obstacle.avoidance_enabled = false
		obstacle.affect_navigation_mesh = false

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tween.tween_callback(queue_free)


func harvest(amount: int = 1) -> int:
	return take_from(global_position, amount)


func is_depleted() -> bool:
	return remaining_amount <= 0 or available_cells.is_empty()


func is_point_near_surface(pos: Vector3, max_dist: float = 0.85) -> bool:
	var local_x: float = abs(pos.x - global_position.x)
	var local_z: float = abs(pos.z - global_position.z)
	var dx: float = max(0.0, local_x - obstacle_half_size.x)
	var dz: float = max(0.0, local_z - obstacle_half_size.y)
	var dist: float = sqrt(dx * dx + dz * dz)
	return dist <= max_dist
