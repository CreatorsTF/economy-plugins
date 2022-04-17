#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <cecon>
#include <cecon_items>
#include <sdktools>
#include <tf2_stocks>

public Plugin myinfo =
{
	name = "[CE Attribute] Make Duck",
	author = "Creators.TF Team - ZoNiCaL & Sappho.",
	description = "Make Duck",
	version = "1.0",
	url = "https://creators.tf"
};

bool	makeDuck[MAXPLAYERS+1];

public void OnPluginStart()
{
	
}

public void OnWeaponSwitch(int client, int weapon)
{
	// Make ducks for this weapon if we have the attribute.
	makeDuck[client] = CEconItems_GetEntityAttributeBool(client, "make duck");
}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
