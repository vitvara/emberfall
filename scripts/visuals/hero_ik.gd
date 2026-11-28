class_name HeroIK
extends SkeletonModifier3D
## Runs after the animation each frame and lets the hero rig bend the skeleton: torso twist and
## lean for sword swings, and arm IK so the hands stay on an aimed weapon's grip.

var rig: Node   # HeroRig


func _process_modification_with_delta(delta: float) -> void:
	if rig != null:
		rig.modify_skeleton(get_skeleton(), delta)
