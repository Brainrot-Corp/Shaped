extends Node2D

@onready var draw_area: GestureDrawArea = $DrawArea

func _ready() -> void:
	draw_area.gesture_matched.connect(_on_matched)
	draw_area.gesture_rejected.connect(_on_rejected)
	draw_area.gesture_finished.connect(_on_finished)

func _on_matched(id: String, score: float) -> void:
	print("MATCH: %s (%.2f)" % [id, score])

func _on_rejected(id: String, score: float) -> void:
	if id.is_empty():
		print("ignored — stroke too short")
	else:
		print("no match — closest was %s (%.2f)" % [id, score])

func _on_finished(ranked: Array) -> void:
	for r in ranked.slice(0, 3):
		print("    %s: %.3f" % [r["id"], r["score"]])
