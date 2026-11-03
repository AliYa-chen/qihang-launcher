extends SceneTree

# Run with the editor matching the bundled Android runtime.
func _initialize() -> void:
	var output: String = ProjectSettings.globalize_path("res://../android-runtime/project.binary")
	var error: Error = ProjectSettings.save_custom(output)
	if error != OK:
		push_error("Could not export runtime project settings: " + error_string(error))
		quit(1)
		return
	print("Android runtime settings exported: " + output)
	quit(0)
