#define MAX_ITEM_IDENTIFIER_LENGTH 64
#define MAX_SOUND_NAME 512
#define MAX_EVENT_NAME 32

#include <stocksoup/files>

// Holds a uid to CustomItemDefinition mapping.
ArrayList g_CustomItems;

enum struct Sample_t
{
	char m_sSound[MAX_SOUND_NAME];

	int m_nIterations;
	int m_nCurrentIteration;

	int m_nMoveToSample;
	int m_iMoveToEvent;

	float m_flDuration;
	float m_flVolume;

	bool m_bPreserveSample;
}

enum struct Event_t
{
	char m_sStartHook[128];
	char m_sStopHook[128];

	int m_iID;
    char m_sID[32];

	bool m_bForceStart;
	bool m_bForceStop;

    bool m_bFireOnce;
    bool m_bSkipPost;

    int m_iPriority;

	Sample_t m_hPreSample;
	Sample_t m_hPostSample;

	ArrayList m_hSamples;
	
	void Init()
	{
		this.m_hSamples = new ArrayList(sizeof(Sample_t));
	}
	
	void Destroy()
	{
		delete this.m_hSamples;
	}
}

enum struct Soundtrack_t
{
	int m_iDefIndex;
	char m_sName[128];
	char m_sUUID[64];

	char m_sWinMusic[512];
	char m_sLossMusic[512];

	ArrayList m_hEvents;
	
	void Init()
	{
		this.m_hEvents = new ArrayList(sizeof(Event_t));
	}
	
	void Destroy()
	{
		for (int i = 0; i < this.m_hEvents.Length; i++)
		{
			Event_t needle;
			g_CustomItems.GetArray(i, needle, sizeof(needle));
			needle.Destroy();
		}
		delete this.m_hEvents;
	}
}

bool GetCustomItemDefinition(const char[] uid, Soundtrack_t item) 
{
	for (int i = 0; i < g_CustomItems.Length; i++)
	{
		Soundtrack_t needle;
		g_CustomItems.GetArray(i, needle, sizeof(needle));
		if (StrEqual(uid, needle.m_sUUID))
		{
			item = needle;
			return true;
		}
	}
	return false;
}

bool GetCustomItemDefinitionByIndex(int index, Soundtrack_t item)
{
	// I could just do a plain ArrayList.GetArray() here, but that would throw a nasty error with
	// invald indexes.
	for (int i = 0; i < g_CustomItems.Length; i++)
	{
		Soundtrack_t needle;
		g_CustomItems.GetArray(i, needle, sizeof(needle));
		if (index == needle.m_iDefIndex)
		{
			item = needle;
			return true;
		}
	}
	return false;
}

public KeyValues LoadMusicKitSchema()
{
	KeyValues itemSchema = new KeyValues("Items");
	
	// We'll ditch the single file legacy format and instead load separate music kit files.
	// These will all be loaded and merged together in one single schema.
	char schemaDir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, schemaDir, sizeof(schemaDir), "configs/%s", "creators/musickits");
	
	// Find files within `configs/creators/musickits/` and import them, too
	ArrayList configFiles = GetFilesInDirectoryRecursive(schemaDir);
	for (int i, n = configFiles.Length; i < n; i++)
	{
		// Grab this file from the directory.
		char kitFilePath[PLATFORM_MAX_PATH];
		configFiles.GetString(i, kitFilePath, sizeof(kitFilePath));
		NormalizePathToPOSIX(kitFilePath);
		
		// Skip files in directories named "disabled", much like SourceMod.
		if (StrContains(kitFilePath, "/disabled/") != -1) continue;
		
		// Skip files that are NOT text files (e.g documentation).
		if (StrContains(kitFilePath, ".txt") == -1) continue;
		
		// Import in this config file.
		KeyValues importKV = new KeyValues("MusicKit");
		importKV.ImportFromFile(kitFilePath);
		
		// Try adding it to our overall schema.
		char uid[MAX_ITEM_IDENTIFIER_LENGTH];
		importKV.GotoFirstSubKey(false);
		do 
		{
			// Does this item already exist?
			importKV.GetSectionName(uid, sizeof(uid));
			if (importKV.GetDataType(NULL_STRING) == KvData_None) 
			{
				if (itemSchema.JumpToKey(uid)) 
				{
					LogMessage("Item uid %s already exists in schema, ignoring entry in %s", uid, kitFilePath);
				} 
				else {
					// Import in.
					itemSchema.JumpToKey(uid, true);
					itemSchema.Import(importKV);
				}
				itemSchema.GoBack();
			}
		} while (importKV.GotoNextKey(false));
		
		// Cleanup.
		importKV.GoBack();
		delete importKV;
	}
	delete configFiles;
	return itemSchema;
}

public void CreateMusicKitSample(KeyValues hSampleConf, Sample_t hSample, bool UseSectionName)
{
	// Get the section name as our sound.
	if (UseSectionName)
	{
		hSampleConf.GetSectionName(hSample.m_sSound, sizeof(hSample.m_sSound));
	}
	else
	{
		hSampleConf.GetString("sound", hSample.m_sSound, sizeof(hSample.m_sSound));
	}
	
	
	// Populates our values for our Sample_t object.
	hSample.m_flDuration = hSampleConf.GetFloat("duration");
	hSample.m_flVolume = hSampleConf.GetFloat("volume");

	hSample.m_iMoveToEvent = hSampleConf.GetNum("move_to_event", -1);

	if(!StrEqual(hSample.m_sSound, "")) PrecacheSound(hSample.m_sSound);

	hSample.m_nIterations = hSampleConf.GetNum("iterations", 1);
	hSample.m_nMoveToSample = hSampleConf.GetNum("move_to_sample", -1);
	hSample.m_bPreserveSample = hSampleConf.GetNum("preserve_sample", 0) == 1;
}


public void CreateMusicKitEvent(KeyValues hEventConf, Event_t hEvent)
{
	hEvent.Init();
	
	// Populates our values for our Event_t object.
	hEvent.m_iPriority = hEventConf.GetNum("priority", 0);

	hEvent.m_bFireOnce = hEventConf.GetNum("fire_once") >= 1;
	hEvent.m_bForceStart = hEventConf.GetNum("force_start") >= 1;
	hEvent.m_bForceStop = hEventConf.GetNum("force_stop") >= 1;
	hEvent.m_bSkipPost = hEventConf.GetNum("skip_post") >= 1;

	hEventConf.GetString("start_hook", hEvent.m_sStartHook, sizeof(hEvent.m_sStartHook));
	hEventConf.GetString("stop_hook", hEvent.m_sStopHook, sizeof(hEvent.m_sStopHook));
	
	// Get the section name and set it as our ID.
	hEventConf.GetSectionName(hEvent.m_sID, sizeof(hEvent.m_sID));
	hEvent.m_iID = StringToInt(hEvent.m_sID);

	// Grab our pre sample if it exists.
	if(hEventConf.JumpToKey("pre_sample", false))
	{
		CreateMusicKitSample(hEventConf, hEvent.m_hPreSample, false);
		hEventConf.GoBack();
	}

	// Grab our post sample if it exists.
	if(hEventConf.JumpToKey("post_sample", false))
	{
		CreateMusicKitSample(hEventConf, hEvent.m_hPostSample, false);
		hEventConf.GoBack();
	}

	// Process the rest of our samples.
	if(hEventConf.JumpToKey("samples", false))
	{
		if(hEventConf.GotoFirstSubKey())
		{
			do {
				Sample_t hSample;
				CreateMusicKitSample(hEventConf, hSample, true);
				hEvent.m_hSamples.PushArray(hSample);
			} while (hEventConf.GotoNextKey());
			hEventConf.GoBack();
		}
		hEventConf.GoBack();
	}
}

public void CreateMusicKit(KeyValues hConf, Soundtrack_t hKit)
{
	hKit.Init();
	
	// Grab our unique identifier
	hConf.GetSectionName(hKit.m_sUUID, sizeof(hKit.m_sUUID));
	
	// Start constructing our kit object.
	hConf.GetString("name", hKit.m_sName, sizeof(hKit.m_sName));
	hKit.m_iDefIndex = g_CustomItems.Length;
	
	// Process all of the logic for this kit such as events and samples.
	if(hConf.JumpToKey("logic", false))
	{
		if (hConf.JumpToKey("broadcast", false))
		{
			// Setting Win and Lose music.
			hConf.GetString("win", hKit.m_sWinMusic, sizeof(hKit.m_sWinMusic));
			hConf.GetString("loss", hKit.m_sLossMusic, sizeof(hKit.m_sLossMusic));
			hConf.GoBack();
		}
		
		// Start processing all of our events.
		if(hConf.JumpToKey("events", false))
		{
			if(hConf.GotoFirstSubKey())
			{
				do 
				{
					// Create an event from our logic.
					Event_t hEvent;
					CreateMusicKitEvent(hConf, hEvent);
					hKit.m_hEvents.PushArray(hEvent);
					hEvent.m_iID = hKit.m_hEvents.Length;
					
				} while (hConf.GotoNextKey());
				hConf.GoBack();
			}
			hConf.GoBack();
		}
		hConf.GoBack();
	}

	// Push our final kit.
	g_CustomItems.PushArray(hKit);
}

public void ProcessMusicKitSchema()
{
	KeyValues itemSchema = LoadMusicKitSchema();
	
	// If we already have existing items and we're reloading in a config, clear them
	// and destroy the items.
	if (g_CustomItems) 
	{
		for (int i = 0; i < g_CustomItems.Length; i++)
		{
			Soundtrack_t needle;
			g_CustomItems.GetArray(i, needle, sizeof(needle));
			needle.Destroy();
		}
	}
	
	delete g_CustomItems;
	g_CustomItems = new ArrayList(sizeof(Soundtrack_t));
	
	// Parse our items.
	if (itemSchema.GotoFirstSubKey()) 
	{
		do 
		{
			// Create our item.
			Soundtrack_t hKit;
			CreateMusicKit(itemSchema, hKit);
		} while (itemSchema.GotoNextKey());
		itemSchema.GoBack();
		
		//BuildEquipMenu();
	} 
	else LogError("No custom items available.");
	delete itemSchema;
}