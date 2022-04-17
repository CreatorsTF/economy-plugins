// ===============================================================================
// Include file for Creators.TF x Custom Weapons X. Includes natives for accessing
// and setting items.

#if defined _CreatorsCWX_Included
	#endinput
#endif
#define _CreatorsCWX_Included

#include <tf2_stocks>

// this is the maximum expected length of our UID
// it is intentional that this is *not* shared to dependent plugins
#define MAX_ITEM_IDENTIFIER_LENGTH 64

// this is the maximum length of the item name displayed to players
#define MAX_ITEM_NAME_LENGTH 128

// this is the number of slots allocated to our thing
#define NUM_ITEMS 7

// okay, so we can't use TFClassType even view_as'd
// otherwise it'll warn on array-based enumstruct
#define NUM_PLAYER_CLASSES 10

#define TF_ITEMDEF_DEFAULT -1


/**
 * Adds custom item definition into the internal schema. Each item is assigned to a unique UUID.
 */
native void CWX_AddCustomItem(char[] UUID, any[] buffer);

/**
 * Clears all custom items from the internal schema.
 */
native void CWX_ClearCustomItems();

/**
 * Grabs a snapshot of the internal schema.
 *
 * @return    StringMapSnapshot struct in "buffer"
 */
native int CWX_GetCustomItemList(any buffer);

/**
 * Adds the given item to the player's session loadout.  This item will be equipped on the
 * player on next regeneration (spawn / resupply) and persisted until they disconnect.
 */
native bool CWX_SetPlayerLoadoutItem(int client, TFClassType playerClass, const char[] uid,
		int flags = 0);

/**
 * Immediately equips the item onto the target player.  The item is not persisted.
 * 
 * As this happens outside of the standard loadout regeneration flow, unexpected side effects
 * may occur.  Consider using `CWX_SetCustomLoadoutItem` instead.
 * 
 * @return    Item entity reference, or INVALID_ENT_REFERENCE on failure.
 * @error     Client is not in-game or uid is invalid.
 */
native int CWX_EquipPlayerItem(int client, const char[] uid);

/**
 * Returns if the item UID is valid.
 */
native bool CWX_IsItemUIDValid(const char[] uid);

/**
 * Grabs the loadout entry struct for the selected slot for a class (or if class is -1, their current class).
 * 
 * The corrosponding CustomItemDefinition may not be initalized. This can be easily checked to see if there
 * is a UUID for the item assigned in the struct.
 *
 * @return    LoadoutEntry struct in "buffer"
 */
native bool CWX_GetCustomWeaponFromSlot(int client, int class=-1, int slot, any[] buffer);

/**
 * Grabs the item definition struct from this UUID.
 *  
 * @return    CustomItemDefinition struct in "buffer"
 * @error     UUID is invalid.
 */
native bool CWX_GetCustomItemDefinition(char[] UUID, any[] buffer);

enum struct CustomItemDefinition {
	KeyValues source;
	
	int defindex;
	char displayName[128];
	KeyValues localizedNames;
	char className[128];
	int loadoutPosition[NUM_PLAYER_CLASSES];
	
	char access[64];
	
	KeyValues nativeAttributes;
	KeyValues customAttributes;
	
	bool bKeepStaticAttributes;
	
	void Init() {
		this.defindex = TF_ITEMDEF_DEFAULT;
		this.source = new KeyValues("Item");
		for (int i; i < sizeof(CustomItemDefinition::loadoutPosition); i++) {
			this.loadoutPosition[i] = -1;
		}
	}
	
	void Destroy() {
		delete this.source;
		delete this.nativeAttributes;
		delete this.customAttributes;
		delete this.localizedNames;
	}
}
 
/***************************************************************************************
 * Constant definitions below are shared between the core plugin and its dependencies. *
 * Values here should not be rearranged.                                               *
 ***************************************************************************************/

#define LOADOUT_FLAG_UPDATE_BACKEND (1 << 0) // update the item on the backing database, in
                                             // addition to the current session -- if this is
                                             // not set, the item will be treated as a temporary
                                             // override
#define LOADOUT_FLAG_ATTEMPT_REGEN  (1 << 1) // if the player is in a spawn room, perform
                                             // regeneration to refresh the loadout


/**
 * Holds the definition for player inventory data.
 */
enum struct LoadoutEntry {
	char uid[MAX_ITEM_IDENTIFIER_LENGTH];
	
	// overload UID -- used when plugins want to take priority over user preference
	char override_uid[MAX_ITEM_IDENTIFIER_LENGTH];
	
	// loadout entity, for persistence
	// note for the future: we do *not* restore this on late load since the schema may have changed
	int entity;
	
	void SetItemUID(const char[] other_uid) {
		strcopy(this.uid, MAX_ITEM_IDENTIFIER_LENGTH, other_uid);
	}
	
	void SetOverloadItemUID(const char[] other_uid) {
		strcopy(this.override_uid, MAX_ITEM_IDENTIFIER_LENGTH, other_uid);
	}
	
	bool IsEmpty() {
		return !(this.override_uid[0] || this.uid[0]);
	}
	
	void Clear(bool initialize = false) {
		this.entity = INVALID_ENT_REFERENCE;
		this.uid = "";
		
		if (initialize) {
			this.override_uid = "";
		}
	}
}
