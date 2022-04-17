/**
 * Contains functionality for the item config.
 */

#include <stocksoup/files>
#include <creators/creators_cwx>

void LoadCustomItemConfig() {
	KeyValues itemSchema = new KeyValues("Items");
	
	// We'll ditch the single file legacy format and instead load separate weapon files.
	// These will all be loaded and merged together in one single schema.
	char schemaDir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, schemaDir, sizeof(schemaDir), "configs/%s", "creators/weapons");
	
	// Find files within `configs/creators/weapons/` and import them, too
	ArrayList configFiles = GetFilesInDirectoryRecursive(schemaDir);
	for (int i, n = configFiles.Length; i < n; i++)
	{
		// Grab this file from the directory.
		char weaponFilePath[PLATFORM_MAX_PATH];
		configFiles.GetString(i, weaponFilePath, sizeof(weaponFilePath));
		NormalizePathToPOSIX(weaponFilePath);
		
		// Skip files in directories named "disabled", much like SourceMod.
		if (StrContains(weaponFilePath, "/disabled/") != -1) continue;
		
		// Skip files that are NOT text files (e.g documentation).
		if (StrContains(weaponFilePath, ".txt") == -1) continue;
		
		// Import in this config file.
		KeyValues importKV = new KeyValues("Weapon");
		importKV.ImportFromFile(weaponFilePath);
		
		// Try adding it to our overall schema.
		char uid[MAX_ITEM_IDENTIFIER_LENGTH];
		importKV.GotoFirstSubKey(false);
		do 
		{
			// Does this item already exist?
			importKV.GetSectionName(uid, sizeof(uid));
			if (importKV.GetDataType(NULL_STRING) == KvData_None) 
			{
				if (itemSchema.JumpToKey(uid)) 
				{
					LogMessage("Item uid %s already exists in schema, ignoring entry in %s", uid, weaponFilePath);
				} 
				else {
					// Import in.
					itemSchema.JumpToKey(uid, true);
					itemSchema.Import(importKV);
				}
				itemSchema.GoBack();
			}
		} while (importKV.GotoNextKey(false));
		
		// Cleanup.
		importKV.GoBack();
		delete importKV;
	}
	delete configFiles;
	
	// TODO add a forward that allows other plugins to hook registered attribute names and
	// precache any resources
	
	// If we already have existing items and we're reloading in a config, clear them
	// and destroy the items.
	CWX_ClearCustomItems();
	
	// Parse our items.
	if (itemSchema.GotoFirstSubKey()) {
		// we have items, go parse 'em
		do {
			CreateItemFromSection(itemSchema);
		} while (itemSchema.GotoNextKey());
		itemSchema.GoBack();
	} else {
		LogError("No custom items available.");
	}
	delete itemSchema;
}

bool CreateItemFromSection(KeyValues config) {
	CustomItemDefinition item;
	item.Init();
	
	item.source.Import(config);
	
	char uid[MAX_ITEM_IDENTIFIER_LENGTH];
	config.GetSectionName(uid, sizeof(uid));
	
	config.GetString("name", item.displayName, sizeof(item.displayName));
	
	char inheritFromItem[64];
	config.GetString("inherits", inheritFromItem, sizeof(inheritFromItem));
	int inheritDef = FindItemByName(inheritFromItem);
	
	// populate values for the 'inherit' entry, if any
	if (inheritDef != TF_ITEMDEF_DEFAULT) {
		item.defindex = inheritDef;
		TF2Econ_GetItemClassName(inheritDef, item.className, sizeof(item.className));
	} else if (inheritFromItem[0]) {
		LogError("Item uid '%s' inherits from unknown item '%s'", uid, inheritFromItem);
		item.Destroy();
		return false;
	}
	
	// apply inherited overrides
	item.defindex = config.GetNum("defindex", item.defindex);
	config.GetString("item_class", item.className, sizeof(item.className), item.className);
	
	if (!item.className[0]) {
		LogError("Item uid '%s' has no classname", uid);
		item.Destroy();
		return false;
	}
	
	if (item.defindex == TF_ITEMDEF_DEFAULT) {
		LogError("Item uid '%s' has no item definition", uid);
		item.Destroy();
		return false;
	}
	
	// compute slots based on inherited itemdef if we have it, else defindex
	ComputeEquipSlotPosition(config,
			inheritDef == TF_ITEMDEF_DEFAULT? item.defindex : inheritDef, item.loadoutPosition);
	
	config.GetString("item_class", item.className, sizeof(item.className), item.className);
	
	item.bKeepStaticAttributes = !!config.GetNum("keep_static_attrs", true);
	
	// allows restricting access to the item
	config.GetString("access", item.access, sizeof(item.access));
	
	if (config.JumpToKey("attributes_game")) {
		// validate that the attributes actually exist
		// we don't throw a complete failure here since it can be injected later
		if (config.GotoFirstSubKey(false)) {
			do {
				char key[256];
				config.GetSectionName(key, sizeof(key));
				
				if (TF2Econ_TranslateAttributeNameToDefinitionIndex(key) == -1) {
					LogError("Item uid '%s' references non-existent attribute '%s'", uid, key);
				}
			} while (config.GotoNextKey(false));
			config.GoBack();
		}
		
		item.nativeAttributes = new KeyValues("attributes_game");
		item.nativeAttributes.Import(config);
		
		config.GoBack();
	}
	
	if (config.JumpToKey("attributes_custom")) {
		item.customAttributes = new KeyValues("attributes_custom");
		item.customAttributes.Import(config);
		config.GoBack();
	}
	
	if (config.JumpToKey("localized_name")) {
		item.localizedNames = new KeyValues("localized_name");
		item.localizedNames.Import(config);
		config.GoBack();
	}
	
	CWX_AddCustomItem(uid, item);
	return true;
}

/**
 * Builds the loadout position array for the item, so the plugin knows which weapons can be
 * rendered in loadout menus and which loadout slot they will be stored in within the database.
 */
static bool ComputeEquipSlotPosition(KeyValues kv, int itemdef,
		int loadoutPosition[NUM_PLAYER_CLASSES]) {
	char uid[MAX_ITEM_IDENTIFIER_LENGTH];
	kv.GetSectionName(uid, sizeof(uid));
	
	if (kv.JumpToKey("used_by_classes")) {
		char playerClassNames[][] = {
				"", "scout", "sniper", "soldier", "demoman",
				"medic", "heavy", "pyro", "spy", "engineer"
		};
		
		for (TFClassType i = TFClass_Scout; i <= TFClass_Engineer; i++) {
			char slotName[16];
			kv.GetString(playerClassNames[i], slotName, sizeof(slotName));
			loadoutPosition[i] = TF2Econ_TranslateLoadoutSlotNameToIndex(slotName);
		}
		
		kv.GoBack();
		return true;
	}
	
	if (!TF2Econ_IsValidItemDefinition(itemdef)) {
		LogError("Item uid '%s' is missing a valid item definition index or 'inherits' item "
				... "name is invalid", uid);
		return false;
	}
	
	for (TFClassType i = TFClass_Scout; i <= TFClass_Engineer; i++) {
		loadoutPosition[i] = TF2Econ_GetItemLoadoutSlot(itemdef, i);
	}
	return true;
}

/**
 * Equips an item from the given CustomItemDefinition instance.
 * Returns the item entity if successful.
 */
int EquipCustomItem(int client, const CustomItemDefinition item) {
	char itemClass[128];
	
	strcopy(itemClass, sizeof(itemClass), item.className);
	TF2Econ_TranslateWeaponEntForClass(itemClass, sizeof(itemClass),
			TF2_GetPlayerClass(client));
	
	// create our item
	int itemEntity = TF2_CreateItem(item.defindex, itemClass);
	
	if (!IsFakeClient(client)) {
		// prevent item from being thrown in resupply
		int accountid = GetSteamAccountID(client);
		if (accountid) {
			SetEntProp(itemEntity, Prop_Send, "m_iAccountID", accountid);
		}
	}
	
	// TODO: implement a version that nullifies runtime attributes to their defaults
	SetEntProp(itemEntity, Prop_Send, "m_bOnlyIterateItemViewAttributes",
			!item.bKeepStaticAttributes);
	
	// apply game attributes
	if (item.nativeAttributes) {
		if (item.nativeAttributes.GotoFirstSubKey(false)) {
			do {
				char key[256], value[256];
				
				// TODO: support multiline KeyValues
				// keyvalues are case-insensitive, so section name + value would sidestep that
				item.nativeAttributes.GetSectionName(key, sizeof(key));
				item.nativeAttributes.GetString(NULL_STRING, value, sizeof(value));
				
				// this *almost* feels illegal.
				TF2Attrib_SetFromStringValue(itemEntity, key, value);
			} while (item.nativeAttributes.GotoNextKey(false));
			item.nativeAttributes.GoBack();
		}
	}
	
	// apply attributes for Custom Attributes
	if (item.customAttributes) {
		TF2CustAttr_UseKeyValues(itemEntity, item.customAttributes);
	}
	
	// remove existing item(s) on player
	bool bRemovedWeaponInSlot;
	if (TF2Util_IsEntityWeapon(itemEntity)) {
		// replace item by slot for cross-class equip compatibility
		int weaponSlot = TF2Util_GetWeaponSlot(itemEntity);
		bRemovedWeaponInSlot = IsValidEntity(GetPlayerWeaponSlot(client, weaponSlot));
		TF2_RemoveWeaponSlot(client, weaponSlot);
	}
	
	// we didn't remove a weapon by its weapon slot; remove item based on loadout slot
	if (!bRemovedWeaponInSlot) {
		int loadoutSlot = item.loadoutPosition[TF2_GetPlayerClass(client)];
		if (loadoutSlot == -1) {
			loadoutSlot = TF2Econ_GetItemDefaultLoadoutSlot(item.defindex);
			if (loadoutSlot == -1) {
				return INVALID_ENT_REFERENCE;
			}
		}
		
		// HACK: remove the correct item for demoman when applying the revolver
		if (TF2Util_IsEntityWeapon(itemEntity)
				&& TF2Econ_GetItemLoadoutSlot(item.defindex, TF2_GetPlayerClass(client)) == -1) {
			loadoutSlot = TF2Util_GetWeaponSlot(itemEntity);
		}
		
		TF2_RemoveItemByLoadoutSlot(client, loadoutSlot);
	}
	TF2_EquipPlayerEconItem(client, itemEntity);
	return itemEntity;
}

/**
 * Returns the item definition index given a name, or TF_ITEMDEF_DEFAULT if not found.
 */
static int FindItemByName(const char[] name) {
	if (!name[0]) {
		return TF_ITEMDEF_DEFAULT;
	}
	
	static StringMap s_ItemDefsByName;
	if (s_ItemDefsByName) {
		int value = TF_ITEMDEF_DEFAULT;
		return s_ItemDefsByName.GetValue(name, value)? value : TF_ITEMDEF_DEFAULT;
	}
	
	s_ItemDefsByName = new StringMap();
	
	ArrayList itemList = TF2Econ_GetItemList();
	char nameBuffer[64];
	for (int i, nItems = itemList.Length; i < nItems; i++) {
		int itemdef = itemList.Get(i);
		TF2Econ_GetItemName(itemdef, nameBuffer, sizeof(nameBuffer));
		s_ItemDefsByName.SetValue(nameBuffer, itemdef);
	}
	delete itemList;
	
	return FindItemByName(name);
}
