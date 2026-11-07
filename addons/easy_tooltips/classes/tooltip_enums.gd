extends RefCounted
class_name TooltipEnums
## Tooltip 系统中使用的全部可选枚举。
##
## 所有枚举的 [code]INHERIT[/code] 值为 [code]-1[/code]，表示“使用 [TooltipSetting] 中的全局默认值”。

## 所有枚举共用的“继承全局设置”取值。
const INHERIT := -1


## 触发方式。
enum TriggerMode {
	INHERIT = -1, ## 继承全局设置
	MOUSE, ## 鼠标悬停触发。
	FOCUS, ## 控件获得键盘焦点时触发。
	BOTH, ## 悬停或聚焦任一条件满足即触发。
}

## Tooltip 相对于锚点的对齐方式（九宫格）。
enum Alignment {
	INHERIT = -1, ## 继承全局设置
	TOP_CENTER,
	TOP_LEFT,
	TOP_RIGHT,
	MIDDLE_CENTER,
	MIDDLE_LEFT,
	MIDDLE_RIGHT,
	BOTTOM_CENTER,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
}

## Tooltip 的锚点来源。
enum Origin {
	INHERIT = -1, ## 继承全局设置
	HOST, ## 宿主控件的矩形。
	REMOTE, ## [member TooltipTrigger.remote_origin] 指定的节点位置。
	MOUSE, ## 触发瞬间的鼠标位置（之后固定不动）。
	MOUSE_FOLLOW, ## 鼠标位置，并持续跟随；钉住后冻结在钉住时的位置。
}

## 面板超出屏幕时的处理方式。
enum Overflow {
	INHERIT = -1, ## 继承全局设置
	FLIP, ## 翻转到锚点另一侧；翻转后仍越界则钳制在屏幕内。
	CLAMP, ## 直接钳制在屏幕内。
	NONE, ## 不处理，允许越界。
}

## 固定（pin）模式，由输入动作 [code]easy_tooltips_pin[/code] 驱动。
enum PinMode {
	INHERIT = -1, ## 继承全局设置
	OFF, ## 不响应钉住动作。
	HOLD, ## 按住钉住动作期间保持钉住，松开后取消。
	TOGGLE, ## 按下钉住动作切换钉住状态，固定后离开宿主也不隐藏。
}
