#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cecon_items>
#include <morecolors>
#include <clientprefs>

#pragma semicolon 1
#pragma newdecls required

#define CTFHatDesc "Locally toggles Creators.TF custom cosmetic visibility"

#define ctftag "{creators}>>{default} "


bool bShowHats[MAXPLAYERS+1] = false;
Handle ctfHatsCookie;

public Plugin myinfo =
{
    name        = "CreatorsTF Hat Removal",
    author      = "Jaro 'Monkeys' Vanderheijden, steph&",
    description = "Gives players the choice to locally toggle CreatorsTF hat visibility",
    version     = "1.0.0b",
    url         = ""
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_cosmetics",       ToggleCTFHat, CTFHatDesc);
    RegConsoleCmd("sm_noctfhats",       ToggleCTFHat, CTFHatDesc);
    RegConsoleCmd("sm_togglectfhats",   ToggleCTFHat, CTFHatDesc);
    RegConsoleCmd("sm_togglehats",      ToggleCTFHat, CTFHatDesc);
    RegConsoleCmd("sm_ctfhats",         ToggleCTFHat, CTFHatDesc);
    RegConsoleCmd("sm_nohats",          ToggleCTFHat, CTFHatDesc);
    RegConsoleCmd("sm_hats",            ToggleCTFHat, CTFHatDesc);

    ctfHatsCookie = RegClientCookie("CTF_ShowHats", CTFHatDesc, CookieAccess_Protected);

    // loop thru clients
    for (int i = 1; i <= MaxClients; i++)
    {
        if (AreClientCookiesCached(i))
        {
            // run OCCC for lateloading
            OnClientCookiesCached(i);
        }
    }
}

public void OnClientCookiesCached(int client)
{
    char cookievalue[8];
    // get cookie value from db
    GetClientCookie(client, ctfHatsCookie, cookievalue, sizeof(cookievalue));
    // if we dont have a cookie value set it to 0
    if (!cookievalue[0])
    {
        cookievalue = "0";
        // save it
        SetClientCookie(client, ctfHatsCookie, cookievalue);
    }

    // StringToIntToBool essentially, the bang bang double negates it, once to an inverted bool, twice to a proper bool
    bShowHats[client] = !!StringToInt(cookievalue);
}

// when a client runs sm_nohats etc
public Action ToggleCTFHat(int client, int args)
{
    // toggle
    bShowHats[client] = !bShowHats[client];

    char cookievalue[8];
    if (bShowHats[client])
    {
        MC_PrintToChat(client, ctftag ... "Toggled Creators.TF custom cosmetics {green}ON{white}!");
        cookievalue = "1";
    }
    else
    {
        MC_PrintToChat(client, ctftag ... "Toggled Creators.TF custom cosmetics {fullred}OFF{white}! Be warned, this may cause invisible heads or feet for some cosmetics!");
        cookievalue = "0";
    }

    if (!AreClientCookiesCached(client))
    {
        MC_PrintToChat(client, ctftag ... "Your settings will not be saved due to our cookie server being down.");
        return Plugin_Handled;
    }

    // save to cookie
    SetClientCookie(client, ctfHatsCookie, cookievalue);

    return Plugin_Handled;
}

public void OnClientDisconnect(int client)
{
    bShowHats[client] = false;
}

public void CEconItems_OnItemIsEquipped(int client, int entity, CEItem item, const char[] type)
{
    // client equipped a ctf hat, hook it
    if (StrEqual(type, "cosmetic"))
    {
        RequestFrame(HookDelay, EntIndexToEntRef(entity));
    }
}

void HookDelay(int entityref)
{
    // make sure this is real
    int entity = EntRefToEntIndex(entityref);
    if (IsValidEntity(entity))
    {
        SDKHook(entity, SDKHook_SetTransmit, SetTransmitHat);
    }
}

public Action SetTransmitHat(int entity, int client)
{
    if (bShowHats[client])
    {
        return Plugin_Continue;
    }
    return Plugin_Stop;
}
