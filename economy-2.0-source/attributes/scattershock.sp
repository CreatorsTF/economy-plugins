#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>
#include <halflife>
#include <sdkhooks>

#define PLUGIN_NAME           "Scattershock Attributes"
#define PLUGIN_AUTHOR         "Creators.TF Team - qualitycont"
#define PLUGIN_DESCRIPTION    ""
#define PLUGIN_VERSION        "2.1"
#define PLUGIN_URL            ""

#pragma semicolon 1

#define CHARGE_READY_SOUND "TFPlayer.ReCharged"
#define CHARGE_USED_SOUND "Weapon_3rd_degree.HitFlesh"
#define CHARGE_LOST_SOUND "Weapon_Pomson.DrainedVictim"

// how long it takes to fully charge a charge shot
// this can be changed with the "charge shot with secondary time" attribute (additive)
#define DEFAULT_CHARGE_TIME 3.0

// how much bonus damage a charge shot deals
// this can be changed with the "charge shot with secondary damage" attribute (percentage)
#define DEFAULT_CHARGE_DAMAGE_MULT 1.4

// how much of the clip one charge shot consumes
// this can be changed with the "charge shot with secondary ammo" attribute (additive)
#define DEFAULT_CHARGE_CLIP_CONSUMPTION 3

// how much time the player has to get the bonus damage after getting a full charge
// this can be changed with the "charge shot with secondary decay" attribute (additive)
#define DEFAULT_CHARGE_DECAY_TIME 1.0

#define HUD_UPDATE_RATE 0.25
#define CHAR_FULL "■"
#define CHAR_EMPTY "□"

ConVar cvOnlyShowHUDWhileCharging;
ConVar cvReloadResetsCharge;

public Plugin:myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

bool m_bIsCharging[MAXPLAYERS];
float m_flChargeStartTime[MAXPLAYERS];
float m_flChargeFinishTime[MAXPLAYERS];
float m_flChargeProgress[MAXPLAYERS]; // the progress in % (0% = 0, 100% = 1)
bool m_bHasPlayedReadySound[MAXPLAYERS]; // so we dont spam clients with charge sounds

public OnPluginStart()
{
	CreateTimer(HUD_UPDATE_RATE, DrawChargeHUD, INVALID_HANDLE, TIMER_REPEAT);
	
	cvOnlyShowHUDWhileCharging = CreateConVar("ce_charge_shot_hide_hud_uncharged", "0.0");
	cvReloadResetsCharge = CreateConVar("ce_charge_shot_reload_reset", "0.0");
}

public void OnMapStart()
{
	// lets make sure our sounds are loaded
	PrecacheScriptSound(CHARGE_READY_SOUND);
	PrecacheScriptSound(CHARGE_LOST_SOUND);
	//PrintToServer("Precached Sound");
}


/*
	Purpose: Apply the bonus shot damage
*/
public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if(IsClientValid(attacker))
	{
		if(inflictor != attacker) // we cant be attacking with the scattergun so ignore this
		{
			return Plugin_Continue;
		}
		
		if(HasAttributeActive(attacker) && m_bIsCharging[attacker])
		{
			UpdateCharge(attacker);
			if(m_flChargeProgress[attacker] >= 1)
			{
				// Use our charge attack
				int iActiveWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
				int iClip = GetEntProp(iActiveWeapon, Prop_Send, "m_iClip1");
				
				int iClipConsumption = DEFAULT_CHARGE_CLIP_CONSUMPTION;
				int iClipConsumptionAttribute = TF2CustAttr_GetInt(iActiveWeapon, "charge shot with secondary ammo");
				if(iClipConsumptionAttribute > 0)
				{
					iClipConsumption = iClipConsumptionAttribute;
				}
				
				if(iClip >= iClipConsumption) // do we have the clip size required
				{
					// increase the damage
					float flDamageMult = DEFAULT_CHARGE_DAMAGE_MULT;
					float flDamageMultAttribute = TF2CustAttr_GetFloat(iActiveWeapon, "charge shot with secondary damage");
					if(flDamageMultAttribute > 0)
					{
						flDamageMult = flDamageMultAttribute;
					}
					damage *= flDamageMult;
					EmitSoundToClient(attacker, CHARGE_USED_SOUND);
					
					// Are we dealing large amounts of damage in one shot? If yes, fire the event
					/*if(damage >= 125.0)
					{
						CEcon_SendEventToClientUnique(attacker, "TF_SCATTERSHOCK_MEATSHOT", 1);
					}*/
					
					// subtract the extra consumption from the clip, minus one because shots already take one ammo
					SetEntProp(iActiveWeapon, Prop_Send, "m_iClip1", iClip - (iClipConsumption - 1)); 
					StopCharging(attacker);
					return Plugin_Changed;
				}
			}
			else
			{
				// Reset the charge to avoid just being able to charge passively during a 1v1
				StopCharging(attacker);
				StartCharging(attacker);
			}
		}
	}
	return Plugin_Continue;
}

/*
	Purpose: Start/Stop the charge)
*/
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(HasAttributeActive(client))
	{
		if (buttons & IN_ATTACK2)
		{	
			if(!m_bIsCharging[client])
			{
				// the player wants to start charging
				StartCharging(client);
			}
		}
	}
}

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result)
{
	if(HasAttributeActive(client))
	{
		RequestFrame(CheckHit, client);
	}
}

void CheckHit(int client)
{
	if(m_bIsCharging[client])
	{
		StopCharging(client);
		//StartCharging(client);
	}
}


public void OnReloadPost(int weapon, bool successful)
{
	if(successful)
	{
		if(HasAttribute(weapon))
		{
			int iOwner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
			if(IsClientValid(iOwner))
			{
				// just reset the charge since all reloading while charged is not allowed
				StopCharging(iOwner);
			}
		}
	}
}

public Action OnSwitchWeapon(int client, int weapon)
{
	if(m_bIsCharging[client])
	{
		StopCharging(client);
	}
}

public Action DrawChargeHUD(Handle timer, any data)
{
	for (int i = 1; i < MaxClients; i++)
	{
		if(IsClientValid(i))
		{
			if(HasAttributeActive(i))
			{
				// repurposed this from the syringe code, hope its not too bad
				char sHUDText[128];
				char sProgress[32];
				
				UpdateCharge(i);
				if(m_bIsCharging[i] || !cvOnlyShowHUDWhileCharging.BoolValue ) // do we even have to do this loop?
				{
					float flProgress = m_flChargeProgress[i];
			
					for (int j = 1; j <= 10; j++)
					{
						if (flProgress >= j * 0.1)
						{
							StrCat(sProgress, sizeof(sProgress), CHAR_FULL);
						}
						else
						{
							StrCat(sProgress, sizeof(sProgress), CHAR_EMPTY);
						}
					}
					
					Format(sHUDText, sizeof(sHUDText), "%s", sProgress );
				}
				else
				{
					return;
				}
				
			
				if(m_flChargeProgress[i] >= 1)
				{
					SetHudTextParams(-1.0, 0.52, HUD_UPDATE_RATE, 255, 0, 0, 255);
				} 
				else 
				{
					SetHudTextParams(-1.0, 0.52, HUD_UPDATE_RATE, 255, 255, 255, 255);
				}
				ShowHudText(i, -1, sHUDText);
			}
		}
	}
}

public void OnClientPutInServer(int client)
{
	m_bIsCharging[client] = false;
	m_flChargeFinishTime[client] = 0.0;
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponSwitch, OnSwitchWeapon);
}

public void OnClientDisconnect(int client)
{
	m_bIsCharging[client] = false;
	m_flChargeFinishTime[client] = 0.0;
}

void StartCharging(int client)
{
	float flChargeTime = DEFAULT_CHARGE_TIME;
	
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(iActiveWeapon))
	{
		float flAttributeChargeTime = TF2CustAttr_GetFloat(iActiveWeapon, "charge shot with secondary time");
		if(flAttributeChargeTime > 0) // override the charge time if the item wants it, if not use default value
		{
			flChargeTime = flAttributeChargeTime;
		}
	}
	
	m_flChargeStartTime[client] = GetEngineTime();
	m_flChargeFinishTime[client] = GetEngineTime() + flChargeTime;
	m_bIsCharging[client] = true;
	m_bHasPlayedReadySound[client] = false;
	
	if(cvReloadResetsCharge.BoolValue)
	{
		SDKHook(iActiveWeapon, SDKHook_ReloadPost, OnReloadPost);
	}
}

void StopCharging(int client)
{
	m_flChargeStartTime[client] = 0.0;
	m_flChargeFinishTime[client] = 0.0;
	m_bIsCharging[client] = false;
	
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(iActiveWeapon))
	{
		SDKUnhook(iActiveWeapon, SDKHook_ReloadPost, OnReloadPost);
		TF2Attrib_SetByName(iActiveWeapon, "weapon spread bonus", 1.0);
		TF2Attrib_SetByName(iActiveWeapon, "sniper fires tracer", 0.0);
	}
}

void UpdateCharge(int client)
{
	if(!m_bIsCharging[client])
	{
		// the client isnt charging, so the progress is obviously 0%
		m_flChargeProgress[client] = 0.0;
		return;
	}
	
	float flDiff = m_flChargeFinishTime[client] - GetEngineTime();
	
	float flDecayTime = DEFAULT_CHARGE_DECAY_TIME;
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	float flDecayAttributeTime = TF2CustAttr_GetFloat(iActiveWeapon, "charge shot with secondary decay");
	if(flDecayAttributeTime > 0)
	{
		flDecayTime = flDecayAttributeTime;
	}
	
	if(flDiff <= flDecayTime * -1)
	{
		//the client has been charging for too long, stop the charge.
		StopCharging(client);
		EmitGameSoundToClient(client, CHARGE_LOST_SOUND);
		return;
	}
	else if(flDiff <= 0)
	{
		// the client has been charging for long enough, so the progress is obviously 100%
		m_flChargeProgress[client] = 1.0;
		if(!m_bHasPlayedReadySound[client])
		{
			EmitGameSoundToClient(client, CHARGE_READY_SOUND);
			m_bHasPlayedReadySound[client] = true;
			TF2Attrib_SetByName(iActiveWeapon, "weapon spread bonus", 0.8);
			TF2Attrib_SetByName(iActiveWeapon, "sniper fires tracer", 1.0);
		}
		return;
	}
	
	// charge progress = 1 - time already charged / time needed to charge
	m_flChargeProgress[client] = 1 - flDiff / (m_flChargeFinishTime[client] - m_flChargeStartTime[client]); 
}

bool HasAttributeActive(int client)
{
    int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (IsValidEntity(iActiveWeapon))
    {
        return TF2CustAttr_GetInt(iActiveWeapon, "charge shot with secondary") > 0;
    }
    return false;
}

bool HasAttribute(int weapon)
{
	if(IsValidEntity(weapon))
	{
		return TF2CustAttr_GetInt(weapon, "charge shot with secondary") > 0;
	}
	return false;
}

bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
