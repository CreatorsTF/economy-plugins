#define MAX_UUID_SIZE 64
#define MAX_CONTRACT_NAME_SIZE 64

#define MAX_SECONDARY_OBJECTIVES 2
#define MAX_OBJECTIVE_DESC_SIZE 128

#define MAX_EVENT_SIZE 64

#define REQUIRED_FILE_EXTENSION ".txt"

#include <stocksoup/files>

// Timer events for ContractObjectiveEvent timers.
enum struct TimerEvent
{
	char m_sEventName[MAX_EVENT_SIZE];
	char m_sAction[MAX_EVENT_SIZE];
	int m_iVariable;
}

// Contract objective events.
enum struct ContractObjectiveEvent
{
	// Name of the event trigger.
	char m_sEventName[MAX_EVENT_SIZE];
	
	// If this event gets triggered and is apart of a special condition, trigger some different text.
	char m_sExclusiveDescription[MAX_OBJECTIVE_DESC_SIZE];

	// Threshold for how many times this event should called before giving an award.
	int m_iThreshold;
	int m_iCurrentThreshold;
	
	// Type of event.
	char m_sEventType[16];
	
	// How many points should be awarded when this event is trigged (if type increment).
	int m_iAward;
	
	// Timers for completing an event again in X time.
	Handle m_hTimer;
	
	// The starting time for the timer.
	float m_fTime;
	
	// The maximum amount of loops.
	int m_iMaxLoops;
	
	// How many times we've looped.
	int m_iCurrentLoops;
	
	// The events that get triggered on certain timer events.
	ArrayList m_hTimerEvents;
	
	bool m_bInitalized;
	
	void Initalize()
	{
		this.m_hTimerEvents = new ArrayList(sizeof(TimerEvent));
		this.m_bInitalized = true;
	}
	
	void Destroy()
	{
		if (!this.m_bInitalized || !this.m_hTimerEvents) return;
		delete this.m_hTimerEvents;
		this.m_bInitalized = false;
	}
}

// Contract objectives.
enum struct ContractObjective
{
	int m_iInternalID;
	bool m_bInitalized;
	
	// Description of the objective.
	char m_sDescription[MAX_OBJECTIVE_DESC_SIZE];
	
	// Progress of this objective.
	int m_iMaxProgress;
	int m_iProgress;
	
	// Restrictions for triggering progress.
	char m_sWeaponRestriction[MAX_UUID_SIZE];
	char m_sCosmeticRestriction[MAX_UUID_SIZE];
	char m_sMapRestriction[MAX_UUID_SIZE];
	
	// Our events.
	ArrayList m_hEvents;
	
	void ResetProgress()
	{ 
		this.m_iProgress = 0;
		return;
	}
	
	bool IsObjectiveComplete()
	{
		return this.m_iProgress >= this.m_iMaxProgress;
	}

	void Initalize()
	{
		this.m_hEvents = new ArrayList(sizeof(ContractObjectiveEvent));
		this.m_bInitalized = true;
	}
	
	void Destroy()
	{
		if (!this.m_bInitalized || !this.m_hEvents) return;
		
		// Destroy all of our events.
		for (int i = 0; i < this.m_hEvents.Length; i++)
		{
			ContractObjectiveEvent hEvent;
			this.m_hEvents.GetArray(i, hEvent, sizeof(ContractObjectiveEvent));
			hEvent.Destroy();
		}
		
		delete this.m_hEvents;
		this.m_bInitalized = false;
	}
}

// Struct representing a Contract.
enum struct Contract
{
	// UUID.
	char m_sUUID[MAX_UUID_SIZE];
	
	// Name of the contract.
	char m_sContractName[MAX_CONTRACT_NAME_SIZE];
	
	// Directory path.
	// NOTE: This isn't strictly the raw path as it's parsed; it's a cut down version
	// that removes everything before and including DIRECTORY_SEPARATOR.
	char m_sDirectoryPath[PLATFORM_MAX_PATH]; 
	
	// Boolean value representing what classes can use this contract.
	bool m_bClass[10];
	
	// Contract objectives.
	ContractObjective m_hPrimaryObjective; 	// While named the "primary" objective, it isn't given any special treatment
											// compared to any other objective struct.
	ContractObjective m_hSecondObjective;
	ContractObjective m_hThirdObjective;
	
	bool IsContractComplete()
	{
		if (this.m_hPrimaryObjective.m_bInitalized)  
		{
			if (this.m_hPrimaryObjective.m_iProgress < this.m_hPrimaryObjective.m_iMaxProgress) return false; 
		}
		if (this.m_hSecondObjective.m_bInitalized)  
		{
			if (this.m_hSecondObjective.m_iProgress < this.m_hSecondObjective.m_iMaxProgress) return false; 
		}
		if (this.m_hThirdObjective.m_bInitalized)  
		{
			if (this.m_hThirdObjective.m_iProgress < this.m_hThirdObjective.m_iMaxProgress) return false; 
		}
		return true;
	}
	
	void Destroy()
	{
		this.m_hPrimaryObjective.Destroy();
		this.m_hSecondObjective.Destroy();
		this.m_hThirdObjective.Destroy();
	}
}

StringMap g_Contracts;

public KeyValues LoadContractsSchema()
{
	KeyValues itemSchema = new KeyValues("Items");
	
	// We'll ditch the single file legacy format and instead load separate contract files.
	// These will all be loaded and merged together in one single schema.
	char schemaDir[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, schemaDir, sizeof(schemaDir), "configs/%s", "creators/contracts");
	
	// Find files within `configs/creators/contracts/` and import them, too
	ArrayList configFiles = GetFilesInDirectoryRecursive(schemaDir);
	for (int i, n = configFiles.Length; i < n; i++)
	{
		// Grab this file from the directory.
		char contractFilePath[PLATFORM_MAX_PATH];
		configFiles.GetString(i, contractFilePath, sizeof(contractFilePath));
		NormalizePathToPOSIX(contractFilePath);
		
		// Skip files in directories named "disabled", much like SourceMod.
		if (StrContains(contractFilePath, "/disabled/") != -1) continue;
		
		// Skip files that are NOT text files (e.g documentation).
		if (StrContains(contractFilePath, REQUIRED_FILE_EXTENSION) == -1) continue;
		
		// Import in this config file.
		KeyValues importKV = new KeyValues("Contract");
		importKV.ImportFromFile(contractFilePath);
		
		// Try adding it to our overall schema.
		char uid[MAX_UUID_SIZE];
		importKV.GotoFirstSubKey(false);
		do 
		{
			// Does this item already exist?
			importKV.GetSectionName(uid, sizeof(uid));
			if (importKV.GetDataType(NULL_STRING) == KvData_None) 
			{
				if (itemSchema.JumpToKey(uid)) 
				{
					LogMessage("Item uid %s already exists in schema, ignoring entry in %s", uid, contractFilePath);
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

// Creates a contract event.
public void CreateContractObjectiveEvent(KeyValues hEventConf, ContractObjectiveEvent hEvent)
{
	hEvent.Initalize();
	
	// Our event trigger is the section name.
	hEventConf.GetSectionName(hEvent.m_sEventName, sizeof(hEvent.m_sEventName));
	
	// If we have an exclusive description, grab it here.
	hEventConf.GetString("exclusive_description", hEvent.m_sExclusiveDescription, sizeof(hEvent.m_sExclusiveDescription));
	
	// Grab our event type.
	hEventConf.GetString("type", hEvent.m_sEventType, sizeof(hEvent.m_sEventType), "increment");
	
	// Grab the threshold.
	hEvent.m_iThreshold = hEventConf.GetNum("threshold", 1);
	
	// Grab the award.
	hEvent.m_iAward = hEventConf.GetNum("award", 1);
	
	// If this event has a timer...
	if (hEventConf.JumpToKey("timer", false))
	{
		// Populate our variables.
		hEvent.m_fTime = hEventConf.GetFloat("time");
		hEvent.m_iMaxLoops = hEventConf.GetNum("loop");
		
		// Check if any events exist.
		if (hEventConf.JumpToKey("OnTimerEnd", false))
		{
			TimerEvent hTimer;
			
			// Populate our variables.
			hTimer.m_sEventName = "OnTimerEnd";
			hTimer.m_iVariable = hEventConf.GetNum("variable");
			hEventConf.GetString("event", hTimer.m_sAction, sizeof(hTimer.m_sAction));
			
			// Add to our list.
			hEvent.m_hTimerEvents.PushArray(hTimer, sizeof(TimerEvent));
			
			hEventConf.GoBack();
		}
		hEventConf.GoBack();
	}
}

// Creates a contract objective.
public void CreateContractObjective(KeyValues hObjectiveConf, ContractObjective hObjective)
{
	hObjective.Initalize();
	hObjective.m_bInitalized = true;
	
	// Grab the description.
	hObjectiveConf.GetString("description", hObjective.m_sDescription, sizeof(hObjective.m_sDescription));
	
	// Required progress to complete the objective.
	hObjective.m_iMaxProgress = hObjectiveConf.GetNum("required_progress", 1);

	// Create our events.
	if (hObjectiveConf.JumpToKey("events", false))
	{
		if(hObjectiveConf.GotoFirstSubKey())
		{
			do 
			{
				// Create an event from our logic.
				ContractObjectiveEvent hEvent;
				CreateContractObjectiveEvent(hObjectiveConf, hEvent);
				hObjective.m_hEvents.PushArray(hEvent);
				
			} while (hObjectiveConf.GotoNextKey());
			hObjectiveConf.GoBack();
		}
		hObjectiveConf.GoBack();
	}
	
	hObjectiveConf.GetString("weapon_restriction", hObjective.m_sWeaponRestriction, sizeof(hObjective.m_sWeaponRestriction));
}

// Creates a contract.
public void CreateContract(KeyValues hContractConf, Contract hContract)
{	
	// Grab our UUID from the section name.
	hContractConf.GetSectionName(hContract.m_sUUID, sizeof(hContract.m_sUUID));
	
	// Grab our name.
	hContractConf.GetString("name", hContract.m_sContractName, sizeof(hContract.m_sContractName));
	
	// Create the path of our Contract.
	hContractConf.GetString("directory", hContract.m_sDirectoryPath, sizeof(hContract.m_sDirectoryPath), "undefined");
	
	// Grab the classes that can do this contract.
	if (hContractConf.JumpToKey("classes", false))
	{
		hContract.m_bClass[TFClass_Scout] 		= view_as<bool>(hContractConf.GetNum("scout", 0));
		hContract.m_bClass[TFClass_Soldier] 	= view_as<bool>(hContractConf.GetNum("soldier", 0));
		hContract.m_bClass[TFClass_Pyro] 		= view_as<bool>(hContractConf.GetNum("pyro", 0));
		hContract.m_bClass[TFClass_DemoMan] 	= view_as<bool>(hContractConf.GetNum("demoman", 0));
		hContract.m_bClass[TFClass_Heavy]		= view_as<bool>(hContractConf.GetNum("heavy", 0));
		hContract.m_bClass[TFClass_Engineer] 	= view_as<bool>(hContractConf.GetNum("engineer", 0));
		hContract.m_bClass[TFClass_Sniper] 		= view_as<bool>(hContractConf.GetNum("sniper", 0));
		hContract.m_bClass[TFClass_Medic] 		= view_as<bool>(hContractConf.GetNum("medic", 0));
		hContract.m_bClass[TFClass_Spy] 		= view_as<bool>(hContractConf.GetNum("spy", 0));
		
		// Return.
		hContractConf.GoBack();
	}
	
	// NOTE: Now you might be asking: ZoNiCaL, why are we only limited to three objectives in this fashion?
	// Well to tell you the truth, nobody went above three objectives in Contracker 1.0, I don't think going over
	// two secondary objectives in the old econ would work at all. So I'm placing this restriction because it makes
	// the most sense to me. It's also easier to visualize in schema files.
	
	// Set the primary objective for this Contract.
	if (hContractConf.JumpToKey("objectives", false))
	{
		if(hContractConf.GotoFirstSubKey())
		{
			do 
			{
				char sID[4];
				hContractConf.GetSectionName(sID, sizeof(sID));
				
				switch (StringToInt(sID))
				{
					case 1:	// First objective.
					{
						hContract.m_hPrimaryObjective.m_iInternalID = 1;
						CreateContractObjective(hContractConf, hContract.m_hPrimaryObjective);
					}
					case 2: // Second objective.
					{
						hContract.m_hSecondObjective.m_iInternalID = 2;
						CreateContractObjective(hContractConf, hContract.m_hSecondObjective);
					}
					case 3: // Third objective.
					{
						hContract.m_hThirdObjective.m_iInternalID = 3;
						CreateContractObjective(hContractConf, hContract.m_hThirdObjective);
					}
				}		
			} while (hContractConf.GotoNextKey());
		}
		hContractConf.GoBack();
	}
	
	// Do we already have contracts in this directory path?
	StringMap hDirectoryOfContracts;
	if (!g_Contracts.GetValue(hContract.m_sDirectoryPath, hDirectoryOfContracts))
	{
		// Create a new ArrayList.
		hDirectoryOfContracts = new StringMap();
	}
	
	// Insert this Contract into our ArrayList and put it into the StringMap.
	hDirectoryOfContracts.SetArray(hContract.m_sUUID, hContract, sizeof(Contract));
	PrintToServer("Created Contract %s in directory: %s", hContract.m_sUUID, hContract.m_sDirectoryPath);
	g_Contracts.SetValue(hContract.m_sDirectoryPath, hDirectoryOfContracts);
	
	hContractConf.GoBack();
}

public void CleanDirectory(StringMap hDirectory)
{
	// Grab a snapshot of the keys from this directory and iterate.
	StringMapSnapshot hKeys = hDirectory.Snapshot();
	for (int i = 0; i < hKeys.Length; i++)
	{
		// Grab our key.
		char sKey[256];
		hKeys.GetKey(i, sKey, sizeof(sKey));
				
		// We now have a "thing" - it can either be contracts or further directories.
		// Contracts should have a key associated with them that matches their UUID "{...}" so we can
		// easily tell them apart and do operations on.
		
		// This function handles the actual cleaning, and can be called recursively if needed.
		
		// If this is a contract, clean the Contract.
		if (sKey[0] == '{') // This is a UUID.
		{
			Contract hContract;
			hDirectory.GetArray(sKey, hContract, sizeof(Contract));
			
			// Cleanup.
			hContract.Destroy();
			hDirectory.Remove(sKey);
		}
		// This is another directory, clean it.
		else
		{
			StringMap hNewDirectory;
			hDirectory.GetValue(sKey, hNewDirectory);
			CleanDirectory(hNewDirectory);
		}
	}
	
	// This directory should be fully clean now. Clear it.
	hDirectory.Clear();
}

public void CleanContrackerDirectories()
{
	if (g_Contracts)
	{
		// Loop over all of our keys and clean up our ArrayLists.
		StringMapSnapshot hKeys = g_Contracts.Snapshot();
		for (int i = 0; i < hKeys.Length; i++)
		{
			// Grab our key.
			char sKey[256];
			hKeys.GetKey(i, sKey, sizeof(sKey));
			
			// Grab our directories here.
			StringMap hDirectory;
			g_Contracts.GetValue(sKey, hDirectory);
				
			// We now have a directory of "things" - they can either be contracts or further directories.
			// Contracts should have a key associated with them that matches their UUID "{...}" so we can
			// easily tell them apart and do operations on.
			
			// This function handles the actual cleaning, and can be called recursively if needed.
			CleanDirectory(hDirectory);
		}
		
		// At this point, all of our Contract's *should* be cleaned up.
		g_Contracts.Clear();
		
		// Cleanup.
		delete hKeys;
	}
	delete g_Contracts;
}

public void ProcessContractsSchema()
{
	KeyValues itemSchema = LoadContractsSchema();
	
	// If we already have existing items and we're reloading in a config, clear them
	// and destroy the items.
	CleanContrackerDirectories();
	
	g_Contracts = new StringMap();
	
	// Parse our items.
	if (itemSchema.GotoFirstSubKey()) 
	{
		do 
		{
			// Create our item.
			Contract hContract;
			CreateContract(itemSchema, hContract);
		} while (itemSchema.GotoNextKey());
		itemSchema.GoBack();
		
		//BuildEquipMenu();
	} 
	else LogError("No custom items available.");
	delete itemSchema;
	
	PrintToServer("[CONTRACTS] Initalized Contracker.");
}

bool GetCustomItemDefinition(const char[] uid, Contract item) 
{
	if (g_Contracts)
	{
		// Loop over all of our directories.
		StringMapSnapshot hKeys = g_Contracts.Snapshot();
		for (int i = 0; i < hKeys.Length; i++)
		{
			// Grab our key.
			char sKey[256];
			hKeys.GetKey(i, sKey, sizeof(sKey));
			
			// Grab our ArrayList from the global list.
			ArrayList hDirectoryOfContracts;
			g_Contracts.GetValue(sKey, hDirectoryOfContracts);
			
			// Loop over our ArrayList and clean up all of the Contracts.
			for (int j = 0; j < hDirectoryOfContracts.Length; j++)
			{
				// Grab our Contract.
				Contract hContract;
				hDirectoryOfContracts.GetArray(j, hContract, sizeof(Contract));
				
				// Are the UUID's equal? If so - return this.
				if (StrEqual(uid, hContract.m_sUUID))
				{
					item = hContract;
					return true;
				}
			}
		}
		// Cleanup.
		delete hKeys;
	}
	return false;
}

/*bool GetCustomItemDefinitionByIndex(int index, Contract item)
{
	// I could just do a plain ArrayList.GetArray() here, but that would throw a nasty error with
	// invald indexes.
	for (int i = 0; i < g_CustomItems.Length; i++)
	{
		Contract needle;
		g_CustomItems.GetArray(i, needle, sizeof(needle));
		if (index == needle.m_iDefIndex)
		{
			item = needle;
			return true;
		}
	}
	return false;
}*/