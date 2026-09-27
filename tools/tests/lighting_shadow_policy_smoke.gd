extends SceneTree
## Headless contract smoke for the two-layer shadow policy.

var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[lighting-shadow-smoke] %s" % message)

func _run() -> void:
	var settings: Node = root.get_node_or_null("GraphicsSettings")
	_check(settings != null, "GraphicsSettings autoload is missing")
	if settings == null:
		quit(1)
		return

	var old_dynamic: bool = settings.shadow_casting_enabled
	var old_quality: int = settings.shadow_quality

	var dynamic_root := Node3D.new()
	var authored_on := MeshInstance3D.new()
	authored_on.mesh = BoxMesh.new()
	var authored_off := MeshInstance3D.new()
	authored_off.mesh = BoxMesh.new()
	authored_off.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dynamic_root.add_child(authored_on)
	dynamic_root.add_child(authored_off)
	root.add_child(dynamic_root)

	settings.shadow_casting_enabled = false
	settings.register_dynamic_shadow_root(dynamic_root)
	_check(authored_on.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"dynamic OFF did not disable an authored caster")
	settings.shadow_casting_enabled = true
	settings._apply_dynamic_shadow_casting()
	_check(authored_on.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		"dynamic ON did not restore authored caster mode")
	_check(authored_off.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"dynamic ON incorrectly enabled an authored-OFF mesh")

	var wall_light: Node3D = load("res://scripts/world/power/WallLight.gd").new()
	wall_light.set("_is_preview_only", true)
	root.add_child(wall_light)
	var spots: Array[Node] = wall_light.find_children("*", "SpotLight3D", true, false)
	var omnis: Array[Node] = wall_light.find_children("*", "OmniLight3D", true, false)
	## Sep 2026 lighting review: the wide spot drew a hard cone edge ("bubble")
	## on nearby walls and banded acne on Low/Medium; the fixture is a cube omni.
	_check(omnis.size() == 1, "wall fixture must own exactly one omni light")
	_check(spots.is_empty(), "wall fixture regressed to the wide cone spot")
	if not omnis.is_empty():
		var omni := omnis[0] as OmniLight3D
		_check(omni.shadow_enabled, "structural wall-light shadows must always be on")
		_check(omni.omni_shadow_mode == OmniLight3D.SHADOW_CUBE,
			"wall light must use cube shadows (dual-paraboloid bends wall shadows)")
		_check(omni.shadow_normal_bias >= 0.6,
			"wall-light normal bias regressed to acne-prone values")

	## Uniform atlas quadrants + filter follow shadow quality.
	settings.shadow_quality = 4096
	settings._apply_to_display()
	var vp: Viewport = root.get_viewport()
	_check(vp.positional_shadow_atlas_quad_0 == vp.positional_shadow_atlas_quad_1
		and vp.positional_shadow_atlas_quad_1 == vp.positional_shadow_atlas_quad_2,
		"primary shadow-atlas quadrants must be uniform (prevents slot churn)")

	## Dynamic-shadow budget: characters only in the nearest lights' maps.
	settings.shadow_casting_enabled = false
	_check(settings.dynamic_shadow_light_budget() == 0, "budget must be 0 with dynamic shadows off")
	settings.shadow_casting_enabled = true
	_check(settings.dynamic_shadow_light_budget() > 0, "budget must be > 0 with dynamic shadows on")
	var probe := OmniLight3D.new()
	root.add_child(probe)
	settings.register_shadow_light(probe)
	_check(probe.shadow_caster_mask & settings.CHARACTER_SHADOW_LAYERS == 0,
		"newly registered light must start without character casters")
	_check(probe.shadow_caster_mask & 1 == 1, "structure layer must always cast")
	probe.queue_free()

	var player_scene: Node = load("res://scenes/player/Player.tscn").instantiate()
	var npc_scene: Node = load("res://scenes/npc/NPC.tscn").instantiate()
	_check(player_scene.get_node_or_null("PlayerModelShadow") == null,
		"player still duplicates its animated model for shadows")
	_check(npc_scene.get_node_or_null("CharacterModelShadow") == null,
		"NPC still duplicates its animated model for shadows")
	player_scene.free()
	npc_scene.free()

	var sun := DirectionalLight3D.new()
	sun.add_to_group("quality_directional_light")
	root.add_child(sun)
	settings.shadow_quality = 1024
	settings._apply_to_display()
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,
		"low quality did not select the one-pass directional shadow mode")
	settings.shadow_quality = 4096
	settings._apply_to_display()
	_check(sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"high quality did not select four directional cascades")

	settings.shadow_casting_enabled = old_dynamic
	settings.shadow_quality = old_quality
	dynamic_root.queue_free()
	wall_light.queue_free()
	sun.queue_free()
	print("[lighting-shadow-smoke] PASS" if _failures == 0 else
		"[lighting-shadow-smoke] FAIL (%d)" % _failures)
	quit(0 if _failures == 0 else 1)
