#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf_custom_attributes>

#define PLUGIN_NAME           "[CE Attribute] no falloff"
#define PLUGIN_AUTHOR         "Creators.TF Team"
#define PLUGIN_DESCRIPTION    ""
#define PLUGIN_VERSION        "1.00"
#define PLUGIN_URL            "https//creators.tf"

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon,
		float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(!IsClientValid(victim) || !IsClientValid(attacker)) return Plugin_Continue;
	
	if(HasAttribute(weapon))
	{
		damagetype |= DMG_NOCLOSEDISTANCEMOD;
		damagetype &= ~DMG_USEDISTANCEMOD;
		PrintToChatAll("No falloff applied");
		
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}

bool HasAttribute(int weapon)
{
	if(IsValidEntity(weapon))
	{
		return TF2CustAttr_GetInt(weapon, "no falloff") > 0;
	}
	return false;
}