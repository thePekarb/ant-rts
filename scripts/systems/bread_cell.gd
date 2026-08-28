class_name BreadCell
extends Node3D

@export var cell_id: int = 0
@export var surface_index: int = 0
@export var starts_exposed: bool = false
@export var neighbor_ids: Array[int] = []

var is_removed: bool = false
var is_exposed: bool = false
var reserved_by: Node = null
