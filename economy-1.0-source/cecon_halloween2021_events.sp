#pragma semicolon 1
#pragma newdecls required

#include <cecon>
#include <cecon_items>
#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>

#define TF_BUILDING_SAPPER 3

public Plugin myinfo =
{
	name = "Creators.TF Economy - Halloween 2021 Events",
	author = "Creators.TF Team (ZoNiCaL)",
	description = "Creators.TF Halloween 2021 Events",
	version = "1.0",
	url = "https://creators.tf"
}

/*
ZoNiCaL here! Let me quickly explain this plugin!

This plugin was made to track *very specific* stuff for certain contracts that
were released for the Halloween 2021 update for Creators.TF. Contracts currently
don't support having cosmetic restrictions, so some events have been modified
to check if a player has X cosmetic and if so, fire a special event.

This plugin is only meant to be active for the duration of the event. Move to
/disabled otherwise!

Thanks :)
*/

public void OnPluginStart()
{
	// Misc Events
	HookEvent("environmental_death", environmental_death);
	HookEvent("teamplay_win_panel", evTeamplayWinPanel);
	HookEvent("teamplay_point_captured", teamplay_point_captured);
	HookEvent("teamplay_flag_event", teamplay_flag_event);
	
	// Object Events
	HookEvent("object_destroyed", object_destroyed);

	// Player Events
	HookEvent("player_death", player_death);
	
	for (int i = 0; i < MAXPLAYERS+1; i++)
	{
		if (!IsClientValid(i)) continue;
		SDKHook(i, SDKHook_OnTakeDamagePost, OnPlayerDamagePost);
	}

}

public Action player_death(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
	int death_flags = GetEventInt(hEvent, "death_flags");
	int customkill = GetEventInt(hEvent, "customkill");

	if (!IsClientValid(client)) return Plugin_Continue;
	if (!IsClientValid(attacker)) return Plugin_Continue;
	if (client == attacker) return Plugin_Continue;

	// Item related events.
	int attackerItemCount = CEconItems_GetClientWearedItemsCount(attacker);
	for (int i = 0; i < attackerItemCount; i++)
	{
		// Grab item.
		CEItem xItem;
		CEconItems_GetClientWearedItemByIndex(attacker, i, xItem);
		
		// Does this item have "holiday restricted" set to 3?
		if (CEconItems_GetAttributeIntegerFromArray(xItem.m_Attributes, "holiday restricted") == 3)
			CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_RESTRICTED_KILL", 1, hEvent);
		
		// Is this item...
		switch (xItem.m_iItemDefinitionIndex)
		{
			case 185: /*Body Builder*/ {
				// Send basic kill event. "Get a kill while wearing the Body Builder"
				CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_BODYBUILDER_KILL", 1, hEvent);
				
				// Are we dominating with this kill? "Get two dominations in a match while wearing the Body Builder"
				// NOTE: Contracker logic handles the two dominations part.
				if(death_flags & TF_DEATHFLAG_KILLERDOMINATION)
					CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_BODYBUILDER_DOMINATE", 1, hEvent);
			}
			case 187: /*BOMBINOCULUS!*/ {
				// Send basic kill event. "Get a kill while wearing the BOMBINOCULUS!"
				CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_BOMB_KILL", 1, hEvent);
				
				// If we're in the air while killing, fire an event. "Kill an enemy while airborne and wearing the BOMBINOCULUS!"
				if(!(GetEntityFlags(attacker) & FL_ONGROUND))
					CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_BOMB_AIRBORNE_KILL", 1, hEvent);
			}
			case 188: /*Iron Sight*/ {
				// If the person we're killing is a Demoman, fire an event. "Kill another Demoman while wearing the Iron Sight"
				if (TF2_GetPlayerClass(client) == TFClass_DemoMan)
					CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_IRON_DEMOKILL", 1, hEvent);
				
				// If the person we're killing is in the air, fire an event. "Kill an airborne enemy while wearing the Iron Sight"
				if(!(GetEntityFlags(client) & FL_ONGROUND))
					CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_IRON_AIRBORNE", 1, hEvent);
			}
			case 189: /*Minor Magus Sleeves*/ {
				
				// If this is a spell kill, send an event. "Kill a player with a spell while using the Minor Magus Sleeves"
				switch (customkill)
				{
					case TF_CUSTOM_SPELL_BATS: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_BLASTJUMP: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_FIREBALL: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_LIGHTNING: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_METEOR: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_MIRV: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_MONOCULUS: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_SKELETON: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_TELEPORT: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
					case TF_CUSTOM_SPELL_TINY: CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MAGUS_SPELLKILL", 1, hEvent);
						
				}
				
			}
			case 190: /*Molten Monitor*/ CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_MOLTENMONITOR_KILL", 1, hEvent);
			case 191: /*Pocket nope.avi*/ {
				// Send basic kill event. "Get a kill while wearing the Pocket nope.avi"
				CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_NOPE_KILL", 1, hEvent);
				
				// If the person we're killing is in the air, fire an event. "Get an airborne kill while wearing the Pocket nope.avi"
				if(!(GetEntityFlags(client) & FL_ONGROUND))
					CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_NOPE_AIRBORNE", 1, hEvent);
					
				// Are we dominating with this kill? ""Exert true dominance by dominating a player while wearing the Pocket nope.avi"
				if(death_flags & TF_DEATHFLAG_KILLERDOMINATION)
					CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_NOPE_DOMINATE", 1, hEvent);
			}
			case 192: {
				// Send basic kill event. "Get a kill while wearing the Voodoonicorn"
				CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_VOODOO_KILL", 1, hEvent);
				
				// Are we getting revenge on someone with this kill? "Get true revenge on your enemies while wearing the Voodoonicorn"
				if(death_flags & TF_DEATHFLAG_KILLERREVENGE)
					CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_VOODOO_REVENGE", 1, hEvent);
			}
		}
	}
	
	return Plugin_Continue;
}

public void OnClientPostAdminCheck(int client)
{
	SDKHook(client, SDKHook_OnTakeDamagePost, OnPlayerDamagePost);
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamagePost, OnPlayerDamagePost);
}

public void OnPlayerDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	if (!IsClientValid(victim)) return;
	if (!IsClientValid(attacker)) return;
	if (attacker == victim) return;
	
	// Item related events..
	int playerItemCount = CEconItems_GetClientWearedItemsCount(attacker);
	for (int i = 0; i < playerItemCount; i++)
	{
		// Grab item.
		CEItem xItem;
		CEconItems_GetClientWearedItemByIndex(attacker, i, xItem);
		
		// Custom damage types.
		if ((damagetype & DMG_CRIT) == DMG_CRIT)		// Crits or mini-crits.
		{
			switch (xItem.m_iItemDefinitionIndex)
			{
				// "Deal 500 mini-crit or critical damage as Pyro while wearing the Aquanaut"
				case 186: /*Aquanaut*/ CEcon_SendEventToClientUnique(attacker, "CREATORS_HALLOWEEN_CRITS_AQUANAUT", RoundToNearest(damage));
			}
		}
		
		
		if ((damagetype & DMG_BLAST) == DMG_BLAST) // Explosive damage.
		{
			// Is this item...
			switch (xItem.m_iItemDefinitionIndex)
			{
				// "Deal 500 blast or fire damage in single life while wearing the BOMBINOCULUS!"
				case 187: /*BOMBINOCULUS!*/ CEcon_SendEventToClientUnique(attacker, "CREATORS_HALLOWEEN_BOMB_FIREORBLAST_DAMAGE", RoundToNearest(damage));
				case 189: /*Minor Magus Sleeves*/ CEcon_SendEventToClientUnique(attacker, "CREATORS_HALLOWEEN_MAGUS_BLASTDAMAGE", RoundToNearest(damage));
				
			}
		}
		else
		{
			// Is this item...
			switch (xItem.m_iItemDefinitionIndex)
			{
				case 189: /*Minor Magus Sleeves*/ CEcon_SendEventToClientUnique(attacker, "CREATORS_HALLOWEEN_MAGUS_NOBLASTDAMAGE", RoundToNearest(damage));
			}
		}
		
		// If the player is in a condition...
		if (TF2_IsPlayerInCondition(attacker, TFCond_Charging))
		{
			switch (xItem.m_iItemDefinitionIndex)
			{
				// "Smash into your enemies with a shield while wearing the Iron Sight"
				case 188: /*Iron Sight*/ CEcon_SendEventToClientUnique(attacker, "CREATORS_HALLOWEEN_IRON_SMASH", RoundToNearest(damage));
			}
		}
		
		else if (TF2_IsPlayerInCondition(victim, TFCond_OnFire))
		{
			// Is this item...
			switch (xItem.m_iItemDefinitionIndex)
			{
				// "Deal 212 fire damage as Pyro while wearing the Aquanaut"
				case 186: /*Aquanaut*/ 		CEcon_SendEventToClientUnique(attacker, "CREATORS_HALLOWEEN_FIRE_AQUANAUT", RoundToNearest(damage));
				
				// "Deal 500 blast or fire damage in single life while wearing the BOMBINOCULUS!"
				case 187: /*BOMBINOCULUS!*/ CEcon_SendEventToClientUnique(attacker, "CREATORS_HALLOWEEN_BOMB_FIREORBLAST_DAMAGE", RoundToNearest(damage));
			}
		}
	}
}

public Action object_destroyed(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
	int objecttype = GetEventInt(hEvent, "objecttype");

	if(IsClientValid(attacker) && attacker != client)
	{
		// Is this a sapper?
		if (objecttype == TF_BUILDING_SAPPER)
		{
			// Item related events.
			int playerItemCount = CEconItems_GetClientWearedItemsCount(attacker);
			for (int i = 0; i < playerItemCount; i++)
			{
				// Grab item.
				CEItem xItem;
				CEconItems_GetClientWearedItemByIndex(attacker, i, xItem);
				
				// Is this item...
				switch (xItem.m_iItemDefinitionIndex)
				{
					// "Destroy 5 sappers in a match while wearing the Body Builder"
					case 185: /*Body Builder*/ CEcon_SendEventToClientFromGameEvent(attacker, "CREATORS_HALLOWEEN_BODYBUILDER_SAPPER", 1, hEvent);
				}
			}
		}
	}

	return Plugin_Continue;
}

public Action environmental_death(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	int killer = GetEventInt(hEvent, "killer");
	int victim = GetEventInt(hEvent, "victim");

	if(IsClientValid(killer) && killer != victim)
	{
		// Item related events.
		int playerItemCount = CEconItems_GetClientWearedItemsCount(killer);
		for (int i = 0; i < playerItemCount; i++)
		{
			// Grab item.
			CEItem xItem;
			CEconItems_GetClientWearedItemByIndex(killer, i, xItem);
			
			// Is this item...
			switch (xItem.m_iItemDefinitionIndex)
			{
				// "Eject a player by causing an environmental kill while wearing the Molten Monitor"
				case 190: /*Molten Monitor*/ CEcon_SendEventToClientFromGameEvent(killer, "CREATORS_HALLOWEEN_MOLTENMONITOR_EJECT", 1, hEvent);
			}
		}
	}

	return Plugin_Continue;
}

public Action evTeamplayWinPanel(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	int players[3];
	players[0] = GetEventInt(hEvent, "player_1");
	players[1] = GetEventInt(hEvent, "player_2");
	players[2] = GetEventInt(hEvent, "player_3");

	for (int p = 0; p < 3; p++)
	{
		int player = players[p];
		if (!IsClientValid(player)) continue;
		
		// Item related events.
		int playerItemCount = CEconItems_GetClientWearedItemsCount(player);
		for (int i = 0; i < playerItemCount; i++)
		{
			// Grab item.
			CEItem xItem;
			CEconItems_GetClientWearedItemByIndex(player, i, xItem);
			
			// Is this item...
			switch (xItem.m_iItemDefinitionIndex)
			{
				// "Be the MVP at the end of the round while wearing the Molten Monitor"
				case 190: /*Molten Monitor*/ CEcon_SendEventToClientFromGameEvent(player, "CREATORS_HALLOWEEN_MOLTENMONITOR_MVP", 1, hEvent);
			}
		}
	}
	

	return Plugin_Continue;
}
public Action teamplay_point_captured(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	char cappers[1024];
	GetEventString(hEvent, "cappers", cappers, sizeof(cappers));
	int len = strlen(cappers);
	for (int i = 0; i < len; i++)
	{
		int client = cappers[i];
		if (!IsClientValid(client))continue;
		
		// Item related events.
		int playerItemCount = CEconItems_GetClientWearedItemsCount(client);
		for (int j = 0; j < playerItemCount; j++)
		{
			// Grab item.
			CEItem xItem;
			CEconItems_GetClientWearedItemByIndex(client, j, xItem);
			
			// Is this item...
			switch (xItem.m_iItemDefinitionIndex)
			{
				// Capture the objective while wearing the Voodoonicorn
				case 192: /*Voodoonicorn*/ CEcon_SendEventToClientFromGameEvent(client, "CREATORS_HALLOWEEN_VOODOO_CAPTURE", 1, hEvent);
			}
		}
	}
	return Plugin_Continue;
}

public Action teamplay_flag_event(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	int player = GetEventInt(hEvent, "player");
	int eventtype = GetEventInt(hEvent, "eventtype");

	if(IsClientValid(player) && eventtype == TF_FLAGEVENT_CAPTURED)
	{
		// Item related events.
		int playerItemCount = CEconItems_GetClientWearedItemsCount(player);
		for (int i = 0; i < playerItemCount; i++)
		{
			// Grab item.
			CEItem xItem;
			CEconItems_GetClientWearedItemByIndex(player, i, xItem);
			
			// Is this item...
			switch (xItem.m_iItemDefinitionIndex)
			{
				// Capture the objective while wearing the Voodoonicorn
				case 192: /*Voodoonicorn*/ CEcon_SendEventToClientFromGameEvent(player, "CREATORS_HALLOWEEN_VOODOO_CAPTURE", 1, hEvent);
			}
		}
	}

	return Plugin_Continue;
}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}

public bool IsClientReady(int client)
{
	if (!IsClientValid(client))return false;
	if (IsFakeClient(client))return false;
	return true;
}