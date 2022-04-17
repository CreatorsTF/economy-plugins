#pragma semicolon 1
#pragma newdecls required

#define PAYLOAD_STAGE_1_START 0.85
#define PAYLOAD_STAGE_2_START 0.93

#include <sourcemod>
#include <sdktools>
#include "musickits/musickit_schema.sp"

int m_iMusicKit[MAXPLAYERS + 1] = { -1, ... };
int m_iNextEvent[MAXPLAYERS + 1];
int m_iCurrentEvent[MAXPLAYERS + 1];

char m_sActiveSound[MAXPLAYERS + 1][MAX_SOUND_NAME];

bool m_bIsPlaying[MAXPLAYERS + 1];
bool m_bShouldStop[MAXPLAYERS + 1];
bool m_bForceNextEvent[MAXPLAYERS + 1];
bool m_bQueuedSkipped[MAXPLAYERS + 1]; // Ignore queue even if there are more samples there.

Handle m_hTimer[MAXPLAYERS + 1];

int m_iQueueLength[MAXPLAYERS + 1];
int m_iQueuePointer[MAXPLAYERS + 1];
Sample_t m_hQueue[MAXPLAYERS + 1][32];
Sample_t m_hPreSample[MAXPLAYERS + 1];
Sample_t m_hPostSample[MAXPLAYERS + 1];

int m_nPayloadStage = 0;
int m_iRoundTime = 0;

// Menu containing our list of items.  This is initalized once, then items are modified
// depending on which ones the player is browsing at the time.
static Menu s_EquipMenu;

public Plugin myinfo =
{
	name = "[Creators.TF] - Music Kits Handler",
	author = "Creators.TF Team - Originally written by Moonly Days, ported by ZoNiCaL.",
	description = "Creators.TF Economy Music Kits Handler",
	
	// Version will follow the Alpha, Beta, Hamma, Delta, Epsilon naming style
	// to show "how stable" this plugin is through the refactoring process.
	version = "beta-2.01",
	url = "https://creators.tf"
};

#define MVM_DANGER_CHECK_INTERVAL 0.5

public void OnPluginStart()
{
	HookEvent("teamplay_broadcast_audio", teamplay_broadcast_audio, EventHookMode_Pre);
	HookEvent("teamplay_round_start", teamplay_round_start, EventHookMode_Pre);
	HookEvent("teamplay_round_win", teamplay_round_win);
	HookEvent("teamplay_point_captured", teamplay_point_captured);

	CreateTimer(0.5, Timer_EscordProgressUpdate, _, TIMER_REPEAT);
	RegConsoleCmd("sm_music", cSetKit);
	RegConsoleCmd("sm_musickit", cSetKit);
	RegConsoleCmd("sm_m", cSetKit);
	RegConsoleCmd("sm_mk", cSetKit);

	HookEntityOutput("team_round_timer", "On30SecRemain", OnEntityOutput);
	HookEntityOutput("team_round_timer", "On1MinRemain", OnEntityOutput);
	
	g_CustomItems = new ArrayList(sizeof(Soundtrack_t));
	ProcessMusicKitSchema();
	BuildMusicKitEquipMenu();
}


public void OnClientPostAdminCheck(int client)
{
	m_iMusicKit[client] = -1;
	BufferFlush(client);
}

public Action cSetKit(int client, int args)
{
	s_EquipMenu.Display(client, 30);
	return Plugin_Handled;
}

public void ResetMusicKit(int client)
{
	// Grab our music kit.
	Soundtrack_t oldKit;
	GetCustomItemDefinitionByIndex(m_iMusicKit[client], oldKit);
	
	PrintHintText(client, "Music Kit soundtrack removed.");
	m_iMusicKit[client] = -1;
	return;
}

public void MusicKit_SetKit(int client, char[] UUID)
{
	Soundtrack_t hNewKit;
	// Try and grab this new soundtrack.
	if (!GetCustomItemDefinition(UUID, hNewKit)) { ResetMusicKit(client); }
	else 
	{ 
		m_iMusicKit[client] = hNewKit.m_iDefIndex; 
		PrintHintText(client, "Music Kit soundtrack set to: %s.", hNewKit.m_sName);
	}
	
	m_iCurrentEvent[client] = -1;
	m_iNextEvent[client] = -1;
	BufferFlush(client);
}

public Action teamplay_broadcast_audio(Event hEvent, const char[] szName, bool bDontBroadcast)
{
	int iTeam = hEvent.GetInt("team");
	char sOldSound[MAX_SOUND_NAME];
	hEvent.GetString("sound", sOldSound, sizeof(sOldSound));

	bool bWillOverride = false;
	if (StrContains(sOldSound, "YourTeamWon") != -1)bWillOverride = true;
	if (StrContains(sOldSound, "YourTeamLost") != -1)bWillOverride = true;

	if (!bWillOverride)return Plugin_Continue;

	for (int i = 1; i < MaxClients; i++)
	{
		if (!IsClientReady(i))continue;
		if (GetClientTeam(i) != iTeam)continue;

		char sSound[MAX_SOUND_NAME];

		Soundtrack_t hKit;
		if (GetCustomItemDefinitionByIndex(m_iMusicKit[i], hKit))
		{
			if(StrContains(sOldSound, "YourTeamWon") != -1)
			{
				strcopy(sSound, sizeof(sSound), hKit.m_sWinMusic);
			}

			if(StrContains(sOldSound, "YourTeamLost") != -1)
			{
				strcopy(sSound, sizeof(sSound), hKit.m_sLossMusic);
			}
		}

		// FireToClient DOES NOT CLOSE THE HANDLE, so we run event.Cancel() after we're done
		if(StrEqual(sSound, ""))
		{
			hEvent.FireToClient(i);
			// we don't need to close this handle, it's fired by the game, not us
			// hEvent.Cancel();

		} else {
			Event hNewEvent = CreateEvent("teamplay_broadcast_audio");
			if (hNewEvent == null)continue;

			hNewEvent.SetInt("team", iTeam);
			hNewEvent.SetInt("override", 1);
			hNewEvent.SetString("sound", sSound);
			hNewEvent.FireToClient(i);
			// we made this, so let's close it
			hNewEvent.Cancel();
		}
	}

	return Plugin_Handled;
}

public void PlaySoundtrackEvent(int client, const char[] event)
{
	Soundtrack_t hKit;
	if (!GetCustomItemDefinitionByIndex(m_iMusicKit[client], hKit)) return;

	for (int i = 0; i < hKit.m_hEvents.Length; i++)
	{
		Event_t hEvent;
		hKit.m_hEvents.GetArray(i, hEvent, sizeof(hEvent));

		// Check if we need to start an event.
		if(StrEqual(hEvent.m_sStartHook, event))
		{
			// If this event is played only once, we skip this.
			if (hEvent.m_bFireOnce && m_iCurrentEvent[client] == hEvent.m_iID)continue;

			if(m_iCurrentEvent[client] > -1)
			{
				Event_t hOldEvent;
				hKit.m_hEvents.GetArray(m_iCurrentEvent[client], hOldEvent, sizeof(hOldEvent));
				if(hOldEvent.m_iPriority > hEvent.m_iPriority) continue;
			}

			m_iNextEvent[client] = hEvent.m_iID;
			m_bForceNextEvent[client] = hEvent.m_bForceStart;
			m_bShouldStop[client] = false;
			break;
		}

		// Start Sample playing.
		if(StrEqual(hEvent.m_sStopHook, event))
		{
			if(m_bIsPlaying[client] && !m_bShouldStop[client])
			{
				m_bShouldStop[client] = true;
				if(hEvent.m_bForceStop)
				{
					m_bIsPlaying[client] = false;
					m_bQueuedSkipped[client] = true;
					PlayNextSample(client);
				}
			}
		}
	}

	PlayNextSample(client);
}

public void PlayNextSample(int client)
{
	if(m_bForceNextEvent[client])
	{
		// Stop everything if we have Force tag set.
		if(m_hTimer[client] != null)
		{
			KillTimer(m_hTimer[client]);
			m_hTimer[client] = null;
		}
		BufferFlush(client);

		m_bForceNextEvent[client] = false;
		m_bIsPlaying[client] = false;
		m_bShouldStop[client] = false;

	} else {
		// Otherwise, return if we're playing something.
		if (m_bIsPlaying[client])
		{
			return;
		}
	}

	Sample_t hSample;
	GetNextSample(client, hSample);

	if(!StrEqual(hSample.m_sSound, "") || hSample.m_bPreserveSample)
	{
		m_bIsPlaying[client] = true;

		if(!StrEqual(hSample.m_sSound, ""))
		{
			if(!StrEqual(m_sActiveSound[client], ""))
			{
				StopSound(client, SNDCHAN_AUTO, m_sActiveSound[client]);
			}

			strcopy(m_sActiveSound[client], sizeof(m_sActiveSound[]), hSample.m_sSound);
			PrecacheSound(hSample.m_sSound);
			EmitSoundToClient(client, hSample.m_sSound);
		}

		float flInterp = GetClientSoundInterp(client);
		float flDelay = hSample.m_flDuration - flInterp;

		m_hTimer[client] = CreateTimer(flDelay, Timer_PlayNextSample, client);
	}
}

public Action Timer_PlayNextSample(Handle timer, any client)
{
	// Play next sample from here only if this timer is the active one.
	if(m_hTimer[client] == timer)
	{
		m_hTimer[client] = INVALID_HANDLE;
		m_bIsPlaying[client] = false;
		PlayNextSample(client);
	}
}


public float GetClientSoundInterp(int client)
{
	return float(TF2_GetNativePing(client)) / 2000.0;
}

public int TF2_GetNativePing(int client)
{
	return GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iPing", _, client);
}

public void BufferFlush(int client)
{
	m_iQueueLength[client] = 0;
	m_iQueuePointer[client] = 0;
	m_iCurrentEvent[client] = -1;

	strcopy(m_hPreSample[client].m_sSound, sizeof(m_hPreSample[].m_sSound), "");
	strcopy(m_hPostSample[client].m_sSound, sizeof(m_hPostSample[].m_sSound), "");
}

public void GetNextSample(int client, Sample_t hSample)
{
	// Make sure client exists.
	if (!IsClientValid(client))return;
	
	// Grab client kit.
	Soundtrack_t hKit;
	GetCustomItemDefinitionByIndex(m_iMusicKit[client], hKit);

	// First, we check if we need to switch to next sample.
	// We only do that if post and pre are not set and queue is empty.
	if(m_bShouldStop[client])
	{
		if(StrEqual(m_hPostSample[client].m_sSound, ""))
		{
			BufferFlush(client);
			m_bShouldStop[client] = false;
		} else {
			hSample = m_hPostSample[client];
			strcopy(m_hPostSample[client].m_sSound, MAX_SOUND_NAME, "");
			return;
		}
	}

	if(m_iNextEvent[client] > -1)
	{
		bool bSkipPost = false;

		Event_t CurrentEvent;
		if(hKit.m_hEvents.GetArray(m_iNextEvent[client], CurrentEvent, sizeof(CurrentEvent)))
		{
			bSkipPost = CurrentEvent.m_bSkipPost;
		}

		if(StrEqual(m_hPostSample[client].m_sSound, "") || bSkipPost)
		{
			BufferLoadEvent(client, m_iNextEvent[client]);
			m_iNextEvent[client] = -1;
		} else {
			hSample = m_hPostSample[client];
			strcopy(m_hPostSample[client].m_sSound, MAX_SOUND_NAME, "");
			return;
		}
	}

	if(!StrEqual(m_hPreSample[client].m_sSound, ""))
	{
		hSample = m_hPreSample[client];
		strcopy(m_hPreSample[client].m_sSound, MAX_SOUND_NAME, "");
		return;
	}

	int iPointer = m_iQueuePointer[client];

	// If we have more things to play in the main queue and queue is not skipped.
	if(m_iQueueLength[client] > iPointer && !m_bQueuedSkipped[client])
	{
		// Get currently active sample.
		Sample_t CurrentSample;
		CurrentSample = m_hQueue[client][iPointer];

		// If we run this sample and amount of iterations has exceeded the max amount,
		// we reset the value and run it again.
		if(CurrentSample.m_nCurrentIteration >= CurrentSample.m_nIterations)
		{
			CurrentSample.m_nCurrentIteration = 0;
		}

		//PrintToConsole(client, "m_hSampleQueue, %d, (%d/%d)", m_iCurrentSample[client], sample.m_nCurrentIteration + 1, sample.m_nIterations);

		// Increase current iteration every time we run through it.
		if(CurrentSample.m_nCurrentIteration < CurrentSample.m_nIterations)
		{
			CurrentSample.m_nCurrentIteration++;
		}

		// Update all changed data in the queue.
		m_hQueue[client][iPointer] = CurrentSample;

		// Move to next sample if we reached our limit.
		if(CurrentSample.m_nCurrentIteration == CurrentSample.m_nIterations)
		{
			if(CurrentSample.m_iMoveToEvent > -1)
			{
				// Check if we need to move to a specific event now.
				m_iNextEvent[client] = CurrentSample.m_iMoveToEvent;
			} else if(CurrentSample.m_nMoveToSample > -1 && CurrentSample.m_nMoveToSample < m_iQueueLength[client])
			{
				// Otherwise check if we need to go to a specific sample.
				// m_iCurrentSample[client] = sample.m_nMoveToSample;
				m_iQueuePointer[client] = CurrentSample.m_nMoveToSample;
			} else {
				// Otherwise, move to next sample.
				m_iQueuePointer[client]++;
			}
		}

		hSample = CurrentSample;
		return;
	}

	if(!StrEqual(m_hPostSample[client].m_sSound, ""))
	{
		hSample = m_hPostSample[client];
		strcopy(m_hPostSample[client].m_sSound, MAX_SOUND_NAME, "");
		return;
	}

	// If we are at this point - nothing is left to play, so we clean up everything.
	BufferFlush(client);
}

public void BufferLoadEvent(int client, int event)
{
	if (!IsClientValid(client))return;
	m_bQueuedSkipped[client] = false;
	
	// Grab client kit.
	Soundtrack_t hKit;
	GetCustomItemDefinitionByIndex(m_iMusicKit[client], hKit);

	Event_t hEvent;
	if (!hKit.m_hEvents.GetArray(event, hEvent, sizeof(hEvent))) return;
	
	for (int i = 0; i < hEvent.m_hSamples.Length; i++)
	{
		Sample_t hSample;
		hEvent.m_hSamples.GetArray(i, hSample, sizeof(hSample));
		m_hQueue[client][i] = hSample;
	}
	m_iQueueLength[client] = hEvent.m_hSamples.Length;
	m_iQueuePointer[client] = 0;

	// Loading pre and post samples.
	m_hPreSample[client] = hEvent.m_hPreSample;
	m_hPostSample[client] = hEvent.m_hPostSample;
}

public Action teamplay_round_start(Event hEvent, const char[] szName, bool bDontBroadcast)
{
	StopEventsForAll();
	if(!TF2_IsSetup() && !TF2_IsWaitingForPlayers())
	{
		RequestFrame(PlayRoundStartMusic, hEvent);
	}
}

public void PlayRoundStartMusic(any hEvent)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsClientReady(i))
		{
			PlaySoundtrackEvent(i, "OST_ROUND_START");
			
		}
	}
}

public void StopEventsForAll()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientValid(i))continue;
		if(m_bIsPlaying[i])
		{
			// Otherwise, queue a stop.

			// Play null sound to stop current sample.
			StopSound(i, SNDCHAN_AUTO, m_sActiveSound[i]);
			strcopy(m_sActiveSound[i], sizeof(m_sActiveSound[]), "");

			// Stop everything if we have Force tag set.
			if(m_hTimer[i] != null)
			{
				KillTimer(m_hTimer[i]);
				m_hTimer[i] = null;
			}
			BufferFlush(i);

			m_bForceNextEvent[i] = false;
			m_bIsPlaying[i] = false;
			m_bShouldStop[i] = false;
		}
		m_iNextEvent[i] = -1;
	}
}


public Action teamplay_round_win(Event hEvent, const char[] szName, bool bDontBroadcast)
{
	int iWinReason = GetEventInt(hEvent, "winreason");
	if(m_nPayloadStage == 2 && iWinReason == 1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if(IsClientReady(i))
			{
				PlaySoundtrackEvent(i, "OST_PAYLOAD_CLIMAX");
			}
		}
	}
}

// Handle each Payload stage and play the samples accordingly.
public Action Timer_EscordProgressUpdate(Handle timer, any data)
{
	static float flOld = 0.0;
	float flNew = Payload_GetProgress();

	if(flOld != flNew)
	{
		switch(m_nPayloadStage)
		{
			case 0:
			{
				if(flNew >= PAYLOAD_STAGE_1_START)
				{
					for (int i = 1; i <= MaxClients; i++)
					{
						// Play our sample.
						if(IsClientReady(i)) PlaySoundtrackEvent(i, "OST_PAYLOAD_S1_START");
					}
					m_nPayloadStage = 1;
				}
			}
			case 1:
			{
				if(flNew >= PAYLOAD_STAGE_2_START)
				{
					for (int i = 1; i <= MaxClients; i++)
					{
						// Play our sample.
						if(IsClientReady(i)) PlaySoundtrackEvent(i, "OST_PAYLOAD_S2_START");
					}
					m_nPayloadStage = 2;
				}

				if(flNew < PAYLOAD_STAGE_1_START)
				{
					for (int i = 1; i <= MaxClients; i++)
					{
						// Play our sample.
						if(IsClientReady(i)) PlaySoundtrackEvent(i, "OST_PAYLOAD_S1_CANCEL");
					}
					m_nPayloadStage = 0;
				}
			}
			case 2:
			{
				if(flNew < PAYLOAD_STAGE_1_START)
				{
					for (int i = 1; i <= MaxClients; i++)
					{
						// Play our sample.
						if(IsClientReady(i)) PlaySoundtrackEvent(i, "OST_PAYLOAD_S2_CANCEL");
					}
					m_nPayloadStage = 0;
				}
			}
		}
		flOld = flNew;
	}
}

public float Payload_GetProgress()
{
	int iEnt = -1;
	float flProgress = 0.0;
	while((iEnt = FindEntityByClassname(iEnt, "team_train_watcher")) != -1 )
	{
		if (IsValidEntity(iEnt))
		{
			// If cart is of appropriate team.
			float flProgress2 = GetEntPropFloat(iEnt, Prop_Send, "m_flTotalProgress");
			if (flProgress < flProgress2)flProgress = flProgress2;
		}
	}
	return flProgress;
}

// Capturing a point plays a special sample.
public Action teamplay_point_captured(Handle hEvent, const char[] szName, bool bDontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientReady(i))continue;
		PlaySoundtrackEvent(i, "OST_POINT_CAPTURE");
	}
}

public void OnEntityOutput(const char[] output, int caller, int activator, float delay)
{
	if (TF2_IsWaitingForPlayers())return;

	// Round almost over.
	if (strcmp(output, "On30SecRemain") == 0)
	{
		if (TF2_IsSetup())return;

		m_iRoundTime = 29;
		CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

	// Setup
	if (strcmp(output, "On1MinRemain") == 0)
	{
		if (!TF2_IsSetup())return;

		m_iRoundTime = 59;
		CreateTimer(1.0, Timer_Countdown, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_Countdown(Handle timer, any data)
{
	if (m_iRoundTime < 1) return Plugin_Stop;

	// Play a sample with 45 seconds to go in setup.
	if(TF2_IsSetup() && m_iRoundTime == 45)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if(IsClientReady(i))
			{
				PlaySoundtrackEvent(i, "OST_ROUND_SETUP");
			}
		}
	}

	// Play a sample with 20 seconds to go in the round.
	if(!TF2_IsSetup() && m_iRoundTime == 20)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if(IsClientReady(i))
			{
				PlaySoundtrackEvent(i, "OST_ROUND_ALMOST_END");
			}
		}
	}

	m_iRoundTime--;
	return Plugin_Continue;
}

// Use game UI sounds for menus to provide a more TF2-sounding experience
#define SOUND_MENU_BUTTON_CLICK "ui/buttonclick.wav"
#define SOUND_MENU_BUTTON_CLOSE "ui/panel_close.wav"
#define SOUND_MENU_BUTTON_EQUIP "ui/panel_open.wav"

public void BuildMusicKitEquipMenu()
{
	delete s_EquipMenu;
	
	// Start constructing a new menu.
	s_EquipMenu = new Menu(OnMusicKitEquipMenuEvent, MENU_ACTIONS_ALL);
	s_EquipMenu.OptionFlags |= MENUFLAG_NO_SOUND;
	s_EquipMenu.ExitBackButton = true;
	
	s_EquipMenu.AddItem("", "[No custom item]");
	
	// Add our menu options in for our music kits.
	for (int i = 0; i < g_CustomItems.Length; i++)
	{
		// Add in the item.
		Soundtrack_t hKit;
		GetCustomItemDefinitionByIndex(i, hKit);
		
		s_EquipMenu.AddItem(hKit.m_sUUID, hKit.m_sName);
	}
}

// Handles selecting the music kit.
static int OnMusicKitEquipMenuEvent(Menu menu, MenuAction action, int param1, int param2) 
{
	switch (action) 
	{
		case MenuAction_Display: 
		{
			Panel panel = view_as<any>(param2);
			panel.SetTitle("Creators.TF Music Kits");
		}
		
		// Reads the custom item UUID from the menu and sets the item for the player.
		case MenuAction_Select: 
		{
			int client = param1;
			int position = param2;
			
			char UUID[64];
			menu.GetItem(position, UUID, sizeof(UUID));
			
			EmitSoundToClient(client, SOUND_MENU_BUTTON_EQUIP);
			
			// Set our music kit.
			if (UUID[0]) MusicKit_SetKit(client, UUID);
			else ResetMusicKit(client);
		}
		
		// Render the item names and display whether it's equipped or not.
		case MenuAction_DisplayItem: 
		{
			int client = param1;
			int position = param2;
			
			char UUID[64], itemName[128];
			menu.GetItem(position, UUID, sizeof(UUID), _, itemName, sizeof(itemName));

			// Add in the item.
			Soundtrack_t hKit;
			GetCustomItemDefinition(UUID, hKit);
			
			if (m_iMusicKit[client] == hKit.m_iDefIndex && UUID[0])
			{
				Format(itemName, sizeof(itemName), "%s (equipped)", itemName);
				return RedrawMenuItem(itemName);
			}
			return 0;
		}
		
		case MenuAction_Cancel: 
		{
			int client = param1;
			EmitSoundToClient(client, SOUND_MENU_BUTTON_CLOSE);
		}
	}
	return 0;
}


// UTILITY FUNCTIONS.
public bool TF2_IsWaitingForPlayers()
{
	return GameRules_GetProp("m_bInWaitingForPlayers") == 1;
}

public bool TF2_IsSetup()
{
	return GameRules_GetProp("m_bInSetup") == 1;
}

public bool IsClientReady(int client)
{
	if (!IsClientValid(client))return false;
	if (IsFakeClient(client))return false;
	return true;
}

public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}

public int FindTargetBySteamID(const char[] steamid)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i))
		{
			char szAuth[256];
			GetClientAuthId(i, AuthId_SteamID64, szAuth, sizeof(szAuth));
			if (StrEqual(szAuth, steamid))return i;
		}
	}
	return -1;
}

public bool IsEntityValid(int entity)
{
	return entity > 0 && entity < 2049 && IsValidEntity(entity);
}
