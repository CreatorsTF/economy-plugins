#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <cecon>
#include <cecon_items>
#include <sdktools>
#include <tf2_stocks>

public Plugin myinfo =
{
	name = "[CE Attribute] The Quickdraw",
	author = "Creators.TF Team - ZoNiCaL.",
	description = "The Quickdraw",
	version = "1.2",
	url = "https://creators.tf"
};

float	fBonusUntil[MAXPLAYERS+1];

public void OnClientPutInServer(int client)
{
	fBonusUntil[client] = 0.0;
	
	// Hook weapon switching for this client here:
	SDKHook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	fBonusUntil[client] = 0.0;
	
	// Unhook our weapon switching:
	SDKUnhook(client, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
	SDKUnhook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
}

public void OnMapStart()
{
	// Just as safety, precache the engineer battlecry we'll use.
	PrecacheScriptSound("Engineer.BattleCry03");
}

public void OnPluginStart()
{
	// Late hook our SDKHooks.
	LateHook();
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
}

public void LateHook()
{
	for (int i = 0; i < MaxClients; i++)
	{
		if (IsClientValid(i))
		{
			SDKHook(i, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
			SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamage);
		}
	}
}

public Action OnPlayerSpawn(Event hEvent, const char[] name, bool dontBroadcast)
{
	// As a safety, hook our player spawn so we can reset our time variables.
	int client = GetClientOfUserId(hEvent.GetInt("userid"));
	if (IsClientValid(client))
	{
		fBonusUntil[client] = 0.0;
	}
}

public void OnWeaponSwitch(int client, int weapon)
{
	// When we switch weapons, we're going to grant a damage bonus
	// based off of the "half second damage bonus" attribute.
	
	// We'll do the damage calculation in another function. Here we'll see
	// when until we can have this bonus.	
	
	// Do we have "half second damage bonus"?
	if (CEconItems_GetEntityAttributeFloat(weapon, "quickdraw timed damage bonus") > 0.0)
	{
		// We have until our current time plus 1 second to have a damage increase.
		fBonusUntil[client] = GetEngineTime() + 1.0;
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon,
		float damageForce[3], float damagePosition[3], int damagecustom)
{
	// Are our clients valid?
	if (!IsClientValid(victim) || !IsClientValid(attacker)) return Plugin_Continue;
	
	// Is the entity inflicting damage a sentry gun?
	char m_szClassname[256];
	GetEdictClassname(inflictor, m_szClassname, sizeof(m_szClassname));  
	if (StrContains(m_szClassname, "obj_") != -1) return Plugin_Continue;
	
	// We're going to check if our attacker is currently under a "half second damage bonus"
	// effect. If so, we'll apply multiply our damage amount by that, or do a duel with
	// another Quickdraw Engineer.
	if (fBonusUntil[attacker] > GetEngineTime())
	{
		// If we're dueling against another engineer with the Quickdraw, it's an insta kill.
		int iActiveWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
		if (CEconItems_GetEntityAttributeBool(iActiveWeapon, "duel against quickdraw engineers"))
		{
			// What's the active weapon of the victim?
			int iVictimActiveWeapon = GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon");
			if (IsValidEntity(iVictimActiveWeapon))
			{
				// Do they have the duel Quickdraw attribute?
				if (CEconItems_GetEntityAttributeBool(iVictimActiveWeapon, "duel against quickdraw engineers"))
				{
					// Kill the victim by dealing an absurd amount of damage.
					damage = 999.0;
					EmitGameSoundToClient(attacker, "Engineer.BattleCry03");
					
					// Send a game event that we've killed someone with the Quickdraw dueling mechanic.
					CEcon_SendEventToClientUnique(attacker, "TF_QUICKDRAW_DUEL_KILL", 1);
					return Plugin_Changed;
				}
			}
			
			
			// If we're not dueling against another Engineer, our damage is now minicrit damage.
			damage = MiniCritDamage(attacker, victim, damage, damage);
			return Plugin_Changed;
		}
		
	}
	return Plugin_Continue;
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Get the attacker of the victim who died.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	// Are we under the Quickdraw one second bonus?
	if (fBonusUntil[attacker] > GetEngineTime())
	{
		// If we are, all crits are dealt as mini-crits. The game doesn't actually
		// recognize this as mini-crits, so we'll change this event to say this was
		// dealt with mini-crits.
		event.SetInt("crit_type", 1); // 1 is a mini-crit.
	}
	return Plugin_Continue;
}

// Deal minicrit damage here. Thanks Ivory!
stock float MiniCritDamage(int attacker, int victim, float damage, float basedamage)
{
	float partpos[3];
	if (damage < basedamage)
		damage = basedamage; //No damage falloff

	damage *= 1.35; //Scale damage by 35%
	
	// Get the client's eye position for the particle.
	GetClientEyePosition(victim, partpos);
	partpos[2] += 15.0;
	
	// Create the particle itself.
	// We don't want to display the particle effect for disguised spies OR for spies who are cloaked.
	// This will give them away! This check will also prevent a fake minicrit if spies are disguised and cloaked.
	if (TF2_IsPlayerInCondition(victim, TFCond_Disguised) || TF2_IsPlayerInCondition(victim, TFCond_Cloaked)) 
	{
		return damage;
	}
	
	int iParticle = CreateEntityByName("info_particle_system");
	if (IsValidEdict(iParticle))
	{
		// Teleport our particle system to slightly above our head.
		TeleportEntity(iParticle, partpos, NULL_VECTOR, NULL_VECTOR);
		
		// Set the particle effect.
		DispatchKeyValue(iParticle, "effect_name", "minicrit_text");
		
		// Parent this particle system to the player.
		SetVariantString("!activator");
		AcceptEntityInput(iParticle, "SetParent", victim, iParticle, 0);
		
		// Spawn entity.
		DispatchSpawn(iParticle);
		ActivateEntity(iParticle);
		
		// Activate the particle system.
		AcceptEntityInput(iParticle, "Start");
	}
	
	// Play the sound:
	char sCritSound[64];
	Format(sCritSound, sizeof sCritSound, "player/crit_hit_mini%i.wav", GetRandomInt(3, 5));
	EmitSoundToAll(sCritSound, victim, SNDCHAN_AUTO, 75);
	EmitSoundToClient(attacker, sCritSound);
	EmitSoundToClient(victim, "player/crit_received2.mp3");
	
	return damage;
}

// Create the particle for Mini Crit's with this special function from Ivory.
stock int CreateParticle(int iEntity=0, char[] sParticle, bool bAttach = false, float pos[3]={0.0, 0.0, 0.0})
{
	int iParticle = CreateEntityByName("info_particle_system");
	if (IsValidEdict(iParticle))
	{
		if (iEntity > 0)
		GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", pos);

		TeleportEntity(iParticle, pos, NULL_VECTOR, NULL_VECTOR);
		DispatchKeyValue(iParticle, "effect_name", sParticle);

		if (bAttach)
		{
			SetVariantString("!activator");
			AcceptEntityInput(iParticle, "SetParent", iEntity, iParticle, 0);
		}

		DispatchSpawn(iParticle);
		ActivateEntity(iParticle);
		AcceptEntityInput(iParticle, "Start");
	}
	return iParticle;
}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
