extends SceneTree

func _init():
	assign_uids()
	write_imports()
	quit(0)

const CLIPS := ["idle", "walk", "run", "idle_carry", "walk_carry", "run_carry"]
const MODELS := ["Superhero_Male_FullBody", "Superhero_Female_FullBody"]
const MIXAMO_MAP := "res://assets/models/player/bone_map_mixamo.tres"
const NATIVE_MAP := "res://assets/models/player/bone_map_native.tres"

func assign_uids():
	for p: String in [MIXAMO_MAP, NATIVE_MAP]:
		var res: Resource = load(p)
		var err := ResourceSaver.save(res)
		print("uid assign ", p, " err=", err)

func write_imports():
	var clip_settings := _base_settings(MIXAMO_MAP)
	for n: String in CLIPS:
		var p := "res://assets/models/player/" + n + ".fbx.import"
		_apply(p, {"PATH:Skeleton3D": clip_settings})

	var model_settings := _base_settings(NATIVE_MAP)
	for n: String in MODELS:
		var p := "res://assets/models/player/" + n + ".gltf.import"
		_apply(p, {"PATH:Armature/Skeleton3D": model_settings})

func _base_settings(bm_path: String) -> Dictionary:
	return {
		"retarget/bone_map": load(bm_path),
		"retarget/bone_renamer/rename_bones": true,
		"retarget/bone_renamer/unique_node/make_unique": true,
		"retarget/bone_renamer/unique_node/skeleton_name": "GeneralSkeleton",
		"retarget/rest_fixer/apply_node_transforms": true,
		"retarget/rest_fixer/normalize_position_tracks": true,
		"retarget/rest_fixer/reset_all_bone_poses_after_import": true,
		"retarget/rest_fixer/retarget_method": 1,
		"retarget/rest_fixer/keep_global_rest_on_leftovers": true,
		"retarget/rest_fixer/use_global_pose": true,
		"retarget/rest_fixer/original_skeleton_name": "OriginalSkeleton",
	}

func _apply(import_path: String, nodes: Dictionary):
	var cfg := ConfigFile.new()
	var err := cfg.load(import_path)
	if err != OK:
		push_error("load fail " + import_path + " err=" + str(err))
		return
	for key in cfg.get_section_keys("params"):
		if key.begins_with("retarget/"):
			cfg.erase_section_key("params", key)
	cfg.set_value("params", "_subresources", {"nodes": nodes})
	err = cfg.save(import_path)
	print("wrote ", import_path, " err=", err)