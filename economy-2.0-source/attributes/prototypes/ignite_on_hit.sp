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

#define PLUGIN_NAME           "[CE Attribute] ignite on hit"
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

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon,
		float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(!IsPlayerAlive(victim) || !IsValidEntity(weapon))
	{
		return;
	}
	
	float fire = TF2CustAttr_GetFloat(weapon, "ignite on hit");
	if(fire > 0.0)
	{
		TF2_IgnitePlayer(victim, attacker, fire);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, OnTakeDamagePost);
}