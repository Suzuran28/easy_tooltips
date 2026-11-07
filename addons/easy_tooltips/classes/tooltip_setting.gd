extends Resource
class_name TooltipSetting
## Tooltip 的全局默认设置。
##
## 当 [TooltipTrigger] 上的同名属性为 [code]INHERIT[/code]（或 [code]null[/code]）时，
## 会回退到这里设置的值。默认实例见 [code]res://addons/easy_tooltips/resources/default.tres[/code]。

## 默认使用的 tooltip 面板场景，根节点必须是 [TooltipTemplate]。
@export var tooltip_template: PackedScene
## 面板宽度（像素）。<= 0 时使用模板自身的宽度。
@export var width: int = 220
## 是否启用打开/关闭动画。动画回调通过 [code]EasyTooltips.set_open_animation()[/code]
## 和 [code]EasyTooltips.set_close_animation()[/code] 设置，不保存在资源里。
@export var enable_animation: bool = true
## 默认触发方式。
@export var trigger_mode: TooltipEnums.TriggerMode = TooltipEnums.TriggerMode.MOUSE
## 默认对齐方式。
@export var alignment: TooltipEnums.Alignment = TooltipEnums.Alignment.TOP_CENTER
## 默认锚点来源。
@export var origin: TooltipEnums.Origin = TooltipEnums.Origin.HOST
## 默认溢出处理方式。
@export var overflow: TooltipEnums.Overflow = TooltipEnums.Overflow.FLIP
## 默认固定模式。
@export var pin_mode: TooltipEnums.PinMode = TooltipEnums.PinMode.OFF
## 默认悬停延迟（毫秒）。
@export var hover_delay: int = 500
## 溢出钳制时与屏幕边缘保留的间距（像素）。
@export var screen_margin: int = 8
