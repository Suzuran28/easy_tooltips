extends Node
## Tooltip 全局管理器（Autoload）。
##
## 负责：按延迟显示 [TooltipTrigger]、计算九宫格位置与溢出处理、鼠标跟随、
## 钉住（pin）与销毁。触发器只需调用 [method register_tooltip] 和
## [method deregister_tooltip]，其余逻辑都在这里完成。

const DEFAULT_SETTING: TooltipSetting = preload("res://addons/easy_tooltips/resources/default.tres")
## 承载所有 tooltip 面板的 CanvasLayer 层级。
const TOOLTIP_LAYER := 100
## 钉住动作名，需要在 Input Map 中配置。默认绑定鼠标中键。
const PIN_ACTION := &"easy_tooltips_pin"

var _tooltip_setting: TooltipSetting = DEFAULT_SETTING
var _tooltip_layer: CanvasLayer

## 当前处于“悬停/聚焦”状态、等待延迟或等待显示的触发器。
var _active: Array[TooltipTrigger] = []
## 已显示的视图，键为触发器实例 ID。
var _views: Dictionary[int, TooltipTemplate] = {}
var _triggers: Dictionary[int, TooltipTrigger] = {}
## 通过钉住动作切换的持久固定状态。
var _pinned: Dictionary[int, bool] = {}
## 按住钉住动作时的临时固定状态（PinMode.HOLD）。
var _hold_pinned: Dictionary[int, bool] = {}
## 刚创建、尚未完成首次布局的面板；等一帧后再计算尺寸与位置。
var _fitting: Dictionary[int, bool] = {}
## 正在播放的打开动画，键为触发器实例 ID。
var _open_tweens: Dictionary[int, Tween] = {}
## 正在播放的关闭动画，键为触发器实例 ID。
var _close_tweens: Dictionary[int, Tween] = {}
## 正在播放关闭动画、等待释放的视图。
var _closing: Dictionary[int, bool] = {}
## 打开/关闭动画回调。由 [method set_open_animation] 等公开方法设置，不写入资源。
var _open_animation: Callable
var _close_animation: Callable

func _ready() -> void:
	_tooltip_layer = CanvasLayer.new()
	_tooltip_layer.name = "TooltipLayer"
	_tooltip_layer.layer = TOOLTIP_LAYER
	add_child(_tooltip_layer)

	if not InputMap.has_action(PIN_ACTION):
		push_warning("未找到输入动作“%s”，钉住功能不会生效。请在项目设置的 Input Map 中添加该动作。" % PIN_ACTION)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_update_views()
	_update_active(now)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(PIN_ACTION):
		_on_pin_pressed()
	elif event.is_action_released(PIN_ACTION):
		_on_pin_released()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			if not _views.is_empty():
				hide_all()
				get_viewport().set_input_as_handled()

#region Private
func _on_pin_pressed() -> void:
	var trigger := _find_pin_target()
	if trigger == null:
		return

	var id := trigger.get_instance_id()
	if not _views.has(id):
		_show(trigger)
		if not _views.has(id):
			return

	match int(get_setting("pin_mode", trigger)):
		TooltipEnums.PinMode.TOGGLE:
			toggle_pin(trigger)
			get_viewport().set_input_as_handled()
		TooltipEnums.PinMode.HOLD:
			_hold_pinned[id] = true
			_update_pin_icon(id)
			get_viewport().set_input_as_handled()

func _on_pin_released() -> void:
	if _hold_pinned.is_empty():
		return

	for id in _hold_pinned.keys():
		_hold_pinned.erase(id)
		_update_pin_icon(id)
		var trigger: TooltipTrigger = _triggers.get(id)
		if not is_instance_valid(trigger):
			_hide_view(id)
			continue
		if not _is_pinned(id) and not trigger.is_trigger_active():
			_hide_view(id)
	get_viewport().set_input_as_handled()

## 选择钉住动作的目标：优先鼠标悬停的宿主（嵌套时是最深一层），
## 其次是鼠标下方的栈顶面板，最后回退到最近钉住的 Tooltip。
func _find_pin_target() -> TooltipTrigger:
	var mouse := _get_viewport_mouse_position()
	var ids := _views.keys()

	for index in range(_active.size() - 1, -1, -1):
		var trigger := _active[index]
		if not is_instance_valid(trigger):
			continue
		if _closing.has(trigger.get_instance_id()):
			continue
		if int(get_setting("pin_mode", trigger)) == TooltipEnums.PinMode.OFF:
			continue
		if trigger.is_mouse_over():
			return trigger

	for index in range(ids.size() - 1, -1, -1):
		var id: int = ids[index]
		if _closing.has(id):
			continue
		var panel: TooltipTemplate = _views.get(id)
		var trigger: TooltipTrigger = _triggers.get(id)
		if not is_instance_valid(panel) or not is_instance_valid(trigger):
			continue
		if int(get_setting("pin_mode", trigger)) == TooltipEnums.PinMode.OFF:
			continue
		if panel.get_global_rect().has_point(mouse):
			return trigger

	for index in range(ids.size() - 1, -1, -1):
		var id: int = ids[index]
		if _closing.has(id) or not _is_pinned(id):
			continue
		var trigger: TooltipTrigger = _triggers.get(id)
		if is_instance_valid(trigger):
			return trigger

	return null

func _update_active(now: int) -> void:
	for index in range(_active.size() - 1, -1, -1):
		var trigger := _active[index]
		if not is_instance_valid(trigger):
			_active.remove_at(index)
			continue

		var id := trigger.get_instance_id()
		if _views.has(id):
			continue
		if not trigger.is_trigger_active():
			_active.remove_at(index)
			continue

		var delay := int(get_setting("hover_delay", trigger))
		if now - trigger.record_timestamp >= delay:
			_show(trigger)

func _update_views() -> void:
	for id in _views.keys():
		if _closing.has(id):
			# 关闭动画期间不再定位/交互；如果面板被外部释放则立即收尾。
			if not is_instance_valid(_views.get(id)):
				_finish_close(id)
			continue

		var panel: TooltipTemplate = _views.get(id)
		var trigger: TooltipTrigger = _triggers.get(id)

		if not is_instance_valid(panel) or not is_instance_valid(trigger):
			_hide_view(id)
			continue

		if _fitting.has(id):
			# 等待一帧让 RichTextLabel 在确定宽度下完成布局，再取真实尺寸。
			_fitting.erase(id)
			panel.reset_size()
			_place(trigger, panel)
			# 尺寸和位置确定后再启动打开动画。
			_play_open_animation(trigger, panel)
			continue

		if not trigger.is_trigger_active() and not _is_pinned(id):
			# 未钉住的 Tooltip 只用于查看：宿主失去悬停就隐藏，鼠标进入面板也会消失。
			_hide_view(id)
			continue

		# 打开动画期间暂停逐帧定位：否则重设 global_position 会把缩放后的
		# 视觉左上角钉回原位，抵消“围绕中心缩放”。
		if _open_tweens.has(id):
			continue

		# 钉住后 MOUSE_FOLLOW 冻结在钉住时的位置，不再跟随鼠标。
		if _is_pinned(id) and int(get_setting("origin", trigger)) == TooltipEnums.Origin.MOUSE_FOLLOW:
			continue

		# 每帧重新定位，宿主移动、滚动或鼠标跟随都能及时反映。
		_place(trigger, panel)

func _show(trigger: TooltipTrigger) -> void:
	var id := trigger.get_instance_id()
	if _views.has(id) or _closing.has(id):
		return

	var template: PackedScene = get_setting("tooltip_template", trigger)
	if template == null:
		push_warning("TooltipTrigger（%s）未能获取有效的 tooltip_template，无法显示。" % trigger.name)
		_active.erase(trigger)
		return

	var instance := template.instantiate()
	if not (instance is TooltipTemplate):
		push_warning("tooltip_template（%s）的根节点必须继承 TooltipTemplate。" % template.resource_path)
		instance.free()
		_active.erase(trigger)
		return

	var panel := instance as TooltipTemplate
	panel.setup(trigger.title, trigger.content, trigger.footer, trigger.contents)
	panel.set_width(int(get_setting("width", trigger)))
	# 先放到屏幕外，避免首帧以错误尺寸闪现。
	panel.position = Vector2(-100000, -100000)
	_tooltip_layer.add_child(panel)

	_views[id] = panel
	_triggers[id] = trigger
	_pinned.erase(id)
	_hold_pinned.erase(id)
	_fitting[id] = true

## 打开动画：在布局和定位完成后调用，回调约定为
## func(tooltip: TooltipTemplate) -> Tween，返回 null 表示无动画。
func _play_open_animation(trigger: TooltipTrigger, panel: TooltipTemplate) -> void:
	if not _animation_enabled(trigger):
		return

	var tween: Tween = null
	if _open_animation.is_valid():
		var result: Variant = _open_animation.call(panel)
		if result is Tween:
			tween = result
	else:
		# 没有自定义回调时使用内置的淡入缩放。
		tween = TooltipAnimation.fade_in(panel)

	if tween == null or not tween.is_valid():
		return

	var id := trigger.get_instance_id()
	_open_tweens[id] = tween
	tween.finished.connect(_on_open_tween_finished.bind(id), CONNECT_ONE_SHOT)

func _on_open_tween_finished(id: int) -> void:
	_open_tweens.erase(id)

func _kill_open_tween(id: int) -> void:
	var tween: Tween = _open_tweens.get(id)
	if tween != null and tween.is_valid():
		tween.kill()
	_open_tweens.erase(id)

func _animation_enabled(trigger: TooltipTrigger) -> bool:
	var value: Variant
	if is_instance_valid(trigger):
		value = get_setting("enable_animation", trigger)
	else:
		value = get_setting("enable_animation")
	return true if value == null else bool(value)

## 隐藏视图。[param animate] 为 false 时立即释放（用于场景退出、嵌套子面板）。
func _hide_view(id: int, animate := true) -> void:
	if _closing.has(id):
		if not animate:
			_finish_close(id)
		return

	var panel: TooltipTemplate = _views.get(id)
	if not is_instance_valid(panel):
		_erase_view_state(id)
		return

	_kill_open_tween(id)

	# 栈语义：子面板瞬时关闭，只给当前这一层做关闭动画。
	for other_id in _views.keys():
		if other_id == id:
			continue
		var other_trigger: TooltipTrigger = _triggers.get(other_id)
		if is_instance_valid(other_trigger) and panel.is_ancestor_of(other_trigger):
			_hide_view(other_id, false)

	var trigger: TooltipTrigger = _triggers.get(id)
	if is_instance_valid(trigger):
		_active.erase(trigger)

	_pinned.erase(id)
	_hold_pinned.erase(id)
	_fitting.erase(id)
	# 关闭期间内容不可交互，但保留 Pin 图标的显示状态，随淡出一起消失。
	panel.set_interactive(false)

	if not animate or not _animation_enabled(trigger):
		_finish_close(id)
		return

	var tween: Tween = null
	if _close_animation.is_valid():
		var result: Variant = _close_animation.call(panel)
		if result is Tween:
			tween = result
	else:
		tween = TooltipAnimation.fade_out(panel)

	if tween == null or not tween.is_valid():
		_finish_close(id)
		return

	_closing[id] = true
	_close_tweens[id] = tween
	tween.finished.connect(_on_close_tween_finished.bind(id), CONNECT_ONE_SHOT)

func _on_close_tween_finished(id: int) -> void:
	_finish_close(id)

## 关闭收尾：释放面板并清理所有状态。可被动画结束、强制关闭、外部释放重复调用。
func _finish_close(id: int) -> void:
	var tween: Tween = _close_tweens.get(id)
	if tween != null and tween.is_valid():
		tween.kill()
	_close_tweens.erase(id)
	_closing.erase(id)
	_kill_open_tween(id)

	var panel: TooltipTemplate = _views.get(id)
	if is_instance_valid(panel):
		panel.queue_free()
	_erase_view_state(id)

func _erase_view_state(id: int) -> void:
	_views.erase(id)
	_triggers.erase(id)
	_pinned.erase(id)
	_hold_pinned.erase(id)
	_fitting.erase(id)
	_closing.erase(id)
	_close_tweens.erase(id)
	_open_tweens.erase(id)

func _is_pinned(id: int) -> bool:
	return bool(_pinned.get(id, false)) or bool(_hold_pinned.get(id, false))

func _update_pin_icon(id: int) -> void:
	var panel: TooltipTemplate = _views.get(id)
	if not is_instance_valid(panel):
		return
	panel.set_pinned(_is_pinned(id))

	# 钉住的瞬间把 MOUSE_FOLLOW 面板固定到当前鼠标位置，之后停止跟随。
	var trigger: TooltipTrigger = _triggers.get(id)
	if _is_pinned(id) and is_instance_valid(trigger) \
			and int(get_setting("origin", trigger)) == TooltipEnums.Origin.MOUSE_FOLLOW:
		_place(trigger, panel)

func _place(trigger: TooltipTrigger, panel: TooltipTemplate) -> void:
	if not is_instance_valid(panel) or not is_instance_valid(trigger):
		return

	var anchor := _get_anchor_rect(trigger)
	var alignment := int(get_setting("alignment", trigger))
	var panel_size := panel.size
	var position := _alignment_position(anchor, alignment, panel_size)
	position = _resolve_overflow(position, anchor, alignment, panel_size, int(get_setting("overflow", trigger)), trigger.offset)
	panel.global_position = position

## 九宫格对齐：左右/上下/居中的分量分别计算。
func _alignment_position(anchor: Rect2, alignment: int, panel_size: Vector2) -> Vector2:
	return Vector2(
		_placement_x(anchor, _horizontal_side(alignment), panel_size),
		_placement_y(anchor, _vertical_side(alignment), panel_size)
	)

func _placement_x(anchor: Rect2, side: int, panel_size: Vector2) -> float:
	if side < 0:
		return anchor.position.x - panel_size.x
	if side > 0:
		return anchor.end.x
	return anchor.position.x + anchor.size.x * 0.5 - panel_size.x * 0.5

func _placement_y(anchor: Rect2, side: int, panel_size: Vector2) -> float:
	if side < 0:
		return anchor.position.y - panel_size.y
	if side > 0:
		return anchor.end.y
	return anchor.position.y + anchor.size.y * 0.5 - panel_size.y * 0.5

## -1 = 左/上，0 = 居中，1 = 右/下。
func _horizontal_side(alignment: int) -> int:
	match alignment:
		TooltipEnums.Alignment.TOP_LEFT, TooltipEnums.Alignment.MIDDLE_LEFT, TooltipEnums.Alignment.BOTTOM_LEFT:
			return -1
		TooltipEnums.Alignment.TOP_RIGHT, TooltipEnums.Alignment.MIDDLE_RIGHT, TooltipEnums.Alignment.BOTTOM_RIGHT:
			return 1
		_:
			return 0

func _vertical_side(alignment: int) -> int:
	match alignment:
		TooltipEnums.Alignment.TOP_LEFT, TooltipEnums.Alignment.TOP_CENTER, TooltipEnums.Alignment.TOP_RIGHT:
			return -1
		TooltipEnums.Alignment.BOTTOM_LEFT, TooltipEnums.Alignment.BOTTOM_CENTER, TooltipEnums.Alignment.BOTTOM_RIGHT:
			return 1
		_:
			return 0

func _resolve_overflow(position: Vector2, anchor: Rect2, alignment: int, panel_size: Vector2, mode: int, offset: Vector2) -> Vector2:
	if mode == TooltipEnums.Overflow.NONE:
		return position + offset

	var bounds := _get_screen_bounds(panel_size)
	var result := position

	if mode == TooltipEnums.Overflow.FLIP:
		if result.x < bounds.position.x or result.x + panel_size.x > bounds.end.x:
			result.x = _placement_x(anchor, -_horizontal_side(alignment), panel_size)
		if result.y < bounds.position.y or result.y + panel_size.y > bounds.end.y:
			result.y = _placement_y(anchor, -_vertical_side(alignment), panel_size)

	# FLIP 之后仍可能越界（例如宿主紧贴屏幕边缘），统一钳制兜底。
	result += offset
	result.x = clampf(result.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - panel_size.x))
	result.y = clampf(result.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - panel_size.y))
	return result

func _get_screen_bounds(panel_size: Vector2) -> Rect2:
	var viewport := _tooltip_layer.get_viewport()
	var screen := viewport.get_visible_rect()
	var margin := float(_get_screen_margin())
	var start := screen.position + Vector2(margin, margin)
	var end := screen.end - Vector2(margin, margin)
	if panel_size.x > end.x - start.x:
		end.x = start.x + panel_size.x
	if panel_size.y > end.y - start.y:
		end.y = start.y + panel_size.y
	return Rect2(start, end - start)

func _get_screen_margin() -> int:
	if _tooltip_setting == null:
		return 8
	return _tooltip_setting.screen_margin

func _get_anchor_rect(trigger: TooltipTrigger) -> Rect2:
	match int(get_setting("origin", trigger)):
		TooltipEnums.Origin.HOST:
			if is_instance_valid(trigger.host):
				return trigger.host.get_global_rect()
			return Rect2(_get_mouse_position(trigger), Vector2.ZERO)
		TooltipEnums.Origin.REMOTE:
			return _get_node_rect(trigger.remote_origin)
		TooltipEnums.Origin.MOUSE:
			return Rect2(trigger.mouse_position, Vector2.ZERO)
		TooltipEnums.Origin.MOUSE_FOLLOW:
			return Rect2(_get_mouse_position(trigger), Vector2.ZERO)
		_:
			return Rect2(Vector2.ZERO, Vector2.ZERO)

func _get_node_rect(node: Node) -> Rect2:
	if not is_instance_valid(node):
		push_warning("TooltipTrigger 的 origin 设置为 REMOTE，但 remote_origin 未设置或已失效。")
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	if node is Control:
		return (node as Control).get_global_rect()
	if node is Node2D:
		return Rect2((node as Node2D).global_position, Vector2.ZERO)

	var position: Variant = node.get("global_position")
	if position is Vector2:
		return Rect2(position, Vector2.ZERO)

	push_warning("remote_origin 需要是 Control、Node2D 或带有 global_position 属性的节点。")
	return Rect2(Vector2.ZERO, Vector2.ZERO)

func _get_mouse_position(trigger: TooltipTrigger) -> Vector2:
	if is_instance_valid(trigger.host):
		return trigger.host.get_global_mouse_position()
	return trigger.get_viewport().get_mouse_position()

func _get_viewport_mouse_position() -> Vector2:
	return _tooltip_layer.get_viewport().get_mouse_position()
#endregion

#region Public
## 由 [TooltipTrigger] 在进入触发状态时调用。
func register_tooltip(trigger: TooltipTrigger) -> void:
	if trigger == null or not is_instance_valid(trigger):
		return
	# 关闭动画进行中再次悬停：直接忽略，等动画结束后需要重新进入宿主。
	if _closing.has(trigger.get_instance_id()):
		return
	if trigger in _active:
		return
	_active.append(trigger)

## 由 [TooltipTrigger] 在离开触发状态时调用。
## 已钉住的视图保留；未钉住的视图播放关闭动画后释放。
func deregister_tooltip(trigger: TooltipTrigger) -> void:
	if trigger == null or not is_instance_valid(trigger):
		return

	_active.erase(trigger)
	var id := trigger.get_instance_id()
	if _closing.has(id):
		return
	if not _views.has(id):
		return
	if _is_pinned(id):
		return
	_hide_view(id)

## 切换某个触发器当前视图的固定状态。
func toggle_pin(trigger: TooltipTrigger) -> void:
	if trigger == null or not is_instance_valid(trigger):
		return

	var id := trigger.get_instance_id()
	if _closing.has(id) or not _views.has(id):
		return

	if _is_pinned(id):
		_pinned.erase(id)
		_hold_pinned.erase(id)
	else:
		_pinned[id] = true
		_hold_pinned.erase(id)

	_update_pin_icon(id)

	if not _is_pinned(id) and not trigger.is_trigger_active():
		_hide_view(id)

## 隐藏某个触发器的 Tooltip（包括固定状态）。[param animate] 为 false 时立即释放。
func hide_tooltip(trigger: TooltipTrigger, animate: bool = true) -> void:
	if trigger == null or not is_instance_valid(trigger):
		return
	var id := trigger.get_instance_id()
	_active.erase(trigger)
	if _closing.has(id) and not animate:
		_finish_close(id)
		return
	_hide_view(id, animate)

## 隐藏全部 Tooltip。[param animate] 为 false 时立即释放。
func hide_all(animate: bool = true) -> void:
	_active.clear()
	for id in _views.keys():
		_hide_view(id, animate)

## 设置打开动画回调：func(tooltip: TooltipTemplate) -> Tween。
## 传入空 Callable() 可恢复内置的 [method TooltipAnimation.fade_in]。
## 回调只保存在 Autoload 中，不会写入资源。
func set_open_animation(callable: Callable) -> void:
	_open_animation = callable

## 获取当前的打开动画回调（可能为无效 Callable）。
func get_open_animation() -> Callable:
	return _open_animation

## 设置关闭动画回调：func(tooltip: TooltipTemplate) -> Tween。
## 传入空 Callable() 可恢复内置的 [method TooltipAnimation.fade_out]；
## 回调返回 null 表示瞬时关闭。
func set_close_animation(callable: Callable) -> void:
	_close_animation = callable

## 获取当前的关闭动画回调（可能为无效 Callable）。
func get_close_animation() -> Callable:
	return _close_animation

## 同时设置打开与关闭动画回调。
func set_animations(open_animation: Callable, close_animation: Callable) -> void:
	_open_animation = open_animation
	_close_animation = close_animation

## 获取生效中的设置：触发器上的值不为 [code]null[/code] 且不是 [code]INHERIT[/code] 时优先使用，
## 否则回退到 [TooltipSetting]。
func get_setting(setting_name: StringName, trigger: TooltipTrigger = null) -> Variant:
	var default_value: Variant = null
	if _tooltip_setting != null:
		default_value = _tooltip_setting.get(setting_name)

	if trigger == null or not is_instance_valid(trigger):
		return default_value

	var value: Variant = trigger.get(setting_name)
	if value == null:
		return default_value
	if typeof(value) == TYPE_INT and int(value) == TooltipEnums.INHERIT:
		return default_value
	return value

## 替换全局默认设置资源。
func set_default_setting(setting: TooltipSetting) -> void:
	if setting == null:
		push_error("TooltipSetting 不能为 null。")
		return
	_tooltip_setting = setting

## 获取当前的全局默认设置资源。
func get_default_setting() -> TooltipSetting:
	return _tooltip_setting
#endregion
