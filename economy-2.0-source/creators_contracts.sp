#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <creators/creators_cwx>
#include <morecolors>

#pragma semicolon 1

#include "contracts/contracts_schema.sp"
#include "contracts/contracts_events.sp"

public Plugin myinfo =
{
	name = "[Creators.TF] Contracker / Player Progression",
	author = "Creators.TF Team - ZoNiCaL",
	description = "Allows server operators to design their own contracts.",
	
	// Version will follow the Alpha, Beta, Hamma, Delta, Epsilon naming style
	// to show "how stable" this plugin is through the refactoring process.
	version = "beta-1.0.1",
	
	url = "https://creators.tf/"
};

public void OnPluginStart()
{
	// Hook all of our game events.
	HookEvents();	
	ProcessContractsSchema();
	CreateContractMenu();
	
	RegConsoleCmd("sm_setcontract", DebugSetContract);
	RegServerCmd("sm_reloadcontracts", ReloadContracts);
	RegConsoleCmd("sm_contract", OpenContrackerForClient);
	RegConsoleCmd("sm_contracts", OpenContrackerForClient);
	RegConsoleCmd("sm_contracker", OpenContrackerForClient);
	RegConsoleCmd("sm_c", OpenContrackerForClient);
}

Contract m_hContracts[MAXPLAYERS+1];

public Action DebugSetContract(int client, int args)
{	
	// Grab UUID.
	char sUUID[64];
	GetCmdArg(1, sUUID, sizeof(sUUID));
	
	ActivateContract(client, sUUID);
	
	return Plugin_Handled;
}

public Action ReloadContracts(int args)
{
	ProcessContractsSchema();
	CreateContractMenu();
}

// Activates a contract for the player.
public void ActivateContract(int client, const char[] sUUID)
{
	if (GetCustomItemDefinition(sUUID, m_hContracts[client]))
	{
		MC_PrintToChat(client,
		"{creators}>>{default} You have selected the contract: {lightgreen}\"%s\"{default}. To complete it, finish all of it's objectives.",
		m_hContracts[client].m_sContractName);
		
		// Print our objectives to chat.
		PrintContractObjective(client, m_hContracts[client].m_hPrimaryObjective);
		PrintContractObjective(client, m_hContracts[client].m_hSecondObjective);
		PrintContractObjective(client, m_hContracts[client].m_hThirdObjective);
	}
}

// Prints a Contract Objective to the player in chat.
public void PrintContractObjective(int client, ContractObjective hObjective)
{
	// Print our first objective.
	if (hObjective.m_bInitalized)
	{
		MC_PrintToChat(client,
		"{creators}>>{default} Objective {%d}: {lightgreen}\"%s\"{default}. [%d/%d]",
		hObjective.m_iInternalID, hObjective.m_sDescription, hObjective.m_iProgress, hObjective.m_iMaxProgress, hObjective.m_iMaxProgress);
	}
}

public bool PerformWeaponCheck(ContractObjective hObjective, int client, int class)
{		
	int iActiveWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int iActiveWeaponSlot;
	
	for (int s = 0; s < TFWeaponSlot_PDA; s++)
	{
		// Is this our slot?
		if (GetPlayerWeaponSlot(client, s) == iActiveWeapon)
		{
			iActiveWeaponSlot = s;
			break;
		}
	}
	
	// Grab our slot.
	LoadoutEntry hSlot;
	CWX_GetCustomWeaponFromSlot(client, class, iActiveWeaponSlot, hSlot);
	
	// This is a custom weapon, deal with it.
	if (CWX_IsItemUIDValid(hSlot.uid))
	{
		CustomItemDefinition hDef;
		if (CWX_GetCustomItemDefinition(hSlot.uid, hDef))
		{
			// Does this weapons UUID or name match?
			if (StrEqual(hDef.displayName, hObjective.m_sWeaponRestriction)) return true;
			if (StrEqual(hSlot.uid, hObjective.m_sWeaponRestriction)) return true;
		}
	}
	
	return false;
}


// Processes events for an events timer. This can do things such as add or subtract another loop to the timer
// or add or subtract progress from the objective (hObjective).
public void TriggerTimeEvent(ContractObjective hObjective, ContractObjectiveEvent hEvent, const char[] m_sEventName)
{
	// Loop over our events and do an action accordingly.
	for (int i = 0; i < hEvent.m_hTimerEvents.Length; i++)
	{
		// Grab our event.
		TimerEvent hTimerEvent;
		hEvent.m_hTimerEvents.GetArray(i, hTimerEvent, sizeof(TimerEvent));
		
		// Is this the event we're looking for?
		if (StrEqual(hTimerEvent.m_sEventName, m_sEventName))
		{
			// What should we do here?
			if (StrEqual(hTimerEvent.m_sAction, "add")) hObjective.m_iProgress += hTimerEvent.m_iVariable;
			if (StrEqual(hTimerEvent.m_sAction, "subtract")) hObjective.m_iProgress -= hTimerEvent.m_iVariable;
			if (StrEqual(hTimerEvent.m_sAction, "addloop")) hEvent.m_iMaxLoops += hTimerEvent.m_iVariable;
			if (StrEqual(hTimerEvent.m_sAction, "subtractloop")) hEvent.m_iMaxLoops -= hTimerEvent.m_iVariable;
		}
	}
}

public void TryIncrementObjectiveProgress(ContractObjective hObjective, int client, const char[] event, int value)
{
	// Have we already completed this objective? No need to process this.
	if (hObjective.IsObjectiveComplete()) return;
	
	// Can this class trigger this objective?
	TFClassType class = TF2_GetPlayerClass(client);
	if (m_hContracts[client].m_bClass[class] == false) return;
	
	// If we are not using Custom Weapons X and we're not using a weapon, skip.
	if (LibraryExists("cwx") && !StrEqual(hObjective.m_sWeaponRestriction, ""))
	{
		if (!PerformWeaponCheck(hObjective, client, view_as<int>(class))) return;
	}
	
	// Loop over all of our objectives and see if this event matches.
	for (int i = 0; i < hObjective.m_hEvents.Length; i++)
	{
		ContractObjectiveEvent m_hEvent;
		hObjective.m_hEvents.GetArray(i, m_hEvent);
		
		// Does this event match?
		if (StrEqual(m_hEvent.m_sEventName, event))
		{
			// Add to our event threshold.
			m_hEvent.m_iCurrentThreshold += value;
			
			// Do we have a timer going?
			if (m_hEvent.m_hTimer != INVALID_HANDLE)
			{
				TriggerTimeEvent(hObjective, m_hEvent, "OnThreshold");
			}
			else // We don't have a timer going. See if we need to create one and if we do, create it.
			{
				// Should we have a timer?
				if (m_hEvent.m_fTime != 0.0)
				{
					// Create a datapack for our timer so we can pass our objective and event through.
					DataPack m_hTimerdata;
					
					// Create our timer.
					m_hEvent.m_hTimer = CreateDataTimer(m_hEvent.m_fTime, EventTimer, m_hTimerdata, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					m_hTimerdata.WriteCell(client); // Pass through our client so we can get our contract.
					m_hTimerdata.WriteCell(hObjective.m_iInternalID); // Pass through our internal ID so we know which objective to look for.
					m_hTimerdata.WriteCell(i); // Pass through the current event index so we know which event we're looking for in our objective.
					// ^^ The reason we do these two things as we can't pass enum structs through into a DataPack.
					
				}
			}
			
			// Have we met this events threshold? If not, return.
			if (m_hEvent.m_iCurrentThreshold >= m_hEvent.m_iThreshold)
			{
				// What type of value are we? Are we incrementing or resetting?
				if (StrEqual(m_hEvent.m_sEventType, "increment"))
				{
					// Add to our event progress.
					hObjective.m_iProgress += m_hEvent.m_iAward;
					
					// Clamp.
					hObjective.m_iProgress = Int_Min(hObjective.m_iProgress, hObjective.m_iMaxProgress);
					
					// Reset our threshold.
					m_hEvent.m_iCurrentThreshold = 0;
					
					// Print that this objective is complete.
					if (hObjective.IsObjectiveComplete())
					{
						// Print to HUD that we've completed this event.
						PrintHintText(client, "Objective Completed: %s (%s)", 
						hObjective.m_sDescription, m_hContracts[client].m_sContractName);
					}
					else
					{
						// If we have any exclusive text for this event that we've triggered, then display it.
						char sDescriptionText[128];
						if (!StrEqual(m_hEvent.m_sExclusiveDescription, "")) sDescriptionText = m_hEvent.m_sExclusiveDescription;
						else sDescriptionText = hObjective.m_sDescription;
						
						// Print to HUD that we've triggered this event.
						PrintHintText(client, "[%d/%d] %s (%s) +%dCP", 
						hObjective.m_iProgress, hObjective.m_iMaxProgress, sDescriptionText,
						m_hContracts[client].m_sContractName, m_hEvent.m_iAward);
					}
				}
				else if (StrEqual(m_hEvent.m_sEventType, "reset"))
				{
					// Reset all of the events' threshold.
					for (int h = 0; h < hObjective.m_hEvents.Length; h++)
					{
						ContractObjectiveEvent m_hEventToReset;
						hObjective.m_hEvents.GetArray(h, m_hEventToReset);
						m_hEventToReset.m_iCurrentThreshold = 0;
						hObjective.m_hEvents.SetArray(h, m_hEventToReset);
					}
				}
				
				// Cancel our timer now that we've reached our threshold.
				if (m_hEvent.m_hTimer != INVALID_HANDLE)
				{
					CloseHandle(m_hEvent.m_hTimer);
					m_hEvent.m_hTimer = INVALID_HANDLE;
				}
			}
		}
		
		hObjective.m_hEvents.SetArray(i, m_hEvent);
	}

	// Is our contract now complete?
	if (m_hContracts[client].IsContractComplete())
	{
		// Print to chat.
			MC_PrintToChat(client,
		"{creators}>>{default} Congratulations! You have completed the contract: {lightgreen}\"%s\"{default}.",
		m_hContracts[client].m_sContractName);
	}
}

// Function for event timers.
public Action EventTimer(Handle hTimer, DataPack hPack)
{
	// Set to the beginning and unpack it.
	hPack.Reset();
	// Grab our client.
	int client = hPack.ReadCell();
	int iObjectiveID = hPack.ReadCell();
	int iEventID = hPack.ReadCell();
	
	// Get our contracts.
	Contract hContract;
	hContract = m_hContracts[client];
	
	// Grab our objective.
	ContractObjective hObjective;
	switch (iObjectiveID)
	{
		case 1: hObjective = hContract.m_hPrimaryObjective; 
		case 2: hObjective = hContract.m_hSecondObjective; 
		case 3: hObjective = hContract.m_hThirdObjective; 
	}
	
	// Grab our event.
	ContractObjectiveEvent hEvent;
	hObjective.m_hEvents.GetArray(iEventID, hEvent, sizeof(ContractObjectiveEvent));
	
	// Add to our loops.
	hEvent.m_iCurrentLoops++;
	
	// Call an event for when this loop of the timer ends.
	TriggerTimeEvent(hObjective, hEvent, "OnTimerEnd");
	
	// Are we at the maximum of our loops?
	if (hEvent.m_iCurrentLoops >= hEvent.m_iMaxLoops)
	{
		// Reset our variables.
		hEvent.m_iCurrentLoops = 0;
		hEvent.m_iCurrentThreshold = 0;
		hEvent.m_hTimer = INVALID_HANDLE;
		hObjective.m_hEvents.SetArray(iEventID, hEvent, sizeof(ContractObjectiveEvent));
		// Exit out of the timer.
		return Plugin_Stop;
	}
	hObjective.m_hEvents.SetArray(iEventID, hEvent, sizeof(ContractObjectiveEvent));
	return Plugin_Continue;
}

// Calls a contracker event and changes data for the clients contract.
public void CallContrackerEvent(int client, const char[] event, int value)
{
	// Are we a bot?
	if (client <= 0 || IsFakeClient(client)) return;
	
	// Do we have a contract currently active?
	if (m_hContracts[client].m_sUUID[0] != '{') return;
	
	// Try to increment all of our objectives.
	TryIncrementObjectiveProgress(m_hContracts[client].m_hPrimaryObjective, client, event, value);
	TryIncrementObjectiveProgress(m_hContracts[client].m_hSecondObjective, client, event, value);
	TryIncrementObjectiveProgress(m_hContracts[client].m_hThirdObjective, client, event, value);

}

// ============ MENU FUNCTIONS ============
static Menu gContractMenu;

public void CreateContractMenu()
{
	// Delete our menu if it exists.
	delete gContractMenu;
	
	gContractMenu = new Menu(ContractMenuHandler, MENU_ACTIONS_ALL);
	gContractMenu.SetTitle("Creators.TF Contracker");
	
	if (g_Contracts)
	{
		// Loop over all of our directories.
		StringMapSnapshot hKeys = g_Contracts.Snapshot();
		for (int i = 0; i < hKeys.Length; i++)
		{
			// Grab our key.
			char sKey[256];
			hKeys.GetKey(i, sKey, sizeof(sKey));
			
			// For internal naming, we'll add a # to know what we're dealing with in the future.
			char sInternalKey[256];
			sInternalKey = sKey;
			StrCat("#", sizeof(sInternalKey), sInternalKey);
			
			gContractMenu.AddItem(sInternalKey, sKey);
		}
	}
}

// Our menu handler.
public int ContractMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
/*
	switch (action)
	{
		
		// If we're currently doing this Contract, disable the option to select it.
		case MenuAction_DrawItem:
		{
			int style;
			
			// Grab the item name, which is the UUID internally.
			char sContractUUID[64];
			menu.GetItem(param2, sContractUUID, sizeof(sContractUUID), style);
			
			// Are we currently using this contract?
			if (StrEqual(sContractUUID, m_hContracts[param1].m_sUUID))
			{
				// Disable it.
				return ITEMDRAW_DISABLED;
			}
			else
			{
				return style;
			}
			
			return style;
		}
		
		// Select a Contract if we're not doing it.
		case MenuAction_Select:
		{
			// Grab the item name selected, which is the UUID internally.
			/*char sContractUUID[64];
			menu.GetItem(param2, sContractUUID, sizeof(sContractUUID));
			
			// Are we NOT currently using this contract?
			if (!StrEqual(sContractUUID, m_hContracts[param1].m_sUUID))
			{
				// Set our contract.
				ActivateContract(param1, sContractUUID);
			}
		}
	}
	return 0;
	*/
}

public Action OpenContrackerForClient(int client, int args)
{	
	// Grab UUID.
	gContractMenu.Display(client, 30);
	
	return Plugin_Handled;
}

// ============ UTILITY FUNCTIONS ============

stock int Int_Min(int a, int b) { return a < b ? a : b; }