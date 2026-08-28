class_name BreadCellV10
extends Node3D

# Logical piece of bread.
# This node itself is gameplay metadata; visible geometry stays inside ONE MeshInstance3D.

@export_group("Identity")
@export var cell_id: int = -1

# Surface index inside BreadChunksMesh.
# Every logical bread piece must have its own mesh surface.
@export var surface_index: int = -1

@export var kind: StringName = &"crumb"

# True for cells that touch the outside edge when the loaf is intact.
@export var starts_exposed: bool = false

# IDs of adjacent cells.
# They are resolved to actual BreadCellV10 nodes by BreadResourceV10.
@export var neighbor_ids: PackedInt32Array = PackedInt32Array()


var neighbors: Array[BreadCellV10] = []

var is_removed: bool = false
var is_exposed: bool = false

# Weak reference means the cell does not keep the ant alive.
var _reserved_by: WeakRef = null


func setup_initial_state() -> void:
    is_removed = false
    is_exposed = starts_exposed
    _reserved_by = null


func is_reserved() -> bool:
    if _reserved_by == null:
        return false

    var worker: Object = _reserved_by.get_ref()

    if worker == null:
        _reserved_by = null
        return false

    return true


func reserve(worker: Node) -> bool:
    if is_removed:
        return false

    if not is_exposed:
        return false

    if is_reserved():
        var current: Object = _reserved_by.get_ref()

        # The same ant may ask again every frame.
        return current == worker

    _reserved_by = weakref(worker)
    return true


func release(worker: Node = null) -> void:
    if _reserved_by == null:
        return

    if worker == null:
        _reserved_by = null
        return

    var current: Object = _reserved_by.get_ref()

    if current == worker:
        _reserved_by = null


func mark_removed() -> void:
    is_removed = true
    is_exposed = false
    _reserved_by = null


func refresh_exposure() -> void:
    if is_removed:
        is_exposed = false
        return

    # A border cell is always accessible from at least one outside side.
    if starts_exposed:
        is_exposed = true
        return

    # Once any neighbor disappears, this cell becomes part of the new eating front.
    for neighbor in neighbors:
        if neighbor == null:
            continue

        if neighbor.is_removed:
            is_exposed = true
            return

    is_exposed = false
