#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <dhooks>
#include <tf2_stocks>
#include <tf_custom_attributes>
#include <tf2utils>

#define PLUGIN_NAME           "[CE Attribute] Autohop"
#define PLUGIN_AUTHOR         "Creators.TF Team - sappho, quality"
#define PLUGIN_DESCRIPTION    "Adds an attribute which allows automatic bhopping"
#define PLUGIN_VERSION        "1.0"
#define PLUGIN_URL            "https//creators.tf"

public void OnMapStart()
{
    PrecacheSound("misc/banana_slip.wav");
    PrecacheSound("player/taunt_bunnyhopper_hop1.wav");
    PrecacheSound("player/taunt_bunnyhopper_hop2.wav");
    PrecacheSound("player/taunt_bunnyhopper_hop3.wav");
    PrecacheSound("player/taunt_bunnyhopper_hop4.wav");
    PrecacheSound("player/taunt_bunnyhopper_hop5.wav");
    PrecacheSound("player/taunt_bunnyhopper_hop6.wav");
    PrecacheSound("player/taunt_bunnyhopper_hop7.wav");
}


int fakejumps[MAXPLAYERS+1];
int perfectjumps[MAXPLAYERS+1] = { -1 , ... };

// THANKS TWIIKUU
public void OnPluginStart()
{
    // https://raw.githubusercontent.com/sapphonie/tf-autohop/dhooks/gamedata/tf-autohop.txt
    // put ^ this file in /tf/addons/sourcemod/gamedata/
    Handle game_config = LoadGameConfigFile("tf-autohop");

    Handle detour_PreventBunnyJumping = DHookCreateFromConf(game_config, "CTFGameMovement::PreventBunnyJumping");
    if (detour_PreventBunnyJumping == INVALID_HANDLE)
    {
        LogMessage("Could not set up detour for CTFGameMovement::PreventBunnyJumping");
    }
    else if (!DHookEnableDetour(detour_PreventBunnyJumping, false, Detour_PreventBunnyJumping))
    {
        LogMessage("Coult not detour CTFGameMovement::PreventBunnyJumping");
    }
}

static MRESReturn Detour_PreventBunnyJumping(Address self)
{
	// We need m_pTFPlayer, aka the entity address of the player currently bunny jumping
	// CTFGameMovement::PlayerSolidMask references m_pTFPlayer directly (twice, actually)
	// so let's grab that offset and convert it to an ent index
	// specific parts of the function:
	//
	//  +F    02C mov     eax, [ebx+ 7A8h]
	//  +39   02C mov     eax, [ebx+ 7A8h]
	//
	Address ptfplayer   = view_as<Address>(0x7A8);
	// entity address
	Address entaddr     = view_as<Address>(LoadFromAddress(self + ptfplayer, NumberType_Int32));
	// actual entity, uses black magic thanks to mr nosoop
	int entidx          = GetEntityFromAddress(entaddr);
	
	if(ClientHasAttribute(entidx))
	{
		//LogMessage("%i %x", entidx, entaddr);
		return MRES_Supercede;
	}
	return MRES_Supercede;
}



public Action OnPlayerRunCmd(
    int client,
    int &buttons,
    int &impulse,
    float vel[3],
    float angles[3],
    int &weapon,
    int &subtype,
    int &cmdnum,
    int &tickcount,
    int &seed,
    int mouse[2]
)
{
    if (IsFakeClient(client) || !IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }


    // if the client doesn't have the boots, don't run the rest of this code
    int boots = GetWeaponWithAttribute(client);
    if (boots == -1)
    {
        return Plugin_Continue;
    }
    
    int nOldButtons     = GetEntProp(client, Prop_Data, "m_nOldButtons");
    int nREALOldButtons = nOldButtons;

    int flags = GetEntityFlags(client);

    // client is on the ground
    if (flags & FL_ONGROUND)
    {
        // they are jumping
        if (buttons & IN_JUMP)
        {
            // last input didn't have a jump - this was a real bhop!
            if (!(nREALOldButtons & IN_JUMP))
            {
                perfectjumps[client]++;
                if (perfectjumps[client] >= 1)
                {
                    //LogMessage("perfect jump %i", perfectjumps[client]);
                    char sndtoplay[64];
                    Format(sndtoplay, sizeof(sndtoplay), "player/taunt_bunnyhopper_hop%i.wav", GetRandomInt(1, 7));
                    EmitSoundToClient(client, sndtoplay, _, _, _, _, 0.5);
                }
            }
            // otherwise, we autobhop for them
            else
            {
                // but only if they havent exceeded the max num of autohops
                if (fakejumps[client] < TF2CustAttr_GetInt(boots, "autohop jumps"))
                {
                    // remove jump and duck from the old buttons netprop to trick the game into letting us bhop
                    nOldButtons &= ~(IN_JUMP | IN_DUCK);
                    SetEntProp(client, Prop_Data, "m_nOldButtons", nOldButtons);
                    // remove duck from our real buttons so that people can duck bhop properly
                    buttons &= ~IN_DUCK;
                    // inc num of plugin-assisted jumps
                    fakejumps[client]++;
                    // Cry about it.
                    // LogMessage("fake jump %i", fakejumps[client]);
                    // don't play a sound unless they bhop at least once
                    if (fakejumps[client] >= 1)
                    {
                        // chromatic scale kind of. don't worry about it
                        int pitch = ( RoundFloat(100 * fakejumps[client] * 0.0833) + 90 );
                        // play pitched banana slip noise to client
                        EmitSoundToClient(client, "misc/banana_slip.wav", _, _, _, _, 0.5, pitch);
                    }
                }
            }
        }
        else
        {
            fakejumps[client] = 0;
            perfectjumps[client] = -1;
        }
    }
    return Plugin_Continue;
}




// FROM NOSOOP'S MEMORY.INC
int GetEntityFromAddress(Address pEntity) {
    static int offs_RefEHandle;
    if (offs_RefEHandle) {
        return LoadEntityHandleFromAddress(pEntity + view_as<Address>(offs_RefEHandle));
    }

    // if we don't have it already, attempt to lookup offset based on SDK information
    // CWorld is derived from CBaseEntity so it should have both offsets
    int offs_angRotation = FindDataMapInfo(0, "m_angRotation"),
            offs_vecViewOffset = FindDataMapInfo(0, "m_vecViewOffset");
    if (offs_angRotation == -1) {
        ThrowError("Could not find offset for ((CBaseEntity) CWorld)::m_angRotation");
    } else if (offs_vecViewOffset == -1) {
        ThrowError("Could not find offset for ((CBaseEntity) CWorld)::m_vecViewOffset");
    } else if ((offs_angRotation + 0x0C) != (offs_vecViewOffset - 0x04)) {
        char game[32];
        GetGameFolderName(game, sizeof(game));
        ThrowError("Could not confirm offset of CBaseEntity::m_RefEHandle "
                ... "(incorrect assumption for game '%s'?)", game);
    }

    // offset seems right, cache it for the next call
    offs_RefEHandle = offs_angRotation + 0x0C;
    return GetEntityFromAddress(pEntity);
}

int LoadEntityHandleFromAddress(Address addr)
{
    return EntRefToEntIndex(LoadFromAddress(addr, NumberType_Int32) | (1 << 31));
}

// ECON STUFF

bool HasAttribute(int weapon)
{
	if(IsValidEntity(weapon))
	{
		//PrintToServer("Has Hop: %i", TF2CustAttr_GetInt(weapon, "autohop"));
		return TF2CustAttr_GetInt(weapon, "autohop") > 0;
	}
	return false;
}

// check if any weapon on the player has the attribute
bool ClientHasAttribute(int client)
{
	for (int i = 0; i <= TFWeaponSlot_Melee; i++)
	{
		int iWeapon = TF2Util_GetPlayerLoadoutEntity(client, i);
		if(iWeapon > 0 && IsValidEntity(iWeapon) && HasAttribute(iWeapon))
		{
			return true;
		}
	}
	return false;
}

int GetWeaponWithAttribute(int client)
{
	for (int i = 0; i <= TFWeaponSlot_Melee; i++)
	{
		int iWeapon = TF2Util_GetPlayerLoadoutEntity(client, i);
		if(iWeapon > 0 && IsValidEntity(iWeapon) && HasAttribute(iWeapon))
		{
			return iWeapon;
		}
	}
	return -1;
}