class_name GestureDrawArea
extends Control
## Drop this on a Control sized to the part of the screen where the player
## is allowed to draw. Hold left click, draw, release — it reports what
## shape you made and how close it was.
##
## Make sure Mouse > Filter is set to "Stop" in the inspector (the default
## for Control) so the area actually receives the clicks.

## Emitted on release when the best match clears `min_score`.
signal gesture_matched(id: String, score: float)
## Emitted on release when nothing cleared `min_score` (id is the closest miss).
signal gesture_rejected(id: String, score: float)
## Every result, best first — handy for tuning and debug overlays.
signal gesture_finished(ranked: Array)
signal gesture_started()

@export_group("Recognition")
## Below this, the stroke counts as a failed cast. 0.75-0.82 is a good range;
## raise it if spells are firing when they shouldn't.
@export_range(0.0, 1.0, 0.01) var min_score := 0.78
## Ignore flicks and accidental clicks.
@export var min_points := 8
@export var min_path_length := 60.0
## Off = "^" and "V" are different shapes. On = any orientation matches.
@export var rotation_invariant := false
@export var install_default_templates := true

@export_group("Capture")
## Points closer together than this are dropped — cheap noise filter.
@export var min_point_spacing := 4.0
## Keep the stroke inside the control even if the mouse wanders off.
@export var clamp_to_rect := true

@export_group("Appearance")
@export var line_color := Color(0.65, 0.85, 1.0, 0.95)
@export var line_width := 5.0
@export var fade_time := 0.3

@export_group("Authoring")
## Prints the drawn stroke to the Output panel as a ready-to-paste template.
@export var record_mode := false

var recognizer := GestureRecognizer.new()

var _points := PackedVector2Array()
var _drawing := false
var _fade := 0.0


func _ready() -> void:
	recognizer.rotation_invariant = rotation_invariant
	if install_default_templates:
		GestureTemplates.install_defaults(recognizer)
	set_process(false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin(event.position)
		elif _drawing:
			_end()
		accept_event()
	elif event is InputEventMouseMotion and _drawing:
		_push_point(event.position)
		accept_event()


func _begin(pos: Vector2) -> void:
	_drawing = true
	_fade = 0.0
	_points.clear()
	_points.append(pos)
	set_process(false)
	queue_redraw()
	gesture_started.emit()


func _push_point(pos: Vector2) -> void:
	if clamp_to_rect:
		pos = pos.clamp(Vector2.ZERO, size)
	if _points.is_empty() or _points[_points.size() - 1].distance_to(pos) >= min_point_spacing:
		_points.append(pos)
		queue_redraw()


func _end() -> void:
	_drawing = false
	_fade = fade_time
	set_process(fade_time > 0.0)
	queue_redraw()

	var stroke := _points
	if record_mode and stroke.size() >= 2:
		print(recognizer.to_template_literal(stroke))

	if stroke.size() < min_points or _length(stroke) < min_path_length:
		gesture_finished.emit([])
		gesture_rejected.emit("", 0.0)
		return

	var ranked := recognizer.rank(stroke)
	gesture_finished.emit(ranked)

	if ranked.is_empty():
		gesture_rejected.emit("", 0.0)
		return

	var best: Dictionary = ranked[0]
	if best["score"] >= min_score:
		gesture_matched.emit(best["id"], best["score"])
	else:
		gesture_rejected.emit(best["id"], best["score"])


func _process(delta: float) -> void:
	_fade = maxf(_fade - delta, 0.0)
	if _fade <= 0.0:
		_points.clear()
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _points.size() < 2:
		return
	var color := line_color
	if not _drawing and fade_time > 0.0:
		color.a *= _fade / fade_time
	draw_polyline(_points, color, line_width, true)


func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## Teach it one of your own runes at runtime (see record_mode to capture points).
func add_shape(id: String, points: PackedVector2Array) -> void:
	recognizer.add_template(id, points)
