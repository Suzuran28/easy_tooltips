@tool
extends EditorPlugin
## Easy Tooltips 编辑器插件入口（空壳）。
##
## 启用时补充两项配置：
## 1. [code]EasyTooltips[/code] Autoload，使用脚本 UID（而不是路径）。
## 2. [code]easy_tooltips_pin[/code] 输入动作，默认鼠标中键。
##
## 禁用时移除这两项；编辑器正常退出不会移除（[method _disable_plugin] 只在
## 用户主动禁用插件时调用，[method _exit_tree] 不处理配置）。
##
## 已经存在的同名 Autoload 不会被覆盖；只有当它的值指向本 addon 的脚本 UID
## （或旧版本的路径）时，禁用插件才会移除它。

const AUTOLOAD_KEY := "autoload/EasyTooltips"
const AUTOLOAD_SCRIPT := "scripts/easy_tooltips.gd"
const PIN_ACTION := "easy_tooltips_pin"
const PIN_SETTING_KEY := "input/easy_tooltips_pin"

func _enter_tree() -> void:
	_ensure_setup()

func _enable_plugin() -> void:
	_ensure_setup()

func _disable_plugin() -> void:
	var changed := false
	if _remove_autoload():
		changed = true
	if _remove_pin_action():
		changed = true
	if changed:
		_save_project_settings()

func _ensure_setup() -> void:
	var changed := false
	if _ensure_autoload():
		changed = true
	if _ensure_pin_action():
		changed = true
	if changed:
		_save_project_settings()

func _ensure_autoload() -> bool:
	if ProjectSettings.has_setting(AUTOLOAD_KEY):
		# 旧版本可能把 Autoload 存成路径；如果指向本 addon，则迁移成 UID。
		var current := str(ProjectSettings.get_setting(AUTOLOAD_KEY, ""))
		var uid_value := _get_autoload_value()
		if current == _get_autoload_path_value() and current != uid_value:
			ProjectSettings.set_setting(AUTOLOAD_KEY, uid_value)
			return true
		return false

	var value := _get_autoload_value()
	if value.is_empty():
		return false

	ProjectSettings.set_setting(AUTOLOAD_KEY, value)
	return true

func _remove_autoload() -> bool:
	if not ProjectSettings.has_setting(AUTOLOAD_KEY):
		return false

	var current := str(ProjectSettings.get_setting(AUTOLOAD_KEY, ""))
	if current != _get_autoload_value() and current != _get_autoload_path_value():
		return false

	ProjectSettings.clear(AUTOLOAD_KEY)
	return true

## 优先读取脚本旁边的 .uid 文件；这比依赖编辑器 UID 缓存更可靠。
func _get_autoload_value() -> String:
	var uid := _get_autoload_uid()
	if uid.is_empty():
		push_warning("Easy Tooltips: autoload script has no UID; falling back to path.")
		return _get_autoload_path_value()
	return "*" + uid

func _get_autoload_uid() -> String:
	var script_path := _get_autoload_script_path()
	var uid_path := script_path + ".uid"
	if FileAccess.file_exists(uid_path):
		var text := FileAccess.get_file_as_string(uid_path).strip_edges()
		if text.begins_with("uid://"):
			return text

	var uid := ResourceLoader.get_resource_uid(script_path)
	if uid == ResourceUID.INVALID_ID:
		return ""
	return ResourceUID.id_to_text(uid)

func _get_autoload_path_value() -> String:
	return "*" + _get_autoload_script_path()

func _get_autoload_script_path() -> String:
	var script: Script = get_script()
	return script.resource_path.get_base_dir().path_join(AUTOLOAD_SCRIPT)

func _ensure_pin_action() -> bool:
	if ProjectSettings.has_setting(PIN_SETTING_KEY):
		return false
	if InputMap.has_action(PIN_ACTION):
		return false

	var event := InputEventMouseButton.new()
	event.device = -1
	event.button_index = MOUSE_BUTTON_MIDDLE
	ProjectSettings.set_setting(PIN_SETTING_KEY, {"deadzone": 0.2, "events": [event]})
	# 同步当前编辑器进程的 InputMap，便于在编辑器里立即生效。
	InputMap.add_action(PIN_ACTION)
	InputMap.action_add_event(PIN_ACTION, event)
	return true

func _remove_pin_action() -> bool:
	var changed := false
	if ProjectSettings.has_setting(PIN_SETTING_KEY):
		ProjectSettings.clear(PIN_SETTING_KEY)
		changed = true
	if InputMap.has_action(PIN_ACTION):
		InputMap.erase_action(PIN_ACTION)
		changed = true
	return changed

func _save_project_settings() -> void:
	var error := ProjectSettings.save()
	if error != OK:
		push_warning("Easy Tooltips: failed to save project settings (error %d)." % error)
