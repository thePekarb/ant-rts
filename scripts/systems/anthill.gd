class_name Anthill
extends StaticBody3D


@onready var deposit_slots: RadialSlots = $DepositSlots

var stored_resources: Dictionary = {
	"food": 0
}


func _ready() -> void:
	# Муравейник на Collision Layer 5 (маска 16: 1 << 4 = 16) и Layer 1 (Здания/Препятствия)
	collision_layer = 16 | 1


func deposit(resource_id: String, amount: int) -> void:
	stored_resources[resource_id] = stored_resources.get(resource_id, 0) + amount
	print("[Муравейник] Сдано ", amount, " ед. ", resource_id, "! Всего в хранилище: ", stored_resources[resource_id])
