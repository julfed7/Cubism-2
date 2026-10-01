extends Node

var items: Dictionary = {
	"medkit": {"name": "Medkit", "sprite": "res://sprites/items/medkit.png", "type": "healing", "stackable": true, "max_stack": 5, "heal": 50.0},
	"ammo_pistol": {"name": "Pistol Ammo", "sprite": "res://sprites/items/ammo_pistol.png", "type": "ammo", "ammo_for": "pistol", "stackable": true, "max_stack": 90},
	"ammo_smg": {"name": "SMG Ammo", "sprite": "res://sprites/items/ammo_smg.png", "type": "ammo", "ammo_for": "smg", "stackable": true, "max_stack": 120},
	"ammo_shotgun": {"name": "Shotgun Shells", "sprite": "res://sprites/items/ammo_shotgun.png", "type": "ammo", "ammo_for": "shotgun", "stackable": true, "max_stack": 40},
	"ammo_rifle": {"name": "Rifle Ammo", "sprite": "res://sprites/items/ammo_rifle.png", "type": "ammo", "ammo_for": "rifle", "stackable": true, "max_stack": 90},
	"coin": {"name": "Coin", "sprite": "res://sprites/items/coin.png", "type": "currency", "stackable": true, "max_stack": 999},
	"pistol": {"name": "Pistol", "sprite": "res://sprites/weapons/pistol.png", "type": "pistol", "weapon_type": "pistol", "stackable": false, "max_stack": 1, "damage": 20.0, "fire_rate": 0.35, "bullet_speed": 700.0, "magazine_size": 12, "starting_ammo": 24},
	"smg": {"name": "SMG", "sprite": "res://sprites/weapons/smg.png", "type": "smg", "weapon_type": "smg", "stackable": false, "max_stack": 1, "damage": 9.0, "fire_rate": 0.08, "bullet_speed": 650.0, "magazine_size": 30, "starting_ammo": 60},
	"shotgun": {"name": "Shotgun", "sprite": "res://sprites/weapons/shotgun.png", "type": "shotgun", "weapon_type": "shotgun", "stackable": false, "max_stack": 1, "damage": 12.0, "fire_rate": 0.75, "bullet_speed": 600.0, "magazine_size": 6, "starting_ammo": 12},
	"rifle": {"name": "Rifle", "sprite": "res://sprites/weapons/rifle.png", "type": "rifle", "weapon_type": "rifle", "stackable": false, "max_stack": 1, "damage": 30.0, "fire_rate": 0.22, "bullet_speed": 900.0, "magazine_size": 20, "starting_ammo": 40}
}

func get_item(id: String) -> Dictionary:
	return items.get(id, {})
