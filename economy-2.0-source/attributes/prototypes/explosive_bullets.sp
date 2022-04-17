#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdktools_functions>
#include <sdktools_entinput>
#include <tf2>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf_custom_attributes>
#include <sdkhooks>
#include <entity>
#include <smlib>
#include <tf2utils>

#define PLUGIN_NAME           "[CE Attribute] exposive bullets"
#define PLUGIN_AUTHOR         "Creators.TF Team - qualitycont"
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

#define SNIPER_BASE_DAMAGE 50.0

float m_flCharge[MAXPLAYERS];

public Action TF2_CalcIsAttackCritical(int client, int weapon, char[] weaponname, bool &result)
{
	if(IsClientValid(client) && HasAttribute(weapon))
	{
		char sClass[64];
		GetEntityClassname(weapon, sClass, sizeof sClass);
		if(StrEqual(sClass,"tf_weapon_sniperrifle"))
		{
			// HACK: RequestFrame only allows for one parameter to be passed
			// and in the next frame the charged damage has already been reset
			// so store it in the only (ugly) way possible
			m_flCharge[client] = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
		}
		RequestFrame(DoExplosiveShot, client);
	}
}

void DoExplosiveShot(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	float vecShooterPos[3], vecShooterAng[3], vecEndPos[3];
	GetClientEyePosition(client, vecShooterPos);
	GetClientEyeAngles(client, vecShooterAng);
	
	TR_TraceRayFilter(vecShooterPos, vecShooterAng, MASK_SHOT, RayType_Infinite, ExplosiveBulletFilter, client);
	TR_GetEndPosition(vecEndPos);
	
	int iDamage = TF2CustAttr_GetInt(weapon, "explosive bullets damage", 30);
	char sClass[64];
	GetEntityClassname(weapon, sClass, sizeof sClass);
	if(StrEqual(sClass,"tf_weapon_sniperrifle"))
	{
		// scale damage with sniper rifle charge
		float flChargeDmg = Math_Min(m_flCharge[client], SNIPER_BASE_DAMAGE);
		iDamage = RoundToNearest( iDamage * flChargeDmg / SNIPER_BASE_DAMAGE); 
		m_flCharge[client] = 0.0;
	}
	
	int iRadius = TF2CustAttr_GetInt(weapon, "explosive bullets radius");
	float flForce = TF2CustAttr_GetFloat(weapon, "explosive bullets force");
	
	// Setup the explosion
	int explosion = SetupExplosion(client, vecEndPos, iDamage, iRadius, flForce);
	
	DispatchSpawn(explosion);
	ActivateEntity(explosion);
	AcceptEntityInput(explosion, "Explode");
}

int SetupExplosion(int attacker, float position[3], int damage, int radius = 0, float force = 0.0)
{
	int iExplosion = CreateEntityByName("env_explosion");
	SetEntPropEnt(iExplosion, Prop_Send, "m_hOwnerEntity", attacker);
	
	char sDmg[32];
	IntToString(damage, sDmg, sizeof sDmg);
	DispatchKeyValue(iExplosion, "iMagnitude",  sDmg);
	if(radius > 0)
	{
		char sRadius[32];
		IntToString(radius, sRadius,32);
		DispatchKeyValue(iExplosion, "iRadiusOverride", sRadius);
	}
	if(force > 0.0)
	{
		DispatchKeyValueFloat(iExplosion, "DamageForce", force);
	}
	
	//PrintToChat(attacker, "Explosion: %i, %i, %f", damage, radius, force);
	
	TeleportEntity(iExplosion, position, NULL_VECTOR, NULL_VECTOR);
	return iExplosion;
}

public bool ExplosiveBulletFilter(int entity, int contentsMask, int attacker)
{
	char sClass[32];
	GetEntityClassname(entity, sClass, sizeof sClass);
	if(StrEqual(sClass, "func_door"))
	{
		return false;
	}
	return entity != attacker;
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
		return TF2CustAttr_GetInt(weapon, "explosive bullets") > 0;
	}
	return false;
}

// OLD ON HIT EXPLOSION CODE

/*
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon,
		float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(!IsClientValid(victim) || !IsClientValid(attacker)) return Plugin_Continue;
	
	if(HasAttribute(weapon))
	{
		float flExplosionDamageMult = TF2CustAttr_GetFloat(weapon, "explosive bullets damage", 0.5);
		int iRadius = TF2CustAttr_GetInt(weapon, "explosive bullets radius");
		float flForce = TF2CustAttr_GetFloat(weapon, "explosive bullets florce");
		
		// Setup the explosion
		int explosiondmg = RoundToNearest(damage * flExplosionDamageMult);
		int explosion = SetupExplosion(attacker, damagePosition, explosiondmg, iRadius, flForce);
		
		char sVic[32];
		IntToString(victim, sVic, 32);
		DispatchKeyValue(explosion, "IgnoredEntity", sVic);
		DispatchSpawn(explosion);
		ActivateEntity(explosion);
		AcceptEntityInput(explosion, "Explode");
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}
*/