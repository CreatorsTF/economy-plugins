#pragma semicolon 1

#include <sdktools>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf_custom_attributes>

#define PLUGIN_NAME           "Projectile Revolver Attributes"
#define PLUGIN_AUTHOR         "Creators.TF Team - kaputon, qualitycont"
#define PLUGIN_DESCRIPTION    "Projectile Revolver Attributes."
#define PLUGIN_VERSION        "2.1"
#define PLUGIN_URL            "https//creators.tf"

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

float TAGGED_VICTIMS[64]; // Store players tagged by the revolver.
bool m_bIsTranqProjectile[2049];

#define PROJ_SPEED 2400.00 // Projectile Revolver's Speed
#define PROJ_NAME "tf_projectile_arrow" // "tf_projectile_healing_bolt"
#define HEALTH_SCALE 0.5
#define KILL_COND TFCond_SpeedBuffAlly
#define KILL_COND_DURATION 5.0
#define TAG_DURATION 1.5 // How long will the projectile tag the victim?

// Client Joins
public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, CheckAttacker);
}

// Client Leaves
public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, CheckAttacker);
}

// Plugin begins running.
public void OnPluginStart()
{
	LateHook();
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
}


public void LateHook()
{
	for (int i = 0; i < MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			SDKHook(i, SDKHook_OnTakeDamage, CheckAttacker);
		}
	}
}

// Check the attacker on damage. If they have the projectile revolver, tag the victim
Action CheckAttacker(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (m_bIsTranqProjectile[inflictor])
	{
		TAGGED_VICTIMS[victim] = GetEngineTime()+TAG_DURATION;

		//PrintToChatAll("[SM] Player has been struck by a projectile revolver.");
	}
	return Plugin_Continue;
}

Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Get the attacker and victim.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));

	if (GetEngineTime() < TAGGED_VICTIMS[victim])
	{
		BuffAttacker(attacker);
	}
}

// Buff the attacker.
void BuffAttacker(int attacker)
{
	// SET HP

	// Give us the Max HP of the attacker.
	int iCurHP = GetClientHealth(attacker);
	int iMaxHP = GetEntProp(attacker, Prop_Data, "m_iMaxHealth");
	int iMaxOverheal = RoundToNearest(iMaxHP * 1.5);

	int target_health = iCurHP + RoundToCeil(iMaxHP*HEALTH_SCALE);
	if(target_health > iMaxOverheal)
	{
		target_health = iMaxOverheal;
	}

	SetEntityHealth(attacker, target_health); // Boost the attackers HP by half of their max HP

	// GIVE EFFECT
	TF2_AddCondition(attacker, KILL_COND, KILL_COND_DURATION);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity != -1 && StrEqual(classname, PROJ_NAME))
	{
		RequestFrame(ProjSpawned, entity);
	}
}

// Just as a fail-safe, mark any entities destroyed as NOT a projectile
// so we don't get problems with recycling indexes.
public void OnEntityDestroyed(int entity)
{
	// For some reason, we can get absurd values here like -2113832908.
	// This is a quick failsafe as well.
	if (entity <= 2048 && entity > 0)
	{
		m_bIsTranqProjectile[entity] = false;
	}
	
}

// Do Vector Math a frame after the entity spawns
public void ProjSpawned(int entity)
{
	int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity"); // Get the 'owner' of the RR Bolt

	if (HasAttributeActive(client))
	{
		float weaponPos[3];
		float clientEyeAngles[3];
		float wepVel[3];

		GetClientEyePosition(client, weaponPos);
		GetClientEyeAngles(client, clientEyeAngles);

		GetAngleVectors(clientEyeAngles, wepVel, NULL_VECTOR, NULL_VECTOR);

		ScaleVector(wepVel, PROJ_SPEED);

		SetEntPropVector(entity, Prop_Send, "m_vInitialVelocity", wepVel);
		TeleportEntity(entity, weaponPos, clientEyeAngles, wepVel);
		SetEntityGravity(entity, 0.15);

		m_bIsTranqProjectile[entity] = true;
	}
}

bool HasAttributeActive(int client)
{
	if (!IsClientValid(client)) return false;
	
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(iActiveWeapon))
	{
		return TF2CustAttr_GetInt(iActiveWeapon, "projectile revolver") > 0;
	}
	return false;
}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
