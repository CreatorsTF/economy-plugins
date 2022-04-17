#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2_stocks>
#include <tf2>
#include <cecon_items>
#include <concolors>

#define BRICKMODEL "models/weapons/c_models/c_brick/c_brick.mdl"


// why in gods name
#define MAXENTITIES 2048
bool bIsBrick[MAXENTITIES + 1];

#define DEFAULT_BRICK_BLEED             4.0
#define DEFAULT_BRICK_BLEED_MIN         3.0
#define DEFAULT_BRICK_BLEED_MAX         8.0
#define DEFAULT_BRICK_BLEED_DIST        550.0
#define DEFAULT_BRICK_BLEED_DIST_MIN    400.0
#define DEFAULT_DAMAGE_BUFF             25.0

public Plugin myinfo =
{
    // lol
    name    = "[Attribute] Brick",
    author  = "IvoryPal",
    version = "1.1"
}

public void OnPluginStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidClient(i))
        {
            OnClientPutInServer(i);
        }
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamage);
}

public void OnMapStart()
{
    PrecacheModel(BRICKMODEL, true);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    // client threw a jar of some sort, hook it
    if (StrEqual(classname, "tf_projectile_jar"))
    {
        if (IsValidEntity(entity) && entity > 0 && entity <= MAXENTITIES)
        {
            SDKHook(entity, SDKHook_SpawnPost, HookJarSpawnPost);
        }
    }
}

void HookJarSpawnPost(int entity)
{
    if (!IsValidEntity(entity) || !entity)
    {
        return;
    }

    // client entity that threw this - this turns to -1 after a frame
    int ownent   = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");

    // if it's not valid ignore (should never happen ????)
    if (!IsValidClient(ownent))
    {
        return;
    }

    // get our weapon
    int weapon = GetPlayerWeaponSlot(ownent, TFWeaponSlot_Secondary);

    // is this a brick or a normal jarate
    if  (CEconItems_GetEntityAttributeBool(weapon, "proj is brick"))
    {
        // it's a brick, yeet the original jarate it's out of bounds and cant splash on anyone
        TeleportEntity(entity, view_as<float>({5000.0, 5000.0, 5000.0}), NULL_VECTOR, NULL_VECTOR);
        // wait a frame to let the entprops initialize on our jarate that we just yeeted to the moon so we can copy them to our brick
        RequestFrame(LetJarateInitAndBrickify, EntIndexToEntRef(entity));
    }

}

void LetJarateInitAndBrickify(int entref)
{
    int entity = EntRefToEntIndex(entref);

    // something has gone wrong
    if (!IsValidEntity(entity) || !entity)
    {
        return;
    }

    // weapon that threw this jaratebricc
    int launcher    = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
    // client who used the above weapon that threw this jaratebricc
    int ownent      = GetEntPropEnt(launcher, Prop_Send, "m_hOwner");

    // team of this jaratebrick
    int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");

    float position[3];
    float velocity[3];
    float rot[3];

    // get position of projectile
    // GetEntPropVector(entity, Prop_Send, "m_vecOrigin", position);
    GetClientEyePosition(ownent, position);

    // get (INIT) velocity of projectile
    GetEntPropVector(entity, Prop_Send, "m_vInitialVelocity", velocity);

    // Get rotation of projectile - "Won't get the angle of the velocity"
    GetEntPropVector(entity, Prop_Send, "m_angRotation", rot);

    // throw from lower than our eyes (but sitll centered)
    position[2] -= 32.0;

    // but increase upward velocity so that it's a lil easier to throw
    velocity[2] += 16.0;

    // increase pitch to try and match how projectiles arc upwards at first
    rot[2] += 45.0;

    // this is so it matches the crosshair a bit better

    // Get our custom speed of this projectile
    float speed = 1.8; //CEconItems_GetEntityAttributeFloat(launcher, "brick speed");

    /*
        DESTROYING THE INITIAL PROJECTILE AND CREATING OUR BRICK
    */

    RemoveEntity(entity);

    // Spawn brick projectile
    int newbrick = CreateEntityByName("tf_projectile_throwable_brick");

    // set its team to ours
    SetEntProp(newbrick, Prop_Send, "m_iTeamNum",               team);

    // assign the owner
    SetEntPropEnt(newbrick, Prop_Send, "m_hOwnerEntity",        ownent);

    // assign the thrower
    SetEntPropEnt(newbrick, Prop_Send, "m_hThrower",            ownent);

    // assign the weapon launching the brick
    SetEntPropEnt(newbrick, Prop_Send, "m_hLauncher",           launcher);
    SetEntPropEnt(newbrick, Prop_Send, "m_hOriginalLauncher",   launcher);

    // Scale our init velocity with speed as a multiplier
    ScaleVector(velocity, speed);

    // Should be using an extension but this should be good enough
    SetEntPropVector(newbrick, Prop_Send, "m_vInitialVelocity", velocity);

    // Spawn that thang!
    DispatchSpawn(newbrick);
    TeleportEntity(newbrick, position, rot, velocity);
    // ActivateEntity(newbrick);

    // TODO TODO TODO: Set the model up properly so that it doesn't use the bread model's hitbox
    // Currently it clips into the ground a bit. Too bad!

    // for some reason this needs to be after we spawn it
    SetEntityModel(newbrick, BRICKMODEL);


    bIsBrick[newbrick] = true;
}

bool IsBrickEntity(int projectile)
{
    char classname[64];
    GetEntityClassname(projectile, classname, sizeof(classname));

    if (StrEqual(classname, "tf_projectile_throwable_brick"))
    {
        return true;
    }

    return false;
}

public Action OnTakeDamage
(
    int client,
    int &attacker,
    int &inflictor,
    float &damage,
    int &damagetype,
    int &weapon,
    float damageForce[3],
    float damagePosition[3]
)
{
    if (bIsBrick[inflictor] && IsBrickEntity(inflictor))
    {
        float distance;
        float bleed;
        float bleedMin;
        float bleedMax;
        float baseDistance;
        float minDist;
        float additionalDamage;
        // Grab the distance between client and attacker.
        float attackerpos[3], vicpos[3];
        GetClientAbsOrigin(attacker, attackerpos);
        GetClientAbsOrigin(client, vicpos);

        // Get our bleed attributes
        distance = (GetVectorDistance(attackerpos, vicpos));

        // If the weapon that dealt this damage wasn't a brick, grab the attackers original brick
        // and get attributes from there.
        if (!CEconItems_GetEntityAttributeBool(weapon, "proj is brick"))
        {
            int brickWeapon = GetPlayerWeaponSlot(attacker, TFWeaponSlot_Secondary);

            // Is this a brick weapon?
            if (IsValidEntity(brickWeapon) && CEconItems_GetEntityAttributeBool(brickWeapon, "proj is brick"))
            {
                bleed            = CEconItems_GetEntityAttributeFloat(brickWeapon, "brick bleed");
                bleedMin         = CEconItems_GetEntityAttributeFloat(brickWeapon, "brick bleed min");
                bleedMax         = CEconItems_GetEntityAttributeFloat(brickWeapon, "brick bleed max");
                baseDistance     = CEconItems_GetEntityAttributeFloat(brickWeapon, "brick bleed dist");
                minDist          = CEconItems_GetEntityAttributeFloat(brickWeapon, "brick bleed dist min");
                additionalDamage = CEconItems_GetEntityAttributeFloat(brickWeapon, "full value damage bonus");
            }
            // This isn't a brick, use placeholder values.
            else
            {
                bleed            = DEFAULT_BRICK_BLEED;
                bleedMin         = DEFAULT_BRICK_BLEED_MIN;
                bleedMax         = DEFAULT_BRICK_BLEED_MAX;
                baseDistance     = DEFAULT_BRICK_BLEED_DIST;
                minDist          = DEFAULT_BRICK_BLEED_DIST_MIN;
                additionalDamage = DEFAULT_DAMAGE_BUFF;
            }
        }
        else
        {
            // This is already a brick, grab it's attributes.
            bleed            = CEconItems_GetEntityAttributeFloat(weapon, "brick bleed");
            bleedMin         = CEconItems_GetEntityAttributeFloat(weapon, "brick bleed min");
            bleedMax         = CEconItems_GetEntityAttributeFloat(weapon, "brick bleed max");
            baseDistance     = CEconItems_GetEntityAttributeFloat(weapon, "brick bleed dist");
            minDist          = CEconItems_GetEntityAttributeFloat(weapon, "brick bleed dist min");
            additionalDamage = CEconItems_GetEntityAttributeFloat(weapon, "full value damage bonus");
        }

        // Add our damage bonus.
        damage += additionalDamage;

        // minimum distance for bleed
        if (distance >= minDist)
        {
            bleed = ClampFloat((distance / baseDistance) * bleed, bleedMin, bleedMax);

            // If we have a valid bleed duration, make the client bleed.
            TF2_MakeBleed(client, attacker, bleed);
        }

        bIsBrick[inflictor] = false;
    }
    return Plugin_Changed;
}

bool IsValidClient(int iClient)
{
    if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
    {
        return false;
    }
    if (IsClientSourceTV(iClient) || IsClientReplay(iClient))
    {
        return false;
    }
    return true;
}

// Self explanatory, just clamps a float value
public float ClampFloat(float val, float min, float max)
{
    return val > max ? max : val < min ? min : val;
}

