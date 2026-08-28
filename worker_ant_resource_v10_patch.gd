# ============================================================
# WorkerAnt V10 resource integration patch
# ============================================================
#
# This is NOT a full WorkerAnt replacement.
# Add these small changes to your current worker_ant_unified.gd.
#
# Goal:
# - an ant reserves a REAL exposed bread piece before gathering;
# - two ants cannot harvest the same piece;
# - after that piece is removed, only its neighbors become the next frontier.
#
# ------------------------------------------------------------
# 1. Add a variable near the other resource variables:
# ------------------------------------------------------------

var reserved_bread_cell: BreadCellV10 = null


# ------------------------------------------------------------
# 2. In _process_gather(), AFTER the ant reached its GatherSlot
#    but BEFORE starting ANT_Gather, add:
# ------------------------------------------------------------

func _ensure_bread_piece_reserved() -> bool:
    if resource_target == null:
        return false

    if not resource_target.has_method(
        "reserve_piece_for_worker"
    ):
        # It is another generic resource type.
        return true

    if (
        reserved_bread_cell != null
        and is_instance_valid(
            reserved_bread_cell
        )
        and not reserved_bread_cell.is_removed
    ):
        return true

    reserved_bread_cell = (
        resource_target
        .reserve_piece_for_worker(self)
    )

    return reserved_bread_cell != null


# Example inside _process_gather():
#
#     _stop_navigation()
#
#     if not _ensure_bread_piece_reserved():
#         # No exposed chunk is free yet.
#         # Keep the gather order alive and wait.
#         animation_state.travel("Idle")
#         return Vector3.ZERO
#
#     var face_point = resource_target.get_gather_face_point(global_position)
#     _face_position(face_point, delta)
#     ...
#     animation_state.travel("Gather")


# ------------------------------------------------------------
# 3. Replace the resource take call inside
#    _complete_gather_cycle().
# ------------------------------------------------------------

func _take_resource_v10() -> int:
    if resource_target == null:
        return 0

    if resource_target.has_method(
        "consume_reserved_piece"
    ):
        var amount: int = (
            resource_target
            .consume_reserved_piece(self)
        )

        reserved_bread_cell = null

        return amount

    # Old generic resource fallback.
    return resource_target.take_from(
        global_position,
        resource_target.units_per_trip
    )


# Then change:
#
#     var amount = resource_target.take_from(...)
#
# to:
#
#     var amount: int = _take_resource_v10()


# ------------------------------------------------------------
# 4. Release reservation if the player cancels the order.
#    Put this inside your resource-order cleanup.
# ------------------------------------------------------------

func _release_bread_piece_reservation() -> void:
    if resource_target == null:
        reserved_bread_cell = null
        return

    if resource_target.has_method(
        "release_piece_reservation"
    ):
        resource_target.release_piece_reservation(
            self
        )

    reserved_bread_cell = null


# Call _release_bread_piece_reservation() from:
#
# - _finish_resource_order()
# - a new Move order
# - Attack order
# - die()
#
# BEFORE resource_target is set to null.
