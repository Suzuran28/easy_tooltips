extends RefCounted
class_name TooltipAnimation
## 内置的 Tooltip 动画示例。
##
## 动画回调的约定：接收一个 [TooltipTemplate]，返回一个绑定在该模板（或其子节点）上的
## [Tween]；返回 [code]null[/code] 表示不使用动画。
##
## 注意：不要 tween 面板的 [code]position[/code] / [code]global_position[/code]，
## 管理器每帧都会重新计算位置。需要位移效果时请使用 Godot 4.7+ 的
## [code]Control.offset_transform_*[/code]（先启用 [code]offset_transform_enabled[/code]），
## 或者动画面板内部的子节点。

## 淡入 + 轻微缩放，作为默认的打开动画。
static func fade_in(tooltip: TooltipTemplate) -> Tween:
	if tooltip == null:
		return null

	# 使用比例 pivot，面板尺寸变化时也能保持围绕中心缩放。
	tooltip.pivot_offset = Vector2.ZERO
	tooltip.pivot_offset_ratio = Vector2(0.5, 0.5)
	# 先设置初始状态，避免第一帧以完全不透明的状态闪现。
	tooltip.modulate.a = 0.0
	tooltip.scale = Vector2(0.94, 0.94)

	var tween := tooltip.create_tween().set_parallel()
	tween.tween_property(tooltip, "modulate:a", 1.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(tooltip, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return tween

## 淡出 + 轻微缩小，作为默认的关闭动画。
static func fade_out(tooltip: TooltipTemplate) -> Tween:
	if tooltip == null:
		return null

	tooltip.pivot_offset = Vector2.ZERO
	tooltip.pivot_offset_ratio = Vector2(0.5, 0.5)

	var tween := tooltip.create_tween().set_parallel()
	tween.tween_property(tooltip, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(tooltip, "scale", Vector2(0.96, 0.96), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tween
