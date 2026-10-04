func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		var wood: ItemData = load("res://items/wood.tres")
		Inventory.add_item(wood, 3)
 
