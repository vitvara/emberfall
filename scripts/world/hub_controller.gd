class_name HubController
extends PlayerController
## Walking around the Outpost: same movement, jump and orbit camera as in the raid,
## but no skills, targeting or party keys. Esc leaves the Outpost.

signal leave_requested


func _unhandled_input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_ESCAPE:
			leave_requested.emit()
			return
		if (k >= KEY_1 and k <= KEY_7) or k == KEY_TAB or k == KEY_C or (k >= KEY_F1 and k <= KEY_F5):
			return  # no combat in the Outpost
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		return  # nothing to target
	super._unhandled_input(event)
