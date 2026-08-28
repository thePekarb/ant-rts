class_name WorkerAnt
extends CharacterBody3D


# ---------------------------------------------------------
# ИДЕНТИФИКАЦИЯ ЮНИТОВ
# ---------------------------------------------------------
static var next_unit_id: int = 1
var unit_id: int = 0
var unit_tag: String = ""

# Включить для подробной диагностики в консоли
@export var debug_movement: bool = false


# ---------------------------------------------------------
# СОСТОЯНИЯ ЮНИТА (FSM)
# ---------------------------------------------------------
enum UnitState {
	IDLE,
	MOVING,
	ATTACKING,
	GATHERING,
	CARRYING,
	DEAD
}

var state: UnitState = UnitState.IDLE


# ---------------------------------------------------------
# НАСТРОЙКИ ДВИЖЕНИЯ
# ---------------------------------------------------------
@export var walk_speed: float = 1.5
@export var run_speed: float = 3.0
@export var run_distance: float = 4.0
@export var acceleration: float = 6.0
@export var turn_speed: float = 7.0
@export var move_angle_tolerance: float = 30.0

const GRAVITY: float = 9.8
@export var floor_snap: float = 0.25

var is_moving: bool = false
var stuck_timer: float = 0.0


# ---------------------------------------------------------
# ЗДОРОВЬЕ И БЛИЖНИЙ БОЙ
# ---------------------------------------------------------
@export var max_health: float = 100.0
var health: float

@export var body_radius: float = 0.28
@export var attack_reach: float = 0.20
@export var engage_margin: float = 0.08
@export var attack_damage: float = 20.0
@export var attack_interval: float = 1.0
@export var auto_size_attack_slots: bool = true

var attack_target: WorkerAnt = null
var attack_slot_index: int = -1
var waiting_slot_index: int = -1

var attack_timer: float = 0.0
var attack_animation_timer: float = 0.0
var attack_hit_timer: float = 0.0
var attack_damage_pending: bool = false


# ---------------------------------------------------------
# СБОР И ПЕРЕНОСКА РЕСУРСОВ
# ---------------------------------------------------------
@export var gather_fx_interval: float = 0.30

var target_resource: ResourceSource = null
var target_anthill: Anthill = null
var current_gather_slot: int = -1
var current_waiting_slot: int = -1
var current_deposit_slot: int = -1
var current_deposit_waiting_slot: int = -1

var gather_timer: float = 0.0
var gather_fx_timer: float = 0.0
var blocked_near_resource_timer: float = 0.0
var blocked_near_anthill_timer: float = 0.0

var carried_amount: int = 0
var carried_visual_node: Node3D = null


# ---------------------------------------------------------
# ССЫЛКИ НА ДОЧЕРНИЕ УЗЛЫ
# ---------------------------------------------------------
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_state: AnimationNodeStateMachinePlayback = animation_tree["parameters/playback"]
@onready var animation_player: AnimationPlayer = $ant/AnimationPlayer
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var selection_indicator: MeshInstance3D = get_node_or_null("SelectionIndicator")
@onready var carry_socket: Marker3D = $CarrySocket
@onready var attack_slots: Node3D = get_node_or_null("AttackSlots")
@onready var attack_waiting_slots: Node3D = get_node_or_null("AttackWaitingSlots")

var wants_to_run: bool = false
var desired_velocity: Vector3 = Vector3.ZERO
var safe_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	unit_id = next_unit_id
	next_unit_id += 1

	if collision_layer == 4:
		unit_tag = "[Враг #" + str(unit_id) + "]"
	else:
		unit_tag = "[Муравей #" + str(unit_id) + "]"

	# Collision Mask = 1 ТОЛЬКО (физически блокируют мир, камни, стены, хлеб)
	collision_mask = 1

	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = floor_snap
	floor_constant_speed = true

	health = max_health

	if auto_size_attack_slots:
		if attack_slots != null and attack_slots.has_method("rebuild_slots"):
			attack_slots.radius = (body_radius * 2.0) + 0.05
			attack_slots.slot_count = 8
			attack_slots.reach_distance = 0.15
			attack_slots.rebuild_slots()
		elif attack_slots != null and "radius" in attack_slots:
			attack_slots.radius = (body_radius * 2.0) + 0.05
			attack_slots.slot_count = 8
			attack_slots.reach_distance = 0.15

		if attack_waiting_slots != null and attack_waiting_slots.has_method("rebuild_slots"):
			attack_waiting_slots.radius = (body_radius * 2.0) + 0.65
			attack_waiting_slots.slot_count = 12
			attack_waiting_slots.reach_distance = 0.15
			attack_waiting_slots.rebuild_slots()
		elif attack_waiting_slots != null and "radius" in attack_waiting_slots:
			attack_waiting_slots.radius = (body_radius * 2.0) + 0.65
			attack_waiting_slots.slot_count = 12
			attack_waiting_slots.reach_distance = 0.15

	add_to_group("selectable_units")
	navigation_agent.velocity_computed.connect(_on_velocity_computed)

	setup_animation_loops()

	animation_tree.active = true
	animation_state.start("Idle")

	ensure_selection_indicator()
	set_selected(false)
	print(unit_tag, " инициализирован (HP: ", health, ")")


# ---------------------------------------------------------
# САМОВОССТАНАВЛИВАЮЩИЙСЯ ИНДИКАТОР ВЫДЕЛЕНИЯ
# ---------------------------------------------------------

func ensure_selection_indicator() -> void:
	if selection_indicator == null:
		selection_indicator = get_node_or_null("SelectionIndicator")

	if selection_indicator == null:
		selection_indicator = MeshInstance3D.new()
		selection_indicator.name = "SelectionIndicator"
		add_child(selection_indicator)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = body_radius * 1.15
	ring_mesh.outer_radius = body_radius * 1.45
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 16

	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.2, 1.0, 0.35, 0.95)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	ring_mesh.material = ring_mat
	selection_indicator.mesh = ring_mesh
	selection_indicator.position = Vector3(0.0, 0.02, 0.0)


func set_selected(selected: bool) -> void:
	if selection_indicator == null:
		ensure_selection_indicator()

	if selection_indicator != null:
		selection_indicator.visible = selected


# ---------------------------------------------------------
# ПРИКАЗЫ
# ---------------------------------------------------------

func move_to(target_position: Vector3) -> void:
	cancel_all_orders()
	navigation_agent.target_position = target_position
	state = UnitState.MOVING
	is_moving = false
	stuck_timer = 0.0


func attack(target: WorkerAnt) -> void:
	if target == null or not is_instance_valid(target) or target == self:
		return

	cancel_all_orders()
	attack_target = target
	state = UnitState.ATTACKING
	is_moving = false
	stuck_timer = 0.0

	var range_val: float = get_effective_attack_range(target)

	if target.attack_slots != null:
		attack_slot_index = target.attack_slots.reserve_slot(self)
		if attack_slot_index == -1 and target.attack_waiting_slots != null:
			waiting_slot_index = target.attack_waiting_slots.reserve_slot(self)
			print("[ATTACK] ", unit_tag, " -> ", target.unit_tag, " range=", snappedf(range_val, 0.01), " slot=wait#", waiting_slot_index)
		else:
			print("[ATTACK] ", unit_tag, " -> ", target.unit_tag, " range=", snappedf(range_val, 0.01), " slot=combat#", attack_slot_index)
	else:
		print("[ATTACK] ", unit_tag, " -> ", target.unit_tag, " range=", snappedf(range_val, 0.01))


func gather(resource: ResourceSource, anthill: Anthill) -> void:
	if resource == null or not is_instance_valid(resource) or resource.is_depleted():
		return

	target_resource = resource
	target_anthill = anthill

	# Если муравей уже несёт груз в челюстях — сначала относит его в муравейник, а потом возвращается за ресурсом!
	if (carried_amount > 0 or carried_visual_node != null) and anthill != null and is_instance_valid(anthill):
		deliver(anthill)
		return

	cancel_all_orders()
	target_resource = resource
	target_anthill = anthill
	state = UnitState.GATHERING
	is_moving = false
	stuck_timer = 0.0
	blocked_near_resource_timer = 0.0
	gather_fx_timer = 0.0

	if resource.gather_slots != null:
		current_gather_slot = resource.gather_slots.reserve_slot(self)
		if current_gather_slot == -1 and resource.waiting_slots != null:
			current_waiting_slot = resource.waiting_slots.reserve_slot(self)
			print(unit_tag, " встал в очередь добычи (слот #", current_waiting_slot, ") у ", resource.name)
		else:
			print(unit_tag, " занял безопасный слот добычи #", current_gather_slot, " у ", resource.name)


func deliver(anthill: Anthill) -> void:
	if anthill == null or not is_instance_valid(anthill):
		return

	cancel_all_orders()
	target_anthill = anthill
	state = UnitState.CARRYING
	is_moving = false
	stuck_timer = 0.0
	blocked_near_anthill_timer = 0.0

	if anthill.deposit_slots != null:
		current_deposit_slot = anthill.deposit_slots.reserve_slot(self)
		if current_deposit_slot == -1 and anthill.deposit_waiting_slots != null:
			current_deposit_waiting_slot = anthill.deposit_waiting_slots.reserve_slot(self)
			print(unit_tag, " встал в очередь сдачи (слот #", current_deposit_waiting_slot, ") у ", anthill.name)
		else:
			print(unit_tag, " занял безопасный слот сдачи #", current_deposit_slot, " у ", anthill.name)


func cancel_all_orders() -> void:
	release_attack_reservation()
	release_gather_reservation()
	release_deposit_reservation()

	attack_target = null
	attack_damage_pending = false
	attack_animation_timer = 0.0
	gather_timer = 0.0
	gather_fx_timer = 0.0
	blocked_near_resource_timer = 0.0
	blocked_near_anthill_timer = 0.0


# ---------------------------------------------------------
# УРОН И СМЕРТЬ
# ---------------------------------------------------------

func take_damage(damage: float, attacker: WorkerAnt = null) -> void:
	health -= damage
	var attacker_name: String = attacker.unit_tag if (attacker != null and is_instance_valid(attacker)) else "Неизвестно"
	print(unit_tag, " получил ", damage, " урона от ", attacker_name, ". Осталось HP: ", max(0.0, health), "/", max_health)

	if health <= 0.0:
		die()


func die() -> void:
	state = UnitState.DEAD
	cancel_all_orders()
	if carried_visual_node and is_instance_valid(carried_visual_node):
		carried_visual_node.queue_free()
	velocity = Vector3.ZERO
	desired_velocity = Vector3.ZERO
	if navigation_agent.avoidance_enabled:
		navigation_agent.velocity = Vector3.ZERO
	print(unit_tag, " погиб в бою!")
	queue_free()


# ---------------------------------------------------------
# ГЛАВНЫЙ ФИЗИЧЕСКИЙ ЦИКЛ
# ---------------------------------------------------------

func _physics_process(delta: float) -> void:
	match state:
		UnitState.IDLE:
			desired_velocity = process_idle(delta)

		UnitState.MOVING:
			desired_velocity = process_movement(delta)

		UnitState.ATTACKING:
			desired_velocity = process_attack(delta)

		UnitState.GATHERING:
			desired_velocity = process_gathering(delta)

		UnitState.CARRYING:
			desired_velocity = process_carrying(delta)

		UnitState.DEAD:
			desired_velocity = Vector3.ZERO
			velocity = Vector3.ZERO
			return

	if navigation_agent.avoidance_enabled:
		navigation_agent.velocity = desired_velocity
	else:
		_on_velocity_computed(desired_velocity)

	check_stuck_diagnostics(delta)


func _on_velocity_computed(new_safe_velocity: Vector3) -> void:
	if desired_velocity.length_squared() < 0.001:
		velocity.x = 0.0
		velocity.z = 0.0
		is_moving = false
	else:
		safe_velocity = new_safe_velocity
		velocity.x = safe_velocity.x
		velocity.z = safe_velocity.z
		is_moving = true

		var move_2d := Vector2(velocity.x, velocity.z)
		if move_2d.length_squared() > 0.05:
			var target_angle: float = atan2(-velocity.x, -velocity.z)
			rotation.y = rotate_toward(rotation.y, target_angle, turn_speed * get_physics_process_delta_time())

	if not is_on_floor():
		velocity.y -= GRAVITY * get_physics_process_delta_time()
	else:
		velocity.y = -0.1

	move_and_slide()


func check_stuck_diagnostics(delta: float) -> void:
	if state in [UnitState.MOVING, UnitState.GATHERING, UnitState.CARRYING, UnitState.ATTACKING]:
		if desired_velocity.length_squared() > 0.1 and get_real_velocity().length() < 0.06:
			stuck_timer += delta
			if stuck_timer >= 0.8:
				stuck_timer = 0.0
				if debug_movement:
					print("[MOVE DEBUG] ", unit_tag, " стоит >0.8с | pos=", global_position, " | next=", navigation_agent.get_next_path_position(), " | target=", navigation_agent.target_position, " | on_floor=", is_on_floor(), " | state=", state)
		else:
			stuck_timer = 0.0


# ---------------------------------------------------------
# ОБРАБОТЧИКИ СОСТОЯНИЙ
# ---------------------------------------------------------

func process_idle(delta: float) -> Vector3:
	is_moving = false
	update_locomotion_animation(Vector3.ZERO)
	return Vector3.ZERO


func process_movement(delta: float) -> Vector3:
	var h_dist: float = get_horizontal_dist(global_position, navigation_agent.target_position)

	if h_dist <= navigation_agent.target_desired_distance:
		state = UnitState.IDLE
		is_moving = false
		wants_to_run = false
		update_locomotion_animation(Vector3.ZERO)
		return Vector3.ZERO

	return get_move_velocity_to(navigation_agent.target_position, walk_speed, delta)


func get_effective_attack_range(target: WorkerAnt) -> float:
	var target_radius: float = target.body_radius if "body_radius" in target else 0.28
	return body_radius + target_radius + attack_reach + engage_margin


func process_attack(delta: float) -> Vector3:
	if attack_target == null or not is_instance_valid(attack_target) or attack_target.state == UnitState.DEAD:
		finish_attack()
		return Vector3.ZERO

	if attack_timer > 0.0:
		attack_timer -= delta

	if attack_animation_timer > 0.0:
		attack_animation_timer -= delta

	var effective_attack_range: float = get_effective_attack_range(attack_target)

	if attack_damage_pending:
		attack_hit_timer -= delta
		if attack_hit_timer <= 0.0:
			attack_damage_pending = false
			if is_instance_valid(attack_target):
				var cur_dist: float = global_position.distance_to(attack_target.global_position)
				if cur_dist <= effective_attack_range * 1.35:
					attack_target.take_damage(attack_damage, self)

	var enemy_distance: float = global_position.distance_to(attack_target.global_position)

	# 1. Если достаём врага — стоим и бьём
	if enemy_distance <= effective_attack_range:
		is_moving = false
		desired_velocity = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		face_point(attack_target.global_position, delta)

		if attack_animation_timer > 0.0:
			return Vector3.ZERO

		if attack_timer <= 0.0 and is_facing_point(attack_target.global_position):
			start_attack_animation()
		else:
			update_locomotion_animation(Vector3.ZERO)

		return Vector3.ZERO

	# 2. Если анимация атаки ещё играет — не прерываемся движением
	if attack_animation_timer > 0.0:
		face_point(attack_target.global_position, delta)
		return Vector3.ZERO

	# 3. Сближаемся к своему слоту
	if attack_slot_index == -1 and attack_target.attack_slots != null:
		var new_slot: int = attack_target.attack_slots.reserve_slot(self)
		if new_slot != -1:
			if attack_target.attack_waiting_slots != null:
				attack_target.attack_waiting_slots.release_slot_index(waiting_slot_index, self)
			waiting_slot_index = -1
			attack_slot_index = new_slot

	if attack_slot_index != -1 and attack_target.attack_slots != null:
		var slot_pos: Vector3 = attack_target.attack_slots.get_slot_position(attack_slot_index)
		navigation_agent.target_position = slot_pos
		return get_move_velocity_to(slot_pos, walk_speed, delta)

	if waiting_slot_index != -1 and attack_target.attack_waiting_slots != null:
		var wait_pos: Vector3 = attack_target.attack_waiting_slots.get_slot_position(waiting_slot_index)
		var dist_to_wait: float = get_horizontal_dist(global_position, wait_pos)
		if dist_to_wait > attack_target.attack_waiting_slots.reach_distance:
			navigation_agent.target_position = wait_pos
			return get_move_velocity_to(wait_pos, walk_speed, delta)
		else:
			is_moving = false
			face_point(attack_target.global_position, delta)
			animation_state.travel("Idle")
			return Vector3.ZERO

	animation_state.travel("Idle")
	return Vector3.ZERO


# ---------------------------------------------------------
# ОБРАБОТКА ДОБЫЧИ (GATHERING)
# ---------------------------------------------------------

func process_gathering(delta: float) -> Vector3:
	if target_resource == null or not is_instance_valid(target_resource) or target_resource.is_depleted():
		if carried_amount > 0 or carried_visual_node != null:
			state = UnitState.CARRYING
			return Vector3.ZERO
		finish_gather()
		return Vector3.ZERO

	# Пробуем подняться из очереди в рабочий слот
	if current_gather_slot == -1 and target_resource.gather_slots != null:
		var new_slot: int = target_resource.gather_slots.reserve_slot(self)
		if new_slot != -1:
			if target_resource.waiting_slots != null:
				target_resource.waiting_slots.release_slot_index(current_waiting_slot, self)
			current_waiting_slot = -1
			current_gather_slot = new_slot
			blocked_near_resource_timer = 0.0

	# 1. Если владеем рабочим безопасным слотом добычи
	if current_gather_slot != -1 and target_resource.gather_slots != null:
		var slot_pos: Vector3 = target_resource.gather_slots.get_slot_position(current_gather_slot)
		var h_dist: float = get_horizontal_dist(global_position, slot_pos)
		var reach_dist: float = target_resource.gather_slots.reach_distance

		var reached_slot: bool = h_dist <= reach_dist
		var near_surface: bool = target_resource.is_point_near_surface(global_position, 0.85)

		if near_surface and not reached_slot and get_real_velocity().length() < 0.06:
			blocked_near_resource_timer += delta
		else:
			blocked_near_resource_timer = 0.0

		var can_gather: bool = reached_slot or (blocked_near_resource_timer >= 0.85)

		if not can_gather:
			navigation_agent.target_position = slot_pos
			return get_move_velocity_to(slot_pos, walk_speed, delta)

		# Мы в точке добычи! Останавливаемся и грызем ресурс
		is_moving = false
		desired_velocity = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		face_point(target_resource.global_position, delta)

		if gather_timer <= 0.0:
			gather_timer = target_resource.gather_duration
			gather_fx_timer = 0.1
			animation_state.travel("Gather")
		else:
			gather_timer -= delta
			animation_state.travel("Gather")

			# Эффект летящих крошек
			gather_fx_timer -= delta
			if gather_fx_timer <= 0.0:
				gather_fx_timer = gather_fx_interval
				target_resource.spawn_gather_tick(global_position)

			if gather_timer <= 0.0:
				var taken_amount: int = target_resource.take_from(global_position, target_resource.units_per_trip)
				carried_amount = taken_amount

				if target_resource.carry_visual_scene != null and carried_amount > 0:
					if carried_visual_node and is_instance_valid(carried_visual_node):
						carried_visual_node.queue_free()
					carried_visual_node = target_resource.carry_visual_scene.instantiate()
					carry_socket.add_child(carried_visual_node)

				# Освобождаем безопасный слот добычи для ожидающих
				target_resource.gather_slots.release_slot_index(current_gather_slot, self)
				current_gather_slot = -1
				blocked_near_resource_timer = 0.0
				gather_fx_timer = 0.0

				state = UnitState.CARRYING
				is_moving = false
				animation_state.travel("Walk")

		return Vector3.ZERO

	# 2. Если ожидаем во внешнем периметре
	if current_waiting_slot != -1 and target_resource.waiting_slots != null:
		var wait_pos: Vector3 = target_resource.waiting_slots.get_slot_position(current_waiting_slot)
		var dist_to_wait: float = get_horizontal_dist(global_position, wait_pos)

		if dist_to_wait > target_resource.waiting_slots.reach_distance:
			navigation_agent.target_position = wait_pos
			return get_move_velocity_to(wait_pos, walk_speed, delta)
		else:
			is_moving = false
			face_point(target_resource.global_position, delta)
			animation_state.travel("Idle")
			return Vector3.ZERO

	animation_state.travel("Idle")
	return Vector3.ZERO


# ---------------------------------------------------------
# ОБРАБОТКА ДОСТАВКИ В МУРАВЕЙНИК (CARRYING)
# ---------------------------------------------------------

func process_carrying(delta: float) -> Vector3:
	if target_anthill == null or not is_instance_valid(target_anthill):
		var dropoffs := get_tree().get_nodes_in_group("resource_dropoff")
		if not dropoffs.is_empty() and dropoffs[0] is Anthill:
			target_anthill = dropoffs[0]
		else:
			finish_gather()
			return Vector3.ZERO

	if current_deposit_slot == -1 and target_anthill.deposit_slots != null:
		current_deposit_slot = target_anthill.deposit_slots.reserve_slot(self)
		if current_deposit_slot == -1 and target_anthill.deposit_waiting_slots != null:
			current_deposit_waiting_slot = target_anthill.deposit_waiting_slots.reserve_slot(self)

	# 1. Если получили слот сдачи
	if current_deposit_slot != -1 and target_anthill.deposit_slots != null:
		var deposit_pos: Vector3 = target_anthill.deposit_slots.get_slot_position(current_deposit_slot)
		var h_dist: float = get_horizontal_dist(global_position, deposit_pos)
		var reach_dist: float = target_anthill.deposit_slots.reach_distance

		var reached_slot: bool = h_dist <= reach_dist
		var near_anthill: bool = target_anthill.is_point_near_surface(global_position, 0.85)

		if near_anthill and not reached_slot and get_real_velocity().length() < 0.06:
			blocked_near_anthill_timer += delta
		else:
			blocked_near_anthill_timer = 0.0

		var can_deposit: bool = reached_slot or (blocked_near_anthill_timer >= 0.85)

		if not can_deposit:
			navigation_agent.target_position = deposit_pos
			return get_move_velocity_to(deposit_pos, walk_speed, delta)

		# Сдаем груз в муравейник
		is_moving = false
		desired_velocity = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		face_point(target_anthill.global_position, delta)

		var res_id: String = target_resource.resource_id if (target_resource and is_instance_valid(target_resource)) else "food"
		var actual_deposit: int = max(1, carried_amount) if (carried_visual_node != null or carried_amount > 0) else carried_amount
		target_anthill.deposit(res_id, actual_deposit)
		carried_amount = 0

		if carried_visual_node and is_instance_valid(carried_visual_node):
			carried_visual_node.queue_free()
			carried_visual_node = null

		release_deposit_reservation()
		blocked_near_anthill_timer = 0.0

		# Автовозврат к ресурсу
		if target_resource != null and is_instance_valid(target_resource) and not target_resource.is_depleted():
			gather(target_resource, target_anthill)
		else:
			finish_gather()

		return Vector3.ZERO

	# 2. Очередь ожидания у муравейника
	if current_deposit_waiting_slot != -1 and target_anthill.deposit_waiting_slots != null:
		var wait_pos: Vector3 = target_anthill.deposit_waiting_slots.get_slot_position(current_deposit_waiting_slot)
		var dist_to_wait: float = get_horizontal_dist(global_position, wait_pos)

		if dist_to_wait > target_anthill.deposit_waiting_slots.reach_distance:
			navigation_agent.target_position = wait_pos
			return get_move_velocity_to(wait_pos, walk_speed, delta)
		else:
			is_moving = false
			face_point(target_anthill.global_position, delta)
			animation_state.travel("Idle")
			return Vector3.ZERO

	animation_state.travel("Idle")
	return Vector3.ZERO


# ---------------------------------------------------------
# РАСЧЁТ ДВИЖЕНИЯ
# ---------------------------------------------------------

func get_move_velocity_to(target_position: Vector3, base_speed: float, delta: float) -> Vector3:
	var next_position: Vector3 = navigation_agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = target_position - global_position
		direction.y = 0.0

	if direction.length_squared() < 0.001:
		update_locomotion_animation(Vector3.ZERO)
		return Vector3.ZERO

	direction = direction.normalized()

	var target_angle: float = atan2(-direction.x, -direction.z)
	var angle_error: float = abs(wrapf(target_angle - rotation.y, -PI, PI))
	var allowed_angle: float = deg_to_rad(move_angle_tolerance)

	var horizontal_distance: float = get_horizontal_dist(global_position, target_position)
	wants_to_run = horizontal_distance > run_distance

	var cur_speed: float = run_speed if wants_to_run else base_speed
	var move_vel: Vector3 = Vector3.ZERO

	if is_moving:
		rotation.y = rotate_toward(rotation.y, target_angle, turn_speed * delta)
		move_vel = direction * cur_speed
	else:
		rotation.y = rotate_toward(rotation.y, target_angle, turn_speed * 1.5 * delta)
		if angle_error <= allowed_angle:
			move_vel = direction * cur_speed
			is_moving = true
		else:
			move_vel = direction * (cur_speed * 0.3)

	update_locomotion_animation(move_vel)
	return move_vel


func update_locomotion_animation(move_velocity: Vector3) -> void:
	if attack_animation_timer > 0.0 or state == UnitState.GATHERING:
		return

	var speed: float = Vector2(move_velocity.x, move_velocity.z).length()

	if speed < 0.01:
		animation_state.travel("Idle")
	elif wants_to_run:
		animation_state.travel("Run")
	else:
		animation_state.travel("Walk")


# ---------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ ОРИЕНТАЦИИ И СЛОТОВ
# ---------------------------------------------------------

func get_horizontal_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func face_point(target_pos: Vector3, delta: float) -> void:
	var direction: Vector3 = target_pos - global_position
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		return

	direction = direction.normalized()
	var target_angle: float = atan2(-direction.x, -direction.z)
	rotation.y = rotate_toward(rotation.y, target_angle, turn_speed * delta)


func is_facing_point(target_pos: Vector3) -> bool:
	var direction: Vector3 = target_pos - global_position
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		return true

	direction = direction.normalized()
	var target_angle: float = atan2(-direction.x, -direction.z)
	var diff: float = abs(wrapf(target_angle - rotation.y, -PI, PI))
	return diff < deg_to_rad(20.0)


func start_attack_animation() -> void:
	animation_state.start("Attack", true)

	var attack_animation: Animation = animation_player.get_animation("ANT_Attack")
	var animation_length: float = attack_animation.length if attack_animation != null else 1.2

	attack_animation_timer = animation_length
	attack_timer = max(attack_interval, animation_length)
	attack_hit_timer = animation_length * 0.55
	attack_damage_pending = true

	var target_name: String = attack_target.unit_tag if (attack_target and is_instance_valid(attack_target)) else "враг"
	print("[ATTACK HIT START] ", unit_tag, " атакует ", target_name)


func release_attack_reservation() -> void:
	if attack_target != null and is_instance_valid(attack_target):
		if attack_slot_index != -1 and attack_target.attack_slots != null:
			attack_target.attack_slots.release_slot_index(attack_slot_index, self)
		if waiting_slot_index != -1 and attack_target.attack_waiting_slots != null:
			attack_target.attack_waiting_slots.release_slot_index(waiting_slot_index, self)

	attack_slot_index = -1
	waiting_slot_index = -1


func release_gather_reservation() -> void:
	if target_resource != null and is_instance_valid(target_resource):
		if current_gather_slot != -1 and target_resource.gather_slots != null:
			target_resource.gather_slots.release_slot_index(current_gather_slot, self)
		if current_waiting_slot != -1 and target_resource.waiting_slots != null:
			target_resource.waiting_slots.release_slot_index(current_waiting_slot, self)

	current_gather_slot = -1
	current_waiting_slot = -1


func release_deposit_reservation() -> void:
	if target_anthill != null and is_instance_valid(target_anthill):
		if current_deposit_slot != -1 and target_anthill.deposit_slots != null:
			target_anthill.deposit_slots.release_slot_index(current_deposit_slot, self)
		if current_deposit_waiting_slot != -1 and target_anthill.deposit_waiting_slots != null:
			target_anthill.deposit_waiting_slots.release_slot_index(current_deposit_waiting_slot, self)

	current_deposit_slot = -1
	current_deposit_waiting_slot = -1


func finish_attack() -> void:
	release_attack_reservation()
	attack_target = null
	attack_damage_pending = false
	attack_animation_timer = 0.0
	desired_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	state = UnitState.IDLE
	is_moving = false
	animation_state.travel("Idle")


func finish_gather() -> void:
	release_gather_reservation()
	release_deposit_reservation()
	target_resource = null
	target_anthill = null
	gather_timer = 0.0
	gather_fx_timer = 0.0
	blocked_near_resource_timer = 0.0
	blocked_near_anthill_timer = 0.0
	desired_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	state = UnitState.IDLE
	is_moving = false
	animation_state.travel("Idle")


func setup_animation_loops() -> void:
	var idle_anim: Animation = animation_player.get_animation("ANT_Idle")
	if idle_anim:
		idle_anim.loop_mode = Animation.LOOP_PINGPONG

	var walk_anim: Animation = animation_player.get_animation("ANT_Walk")
	if walk_anim:
		walk_anim.loop_mode = Animation.LOOP_LINEAR

	var run_anim: Animation = animation_player.get_animation("ANT_Run")
	if run_anim:
		run_anim.loop_mode = Animation.LOOP_LINEAR

	var gather_anim: Animation = animation_player.get_animation("ANT_Gather")
	if gather_anim:
		gather_anim.loop_mode = Animation.LOOP_LINEAR

	var attack_anim: Animation = animation_player.get_animation("ANT_Attack")
	if attack_anim:
		attack_anim.loop_mode = Animation.LOOP_NONE
