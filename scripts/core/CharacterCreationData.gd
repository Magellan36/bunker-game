extends Node
## Autoload — CharacterCreationData
## Holds the player's chosen customization from the character-creation
## screen (scenes/ui/character_creation/CharacterCreation.tscn), read by
## PlayerModelController.gd at _ready() for any instance with
## use_character_creation_data = true (Player.tscn's PlayerModel/
## PlayerModelShadow nodes, and the creation screen's own live preview
## instance). NPCs never read this — nothing about their appearance
## changes based on what the player picks for themselves.

var gender: String = "male"
var hairstyle_key: String = "buzzed"
var hair_tint_color: Color = Color(0.12, 0.08, 0.05)
## Independent of hairstyle_key — combinable with any hairstyle, not a
## mutually-exclusive style choice. Applies to either gender.
var beard_enabled: bool = false