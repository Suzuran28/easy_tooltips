extends Control
## Example scene controller: wires the remote anchor and the animation toggles.

@export var toggle_animation_button: Button
@export var custom_animation_button: Button
@export var remote_trigger: TooltipTrigger
@export var remote_node: Control

func _ready() -> void:
	toggle_animation_button.toggled.connect(_on_toggle_animation)
	custom_animation_button.toggled.connect(_on_toggle_custom_animation)

	if remote_trigger != null and remote_node != null:
		remote_trigger.remote_origin = remote_node

	_refresh_labels()

func _on_toggle_animation(pressed: bool) -> void:
	EasyTooltips.get_default_setting().enable_animation = pressed
	_refresh_labels()

func _on_toggle_custom_animation(pressed: bool) -> void:
	if pressed:
		EasyTooltips.set_animations(fade_in_v2, fade_out_v2)
	else:
		EasyTooltips.set_animations(TooltipAnimation.fade_in, TooltipAnimation.fade_out)
	_refresh_labels()

func _refresh_labels() -> void:
	toggle_animation_button.text = "Animation: %s" % ("ON" if toggle_animation_button.button_pressed else "OFF")
	custom_animation_button.text = "Custom animation: %s" % ("ON" if custom_animation_button.button_pressed else "OFF")

## A more pronounced fade + scale, used when "Custom animation" is enabled.
static func fade_in_v2(tooltip: TooltipTemplate) -> Tween:
	if tooltip == null:
		return null

	# Ratio pivot keeps the scale centered even if the panel resizes.
	tooltip.pivot_offset = Vector2.ZERO
	tooltip.pivot_offset_ratio = Vector2(0.5, 0.5)
	# Set the initial state before the first draw to avoid a one-frame flash.
	tooltip.modulate.a = 0.0
	tooltip.scale = Vector2(0.4, 0.4)

	var tween := tooltip.create_tween().set_parallel()
	tween.tween_property(tooltip, "modulate:a", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(tooltip, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween

## Matching close animation for the custom preset.
static func fade_out_v2(tooltip: TooltipTemplate) -> Tween:
	if tooltip == null:
		return null

	tooltip.pivot_offset = Vector2.ZERO
	tooltip.pivot_offset_ratio = Vector2(0.5, 0.5)

	var tween := tooltip.create_tween().set_parallel()
	tween.tween_property(tooltip, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(tooltip, "scale", Vector2(0.4, 0.4), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tween
