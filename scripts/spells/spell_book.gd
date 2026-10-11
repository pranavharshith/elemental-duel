class_name SpellBook
extends RefCounted
## Data table for every element and spell. Combos are keyed by the sorted list of
## queued elements, so key order never matters ("fire+water" == "water+fire").
## Adding a new combo = adding a dictionary entry; no new code paths needed
## unless it introduces a brand-new spell "type".

const ELEMENTS := ["fire", "water", "earth", "wind", "lightning"]

const ELEMENT_INFO := {
	"fire": {"name": "Fire", "key": "Q", "color": Color(1.0, 0.45, 0.12)},
	"water": {"name": "Water", "key": "E", "color": Color(0.2, 0.6, 1.0)},
	"earth": {"name": "Earth", "key": "R", "color": Color(0.62, 0.45, 0.25)},
	"wind": {"name": "Wind", "key": "F", "color": Color(0.4, 0.88, 0.68)},
	"lightning": {"name": "Lightning", "key": "C", "color": Color(1.0, 0.8, 0.15)},
}

const MAX_QUEUE := 3

# Spell types: projectile, strike, area, wall, cone, beam, self
# Common fields: name, type, mana, cooldown, color, desc
const SPELLS := {
	# ------------------------------------------------------------ singles
	"fire": {"name": "Fireball", "type": "projectile", "mana": 12, "cooldown": 0.45,
		"speed": 24.0, "damage": 11.0, "size": 0.28, "explode": 1.4, "burn": 3.0,
		"color": Color(1.0, 0.45, 0.12), "desc": "Explosive orb that sets the target ablaze."},
	"water": {"name": "Water Rocket", "type": "projectile", "mana": 10, "cooldown": 0.4,
		"speed": 36.0, "damage": 8.0, "size": 0.22, "knockback": 10.0,
		"color": Color(0.2, 0.6, 1.0), "desc": "Fast jet that shoves the target back."},
	"earth": {"name": "Earth Wall", "type": "wall", "mana": 18, "cooldown": 2.5,
		"segments": 1, "duration": 6.0, "wall_hp": 45.0,
		"color": Color(0.62, 0.45, 0.25), "desc": "Raises a stone wall that blocks spells."},
	"wind": {"name": "Gust", "type": "cone", "mana": 12, "cooldown": 1.2,
		"range": 7.5, "angle": 55.0, "damage": 4.0, "knockback": 18.0, "deflect": true,
		"color": Color(0.4, 0.88, 0.68), "desc": "Blast of air. Knocks back and deflects spells."},
	"lightning": {"name": "Lightning Strike", "type": "strike", "mana": 20, "cooldown": 1.8,
		"delay": 0.8, "radius": 1.8, "damage": 17.0, "stun": 0.35,
		"color": Color(1.0, 0.8, 0.15), "desc": "Calls a bolt at the crosshair after a short warning."},

	# ------------------------------------------------------------ doubles
	"fire+fire": {"name": "Inferno Orb", "type": "projectile", "mana": 28, "cooldown": 3.0,
		"speed": 17.0, "damage": 20.0, "size": 0.55, "explode": 2.8, "burn": 4.0, "knockback": 8.0,
		"color": Color(1.0, 0.3, 0.05), "desc": "Heavy orb with a huge blast radius."},
	"fire+water": {"name": "Scalding Steam", "type": "area", "mana": 24, "cooldown": 5.0,
		"radius": 3.2, "duration": 5.0, "dps": 6.0, "slow": 0.6,
		"color": Color(0.72, 0.77, 0.86), "desc": "Cloud of steam that burns and slows."},
	"earth+fire": {"name": "Meteor", "type": "strike", "mana": 34, "cooldown": 6.0,
		"delay": 1.2, "radius": 3.0, "damage": 24.0, "knockback": 12.0, "burn": 3.0, "meteor": true,
		"color": Color(1.0, 0.35, 0.1), "desc": "A flaming rock falls from the sky."},
	"fire+wind": {"name": "Flame Tornado", "type": "projectile", "mana": 28, "cooldown": 4.0,
		"speed": 10.0, "damage": 16.0, "size": 0.6, "burn": 5.0, "homing": 2.2, "lifetime": 3.5,
		"tornado": true,
		"color": Color(1.0, 0.55, 0.15), "desc": "Slow whirling fire that seeks its target."},
	"fire+lightning": {"name": "Plasma Lance", "type": "projectile", "mana": 30, "cooldown": 3.5,
		"speed": 55.0, "damage": 18.0, "size": 0.18, "stretch": 6.0,
		"color": Color(1.0, 0.4, 0.9), "desc": "Blinding-fast bolt of plasma."},
	"earth+water": {"name": "Mud Bog", "type": "area", "mana": 20, "cooldown": 6.0,
		"radius": 3.6, "duration": 6.0, "dps": 2.0, "slow": 0.35,
		"color": Color(0.38, 0.27, 0.15), "desc": "Sticky swamp that heavily slows."},
	"water+wind": {"name": "Ice Shards", "type": "projectile", "mana": 24, "cooldown": 3.0,
		"speed": 30.0, "damage": 4.0, "size": 0.16, "count": 5, "spread": 16.0, "slow": 0.6, "slow_time": 2.0,
		"shard": true,
		"color": Color(0.4, 0.78, 1.0), "desc": "Fan of freezing shards that slow."},
	"lightning+water": {"name": "Storm Orb", "type": "projectile", "mana": 30, "cooldown": 5.0,
		"speed": 13.0, "damage": 12.0, "size": 0.45, "explode": 2.2, "stun": 0.6,
		"color": Color(0.45, 0.75, 1.0), "desc": "Crackling orb that stuns on impact."},
	"earth+wind": {"name": "Boulder Barrage", "type": "projectile", "mana": 24, "cooldown": 3.0,
		"speed": 26.0, "damage": 10.0, "size": 0.32, "count": 3, "spread": 10.0, "knockback": 9.0,
		"gravity": 6.0, "rock": true,
		"color": Color(0.55, 0.45, 0.35), "desc": "Three hurled boulders."},
	"earth+lightning": {"name": "Crystal Spikes", "type": "strike", "mana": 28, "cooldown": 5.0,
		"line": 7, "delay": 0.35, "stagger": 0.08, "radius": 1.3, "damage": 7.0, "stun": 0.25,
		"spike": true,
		"color": Color(0.75, 0.55, 1.0), "desc": "A line of crystals erupts toward the crosshair."},
	"lightning+wind": {"name": "Thunderstorm", "type": "strike", "mana": 34, "cooldown": 6.0,
		"count": 5, "scatter": 3.0, "delay": 0.8, "stagger": 0.22, "radius": 1.6, "damage": 8.0, "stun": 0.25,
		"color": Color(0.5, 0.6, 1.0), "desc": "Several bolts rain around the crosshair."},
	"water+water": {"name": "Tidal Wave", "type": "cone", "mana": 26, "cooldown": 4.0,
		"range": 9.0, "angle": 75.0, "damage": 12.0, "knockback": 24.0,
		"color": Color(0.15, 0.5, 1.0), "desc": "Crashing wave that sweeps enemies away."},
	"earth+earth": {"name": "Stone Skin", "type": "self", "mana": 28, "cooldown": 10.0,
		"shield": 30.0, "duration": 6.0,
		"color": Color(0.75, 0.6, 0.4), "desc": "Absorbs the next 30 damage."},
	"wind+wind": {"name": "Tailwind", "type": "self", "mana": 20, "cooldown": 8.0,
		"haste": 1.6, "duration": 4.0, "cleanse": true, "sp_restore": 35.0,
		"color": Color(0.4, 0.88, 0.68), "desc": "Speed boost, restores SP and removes slows."},
	"lightning+lightning": {"name": "Chain Bolt", "type": "beam", "mana": 30, "cooldown": 4.0,
		"range": 30.0, "damage": 13.0, "stun": 0.3,
		"color": Color(1.0, 0.82, 0.2), "desc": "Instant bolt along the crosshair."},

	# ------------------------------------------------------------ triples
	"fire+fire+fire": {"name": "Sun Flare", "type": "projectile", "mana": 62, "cooldown": 14.0,
		"speed": 15.0, "damage": 30.0, "size": 0.9, "explode": 4.2, "burn": 5.0, "knockback": 16.0,
		"color": Color(1.0, 0.8, 0.25), "desc": "A miniature sun. Devastating blast."},
	"earth+fire+lightning": {"name": "Cataclysm", "type": "strike", "mana": 60, "cooldown": 14.0,
		"count": 6, "scatter": 4.0, "delay": 0.9, "stagger": 0.18, "radius": 2.2, "damage": 15.0,
		"burn": 2.0, "meteor": true,
		"color": Color(1.0, 0.3, 0.1), "desc": "A meteor shower around the crosshair."},
	"lightning+water+wind": {"name": "Tempest", "type": "area", "mana": 55, "cooldown": 12.0,
		"radius": 4.2, "duration": 4.5, "dps": 9.0, "slow": 0.5, "zap": true,
		"color": Color(0.55, 0.7, 1.0), "desc": "A raging storm that shocks all within."},
	"earth+earth+water": {"name": "Spring of Life", "type": "self", "mana": 50, "cooldown": 18.0,
		"heal": 35.0, "duration": 5.0,
		"color": Color(0.4, 1.0, 0.55), "desc": "Restores 35 HP over 5 seconds."},
	"wind+wind+wind": {"name": "Hurricane", "type": "cone", "mana": 45, "cooldown": 10.0,
		"range": 12.0, "angle": 95.0, "damage": 14.0, "knockback": 34.0, "deflect": true,
		"color": Color(0.45, 0.85, 0.7), "desc": "Overwhelming gale. Hurls enemies across the arena."},
	"lightning+lightning+lightning": {"name": "Judgment", "type": "strike", "mana": 66, "cooldown": 15.0,
		"delay": 1.3, "radius": 3.0, "damage": 34.0, "stun": 0.7,
		"color": Color(1.0, 0.78, 0.2), "desc": "A colossal bolt from the heavens."},
	"earth+earth+earth": {"name": "Fortress", "type": "wall", "mana": 40, "cooldown": 12.0,
		"segments": 3, "duration": 8.0, "wall_hp": 70.0,
		"color": Color(0.55, 0.42, 0.3), "desc": "Three-sided stone barricade."},
	"water+water+water": {"name": "Maelstrom", "type": "area", "mana": 52, "cooldown": 12.0,
		"radius": 4.5, "duration": 5.0, "dps": 7.0, "slow": 0.6, "pull": 6.0,
		"color": Color(0.1, 0.4, 0.95), "desc": "Whirlpool that drags enemies to its center."},
}

static func key_for(elements: Array) -> String:
	var sorted := elements.duplicate()
	sorted.sort()
	return "+".join(sorted)

## Longest-match resolution: an exact combo wins; otherwise the best defined
## pair from the queue (prefer the most recent elements); otherwise the latest
## single element.
static func resolve(elements: Array) -> String:
	if elements.is_empty():
		return ""
	var exact := key_for(elements)
	if SPELLS.has(exact):
		return exact
	if elements.size() == 3:
		for pair in [[1, 2], [0, 2], [0, 1]]:
			var k := key_for([elements[pair[0]], elements[pair[1]]])
			if SPELLS.has(k):
				return k
	return String(elements[elements.size() - 1])

static func get_spell(key: String) -> Dictionary:
	return SPELLS.get(key, {})

static func elements_of(key: String) -> Array:
	return Array(key.split("+"))
