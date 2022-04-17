# Defining a weapon
Defining a custom weapon follows the Custom Weapon X format, which is a KeyValues file with several parameters for the weapon. Each weapon is expected to be defined in it's own file (e.g `thumper.txt`). Each weapon object must have a unique UUID tied to it for unique identification. You can use a site like [UUIDGenerator](https://www.uuidgenerator.net/) to easily generate a unique UUID for you.

## Parameters
| Name | Purpose | Example |
| ---  | ---     | ---     |
| name   | Item name, to be displayed in any menus.   | `The Airblaster` |
| inherits   | Resolves to item definition and determines classname, item slots, quality   | `TF_WEAPON_FLAMETHROWER` |
| defid | "inherits" automatically determines this if provided, but sometimes you want a different itemdef (e.g. hiding weapon viewmodels with fists) | 21 |
| item_class | If "inherits" is not used, the classname of the weapon must be provided. Class specific names are determined at runtime. | `tf_weapon_flamethrower` |
| used_by_classes | Separate object. Manually defined loadout slot, for listing in the correct menu and for inventory storage. "inherits" can determine this at runtime. If manually defined, the slot must match up with the intended weapon. | Nested inside `used_by_classes`: `"pyro" "primary"` |
| keep_static_attrs | Whether or not static (item schema) attributes are preserved. 0 keeps runtime attributes, 1 preserves static attributes, 2 attempts to nullify gameplay-affecting attributes. | `1` |
| attributes_game | Contains official game attributes. | Nested inside `attributes_game`: `"airblast_destroy_projectile" "1"` |
| attributes_custom | Contains custom attributes. | Nested inside `attributes_custom`: `"super cool attribute enabled" "1"` |