class_name WhelpBrain
extends RefCounted
## Ember Whelp add: chase the highest-threat party member and bite.

var unit: Unit
var world  # RaidWorld
var bite_timer := 1.0


func _init(u: Unit, w) -> void:
	unit = u
	world = w


func tick(delta: float) -> void:
	if not unit.alive:
		return
	var tgt := unit.get_threat_target()
	if tgt == null:
		var party: Array = world.party_alive()
		if party.is_empty():
			return
		tgt = party[0]
	unit.target = tgt
	if not unit.in_range(tgt, GameData.MELEE_RANGE - 2.0):
		unit.move_toward_point(tgt.flat_pos(), delta, 6.5)
	else:
		unit.turn_toward(tgt, delta, 6.0)
	bite_timer -= delta
	if bite_timer <= 0.0 and unit.in_range(tgt, GameData.MELEE_RANGE):
		var w: Dictionary = GameData.BOSS["whelp"]
		bite_timer = float(w["interval"])
		world.on_auto_attack(unit, tgt)
		tgt.take_damage(float(w["damage"]) * unit.get_mod("damage_done"), "physical", unit, "Bite", false, 1.0, true)
