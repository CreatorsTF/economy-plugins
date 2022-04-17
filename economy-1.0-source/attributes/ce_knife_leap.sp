#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdktools_hooks>
#include <sdkhooks>
#include <tf2_stocks>
#include <cecon_items>
#include <timers>

#define PLUGIN_NAME           "[CE Attribute] knife leap"
#define PLUGIN_AUTHOR         "Creators.TF Team"
#define PLUGIN_DESCRIPTION    ""
#define PLUGIN_VERSION        "1.11"
#define PLUGIN_URL            "https//creators.tf"

#define SOUND_LEAP "TFPlayer.AirBlastImpact"

#define DEFAULT_LEAP_DISTANCE 512.0 // attribute: knife leap distance
#define DEFAULT_LEAP_DISTANCE_VERTICAL 128.0 // attribute: knife leap distance vertical
#define DEFAULT_LEAP_COOLDOWN 8.0 // attribute: knife leap cooldown
#define DEFAULT_LEAP_DRAIN 25.0 // attribute: knife leap drain

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

float m_flLastLeapTime[MAXPLAYERS];

public void OnPluginStart()
{
	CreateTimer(0.5, Timer_Hud, INVALID_HANDLE, TIMER_REPEAT);
}

public void OnMapStart()
{
	PrecacheScriptSound(SOUND_LEAP);
}

public Action Timer_Hud(Handle time)
{
	for(int i = 1; i < MaxClients; i++)
	{
		if(IsClientValid(i) && HasAttribute(i))
		{
			DrawHUD(i);
		}
	}
}

void DrawHUD(int client)
{
	char sHUDText[128];
	float flCooldown = CEconItems_GetEntityAttributeFloat(GetAttribute(client), "knife leap cooldown");
	if(flCooldown <= 0)
	{
		flCooldown = DEFAULT_LEAP_COOLDOWN;
	}
	
	float flTimeLeft = flCooldown - (GetEngineTime() - m_flLastLeapTime[client]);
	if(flTimeLeft < 0.0)
	{
		sHUDText = "Leap Ready";
		SetHudTextParams(1.0, 0.8, 0.5, 255, 0, 0, 255);
	}
	else
	{
		Format(sHUDText, sizeof(sHUDText), "Leap Ready in %i seconds", RoundToNearest(flTimeLeft));
		SetHudTextParams(1.0, 0.8, 0.5, 255, 255, 255, 255);
	}
	ShowHudText(client, -1, sHUDText);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(buttons & IN_RELOAD)
	{
		int iWeapon = GetAttribute(client);
		if(iWeapon >= 0)
		{
			//PrintToChat(client, "Knife dash");
			
			float flCooldown = CEconItems_GetEntityAttributeFloat(iWeapon, "knife leap cooldown");
			if(flCooldown <= 0 )
			{
				flCooldown = DEFAULT_LEAP_COOLDOWN;
			}
			if(GetEngineTime() - m_flLastLeapTime[client] >= flCooldown)
			{
				PerformDash(client, iWeapon);
			}
		}
	}
}

public void OnClientConnected(int client)
{
	m_flLastLeapTime[client] = 0.0;
}

// this is where the magic happens
void PerformDash(int client, int weapon)
{
	if(!TF2_IsPlayerInCondition(client, TFCond_Cloaked))
	{
		// we can only leap while cloaked
		return;
	}
	//PrintToChat(client, "finish time: %f, time: %f", flCloakFinishTime, GetGameTime());
	if(GetEntPropFloat(client, Prop_Send, "m_flInvisChangeCompleteTime") >= GetGameTime())
	{
		// we havent finished cloaking yet
		return;
	}
	
	float flCloakAmount = GetEntPropFloat(client, Prop_Send, "m_flCloakMeter");
	float flCloakDrain = CEconItems_GetEntityAttributeFloat(client, "knife leap drain");
	if(flCloakDrain <= 0)
	{
		flCloakDrain = DEFAULT_LEAP_DRAIN;
	}
	
	if(flCloakAmount < flCloakDrain)
	{
		// we dont have enough cloak!
		return;
	}
	
	float vOrigin[3], vAngles[3], vForward[3], vVelocity[3];
	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);
	
	// Get the direction we want to go
	GetAngleVectors(vAngles, vForward, NULL_VECTOR, NULL_VECTOR);
	
	// make it usable
	float flDistance = CEconItems_GetEntityAttributeFloat(weapon, "knife leap distance");
	if(flDistance <= 0)
	{
		flDistance = DEFAULT_LEAP_DISTANCE;
	}
	ScaleVector(vForward, flDistance);	
	
	// add it to the current velocity to avoid just being able to do full 180s
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVelocity);
	AddVectors(vVelocity, vForward, vVelocity);
	
	float flDistanceVertical = CEconItems_GetEntityAttributeFloat(weapon, "knife leap distance vertical");
	if(flDistanceVertical <= 0)
	{
		flDistanceVertical = DEFAULT_LEAP_DISTANCE_VERTICAL;
	}
	vVelocity[2] += flDistanceVertical; // we always want to go a bit up
	
	// And set it
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vVelocity);
	SetEntPropFloat(client, Prop_Send, "m_flCloakMeter", flCloakAmount - flCloakDrain);
	EmitGameSoundToAll(SOUND_LEAP,client);
	m_flLastLeapTime[client] = GetEngineTime();
}

// check if any weapon on the player has the attribute
bool HasAttribute(int client)
{
	for (int i = 0; i <= TFWeaponSlot_Melee; i++)
	{
		int iWeapon = GetPlayerWeaponSlot(client, i);
		if(iWeapon > 0 && IsValidEntity(iWeapon) && CEconItems_GetEntityAttributeBool(iWeapon, "knife leap"))
		{
			return true;
		}
	}
	return false;
}

int GetAttribute(int client)
{
	for (int i = 0; i <= TFWeaponSlot_PDA; i++)
	{
		int iWeapon = GetPlayerWeaponSlot(client, i);
		if(iWeapon > 0 && IsValidEntity(iWeapon) && CEconItems_GetEntityAttributeBool(iWeapon, "knife leap"))
		{
			return iWeapon;
		}
	}
	return -1;
}

/*
bool HasAttributeActive(int client)
{
    int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (IsValidEntity(iActiveWeapon))
    {
        return CEconItems_GetEntityAttributeBool(iActiveWeapon, "knife leap");
    }
    return false;
}
*/

stock int GetActiveWeapon(int client)
{
	if(!IsClientValid(client))
	{
		return -1;
	}
	return GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
}

bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients) return false;
	if(!IsValidEntity(client)) return false;
	if (!IsClientInGame(client)) return false;
	if (!IsClientAuthorized(client)) return false;
	return true;
}