extends Control

@export var ring_thickness: float = 8.0
@export var radius: float = 34.0

var remaining_time: float = 0.0
var total_time: float = 30.0
var can_use: bool = false
var full_health: bool = true

@onready var center_label: Label = $CenterLabel


func set_state(remaining: float, total: float, usable: bool, health_full: bool) -> void:
	remaining_time = max(remaining, 0.0)
	total_time = max(total, 0.001)
	can_use = usable
	full_health = health_full
	_update_label()
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_arc(center, radius, 0.0, TAU, 90, Color(0.2, 0.22, 0.25, 0.9), ring_thickness)

	if remaining_time > 0.0:
		var pct_remaining := clampf(remaining_time / total_time, 0.0, 1.0)
		var start_angle := -PI * 0.5
		var end_angle := start_angle + TAU * pct_remaining
		draw_arc(center, radius, start_angle, end_angle, 90, Color(0.97, 0.66, 0.22, 0.98), ring_thickness)
	elif can_use:
		draw_arc(center, radius, 0.0, TAU, 90, Color(0.35, 0.9, 0.4, 0.98), ring_thickness)
	else:
		draw_arc(center, radius, 0.0, TAU, 90, Color(0.9, 0.25, 0.25, 0.98), ring_thickness)


func _update_label() -> void:
	if remaining_time > 0.0:
		center_label.text = str(int(ceil(remaining_time)))
	elif can_use:
		center_label.text = "Z"
	else:
		center_label.text = "HP"
