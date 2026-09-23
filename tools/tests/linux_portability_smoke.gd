extends SceneTree
## Run with isolated XDG_DATA_HOME; exercises Windows settings migration on Linux.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var graphics: Node = root.get_node("GraphicsSettings")
	var path: String = graphics.CFG_PATH
	var existed: bool = FileAccess.file_exists(path)
	var original: PackedByteArray = FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "rendering_driver", "d3d12")
	if cfg.save(path) != OK:
		push_error("Could not write isolated migration fixture")
		quit(1)
		return
	graphics._load()
	var expected: String = "d3d12" if OS.get_name() == "Windows" else "vulkan"
	var passed: bool = graphics.rendering_driver == expected
	passed = passed and graphics.is_rendering_driver_supported("vulkan")
	passed = passed and not graphics.is_rendering_driver_supported("invalid-driver")
	passed = passed and graphics.is_rendering_driver_supported("d3d12") == (OS.get_name() == "Windows")
	if existed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(original)
		file.close()
	else:
		DirAccess.remove_absolute(path)
	if not passed:
		push_error("Windows rendering preferences were not migrated safely")
		quit(1)
		return
	print("LINUX_PORTABILITY_SMOKE_OK")
	quit(0)
