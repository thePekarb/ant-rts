class_name BreadResourceV10
extends StaticBody3D

signal depleted(source: BreadResourceV10)
signal amount_changed(current_amount: int, max_amount: int)
signal cell_reserved(worker: Node, cell: BreadCellV10)
signal cell_consumed(worker: Node, cell: BreadCellV10)

@export_group("Resource")
@export var display_name: String = "Хлеб"
@export var resource_id: StringName = &"food"
@export var units_per_trip: int = 1
@export var gather_duration: float = 1.2
@export var carry_visual_scene: PackedScene

@export_group("V10 Chunk Mesh")
# IMPORTANT:
# This is ONE MeshInstance3D.
# Each logical bread piece is one surface inside this mesh.
@export var chunk_mesh_path: NodePath = NodePath("Model/BreadChunksMesh")

# Logical BreadCellV10 nodes can live below this node.
@export var cells_root_path: NodePath = NodePath("BreadCells")

# Optional interior/cut mesh that is always visible and sits between pieces.
# It gives freshly exposed faces a crumb texture instead of a black void.
@export var cut_interior_path: NodePath = NodePath("Model/BreadCutInterior")

@export_group("Piece Selection")
# How much to prefer a piece on the same side as the worker.
@export var side_alignment_weight: float = 2.4

# Prefer physically closer exposed pieces.
@export var distance_weight: float = 1.0

# Small randomness prevents every worker on one side from always selecting
# the mathematically identical piece.
@export var score_randomness: float = 0.08

@export_group("Removal")
@export var vanish_duration: float = 0.15
@export var shrink_before_hide: bool = false

@export_group("Physical Footprint")
@export var obstacle_half_size: Vector2 = Vector2(2.70, 3.35)
@export var obstacle_height: float = 1.2
@export var gather_surface_reach: float = 0.72

@export_group("Slot Auto Setup")
@export var auto_configure_slots: bool = true
@export var gather_clearance: float = 0.68
@export var waiting_extra_clearance: float = 0.95

@export_group("Collision / Navigation")
@export_flags_3d_physics var world_layer_mask: int = 1
@export_flags_3d_physics var resource_layer_mask: int = 8
@export var configure_collision_layers_on_ready: bool = true
@export var configure_navigation_obstacle_on_ready: bool = true

@onready var chunk_mesh: MeshInstance3D = get_node(chunk_mesh_path)
@onready var cells_root: Node = get_node(cells_root_path)
@onready var cut_interior: Node3D = get_node_or_null(cut_interior_path)
@onready var gather_slots: SafeInteractionSlots = $GatherSlots
@onready var waiting_slots: SafeInteractionSlots = $WaitingSlots
@onready var navigation_obstacle: NavigationObstacle3D = get_node_or_null("NavigationObstacle3D")


var max_amount: int = 0
var remaining_amount: int = 0

var _cells: Array[BreadCellV10] = []
var _cell_by_id: Dictionary = {}

# worker instance_id -> BreadCellV10
var _reservation_by_worker: Dictionary = {}

var _hidden_material: StandardMaterial3D = null
var _depletion_started: bool = false


func _ready() -> void:
    add_to_group("resource_sources")

    if configure_collision_layers_on_ready:
        collision_layer = world_layer_mask | resource_layer_mask
        collision_mask = 0

    _create_hidden_material()
    _collect_cells(cells_root)
    _build_neighbors()
    _initialize_cells()

    max_amount = _cells.size()
    remaining_amount = max_amount

    if auto_configure_slots:
        _configure_slots()

    if (
        configure_navigation_obstacle_on_ready
        and navigation_obstacle != null
    ):
        _configure_navigation_obstacle()

    amount_changed.emit(remaining_amount, max_amount)

    print(
        "[Bread V10] ",
        name,
        " cells=",
        _cells.size(),
        " mesh surfaces=",
        chunk_mesh.mesh.get_surface_count()
    )


# =========================================================
# SETUP
# =========================================================

func _create_hidden_material() -> void:
    _hidden_material = StandardMaterial3D.new()

    _hidden_material.transparency = (
        BaseMaterial3D.TRANSPARENCY_ALPHA
    )

    _hidden_material.albedo_color = Color(
        1.0,
        1.0,
        1.0,
        0.0
    )

    _hidden_material.shading_mode = (
        BaseMaterial3D.SHADING_MODE_UNSHADED
    )

    _hidden_material.cast_shadow = (
        BaseMaterial3D.SHADOW_CASTING_SETTING_OFF
    )


func _collect_cells(node: Node) -> void:
    for child in node.get_children():
        if child is BreadCellV10:
            var cell := child as BreadCellV10

            if cell.cell_id < 0:
                push_warning(
                    "BreadCell has invalid cell_id: "
                    + str(cell.name)
                )
            else:
                _cells.append(cell)
                _cell_by_id[cell.cell_id] = cell

        _collect_cells(child)


func _build_neighbors() -> void:
    for cell in _cells:
        cell.neighbors.clear()

        for neighbor_id in cell.neighbor_ids:
            if not _cell_by_id.has(neighbor_id):
                continue

            var neighbor: BreadCellV10 = (
                _cell_by_id[neighbor_id]
            )

            if neighbor != cell:
                cell.neighbors.append(neighbor)


func _initialize_cells() -> void:
    for cell in _cells:
        cell.setup_initial_state()

        # Restore original material in case of scene reset/reuse.
        if cell.surface_index >= 0:
            chunk_mesh.set_surface_override_material(
                cell.surface_index,
                null
            )


func _configure_slots() -> void:
    gather_slots.layout = (
        SafeInteractionSlots.Layout.RECTANGLE
    )

    gather_slots.rectangle_half_size = (
        obstacle_half_size
    )

    gather_slots.clearance = gather_clearance
    gather_slots.arrival_radius = 0.34
    gather_slots._rebuild()

    waiting_slots.layout = (
        SafeInteractionSlots.Layout.RECTANGLE
    )

    waiting_slots.rectangle_half_size = (
        obstacle_half_size
    )

    waiting_slots.clearance = (
        gather_clearance
        + waiting_extra_clearance
    )

    waiting_slots.arrival_radius = 0.38
    waiting_slots._rebuild()


func _configure_navigation_obstacle() -> void:
    var hx: float = obstacle_half_size.x
    var hz: float = obstacle_half_size.y

    navigation_obstacle.vertices = PackedVector3Array([
        Vector3(-hx, 0.0, -hz),
        Vector3( hx, 0.0, -hz),
        Vector3( hx, 0.0,  hz),
        Vector3(-hx, 0.0,  hz),
    ])

    navigation_obstacle.height = obstacle_height
    navigation_obstacle.avoidance_enabled = true
    navigation_obstacle.use_3d_avoidance = false
    navigation_obstacle.affect_navigation_mesh = true


# =========================================================
# RESERVATION / FRONTIER CONSUMPTION
# =========================================================

func reserve_piece_for_worker(
    worker: Node3D
) -> BreadCellV10:
    if worker == null:
        return null

    if remaining_amount <= 0:
        return null

    var worker_id: int = worker.get_instance_id()

    # If this ant already owns a still-valid piece, keep it.
    if _reservation_by_worker.has(worker_id):
        var existing: BreadCellV10 = (
            _reservation_by_worker[worker_id]
        )

        if (
            existing != null
            and is_instance_valid(existing)
            and not existing.is_removed
        ):
            return existing

        _reservation_by_worker.erase(worker_id)

    var cell: BreadCellV10 = _find_best_exposed_cell(
        worker.global_position
    )

    if cell == null:
        return null

    if not cell.reserve(worker):
        return null

    _reservation_by_worker[worker_id] = cell

    cell_reserved.emit(worker, cell)

    return cell


func get_reserved_piece_for_worker(
    worker: Node
) -> BreadCellV10:
    if worker == null:
        return null

    var worker_id: int = worker.get_instance_id()

    if not _reservation_by_worker.has(worker_id):
        return null

    var cell: BreadCellV10 = (
        _reservation_by_worker[worker_id]
    )

    if (
        cell == null
        or not is_instance_valid(cell)
        or cell.is_removed
    ):
        _reservation_by_worker.erase(worker_id)
        return null

    return cell


func release_piece_reservation(worker: Node) -> void:
    if worker == null:
        return

    var worker_id: int = worker.get_instance_id()

    if not _reservation_by_worker.has(worker_id):
        return

    var cell: BreadCellV10 = (
        _reservation_by_worker[worker_id]
    )

    _reservation_by_worker.erase(worker_id)

    if cell != null and is_instance_valid(cell):
        cell.release(worker)


func _find_best_exposed_cell(
    worker_position: Vector3
) -> BreadCellV10:
    var center: Vector3 = global_position

    var worker_side: Vector3 = (
        worker_position - center
    )

    worker_side.y = 0.0

    if worker_side.length_squared() < 0.001:
        worker_side = Vector3.FORWARD

    worker_side = worker_side.normalized()

    var best_cell: BreadCellV10 = null
    var best_score: float = INF

    for cell in _cells:
        if cell.is_removed:
            continue

        if not cell.is_exposed:
            continue

        if cell.is_reserved():
            continue

        var cell_side: Vector3 = (
            cell.global_position - center
        )

        cell_side.y = 0.0

        if cell_side.length_squared() < 0.001:
            cell_side = Vector3.FORWARD
        else:
            cell_side = cell_side.normalized()

        # 1.0 means "same side of the bread as the ant".
        var alignment: float = clampf(
            cell_side.dot(worker_side),
            -1.0,
            1.0
        )

        var distance_score: float = (
            worker_position
            .distance_squared_to(cell.global_position)
            * distance_weight
        )

        # High alignment should REDUCE the score.
        var side_score: float = (
            -alignment
            * side_alignment_weight
        )

        var random_score: float = randf_range(
            -score_randomness,
            score_randomness
        )

        var score: float = (
            distance_score
            + side_score
            + random_score
        )

        if score < best_score:
            best_score = score
            best_cell = cell

    return best_cell


# =========================================================
# CONSUMPTION
# =========================================================

func consume_reserved_piece(
    worker: Node3D
) -> int:
    if worker == null:
        return 0

    var cell: BreadCellV10 = (
        get_reserved_piece_for_worker(worker)
    )

    if cell == null:
        # Fallback: reserve immediately if worker reached the bread
        # without a previous explicit reservation.
        cell = reserve_piece_for_worker(worker)

    if cell == null:
        return 0

    _remove_cell_visual(cell)

    cell.mark_removed()

    var worker_id: int = worker.get_instance_id()
    _reservation_by_worker.erase(worker_id)

    remaining_amount = maxi(
        remaining_amount - units_per_trip,
        0
    )

    _refresh_frontier_around(cell)

    cell_consumed.emit(worker, cell)

    amount_changed.emit(
        remaining_amount,
        max_amount
    )

    if remaining_amount <= 0:
        _begin_depletion()

    return units_per_trip


func _remove_cell_visual(
    cell: BreadCellV10
) -> void:
    if cell.surface_index < 0:
        return

    if (
        cell.surface_index
        >= chunk_mesh.mesh.get_surface_count()
    ):
        push_warning(
            "Bread V10: surface_index out of range for cell "
            + str(cell.cell_id)
        )
        return

    # Because every chunk is a surface of ONE mesh,
    # intact bread has continuous geometry / normals.
    # Consuming one cell only swaps this surface to a transparent material.
    chunk_mesh.set_surface_override_material(
        cell.surface_index,
        _hidden_material
    )


func _refresh_frontier_around(
    removed_cell: BreadCellV10
) -> void:
    # Only its neighbors can become newly exposed.
    # No need to scan the entire loaf.
    for neighbor in removed_cell.neighbors:
        if neighbor == null:
            continue

        neighbor.refresh_exposure()


func get_remaining_fraction() -> float:
    if max_amount <= 0:
        return 0.0

    return (
        float(remaining_amount)
        / float(max_amount)
    )


# =========================================================
# GENERIC API COMPATIBILITY
# =========================================================

# This keeps the old WorkerAnt usable during migration.
# New WorkerAnt V10 should call reserve_piece_for_worker() first.
func take_from(
    worker_position: Vector3,
    requested_amount: int
) -> int:
    if remaining_amount <= 0:
        return 0

    # We cannot know the exact WorkerAnt node from a position alone,
    # so this compatibility method consumes the best exposed free cell.
    var cell: BreadCellV10 = _find_best_exposed_cell(
        worker_position
    )

    if cell == null:
        return 0

    _remove_cell_visual(cell)
    cell.mark_removed()

    remaining_amount = maxi(
        remaining_amount - mini(
            requested_amount,
            units_per_trip
        ),
        0
    )

    _refresh_frontier_around(cell)

    amount_changed.emit(
        remaining_amount,
        max_amount
    )

    if remaining_amount <= 0:
        _begin_depletion()

    return mini(requested_amount, units_per_trip)


func take(requested_amount: int) -> int:
    return take_from(
        global_position,
        requested_amount
    )


# =========================================================
# GATHER DISTANCE
# =========================================================

func get_gather_face_point(
    worker_position: Vector3
) -> Vector3:
    var local: Vector3 = to_local(
        worker_position
    )

    var hx: float = obstacle_half_size.x
    var hz: float = obstacle_half_size.y

    var nearest := Vector3(
        clampf(local.x, -hx, hx),
        0.0,
        clampf(local.z, -hz, hz)
    )

    if (
        absf(local.x) <= hx
        and absf(local.z) <= hz
    ):
        var dx: float = (
            hx - absf(local.x)
        )

        var dz: float = (
            hz - absf(local.z)
        )

        if dx < dz:
            nearest.x = (
                hx
                * signf(
                    local.x
                    if absf(local.x) > 0.001
                    else 1.0
                )
            )
        else:
            nearest.z = (
                hz
                * signf(
                    local.z
                    if absf(local.z) > 0.001
                    else 1.0
                )
            )

    return to_global(nearest)


func can_gather_from(
    worker_position: Vector3,
    worker_radius: float = 0.28
) -> bool:
    var local: Vector3 = to_local(
        worker_position
    )

    var dx: float = maxf(
        absf(local.x)
        - obstacle_half_size.x,
        0.0
    )

    var dz: float = maxf(
        absf(local.z)
        - obstacle_half_size.y,
        0.0
    )

    var distance_to_surface: float = (
        Vector2(dx, dz).length()
    )

    return (
        distance_to_surface
        <= gather_surface_reach
        + worker_radius
    )


func _begin_depletion() -> void:
    if _depletion_started:
        return

    _depletion_started = true

    gather_slots.clear_all_reservations()
    waiting_slots.clear_all_reservations()

    collision_layer = 0
    collision_mask = 0

    if navigation_obstacle != null:
        navigation_obstacle.avoidance_enabled = false

    depleted.emit(self)

    call_deferred("_free_after_depletion")


func _free_after_depletion() -> void:
    await get_tree().create_timer(
        vanish_duration + 0.05
    ).timeout

    if is_instance_valid(self):
        queue_free()
