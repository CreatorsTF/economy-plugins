#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf_custom_attributes>

#pragma semicolon 1
#pragma newdecls required

#define DISPENSER_BLUEPRINT	"models/buildables/dispenser_blueprint.mdl"
#define DispenserBackpackAttribute "engie has dispenser backpack"

int g_CarriedDispenser[MAXPLAYERS+1];
Handle g_hSDKMakeCarriedObject;

public Plugin myinfo = 
{
	name = "Backpack Dispenser Attributes",
	author = "Originally by Pelipoika, adapted by ZoNiCaL.",
	description = "Engineers can carry their dispensers on their backs",
	version = "1.0",
	url = "http://www.sourcemod.net/plugins.php?author=Pelipoika&search=1"
};

public void OnPluginStart()
{
	// Get a hook for CBaseObject::MakeCarriedObject, this will handle building a dispenser in the
	// the same way that any other is made (with the blueprint model and such).
	Handle hConfig = LoadGameConfigFile("tf2.backpackdispenser");
	if (!hConfig) 
	{
		SetFailState("Failed to load gamedata (tf2.custom_weapons_x).");
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hConfig, SDKConf_Virtual, "CBaseObject::MakeCarriedObject");
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer); //Player
	
	// Couldn't make the SDKCall :(
	if ((g_hSDKMakeCarriedObject = EndPrepSDKCall()) == INVALID_HANDLE)
	{
		SetFailState("Failed To create SDKCall for CBaseObject::MakeCarriedObject offset");
	}
	
	delete hConfig;
	
	// Hook player events.
	HookEvent("player_death", Event_PlayerDeath);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			// Set our dispenser to be an invalid entity.
			g_CarriedDispenser[i] = INVALID_ENT_REFERENCE;
		}
	}
}

// Check to see if we have the attribute "dispenser backpack"
// on one of our weapons.
bool IsPlayerUsingBackpack(int client)
{
	// Loop over our weapons.
	for (int i = 0; i < TFWeaponSlot_PDA; i++)
	{
		// Grab weapon.
		int iWeapon = GetPlayerWeaponSlot(client, i);
		if (!IsValidEntity(iWeapon)) continue;
		
		// Does this weapon have our attribute?
		if (TF2CustAttr_GetInt(iWeapon, DispenserBackpackAttribute) > 0) return true;
	}
	return false;
}

public void OnClientPutInServer(int client)
{
	g_CarriedDispenser[client] = INVALID_ENT_REFERENCE;
}

public void OnEntityDestroyed(int iEntity)
{
	if(IsValidEntity(iEntity))
	{
		char classname[64];
		GetEntityClassname(iEntity, classname, sizeof(classname));
		
		// If a sentry gets destroyed, 
		if(StrEqual(classname, "obj_dispenser"))
		{
			int builder = GetEntPropEnt(iEntity, Prop_Send, "m_hBuilder");
			if(builder > 0 && builder <= MaxClients && IsClientInGame(builder))
			{
				if(g_CarriedDispenser[builder] != INVALID_ENT_REFERENCE)
				{
					int Dispenser = EntRefToEntIndex(g_CarriedDispenser[builder]);

					int iLink = GetEntPropEnt(Dispenser, Prop_Send, "m_hEffectEntity");
					if(IsValidEntity(iLink))
					{
						AcceptEntityInput(iLink, "ClearParent");
						AcceptEntityInput(iLink, "Kill");
					}
					
					g_CarriedDispenser[builder] = INVALID_ENT_REFERENCE;
					TF2_RemoveCondition(builder, TFCond_MarkedForDeath);
				}
			}
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse,
float vel[3], float angles[3], int &weapon, int &subtype,
int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	// This is a dispenser backpack check, why would we check for any other class?
	if (IsClientValid(client) && IsClientInGame(client) && TF2_GetPlayerClass(client) == TFClass_Engineer)
	{
		// Are any of the players weapons using the dispenser backpack attribute?
		if (!IsPlayerUsingBackpack(client)) return Plugin_Continue;
		
		// When playing MvM we don't want blue engineers to be able to carry dispensers.
		if(GameRules_GetProp("m_bPlayingMannVsMachine") && TF2_GetClientTeam(client) != TFTeam_Red) return Plugin_Changed;

		// Are we not carrying a dispenser?	
		if(g_CarriedDispenser[client] == INVALID_ENT_REFERENCE)
		{
			// Pick up our dispenser if we press RELOAD.
			if(buttons & IN_RELOAD && GetEntProp(client, Prop_Send, "m_bCarryingObject") != 1)
			{
				int iAim = GetClientAimTarget(client, false);
				if(IsValidEntity(iAim))
				{
					char strClass[64];
					GetEntityClassname(iAim, strClass, sizeof(strClass));
					if(StrEqual(strClass, "obj_dispenser") && IsBuilder(iAim, client))
					{
						EquipDispenser(client, iAim);
					}
				}
			}
		}
		// Drop our dispenser if we're holding one.
		else if(g_CarriedDispenser[client] != INVALID_ENT_REFERENCE)
		{
			if((buttons & IN_RELOAD && buttons & IN_ATTACK2) &&
			GetEntProp(client, Prop_Send, "m_bCarryingObject") == 0 &&
			g_CarriedDispenser[client] != INVALID_ENT_REFERENCE)
			{
				UnequipDispenser(client);
			}
		}
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	// If we're currently holding a dispenser, destroy it.
	if(IsClientValid(client) && IsClientInGame(client) && g_CarriedDispenser[client] != INVALID_ENT_REFERENCE)
	{
		DestroyDispenser(client);
	}
}

// Create a dispenser for the player.
stock void EquipDispenser(int client, int target)
{
	float dPos[3], bPos[3];
	GetEntPropVector(target, Prop_Send, "m_vecOrigin", dPos);
	GetClientAbsOrigin(client, bPos);
	
	// Hook our dispenser_touch_trigger entity and parent it to our dispenser properly.
	if(GetVectorDistance(dPos, bPos) <= 125.0 && IsValidBuilding(target))
	{	
		int trigger = -1;
		while ((trigger = FindEntityByClassname(trigger, "dispenser_touch_trigger")) != -1)
		{
			if(IsValidEntity(trigger))
			{
				int ownerentity = GetEntPropEnt(trigger, Prop_Send, "m_hOwnerEntity");
				if(ownerentity == target)
				{
					SetVariantString("!activator");
					AcceptEntityInput(trigger, "SetParent", target);
				}
			}
		}

		// Create the viusal link of this dispenser.
		int iLink = CreateLink(client);
		
		// Parent our link to our dispenser.
		SetVariantString("!activator");
		AcceptEntityInput(target, "SetParent", iLink); 
		SetVariantString("flag"); 
		AcceptEntityInput(target, "SetParentAttachment", iLink); 
		SetEntPropEnt(target, Prop_Send, "m_hEffectEntity", iLink);
		
		float pPos[3], pAng[3];

		pPos[0] += 30.0;	// This moves it up/down
		pPos[1] += 40.0;
		
		pAng[0] += 180.0;
		pAng[1] -= 90.0;
		pAng[2] += 90.0;

		// Position our dispenser.
		SetEntPropVector(target, Prop_Send, "m_vecOrigin", pPos);
		SetEntPropVector(target, Prop_Send, "m_angRotation", pAng);
		
		// Make it non-solid.
		SetEntProp(target, Prop_Send, "m_nSolidType", 0);
		SetEntProp(target, Prop_Send, "m_usSolidFlags", 0x0004);
		
		// Set ourselves to be marked for death forever until we drop the dispenser.
		TF2_AddCondition(client, TFCond_MarkedForDeath, -1.0);
		
		g_CarriedDispenser[client] = EntIndexToEntRef(target);
	}
}

stock void UnequipDispenser(int client)
{
	int Dispenser = EntRefToEntIndex(g_CarriedDispenser[client]);
	if(Dispenser != INVALID_ENT_REFERENCE)
	{
		int iBuilder = GetPlayerWeaponSlot(client, view_as<int>(TFWeaponSlot_PDA));
		
		// Call CBaseObject::MakeCarriedObject.
		SDKCall(g_hSDKMakeCarriedObject, Dispenser, client);

		// Set props relating to building our dispenser.
		SetEntPropEnt(iBuilder, Prop_Send, "m_hObjectBeingBuilt", Dispenser); 
		SetEntProp(iBuilder, Prop_Send, "m_iBuildState", 2); 

		// Set props relating to the dispenser itself being built.
		SetEntProp(Dispenser, Prop_Send, "m_bCarried", 1); 
		SetEntProp(Dispenser, Prop_Send, "m_bPlacing", 1); 
		SetEntProp(Dispenser, Prop_Send, "m_bCarryDeploy", 0);
		SetEntProp(Dispenser, Prop_Send, "m_iDesiredBuildRotations", 0);
		SetEntProp(Dispenser, Prop_Send, "m_iUpgradeLevel", 1);
		SetEntProp(Dispenser, Prop_Send, "m_nSolidType", 2);
		SetEntProp(Dispenser, Prop_Send, "m_usSolidFlags", 0);

		// Set the model to the blueprint like we grabbed it from the PDA.
		SetEntityModel(Dispenser, DISPENSER_BLUEPRINT); 
		
		// Set our active weapon to the PDA.
		SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", iBuilder); 

		// Destroy our visual link.
		int iLink = GetEntPropEnt(Dispenser, Prop_Send, "m_hEffectEntity");
		if(IsValidEntity(iLink))
		{
			AcceptEntityInput(Dispenser, "ClearParent");
			AcceptEntityInput(iLink, "ClearParent");
			AcceptEntityInput(iLink, "Kill");
			
			// Remove our marked for death condition.
			TF2_RemoveCondition(client, TFCond_MarkedForDeath);
		}

		g_CarriedDispenser[client] = INVALID_ENT_REFERENCE;
	}
}

stock void DestroyDispenser(int client)
{
	// Destory our link entitiy when our dispenser gets destroyed.
	int Dispenser = EntRefToEntIndex(g_CarriedDispenser[client]);
	if(Dispenser != INVALID_ENT_REFERENCE)
	{
		int iLink = GetEntPropEnt(Dispenser, Prop_Send, "m_hEffectEntity");
		if(IsValidEntity(iLink))
		{
			AcceptEntityInput(iLink, "ClearParent");
			AcceptEntityInput(iLink, "Kill");
		
			SetVariantInt(5000);
			AcceptEntityInput(Dispenser, "RemoveHealth");
			
			TF2_RemoveCondition(client, TFCond_MarkedForDeath);
			
			g_CarriedDispenser[client] = INVALID_ENT_REFERENCE;
		}
	}
}

stock int CreateLink(int iClient)
{
	int iLink = CreateEntityByName("tf_taunt_prop");
	DispatchKeyValue(iLink, "targetname", "DispenserLink");
	DispatchSpawn(iLink); 
	
	char strModel[PLATFORM_MAX_PATH];
	GetEntPropString(iClient, Prop_Data, "m_ModelName", strModel, PLATFORM_MAX_PATH);
	
	SetEntityModel(iLink, strModel);
	
	SetEntProp(iLink, Prop_Send, "m_fEffects", 16|64);
	
	SetVariantString("!activator"); 
	AcceptEntityInput(iLink, "SetParent", iClient); 
	
	SetVariantString("flag");
	AcceptEntityInput(iLink, "SetParentAttachment", iClient);
	
	return iLink;
}

// ================ Utility Functions ================

stock bool IsValidBuilding(int iBuilding)
{
	if (IsValidEntity(iBuilding))
	{
		if (GetEntProp(iBuilding, Prop_Send, "m_bPlacing") == 0
		 && GetEntProp(iBuilding, Prop_Send, "m_bCarried") == 0
		 && GetEntProp(iBuilding, Prop_Send, "m_bCarryDeploy") == 0)
			return true;
	}
	
	return false;
}

stock bool IsBuilder(int iBuilding, int iClient)
{
	return (GetEntPropEnt(iBuilding, Prop_Send, "m_hBuilder") == iClient);
}

bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients) return false;
	if(!IsValidEntity(client)) return false;
	if (!IsClientInGame(client)) return false;
	if (!IsClientAuthorized(client)) return false;
	return true;
}
