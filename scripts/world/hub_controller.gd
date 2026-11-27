class_name HubController
extends PlayerController
## Walking around the Outpost: same movement, jump, orbit camera and skills as in the raid (the
## training dummies take hits), all played out locally. Esc cancels ground aiming, then clears the
## target, then leaves (offline) or opens the War Party window (online).

signal leave_requested


func setup(w, u: Unit, auto: bool) -> void:
	super.setup(w, u, auto)
	local_only = true


func _unhandled_input(event: InputEvent) -> void:
	if blocked:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		if ground_aid != "":
			_cancel_ground()
		elif unit.target != null:
			set_target(null)
		else:
			leave_requested.emit()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)
