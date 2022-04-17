#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>
#include <halflife>
#include <sdkhooks>
#include <tf2utils>

#define PLUGIN_NAME           "[CE Attribute] restock clip on kill"
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

public void OnPluginStart()
{
	HookEvent("player_death", Event_PlayerDeath);
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int weapon = event.GetInt("weapon");
	if(HasAttribute(weapon))
	{
		int clip = TF2Util_GetWeaponMaxClip(weapon);
		SetEntProp(weapon, Prop_Send, "m_iClip", clip);
	}
}

bool HasAttribute(int weapon)
{
	if(IsValidEntity(weapon))
	{
		return TF2CustAttr_GetInt(weapon, "restock clip on kill") > 0;
	}
	return false;
}
