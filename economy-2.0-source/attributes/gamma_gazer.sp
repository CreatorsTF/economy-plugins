#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <tf_custom_attributes>

public Plugin myinfo =
{
	name = "Gamma Gazer Attributes",
	author = "Creators.TF Team",
	description = "Adds the weapon removes sappers attributes for the Gamma Gazer.",
	version = "2.00",
	url = "https://creators.tf"
};

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "obj_attachment_sapper"))
	{
    	SDKHook(entity, SDKHook_Spawn, OnEntitySpawned);
	}
}

public Action OnEntitySpawned(int entity)
{
    SDKHook(entity, SDKHook_OnTakeDamage, SapperDamage);
}

public Action SapperDamage(int building, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (IsClientValid(attacker) && IsPlayerAlive(attacker))
	{
		int iWeapon = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
		if (IsValidEntity(iWeapon))
		{
			float flDamage = TF2CustAttr_GetFloat(iWeapon, "fixed damage against sappers");
			
			// This wasn't implemented in the Gamma Gazer as of 21/12/21, so I'm going to disable it.
			int iMetalRequired = 0; // CEconItems_GetEntityAttributeInteger(iWeapon, "metal for sapper removal");
			int iMetal = GetEntProp(attacker, Prop_Data, "m_iAmmo", 4, 3);

			if(flDamage > 0.0)
			{
				if(iMetal >= iMetalRequired || iMetalRequired == 0)
				{
					damage = flDamage;
					if(iMetalRequired > 0)
					{
						SetEntProp(attacker, Prop_Data, "m_iAmmo", iMetal - iMetalRequired, 4, 3);
					}

					return Plugin_Changed;
				} else {
					damage = 0.0;
					return Plugin_Handled;
				}
			}
		}
	}
	return Plugin_Changed;
}


public bool IsClientValid(int client)
{
	if (client <= 0 || client > MaxClients)return false;
	if (!IsClientInGame(client))return false;
	if (!IsClientAuthorized(client))return false;
	return true;
}
