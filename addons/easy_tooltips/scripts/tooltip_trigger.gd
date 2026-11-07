@icon("uid://cd7tt57sj22wa")
extends Node
class_name TooltipTrigger
## 挂载在宿主 [Control] 下的 Tooltip 触发器。
##
## 把本节点添加为宿主控件的子节点即可（宿主会被自动推断），
## 也可以在 [member host] 中手动指定。内容与外观都在 Inspector 中配置，
## 未显式设置（[code]INHERIT[/code]）的项会回退到 [TooltipSetting] 的全局默认值。

## 是否启用。Inspector 勾选和运行时赋值都生效，禁用时会立即隐藏已显示的 Tooltip。
@export var enabled: bool = true
## 宿主控件；留空时自动使用父节点（要求父节点是 [Control]）。
@export var host: Control

@export_group("Content")
## 标题文本（支持 BBCode）。为空时使用模板自身的标题。
@export_multiline var title: String = ""
## 正文文本（支持 BBCode），写入模板的 body_label。为空时使用模板自身的正文。
@export_multiline var content: String = ""
## 页脚文本（支持 BBCode）。为空时使用模板自身的页脚。
@export_multiline var footer: String = ""
## 自定义富内容场景。显示时逐个实例化并挂载到模板的 content_holder 中。
@export var contents: Array[PackedScene] = []

@export_group("Display")
## 使用的面板场景；留空时使用全局默认模板。
@export var tooltip_template: PackedScene
## 相对锚点的对齐方式。
@export var alignment: TooltipEnums.Alignment = TooltipEnums.Alignment.INHERIT
## 锚点来源。
@export var origin: TooltipEnums.Origin = TooltipEnums.Origin.INHERIT
## [constant TooltipEnums.Origin.REMOTE] 时使用的参考节点。
@export var remote_origin: Node
## 在最终位置基础上附加的偏移（像素）。
@export var offset: Vector2 = Vector2.ZERO
## 面板超出屏幕时的处理方式。
@export var overflow: TooltipEnums.Overflow = TooltipEnums.Overflow.INHERIT

@export_group("Behavior")
## 触发方式。
@export var trigger_mode: TooltipEnums.TriggerMode = TooltipEnums.TriggerMode.INHERIT
## 悬停/聚焦多久后显示（毫秒），[code]-1[/code] 表示继承全局设置。
@export var hover_delay: int = -1
## 固定模式。钉住由输入动作 [code]easy_tooltips_pin[/code] 驱动。
@export var pin_mode: TooltipEnums.PinMode = TooltipEnums.PinMode.INHERIT

## 本轮触发开始的时间戳（毫秒），由触发器自身维护。
var record_timestamp: int = 0
## 触发瞬间的鼠标位置，用于 [constant TooltipEnums.Origin.MOUSE] 锚点。
var mouse_position: Vector2 = Vector2.ZERO

var _mouse_inside := false
var _focused := false
var _registered := false
var _connected := false
var _mode := TooltipEnums.TriggerMode.MOUSE
## 上一帧的 enabled，用于轮询运行时直接赋值。
var _enabled_cache := true

func _ready() -> void:
	_enabled_cache = enabled
	_init_default()
	if not _valid_check():
		return
	_connect_host_signals()
	_refresh_active()

func _process(_delta: float) -> void:
	# enabled 是普通导出属性，无法用 setter 拦截运行时赋值，这里做轻量轮询。
	if _enabled_cache == enabled:
		return
	set_enabled(enabled)

func _exit_tree() -> void:
	EasyTooltips.hide_tooltip(self, false)
	if _registered:
		_registered = false
		EasyTooltips.deregister_tooltip(self)

#region Private
func _init_default() -> void:
	if host == null:
		var parent := get_parent()
		if parent is Control:
			host = parent
	_mode = int(EasyTooltips.get_setting("trigger_mode", self))

func _valid_check() -> bool:
	if host == null or not is_instance_valid(host):
		push_warning("TooltipTrigger（%s）未能找到宿主控件，Tooltip 不会显示。" % name)
		return false
	if _uses_mouse() and host.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		push_warning("TooltipTrigger（%s）的宿主控件鼠标过滤器为 MOUSE_FILTER_IGNORE，鼠标触发不会生效。" % name)
	return true

func _connect_host_signals() -> void:
	if _connected or host == null:
		return
	_connected = true

	if _uses_mouse():
		host.mouse_entered.connect(_on_mouse_entered)
		host.mouse_exited.connect(_on_mouse_exited)
	if _uses_focus():
		host.focus_entered.connect(_on_focus_entered)
		host.focus_exited.connect(_on_focus_exited)

	host.tree_exiting.connect(_on_host_tree_exiting)

func _uses_mouse() -> bool:
	return _mode == TooltipEnums.TriggerMode.MOUSE or _mode == TooltipEnums.TriggerMode.BOTH

func _uses_focus() -> bool:
	return _mode == TooltipEnums.TriggerMode.FOCUS or _mode == TooltipEnums.TriggerMode.BOTH

func _refresh_active() -> void:
	var wants := enabled and ((_uses_mouse() and _mouse_inside) or (_uses_focus() and _focused))
	if wants == _registered:
		return

	if wants:
		record_timestamp = Time.get_ticks_msec()
		mouse_position = _get_mouse_global_position()
		_registered = true
		EasyTooltips.register_tooltip(self)
	else:
		_registered = false
		EasyTooltips.deregister_tooltip(self)

func _get_mouse_global_position() -> Vector2:
	if host != null and is_instance_valid(host):
		return host.get_global_mouse_position()
	return get_viewport().get_mouse_position()
#endregion

#region Public
## 运行时启用/禁用触发器。禁用时会立刻隐藏已显示的 Tooltip。
func set_enabled(value: bool) -> void:
	enabled = value
	_enabled_cache = value
	if not is_node_ready():
		return
	_refresh_active()
	if not enabled:
		EasyTooltips.hide_tooltip(self)

## 当前是否处于触发状态（鼠标悬停或已聚焦），且未被禁用。
func is_trigger_active() -> bool:
	if not _registered or not enabled:
		return false
	if host == null or not is_instance_valid(host):
		return false
	return host.is_visible_in_tree()

## 鼠标当前是否位于宿主控件矩形内。
func is_mouse_over() -> bool:
	if host == null or not is_instance_valid(host) or not host.is_visible_in_tree():
		return false
	return host.get_global_rect().has_point(host.get_global_mouse_position())
#endregion

#region Signal Handlers
func _on_mouse_entered() -> void:
	_mouse_inside = true
	_refresh_active()

func _on_mouse_exited() -> void:
	_mouse_inside = false
	_refresh_active()

func _on_focus_entered() -> void:
	_focused = true
	_refresh_active()

func _on_focus_exited() -> void:
	_focused = false
	_refresh_active()

func _on_host_tree_exiting() -> void:
	EasyTooltips.hide_tooltip(self, false)
	_registered = false
	EasyTooltips.deregister_tooltip(self)
#endregion
