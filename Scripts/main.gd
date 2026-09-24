extends Control


func _ready():
	var size = DisplayServer.screen_get_size()
	var is_portrait = size.x < size.y
	var is_tablet_like = min(size.x, size.y) > 900
	
	var target_scene = "res://Scenes/mobile_gui.tscn"
	if is_portrait and get_device_category() == "phone":
		target_scene = "res://Scenes/mobile_gui.tscn"
	else:
		target_scene = "res://Scenes/desktop_gui.tscn"
	
	get_tree().call_deferred("change_scene_to_file", target_scene)

func get_device_category() -> String:
	var size = DisplayServer.screen_get_size()
	var min_dim = min(size.x, size.y)
	var max_dim = max(size.x, size.y)
	var aspect = float(max_dim) / float(min_dim)
	
	if OS.has_feature("mobile"):
		return "phone"
	else:
		return "pc"
