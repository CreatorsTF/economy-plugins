#include <sdkhooks>

// Hook all of our game events.
public void HookEvents()
{
	// Hook player events.
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("teamplay_round_win", OnRoundWin);
	
	for (int i = 0; i < MAXPLAYERS + 1; i++)
	{
	}
}

public void OnClientPostAdminCheck(int client)
{

}

// Events relating to the attacker killing a victim.
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int assister = GetClientOfUserId(event.GetInt("assister"));
	
	// Other variables.
	int crit_type = event.GetInt("crit_type");
	int death_flags = event.GetInt("death_flags");
	
	// Make sure we're not the same.
	if (IsClientValid(attacker) && IsClientValid(victim)
		&& attacker != victim)
	{
		// Award an event for the killer.
		CallContrackerEvent(attacker, "CONTRACTS_PLAYER_KILL", 1);
		// Award an event for the person who died.
		CallContrackerEvent(victim, "CONTRACTS_PLAYER_DEATH", 1);
		
		// Award our assister.
		if (IsClientValid(assister)) CallContrackerEvent(assister, "CONTRACTS_PLAYER_ASSIST_KILL", 1);
		
		// Deal with Critical damage.
		switch (crit_type)
		{
			case 1: 
			{
				CallContrackerEvent(attacker, "CONTRACTS_PLAYER_KILL_MINICRIT", 1);
				CallContrackerEvent(victim, "CONTRACTS_PLAYER_DEATH_MINICRIT", 1);
			}
			case 2: 
			{
				CallContrackerEvent(attacker, "CONTRACTS_PLAYER_KILL_CRIT", 1);
				CallContrackerEvent(victim, "CONTRACTS_PLAYER_DEATH_CRIT", 1);	
			}
		}
	
		// Domination.
		if(death_flags & TF_DEATHFLAG_KILLERDOMINATION) CallContrackerEvent(attacker, "CONTRACTS_PLAYER_DOMINATE", 1);
		
		// Custom Creators content triggers.
		// Are we currently using CWX?
		if (LibraryExists("cwx"))
		{
			// Get this persons active weapon and see if it's a custom weapon. If so - send a blanket event.
			int iActiveWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
			int iActiveWeaponSlot;
			
			for (int s = 0; s < TFWeaponSlot_PDA; s++)
			{
				// Is this our slot?
				if (GetPlayerWeaponSlot(attacker, s) == iActiveWeapon)
				{
					iActiveWeaponSlot = s;
					break;
				}
			}
	
			// Grab our slot.
			LoadoutEntry hSlot;
			CWX_GetCustomWeaponFromSlot(attacker, view_as<int>(TF2_GetPlayerClass(attacker)), iActiveWeaponSlot, hSlot);
			
			// This is a custom weapon, deal with it.
			if (CWX_IsItemUIDValid(hSlot.uid)) CallContrackerEvent(attacker, "CONTRACTS_PLAYER_KILL_CUSTOMWEAPON", 1);
		}
	}
}

// Events relating to the attacker hurting a victim.
public Action OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	// Get our players.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int damage = event.GetInt("damageamount");
	
	// Make sure we're not the same.
	if (attacker != victim)
	{
		// Award an event for the killer.
		CallContrackerEvent(attacker, "CONTRACTS_PLAYER_DEAL_DAMAGE", damage);
		// Award an event for the person who died.
		CallContrackerEvent(victim, "CONTRACTS_PLAYER_TAKE_DAMAGE", damage);
	}
}

// Events relating to the round ending
public Action OnRoundWin(Event event, const char[] name, bool dontBroadcast)
{
	int team = event.GetInt("team");
	int winreason = event.GetInt("winreason");
	
	// Did we win by capturing the objective?
	switch (winreason)
	{
		case 1:
		{
			for (int i = 0; i < MAXPLAYERS+1; i++)
			{
				if (IsClientValid(i)) continue;
				// Are we on the same team?
				if (view_as<int>(TF2_GetClientTeam(i)) == team)
				{
					CallContrackerEvent(i, "CONTRACTS_PLAYER_WIN_ROUND", 1);
					CallContrackerEvent(i, "CONTRACTS_PLAYER_WIN_CAPTUREOBJECTIVE", 1);
				}
			}
		}
		
	}
}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
