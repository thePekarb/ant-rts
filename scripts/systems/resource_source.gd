class_name ResourceSource
extends StaticBody3D


signal amount_changed(current_amount: int, max_amount: int)

@export var resource_id: String = "food"
@export var display_name: String = "Хлеб"
@export var sync_amount_to_pieces: bool = true
@export var remaining_amount: int = 16
@export var max_amount: int = 16
@export var units_per_trip: int = 1
@export var gather_duration: float = 1.2
@export var carry_visual_scene: PackedScene

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

var chunks_mesh: MeshInstance3D = null
var cells_by_id: Dictionary = {} # int -> BreadCell
var cells_list: Array[BreadCell] = []

var hidden_material: StandardMaterial3D
var crumb_particle_material: StandardMaterial3D


func _ready() -> void:
	# V10.1: Хлеб блокирует физически (Layer 1 = World) и детектируется мышью (Layer 4 = Resource)
	# 1 | 8 = 9
	collision_layer = 1 | 8
	collision_mask = 0

	crumb_particle_material = StandardMaterial3D.new()
	crumb_particle_material.albedo_color = Color(0.90, 0.83, 0.65)
	crumb_particle_material.roughness = 0.85

	# Невидимый материал для скрытия съеденной поверхности
	hidden_material = StandardMaterial3D.new()
	hidden_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hidden_material.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	hidden_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	hidden_material.no_depth_test = false

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

	find_chunks_mesh(self)
	init_bread_cells(self)

	if sync_amount_to_pieces and not cells_list.is_empty():
		remaining_amount = cells_list.size()
		max_amount = remaining_amount

	amount_changed.emit(remaining_amount, max_amount)
	print("[Ресурс V10.1: ", name, "] Инициализирован: ячеек=", cells_list.size(), ", запас=", remaining_amount, "/", max_amount)


func find_chunks_mesh(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and (child.name.begins_with("BreadChunksMesh") or child.name == "Model"):
			chunks_mesh = child
			return
		find_chunks_mesh(child)


func init_bread_cells(node: Node) -> void:
	for child in node.get_children():
		if child.name.begins_with("BreadCell_"):
			# Парсим имя формата BreadCell_<ID>_<E|I>_N<neighbor-ids>
			# Например: BreadCell_03_E_N02-06-07
			var parts: PackedStringArray = child.name.split("_")
			if parts.size() >= 3:
				var cid: int = parts[1].to_int()
				var exposed_flag: String = parts[2]
				var starts_exp: bool = (exposed_flag == "E")

				var neighbor_list: Array[int] = []
				if parts.size() >= 4 and parts[3].begins_with("N"):
					var n_str: String = parts[3].substr(1)
					if not n_str.is_empty():
						var n_parts: PackedStringArray = n_str.split("-")
						for np in n_parts:
							if not np.is_empty():
								neighbor_list.append(np.to_int())

				var cell: BreadCell = BreadCell.new()
				cell.name = "LogicalCell_%02d" % cid
				cell.cell_id = cid
				cell.surface_index = cid
				cell.starts_exposed = starts_exp
				cell.is_exposed = starts_exp
				cell.is_removed = false
				cell.neighbor_ids = neighbor_list
				cell.position = child.position

				child.add_child(cell)

				cells_by_id[cid] = cell
				cells_list.append(cell)

		init_bread_cells(child)


func spawn_gather_tick(worker_pos: Vector3) -> void:
	if not gather_fx_enabled:
		return

	var dir_to_bread: Vector3 = (global_position - worker_pos).normalized()
	var spawn_pos: Vector3 = worker_pos + dir_to_bread * 0.38
	spawn_pos.y = 0.22
	spawn_crumbs(spawn_pos, gather_tick_particles, 0.04, 0.6)


func reserve_piece_for_worker(worker: Node3D) -> BreadCell:
	# Освобождаем предыдущую бронь, если была
	release_piece_reservation(worker)

	var worker_pos: Vector3 = worker.global_position
	var to_worker_2d := Vector2(worker_pos.x - global_position.x, worker_pos.z - global_position.z)
	var dir_to_worker: Vector2 = to_worker_2d.normalized() if to_worker_2d.length_squared() > 0.001 else Vector2.RIGHT

	var best_cell: BreadCell = null
	var best_score: float = INF

	for cell in cells_list:
		if not is_instance_valid(cell) or cell.is_removed or not cell.is_exposed:
			continue
		if cell.reserved_by != null and is_instance_valid(cell.reserved_by) and cell.reserved_by != worker:
			continue

		var cell_world_pos: Vector3 = cell.global_position
		var cell_vec := Vector2(cell_world_pos.x - global_position.x, cell_world_pos.z - global_position.z)
		var cell_dist_from_center: float = cell_vec.length()
		var cell_dir: Vector2 = cell_vec.normalized() if cell_dist_from_center > 0.001 else dir_to_worker

		var alignment: float = dir_to_worker.dot(cell_dir)
		var dist_to_worker: float = worker_pos.distance_to(cell_world_pos)

		var score: float = dist_to_worker * 1.2 - (alignment * 2.5) - (cell_dist_from_center * 0.40)

		if score < best_score:
			best_score = score
			best_cell = cell

	if best_cell != null:
		best_cell.reserved_by = worker

	return best_cell


func release_piece_reservation(worker: Node3D) -> void:
	for cell in cells_list:
		if is_instance_valid(cell) and cell.reserved_by == worker:
			cell.reserved_by = null


func consume_reserved_piece(worker: Node3D) -> int:
	var target_cell: BreadCell = null
	for cell in cells_list:
		if is_instance_valid(cell) and cell.reserved_by == worker and not cell.is_removed:
			target_cell = cell
			break

	if target_cell == null:
		# Fallback: резервируем и сразу съедаем
		target_cell = reserve_piece_for_worker(worker)

	if target_cell == null:
		return 0

	target_cell.is_removed = true
	target_cell.reserved_by = null

	# Скрываем соответствующую поверхность в едином Mesh
	if chunks_mesh != null:
		chunks_mesh.set_surface_override_material(target_cell.surface_index, hidden_material)

	# Открываем соседние куски (frontier расширяется вглубь)
	for nid in target_cell.neighbor_ids:
		if cells_by_id.has(nid):
			var neighbor: BreadCell = cells_by_id[nid]
			if is_instance_valid(neighbor) and not neighbor.is_removed:
				neighbor.is_exposed = true

	remaining_amount = max(0, remaining_amount - 1)

	if gather_fx_enabled:
		var piece_pos: Vector3 = target_cell.global_position
		piece_pos.y = max(0.22, piece_pos.y)
		spawn_crumbs(piece_pos, gather_take_particles, particle_size, 1.2)

	amount_changed.emit(remaining_amount, max_amount)
	print("[Ресурс V10.1: ", name, "] Съеден кусок #", target_cell.cell_id, "! Осталось: ", remaining_amount, "/", max_amount)

	if remaining_amount <= 0:
		on_fully_depleted()

	return 1


func take_from(worker_pos: Vector3, amount: int = 1) -> int:
	# Совместимость со старым API
	if remaining_amount <= 0:
		return 0

	var dummy_worker: Node3D = Node3D.new()
	add_child(dummy_worker)
	dummy_worker.global_position = worker_pos

	var actual_take: int = 0
	for _i in range(amount):
		if remaining_amount <= 0:
			break
		var taken: int = consume_reserved_piece(dummy_worker)
		actual_take += taken

	dummy_worker.queue_free()
	return actual_take


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
	print("[Ресурс V10.1: ", name, "] Полностью съеден!")
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
	return remaining_amount <= 0


func is_point_near_surface(pos: Vector3, max_dist: float = 0.85) -> bool:
	var local_x: float = abs(pos.x - global_position.x)
	var local_z: float = abs(pos.z - global_position.z)
	var dx: float = max(0.0, local_x - obstacle_half_size.x)
	var dz: float = max(0.0, local_z - obstacle_half_size.y)
	var dist: float = sqrt(dx * dx + dz * dz)
	return dist <= max_dist
