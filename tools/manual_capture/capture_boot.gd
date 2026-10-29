extends Node
## Documentation screenshots: hands over to capture_driver.gd, which lives on
## the root so it survives scene changes.

func _ready() -> void:
	var driver: Node = (load("res://tools/manual_capture/capture_driver.gd") as GDScript).new()
	driver.name = "ManualCapture"
	get_tree().root.add_child.call_deferred(driver)
