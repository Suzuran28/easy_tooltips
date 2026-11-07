extends PanelContainer
class_name TooltipTemplate
## Tooltip 面板基类。
##
## 面板由 [EasyTooltips] 在显示时实例化，并由 [TooltipTrigger] 传入内容。
## 自定义面板可以继承本类并重写 [method when_empty] 来做额外排版，
## 也可以直接在子类里覆盖 [method _when_empty]。
##
## 交互约定：未钉住时整个面板鼠标穿透，只用于查看；钉住后面板本身拦截鼠标，
## 并启用 [member content_holder] 内控件的交互，因此内容里的按钮和嵌套 Tooltip 只在钉住态可用。

## 标题标签，必填。
@export var title_label: RichTextLabel
## 正文标签，可选；触发器上的 [member TooltipTrigger.content] 会写入这里。
@export var body_label: RichTextLabel
## 自定义内容的父容器，必填。
@export var content_holder: Container
## 页脚标签，必填。
@export var footer_label: RichTextLabel
## 标题与正文之间的分隔线，可选；标题为空时会自动隐藏。
@export var title_separator: Control
## 钉住状态图标，可选；固定 Tooltip 时显示。
@export var pin_icon: Control
## 预置的自定义内容场景，显示时会实例化到 [member content_holder] 下。
@export var contents: Array[PackedScene] = []

## 内容子控件在“钉住可交互”状态下的原始 mouse_filter。
var _content_filters: Dictionary[Control, int] = {}
var _title: String = ""
var _body: String = ""
var _footer: String = ""
var _pinned := false
var _interactive := false
var _built := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _is_valid():
		push_error("TooltipTemplate（%s）的导出变量未正确设置：title_label、content_holder、footer_label 均为必填。" % name)
		return
	_build()
	_capture_content_filters()
	_apply_mouse_passthrough()
	set_pinned(false)
	reset_size()

## 由 [EasyTooltips] 在实例化后、加入场景树前调用。
## [param extra_contents] 中的场景会在面板就绪后逐一实例化。
func setup(title: String, body: String, footer: String, extra_contents: Array[PackedScene] = []) -> void:
	if not title.is_empty():
		_title = title
	if not body.is_empty():
		_body = body
	if not footer.is_empty():
		_footer = footer

	for scene in extra_contents:
		if scene != null:
			contents.append(scene)

	if is_node_ready():
		_build()
		reset_size()

## 设置面板宽度。<= 0 时保留模板自身的宽度。
func set_width(value: int) -> void:
	if value <= 0:
		return
	custom_minimum_size = Vector2(value, custom_minimum_size.y)
	size = Vector2(value, size.y)

func _is_valid() -> bool:
	return title_label != null and content_holder != null and footer_label != null

func _build() -> void:
	if _built:
		return
	_built = true
	_apply_texts()
	_mount_contents()
	_when_empty()

func _apply_texts() -> void:
	if title_label != null and not _title.is_empty():
		title_label.text = _title
	if body_label != null and not _body.is_empty():
		body_label.text = _body
	if footer_label != null and not _footer.is_empty():
		footer_label.text = _footer

func _mount_contents() -> void:
	for scene in contents:
		if scene == null:
			continue
		var instance := scene.instantiate()
		if instance == null:
			push_warning("无法实例化 Tooltip 自定义内容场景：%s" % scene.resource_path)
			continue
		content_holder.add_child(instance)

func _when_empty() -> void:
	if title_label != null:
		title_label.visible = not title_label.text.strip_edges().is_empty()
	if body_label != null:
		body_label.visible = not body_label.text.strip_edges().is_empty()
	if footer_label != null:
		footer_label.visible = not footer_label.text.strip_edges().is_empty()
	if title_separator != null:
		title_separator.visible = title_label != null and title_label.visible
	if content_holder != null:
		content_holder.visible = _has_visible_content()

	when_empty()

## 内容为空时的扩展点，供子类重写。
## 基类在此处不做任何事；[member title_separator] 的显隐已由 [method _when_empty] 处理。
func when_empty() -> void:
	pass

## 设置钉住状态，并同步 [member pin_icon] 的显隐、面板拦截鼠标与内容区交互。
func set_pinned(value: bool) -> void:
	_pinned = value
	if pin_icon != null:
		pin_icon.visible = value
	set_interactive(value)
	# 图标显隐会改变标题行的最小尺寸，已就绪时重新适配一次。
	if _built and is_inside_tree():
		reset_size()

## 设置面板是否为可交互状态：可交互时面板拦截鼠标（不再穿透到下层 UI），
## 内容区恢复交互；否则整个面板鼠标穿透。关闭动画期间会关闭交互，但不改变 Pin 图标。
func set_interactive(value: bool) -> void:
	_interactive = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	_apply_content_interaction(value)

## 面板当前是否可交互（拦截鼠标）。
func is_interactive() -> bool:
	return _interactive

## 当前是否处于钉住状态。
func is_pinned() -> bool:
	return _pinned

func _capture_content_filters() -> void:
	_content_filters.clear()
	for child in content_holder.get_children():
		_capture_filters(child)

func _capture_filters(node: Node) -> void:
	if node is Control:
		_content_filters[node as Control] = (node as Control).mouse_filter
	for child in node.get_children():
		_capture_filters(child)

func _apply_content_interaction(interactive: bool) -> void:
	for control in _content_filters.keys():
		if is_instance_valid(control):
			control.mouse_filter = _content_filters[control] if interactive else Control.MOUSE_FILTER_IGNORE

## 让面板结构节点始终鼠标穿透；内容区是否可交互由 [method set_pinned] 控制。
func _apply_mouse_passthrough() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_passthrough_to_children(self)

func _apply_passthrough_to_children(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		if child == content_holder:
			continue
		_apply_passthrough_to_children(child)

func _has_visible_content() -> bool:
	for child in content_holder.get_children():
		if child is CanvasItem:
			if (child as CanvasItem).visible:
				return true
		else:
			return true
	return false
