extends SceneTree
## Headless regression smoke for the build/shop/storage rehaul. Run with:
## godot --headless --path . --script res://tools/tests/ui_rehaul_smoke.gd

const TARGETS := [
	"res://scripts/ui/common/BunkerPanelStyle.gd",
	"res://scripts/ui/common/BunkerUIComponents.gd",
	"res://scripts/ui/common/ItemPresentation.gd",
	"res://scripts/ui/common/PreviewPresentation.gd",
	"res://scripts/ui/common/BunkerItemCard.gd",
	"res://scripts/ui/common/ControllerUINavigation.gd",
	"res://scripts/ui/common/UIProximityClose.gd",
	"res://scripts/ui/inventory/StorageUI.gd",
	"res://scripts/ui/build/ShopCart.gd",
	"res://scripts/ui/build/BuildCatalogPanel.gd",
	"res://scripts/ui/build/BuildCatalogCard.gd",
	"res://scripts/ui/build/ShopProductCard.gd",
	"res://scripts/ui/build/BuildCursor.gd",
	"res://scripts/ui/build/ShopPanel.gd",
	"res://scripts/ui/build/BuildWorkspace.gd",
	"res://scripts/ui/build/BuildModeHUD.gd",
	"res://scripts/world/build/FarmingShopHelper.gd",
	"res://scripts/world/build/BuildModeController.gd",
	"res://scripts/player/Player.gd",
	"res://scripts/ui/character_creation/CharacterPreviewViewport.gd",
]
const STORAGE_UI_SCRIPT: GDScript = preload("res://scripts/ui/inventory/StorageUI.gd")

var failures := 0

class FakeItem:
	extends Node3D
	var label := ""
	func _init(value: String) -> void: label = value
	func get_display_name() -> String: return label

class FakeInventory:
	extends Node
	func is_full() -> bool: return false

class FakeWaterBottle:
	extends Node3D
	func get_display_name() -> String: return "Water Bottle"
	func get_bottle_badge_info() -> Dictionary:
		return {"fill_mL": 562.0, "max_fill_mL": 750.0, "quality": 87.0}

class FakeWallet:
	extends Node3D
	var cash := 0
	var charges := 0
	func get_cash() -> int: return cash
	func spend_cash(amount: int) -> bool:
		if amount > cash: return false
		cash -= amount
		charges += 1
		return true
	func add_cash(amount: int) -> void: cash += amount

class FakeStorage:
	extends Node3D
	var slots: Array = [FakeItem.new("Bottom"), FakeItem.new("Middle"), FakeItem.new("Top")]
	var last_index := -1
	func _ready() -> void:
		for item in slots:
			add_child(item)
	func get_ui_config() -> Dictionary:
		return {"title": "Test shelf", "slot_count": 3, "grid_cols": 2, "grid_rows": 2,
			"display_order": [2, 1, 0], "closes_on_action": true,
			"primary_button_tooltip": "Carry item", "primary_requires_empty_hands": false}
	func get_slot_display(index: int) -> Array:
		return [slots[index], 1] if slots[index] != null else [null, 0]
	func take_for_inventory(index: int, _inventory: Node) -> bool:
		last_index = index
		slots[index] = null
		return true
	func take_for_carry(index: int, _interaction: Node) -> bool:
		last_index = index
		slots[index] = null
		return true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in TARGETS:
		var resource := ResourceLoader.load(path)
		_check(
			resource != null
			and (not resource is Script or (resource as Script).can_instantiate()),
			"loads %s" % path)
	_test_cart()
	_test_checkout_guards()
	_test_panel_geometry()
	_test_item_details()
	await _test_runtime_ui()
	await _test_storage_contract()
	if failures == 0:
		print("UI_REHAUL_SMOKE_OK: %d scripts + cart/geometry contracts" % TARGETS.size())
	quit(failures)

func _test_runtime_ui() -> void:
	var hud_script := load("res://scripts/ui/build/BuildModeHUD.gd") as GDScript
	var hud: CanvasLayer = hud_script.new()
	root.add_child(hud)
	await process_frame
	hud.show_hud()
	var workspace: Control = hud.get("_workspace")
	_check(workspace != null, "build workspace instantiates")
	_check(workspace.catalog.size.x <= 500.0 and workspace.catalog.size.y <= 620.0,
		"build catalog keeps compact desktop proportions")
	var viewport_size := root.get_viewport().get_visible_rect().size
	_check(workspace.catalog.position.y + workspace.catalog.size.y <= viewport_size.y,
		"build catalog remains inside the viewport after minimum-size calculation")
	_check(workspace.catalog.custom_maximum_size == workspace.catalog.size,
		"build catalog has an authoritative maximum bound")
	var object_grid: GridContainer = workspace.catalog.get("_items") as GridContainer
	_check(object_grid != null and object_grid.columns == 2,
		"build catalog presents large previews in a two-column object grid")
	var first_card: Control = workspace.catalog.get("_first_item") as Control
	_check(first_card != null and first_card.custom_minimum_size.y >= 160.0,
		"build cards reserve enough height for previews and information bands")
	var price_label: Label = first_card.get("_price_label") as Label
	_check(price_label != null \
		and price_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER,
		"build-card prices are centered in their badges")
	var category_grid: GridContainer = workspace.catalog.get("_category_grid") as GridContainer
	_check(category_grid != null and category_grid.columns == 4,
		"build categories are immediate labeled controls instead of a dropdown")
	_check(workspace.catalog.get("_mode_card") != null,
		"build catalog has an explicit browse/placement state block")
	_check(workspace.shop.size.x >= 900.0 and workspace.shop.size.x <= 1380.0 \
		and workspace.shop.size.y <= 780.0,
		"shop uses a bounded desktop workspace")
	var products: GridContainer = workspace.shop.get("_products") as GridContainer
	_check(products != null and products.columns == 3,
		"shop uses a three-column premium product catalog")
	var product_viewport: Control = workspace.shop.get("_product_viewport") as Control
	var cart_viewport: Control = workspace.shop.get("_cart_viewport") as Control
	_check(product_viewport != null and product_viewport.clip_contents \
		and cart_viewport != null and cart_viewport.clip_contents,
		"shop product and cart content stay inside explicit scroll viewports")
	_check(workspace.shop_button.focus_mode == Control.FOCUS_ALL,
		"shop shortcut participates in controller focus navigation")
	_check(not _contains_button_text(workspace.catalog, "Place selected item"),
		"build catalog has no second placement confirmation")
	hud.open_construct_menu()
	await process_frame
	_check(workspace.catalog.visible and not workspace.shop.visible,
		"catalog and shop are separate workflows")
	var first_item: Dictionary = hud.CONSTRUCT_ITEMS[0]
	hud.choose_build_item(int(first_item.tile_id))
	await process_frame
	_check(workspace.catalog.visible and bool(hud.get("_submenu_open")),
		"catalog remains open while an object is being placed")
	_check(int(workspace.catalog.get("_selected_tile_id")) == int(first_item.tile_id),
		"active placement remains visibly selected in the open catalog")
	hud.open_shop_menu()
	await process_frame
	_check(workspace.shop.visible and not workspace.catalog.visible, "shop opens its own overlay")
	_check(workspace.shop.position.y + workspace.shop.size.y <= viewport_size.y,
		"shop remains inside the viewport after minimum-size calculation")
	var shop_cart: ShopCart = workspace.shop.cart
	shop_cart.change(2, 1)
	await process_frame
	var cart_targets: Dictionary = workspace.shop.get("_cart_focus_targets") as Dictionary
	var plus_button: Button = cart_targets.get("2:plus") as Button
	if plus_button != null:
		plus_button.grab_focus()
	shop_cart.change(2, 1)
	await process_frame
	await process_frame
	cart_targets = workspace.shop.get("_cart_focus_targets") as Dictionary
	var restored_plus: Button = cart_targets.get("2:plus") as Button
	_check(plus_button != null and root.get_viewport().gui_get_focus_owner() == restored_plus,
		"cart quantity refresh restores the exact controller focus target")
	## Reproduce the reported lifecycle: leave Build Mode while Shop owns the
	## workspace, then enter again. The catalog and shared dock must be restored
	## without relying on any remembered child visibility.
	hud.hide_hud()
	await process_frame
	hud.show_hud()
	await process_frame
	_check(bool(hud.get("_submenu_open")) \
		and String(hud.get("_submenu_source")) == "construct",
		"build re-entry resets the workspace to Construct")
	_check(workspace.catalog.visible and not workspace.shop.visible,
		"build re-entry opens a usable fresh catalog after exiting from Shop")
	_check(int(workspace.catalog.get("_selected_tile_id")) == -1,
		"build re-entry carries no stale placement selection")
	var tool_dock: PanelContainer = workspace.get("_toolbar_panel") as PanelContainer
	_check(tool_dock != null and tool_dock.visible and workspace.shop_button.visible,
		"shop shutdown cannot leak hidden shared controls into the next session")
	_check(not _contains_button_text(workspace.shop, "Return to build catalog"),
		"shop omits the redundant return-to-build button")
	_check(ControllerUINavigation.owns_directional_input(self), "build workspace owns d-pad focus")
	_check(not ControllerUINavigation.blocks_world_cursor_input(self),
		"build workspace leaves its right-stick pointer active")
	hud.close_workspace_menu()
	await process_frame
	_check(ControllerUINavigation.owns_directional_input(self),
		"toolbar remains controller-navigable when catalogs are closed")
	await _test_focusable_scrollbar()
	var storage: CanvasLayer = STORAGE_UI_SCRIPT.new()
	root.add_child(storage)
	await process_frame
	var storage_panel: PanelContainer = storage.get("_panel")
	_check(storage_panel != null and storage_panel.size.x <= 460.0,
		"storage inspector is a compact in-world rail")
	storage.free()

func _test_focusable_scrollbar() -> void:
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(200, 100)
	ui.add_child(scroll)
	var content := Control.new()
	content.custom_minimum_size = Vector2(180, 600)
	scroll.add_child(content)
	var nav := ControllerUINavigation.new()
	nav.ui_root = ui
	ui.add_child(nav)
	await process_frame
	nav.call("_prepare_scrollbars", ui)
	var bar := scroll.get_v_scroll_bar()
	_check(bar.focus_mode == Control.FOCUS_ALL, "visible scrollbar becomes a controller focus target")
	bar.grab_focus()
	var before := bar.value
	var handled: bool = nav.call("_adjust_focused_range", Vector2.DOWN, 1.0)
	_check(handled and bar.value > before, "focused scrollbar scrolls with directional input")
	ui.free()

func _test_storage_contract() -> void:
	var player := Node3D.new()
	player.add_to_group("player")
	root.add_child(player)
	var target := FakeStorage.new()
	root.add_child(target)
	var storage := STORAGE_UI_SCRIPT.new() as CanvasLayer
	storage.inventory = FakeInventory.new()
	storage.add_child(storage.inventory)
	root.add_child(storage)
	await process_frame
	var empty_target := FakeStorage.new()
	root.add_child(empty_target)
	empty_target.slots = [null, null, null]
	storage.open(empty_target)
	await process_frame
	await process_frame
	var panel: PanelContainer = storage.get("_panel")
	var viewport_size := root.get_viewport().get_visible_rect().size
	_check(panel.position.y + panel.size.y <= viewport_size.y - 24.0,
		"empty storage remains inside the viewport on its first layout")
	storage.close()
	empty_target.free()
	storage.open(target)
	await process_frame
	_check(absf((panel.position.x + panel.size.x) - (viewport_size.x - 24.0)) <= 1.0,
		"storage rail stays right aligned")
	_check(absf((panel.position.y + panel.size.y * 0.5) - viewport_size.y * 0.5) <= 1.0,
		"storage rail is vertically centered")
	var shown_ids: Array = storage.get("_shown_ids")
	_check(shown_ids[0] == (target.slots[2] as Node).get_instance_id(),
		"storage preserves physical display_order mapping")
	storage.call("_select", 0)
	storage.call("_take_for_inventory")
	_check(storage.is_open, "inventory transfer keeps storage open")
	_check(target.last_index == 2, "inventory transfer delegates mapped data slot")
	_check(panel.position.y + panel.size.y <= viewport_size.y - 24.0,
		"storage remains bounded after an inventory transfer")
	storage.call("_select", 1)
	storage.call("_take_for_carry")
	_check(not storage.is_open, "primary carry preserves close-on-action contract")
	storage.open(target)
	player.global_position = Vector3(10, 0, 0)
	await process_frame
	_check(not storage.is_open, "walking away closes storage from live host distance")
	storage.free()
	target.free()
	player.free()

func _test_cart() -> void:
	var script := load("res://scripts/ui/build/ShopCart.gd") as GDScript
	var cart: RefCounted = script.new()
	_check(cart.change(2, 1), "cart accepts first item")
	_check(cart.change(2, 2), "cart combines quantities")
	_check(cart.quantity(2) == 3, "cart quantity is stable")
	_check(cart.total({2: {"price": 25}}) == 75, "cart computes total")
	cart.change(2, -3)
	_check(cart.lines.is_empty(), "zero quantity removes line")
	for _i in ShopCart.MAX_ITEMS:
		cart.change(1, 1)
	_check(not cart.change(1, 1) and cart.quantity(1) == ShopCart.MAX_ITEMS,
		"cart enforces bounded order size")

func _test_checkout_guards() -> void:
	var controller_script := load("res://scripts/world/build/BuildModeController.gd") as GDScript
	var helper_script := load("res://scripts/world/build/FarmingShopHelper.gd") as GDScript
	if controller_script == null or not controller_script.can_instantiate() \
			or helper_script == null or not helper_script.can_instantiate():
		_check(false, "checkout scripts instantiate")
		return
	var controller: Node3D = controller_script.new()
	var wallet := FakeWallet.new()
	controller.set("world_node", wallet)
	var helper: RefCounted = helper_script.new(controller)
	var result: Dictionary = helper.checkout_order({})
	_check(not result.ok and wallet.charges == 0, "empty checkout never charges")
	result = helper.checkout_order({999: 1})
	_check(not result.ok and wallet.charges == 0, "unknown shop ID never charges")
	result = helper.checkout_order({1: 1})
	_check(not result.ok and wallet.charges == 0, "insufficient-cash checkout never charges")
	controller.free()
	wallet.free()

func _test_panel_geometry() -> void:
	var style := load("res://scripts/ui/common/BunkerPanelStyle.gd") as GDScript
	var panel_style: StyleBoxFlat = style.box()
	_check(panel_style.bg_color.a == 1.0, "panel is opaque over live world")
	_check(panel_style.corner_radius_top_left == 8, "panel radius token")

func _test_item_details() -> void:
	var bottle := FakeWaterBottle.new()
	var detail := ItemPresentation.detail(bottle)
	_check("562 / 750 mL" in detail and "87%" in detail,
		"storage exposes water fill and quality")
	bottle.free()

func _contains_button_text(root_node: Node, expected: String) -> bool:
	for candidate: Node in root_node.find_children("*", "Button", true, false):
		if candidate is Button and (candidate as Button).text == expected:
			return true
	return false

func _check(ok: bool, label: String) -> void:
	if ok:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: %s" % label)
