#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf_custom_attributes>
#include <tf2attributes>
#include <dhooks>
#include <sdkhooks>

#define PLUGIN_NAME           "[CE Attribute] lunchbox custom effect"
#define PLUGIN_AUTHOR         "Creators.TF Team - qualitycont, nosoop" //Repurposed from the custom lunchbox effect system of nosoops custom attribute starter pack, thanks!
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

enum TFTauntAttack {
	TF_TAUNTATTACK_LUNCHBOX = 5
};

enum CustomLunchboxEffects
{
	Effect_None = 0,
	Effect_Speed = 1,
	Effect_LowGrav = 2
}

int o_iTauntAttack;
float m_flBuffEndTime[MAXPLAYERS];
CustomLunchboxEffects m_eCurrentBuff[MAXPLAYERS];

public void OnPluginStart()
{
	PrecacheScriptSound("DisciplineDevice.PowerDown");
	PrecacheSound(")weapons\\discipline_device_power_down.wav");
	
	Handle hConf = LoadGameConfigFile("tf2.lunchbox");
	if (!hConf) {
		SetFailState("Failed to load gamedata (tf2.lunchbox).");
	}
	
	Handle hLunchBoxPrimaryAttack =
			DHookCreateFromConf(hConf, "CTFPlayer::DoTauntAttack()");
	DHookEnableDetour(hLunchBoxPrimaryAttack, false, OnDoTauntAttackPre);
	
	Handle hLunchBoxApplyBite = DHookCreateFromConf(hConf, "CTFLunchBox::ApplyBiteEffects()");
	DHookEnableDetour(hLunchBoxApplyBite, false, OnApplyBiteEffects);
	
	Address xTauntAttackInfo = GameConfGetAddress(hConf,
			"CTFPlayer::DoTauntAttack()::TauntAttackOffset");
	o_iTauntAttack = LoadFromAddress(xTauntAttackInfo, NumberType_Int32);
	if (o_iTauntAttack & 0xFFFF != o_iTauntAttack) {
		SetFailState("Couldn't determine offset for CTFPlayer::m_iTauntAttack.");
	}
	
	delete hConf;
}

public void OnClientPutInServer(int client) {
	m_flBuffEndTime[client] = 0.0;
	SDKHook(client, SDKHook_PostThinkPost, OnClientPostThinkPost);
}

public void OnClientPostThinkPost(int client) {
	if (!m_flBuffEndTime[client] || m_flBuffEndTime[client] >= GetGameTime()) {
		return;
	}
	
	CustomLunchboxEffects eBuff = m_eCurrentBuff[client];
	if(eBuff == Effect_LowGrav)
	{
		TF2Attrib_RemoveByName(client, "increased jump height");
		TF2Attrib_RemoveByName(client, "cancel falling damage");
		PlayEffectEndSound(client);
	}
	
	m_flBuffEndTime[client] = 0.0;
	m_eCurrentBuff[client] = Effect_None;
}

public MRESReturn OnDoTauntAttackPre(int client) {
	if (GetClientTauntAttack(client) != TF_TAUNTATTACK_LUNCHBOX) {
		return MRES_Ignored;
	}
	
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	
	if(!HasAttribute(weapon))
	{
		return MRES_Ignored;
	}
	
	ApplyCustomLunchboxEffect(weapon, client);
	
	return MRES_Supercede;
}

public MRESReturn OnApplyBiteEffects(int weapon, Handle hParams)
{
	if(!HasAttribute(weapon))
	{
		return MRES_Ignored;
	}
	
	int client = DHookGetParam(hParams, 1);
	//PrintToChat(client, "Drink successful, applying attribute");
	ApplyCustomLunchboxEffect(weapon, client);
	return MRES_Supercede;
}

void ApplyCustomLunchboxEffect(int weapon, int client)
{
	CustomLunchboxEffects eEffect = view_as<CustomLunchboxEffects>(TF2CustAttr_GetInt(weapon, "lunchbox custom effect"));
	//PrintToChat(client, "Applying custom effect %i", eEffect);
	float flDuration = TF2CustAttr_GetFloat(weapon, "lunchbox custom duration", 5.0);
	float flEffectScale = TF2CustAttr_GetFloat(weapon, "lunchbox custom scale", 1.0);
	int iHealing = TF2CustAttr_GetInt(weapon, "lunchbox custom healing", 0);
	
	if(eEffect == Effect_Speed)
	{
		TF2_AddCondition(client, TFCond_SpeedBuffAlly, flDuration);
	}
	else if(eEffect == Effect_LowGrav)
	{
		TF2Attrib_SetByName(client, "increased jump height", flEffectScale);
		TF2Attrib_SetByName(client, "cancel falling damage", 1.0);
	}
	
	if(iHealing > 0)
	{
		int iCurHP = GetClientHealth(client);
		int iMaxHP = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	
		int iHealth = iCurHP + iHealing;
		if(iHealth > iMaxHP)
		{
			iHealth = iMaxHP;
		}
		
		SetEntityHealth(client, iHealth);
	}
	
	m_flBuffEndTime[client] = GetGameTime() + flDuration;
	m_eCurrentBuff[client] = eEffect;
}

void PlayEffectEndSound(int client)
{
	EmitGameSoundToClient(client, "DisciplineDevice.PowerDown");
}

bool HasAttribute(int weapon)
{
	if(IsValidEntity(weapon))
	{
		return TF2CustAttr_GetInt(weapon, "lunchbox custom effect") > 0;
	}
	return false;
}

static TFTauntAttack GetClientTauntAttack(int client) {
	return view_as<TFTauntAttack>(GetEntData(client, o_iTauntAttack));
}