class_name ResourceSource
extends StaticBody3D


signal amount_changed(current_amount: int, max_amount: int)

@export var resource_id: String = "food"
@export var display_name: String = "Хлеб"
@export var sync_amount_to_pieces: bool = true
@export var remaining_amount: int = 104
@export var max_amount: int = 104
@export var units_per_trip: int = 1
@export var gather_duration: float = 1.2
@export var carry_visual_scene: PackedScene
@export var piece_vanish_duration: float = 0.18

# Настройки эффекта крошек
@export var gather_fx_enabled: bool = true
@export var gather_tick_particles: int = 3
@export var gather_take_particles: int = 8
@export var particle_lifetime: float = 0.52
@export var particle_size: float = 0.075

# Размеры препятствия и безопасных слотов
@export var obstacle_half_size: Vector2 = Vector2(2.55, 3.05)
@export var gather_surface_reach: float = 0.72
@export var gather_clearance: float = 0.68
@export var waiting_extra_clearance: float = 0.95

@export var gather_slot_count: int = 10
@export var waiting_slot_count: int = 16

@onready var gather_slots: SafeInteractionSlots = $GatherSlots
@onready var waiting_slots: SafeInteractionSlots = $WaitingSlots
@onready var obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")

var available_pieces: Array[Node3D] = []
var active_vanish_count: int = 0

var crumb_particle_material: StandardMaterial3D


func _ready() -> void:
	# V7.1: Хлеб блокирует физически (Layer 1 = World) и детектируется мышью (Layer 4 = Resource)
	# 1 | 8 = 9
	collision_layer = 1 | 8
	collision_mask = 0

	crumb_particle_material = StandardMaterial3D.new()
	crumb_particle_material.albedo_color = Color(0.86, 0.77, 0.56)
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

	collect_visual_pieces(self)

	if sync_amount_to_pieces and not available_pieces.is_empty():
		remaining_amount = available_pieces.size()
		max_amount = remaining_amount

	amount_changed.emit(remaining_amount, max_amount)
	print("[Ресурс: ", name, "] Инициализирован V7.1: кусочков=", available_pieces.size(), ", запас=", remaining_amount, "/", max_amount)


func collect_visual_pieces(node: Node) -> void:
	for child in node.get_children():
		if child is Node3D and child.name.begins_with("BreadPiece_"):
			available_pieces.append(child)
		collect_visual_pieces(child)


func spawn_gather_tick(worker_pos: Vector3) -> void:
	if not gather_fx_enabled:
		return

	var dir_to_bread: Vector3 = (global_position - worker_pos).normalized()
	var spawn_pos: Vector3 = worker_pos + dir_to_bread * 0.38
	spawn_pos.y = 0.22
	spawn_crumbs(spawn_pos, gather_tick_particles, 0.04, 0.6)


func take_from(worker_pos: Vector3, amount: int = 1) -> int:
	if available_pieces.is_empty() or remaining_amount <= 0:
		return 0

	var actual_take: int = min(amount, remaining_amount)

	# Вектор от центра хлеба к муравью
	var to_worker_2d := Vector2(worker_pos.x - global_position.x, worker_pos.z - global_position.z)
	var dir_to_worker: Vector2 = to_worker_2d.normalized() if to_worker_2d.length_squared() > 0.001 else Vector2.RIGHT

	for _i in range(actual_take):
		if available_pieces.is_empty():
			break

		var best_idx: int = -1
		var best_score: float = INF

		for j in range(available_pieces.size()):
			var piece: Node3D = available_pieces[j]
			if not is_instance_valid(piece):
				continue

			var piece_vec := Vector2(piece.global_position.x - global_position.x, piece.global_position.z - global_position.z)
			var piece_dist_from_center: float = piece_vec.length()
			var piece_dir: Vector2 = piece_vec.normalized() if piece_dist_from_center > 0.001 else dir_to_worker

			var alignment: float = dir_to_worker.dot(piece_dir) # 1.0 = точно с этой стороны
			var dist_to_worker: float = worker_pos.distance_to(piece.global_position)

			# V7.1: Умный скоринг — сильно предпочитает внешние кусочки с рабочей стороны муравья
			var score: float = dist_to_worker * 1.2 - (alignment * 2.0) - (piece_dist_from_center * 0.35)

			if score < best_score:
				best_score = score
				best_idx = j

		if best_idx != -1:
			var target_piece: Node3D = available_pieces[best_idx]
			available_pieces.remove_at(best_idx)
			remaining_amount -= 1

			if gather_fx_enabled:
				var piece_pos: Vector3 = target_piece.global_position
				piece_pos.y = max(0.2, piece_pos.y)
				spawn_crumbs(piece_pos, gather_take_particles, particle_size, 1.2)

			animate_piece_vanish(target_piece)

	amount_changed.emit(remaining_amount, max_amount)
	print("[Ресурс: ", name, "] Отщипнут кусочек! Осталось: ", remaining_amount, "/", max_amount)

	if remaining_amount <= 0 or available_pieces.is_empty():
		on_fully_depleted()

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


func animate_piece_vanish(piece: Node3D) -> void:
	if not is_instance_valid(piece):
		return

	active_vanish_count += 1
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(piece, "scale", Vector3(0.01, 0.01, 0.01), piece_vanish_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(piece, "position:y", piece.position.y + 0.15, piece_vanish_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func():
		active_vanish_count -= 1
		if is_instance_valid(piece):
			piece.queue_free()
		if remaining_amount <= 0 and active_vanish_count <= 0:
			queue_free()
	)


func on_fully_depleted() -> void:
	print("[Ресурс: ", name, "] Полностью истощён и съеден!")
	collision_layer = 0
	if obstacle != null:
		obstacle.avoidance_enabled = false
		obstacle.affect_navigation_mesh = false

	if active_vanish_count <= 0:
		queue_free()


func harvest(amount: int = 1) -> int:
	return take_from(global_position, amount)


func is_depleted() -> bool:
	return remaining_amount <= 0 or (available_pieces.is_empty() and active_vanish_count <= 0)


func is_point_near_surface(pos: Vector3, max_dist: float = 0.85) -> bool:
	var local_x: float = abs(pos.x - global_position.x)
	var local_z: float = abs(pos.z - global_position.z)
	var dx: float = max(0.0, local_x - obstacle_half_size.x)
	var dz: float = max(0.0, local_z - obstacle_half_size.y)
	var dist: float = sqrt(dx * dx + dz * dz)
	return dist <= max_dist
