#include <sourcemod>
#include <sdktools_functions>
#include <sdktools_entinput>
#include <sdktools_engine>
#include <sdktools_trace>
#include <halflife>
#include <sdkhooks>

#define PLUGIN_VERSION "1"

#pragma semicolon 1
#pragma newdecls required

ArrayList gChildren[MAXPLAYERS + 1] = null; //Current PArentedEntities for each client
ArrayList gCarrying[MAXPLAYERS + 1] = null; //Entity index cache for quick lookups

int gInfoTargets[MAXPLAYERS + 1]; //info_target entities for each client

enum ParentedEntity {
	PERef,
	PEMeasure,
	PEOriginalCollisionGroup,
	PEOriginalRenderColor[4],
	RenderMode:PEOriginalRenderMode,
	Float:PEOriginalAngles[3],
	Float:PEMaxs[3],
	Float:PEMins[3],
	String:PETargetName[128],
	String:PEClass[128],
}

public Plugin myinfo = 
{
	name = "Pickup mod",
	author = "Jim",
	description = "Na na na na na na na na na Katamari Damacy",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net/"
};

public void OnPluginStart() {
	RegAdminCmd("sm_pickup", Command_Pickup, ADMFLAG_GENERIC);
	RegAdminCmd("sm_drop", Command_Drop, ADMFLAG_GENERIC);
	RegAdminCmd("sm_dropall", Command_DropAll, ADMFLAG_GENERIC);
	RegAdminCmd("sm_put", Command_Put, ADMFLAG_GENERIC);

	//TODO: Command to list carried PArentedEntities

	LoadTranslations("common.phrases");

	HookEvent("teamplay_round_start", OnRoundStart);

	for(int i = 1; i <= MaxClients; i++) {
		gChildren[i] = new ArrayList(view_as<int>(ParentedEntity), 0);
		gCarrying[i] = new ArrayList();
		gInfoTargets[i] = 0;
	}
}

public void OnMapStart() {
	DispatchKeyValue(0, "targetname", "worldspawn");

	FixResupplyCabinets();
}

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
	bool full = event.GetBool("full_reset");

	if(full) {
		OnMapStart();
		
		for(int i = 1; i <= MaxClients; i++) {
			ResetClient(i, true);
		}
	}

	return Plugin_Continue;
}

public void OnPluginEnd() {
	for(int i = 1; i <= MaxClients; i++) {
		ResetClient(i, false);
	}
}

public void OnClientDisconnect(int client) {
	ResetClient(client, false);
}

public void OnEntityDestroyed(int index) {
	for(int i = 1; i <= MaxClients; i++) {
		int carrying = gCarrying[i].FindValue(index);

		if(carrying > -1) {
			ParentedEntity entity[ParentedEntity];

			gChildren[i].GetArray(carrying, entity[0], view_as<int>(ParentedEntity));
			gChildren[i].Erase(carrying);
			gCarrying[i].Erase(carrying);

			ResetEntity(entity);
			PrintToChat(i, "[SM] Entity %s (%s) was destroyed", entity[PETargetName], entity[PEClass]);

			break;
		}
	}
}

public void FixResupplyCabinets() {
	int index = -1;

	while((index = FindEntityByClassname(index, "func_regenerate")) != -1) {
		int cabinet = GetEntPropEnt(index, Prop_Data, "m_hAssociatedModel");
		
		if(cabinet) {
			SetVariantString("!activator");
			AcceptEntityInput(index, "SetParent", cabinet, cabinet);
		}
	}
}

public void ResetClient(int client, bool mapReset) {
	if(IsClientInGame(client) && !mapReset) {
		Command_DropAll(client, 0);
	}

	if(gChildren[client] != null) {
		gChildren[client].Close();
	}

	if(gCarrying[client] != null) {
		gCarrying[client].Close();
	}
	
	if(gInfoTargets[client] && IsValidEntity(gInfoTargets[client]) && !mapReset) {
		AcceptEntityInput(gInfoTargets[client], "Kill");
	}

	gChildren[client] = new ArrayList(view_as<int>(ParentedEntity), 0);
	gCarrying[client] = new ArrayList();
	gInfoTargets[client] = 0;
}

public Action Command_Pickup(int client, int args) {
	float position[3];
	int target = GetClientAimTargetIncludePlayers(client, position);

	if(!gInfoTargets[client]) {
		CreateInfoTarget(client);
	}

	if(target > 0) {
		PickupEntity(target, client);
	} else {
		PrintToChat(client, "[SM] No parentable entities found");
	}

	return Plugin_Handled;
}

public Action Command_Drop(int client, int args) {
	if(!gChildren[client].Length) {
		PrintToChat(client, "[SM] You are not carrying anything");

		return Plugin_Handled;
	}

	int index = (gChildren[client].Length - 1);
	ParentedEntity entity[ParentedEntity];

	gChildren[client].GetArray(index, entity[0], view_as<int>(ParentedEntity));
	gChildren[client].Erase(index);
	gCarrying[client].Erase(index);

	ResetEntity(entity);
	PrintToChat(client, "[SM] Dropped %s (%s). Entity will become solid in 3 seconds.", entity[PETargetName], entity[PEClass]);

	return Plugin_Handled;
}

public Action Command_DropAll(int client, int args) {
	if(!gChildren[client].Length) {
		PrintToChat(client, "[SM] You are not carrying anything");

		return Plugin_Handled;
	}

	for(int i = 0; i < gChildren[client].Length; i++) {
		ParentedEntity entity[ParentedEntity];

		gChildren[client].GetArray(i, entity[0], view_as<int>(ParentedEntity));

		ResetEntity(entity);
		PrintToChat(client, "[SM] Dropped %s (%s). Entity will become solid in 3 seconds.", entity[PETargetName], entity[PEClass]);
	}

	gChildren[client].Clear();
	gCarrying[client].Clear();

	return Plugin_Handled;
}

public Action Command_Put(int client, int args) {
	if(!gChildren[client].Length) {
		PrintToChat(client, "[SM] You are not carrying anything");

		return Plugin_Handled;
	}

	int index = (gChildren[client].Length - 1);
	float position[3];
	ParentedEntity entity[ParentedEntity];

	gChildren[client].GetArray(index, entity[0], view_as<int>(ParentedEntity));
	gChildren[client].Erase(index);
	gCarrying[client].Erase(index);
	
	if(GetClientAimTargetEx(client, position) >= 0) {
		DataPack data = new DataPack();

		data.WriteCell(entity[PERef]);
		data.WriteCell(client);

		data.WriteFloat(entity[PEMins][0]);
		data.WriteFloat(entity[PEMins][1]);
		data.WriteFloat(entity[PEMins][2]);

		ResetEntity(entity);
		RequestFrame(PutEntity, data);
		PrintToChat(client, "[SM] Placed %s (%s). Entity will become solid in 3 seconds.", entity[PETargetName], entity[PEClass]);
	}

	return Plugin_Handled;
}

public void PickupEntity(int target, int client) {
	char clientTargetName[128];

	ParentedEntity entity[ParentedEntity];

	SaveEntityState(target, entity);

	SetEntProp(target, Prop_Send, "m_CollisionGroup", 2);

	if(HasEntProp(target, Prop_Send, "m_hBuilder") && GetEntPropEnt(target, Prop_Send, "m_hBuilder") == client) {
		PrintToChat(client, "here");
		SetEntProp(target, Prop_Send, "m_nSolidType", 0);
	}

	entity[PERef] = EntIndexToEntRef(target);
	entity[PEMeasure] = CreateMeasure();

	gChildren[client].PushArray(entity[0], view_as<int>(ParentedEntity));
	gCarrying[client].Push(target);

	Format(clientTargetName, sizeof(clientTargetName), "client-%d", client);

	DispatchKeyValue(entity[PEMeasure], "MeasureTarget", clientTargetName);
	DispatchKeyValue(entity[PEMeasure], "Target", entity[PETargetName]);

	DispatchSpawn(entity[PEMeasure]);
	ActivateEntity(entity[PEMeasure]);
	AcceptEntityInput(entity[PEMeasure], "Enable");

	PrintToChat(client, "[SM] You picked up %s (%s)", entity[PETargetName], entity[PEClass]);
}

public void PutEntity(DataPack data) {
	ResetPack(data);

	float mins[3];
	float position[3];
	int entity = data.ReadCell();
	int client = data.ReadCell();

	mins[0] = data.ReadFloat();
	mins[1] = data.ReadFloat();
	mins[2] = data.ReadFloat();

	//TODO: Fix entities being placed underground (mins/maxs?)
	//TODO: Allow placing of entities on top of other targeted entities?
	//TODO: Allow passing entities to other players?	

	if(GetClientAimTargetEx(client, position) >= 0) {
		SubtractVectors(position, mins, position);
		TeleportEntity(entity, position, NULL_VECTOR, NULL_VECTOR);
	}
}

public void SaveEntityState(int target, ParentedEntity state[ParentedEntity]) {
	float angles[3],
		  maxs[3],
		  mins[3];

	GetEntPropString(target, Prop_Data, "m_iName", state[PETargetName], sizeof(state[PETargetName]));
	GetEntityClassname(target, state[PEClass], sizeof(state[PEClass]));

	if(!strlen(state[PETargetName])) {
		Format(state[PETargetName], sizeof(state[PETargetName]), "tempname-%d", RoundFloat(GetEngineTime() * 1000));
		DispatchKeyValue(target, "targetname", state[PETargetName]);
	}

	if(HasEntProp(target, Prop_Send, "m_vecAngles")) {
		GetEntPropVector(target, Prop_Send, "m_vecAngles", angles);
	}

	if(HasEntProp(target, Prop_Data, "m_angRotation")) {
		GetEntPropVector(target, Prop_Data, "m_angRotation", angles);
	}

	GetEntPropVector(target, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(target, Prop_Send, "m_vecMaxs", maxs);

	state[PEOriginalAngles][0] = angles[0];
	state[PEOriginalAngles][1] = angles[1];
	state[PEOriginalAngles][2] = angles[2];

	state[PEMaxs][0] = maxs[0];
	state[PEMaxs][1] = maxs[1];
	state[PEMaxs][2] = maxs[2];

	state[PEMins][0] = mins[0];
	state[PEMins][1] = mins[1];
	state[PEMins][2] = mins[2];

	GetEntityRenderColor(target, state[PEOriginalRenderColor][0], state[PEOriginalRenderColor][1], state[PEOriginalRenderColor][2], state[PEOriginalRenderColor][3]);
	state[PEOriginalRenderMode] = GetEntityRenderMode(target);

	state[PEOriginalCollisionGroup] = GetEntProp(target, Prop_Send, "m_CollisionGroup");
}

public void ResetEntity(ParentedEntity entity[ParentedEntity]) {
	float angles[3];
	int index = EntRefToEntIndex(entity[PERef]);

	if(IsValidEntity(entity[PEMeasure])) {
		AcceptEntityInput(entity[PEMeasure], "Disable");
		AcceptEntityInput(entity[PEMeasure], "Kill");
	} else {
		LogMessage("Invalid measure entity");
	}

	if(index == INVALID_ENT_REFERENCE) {
		LogMessage("Invalid child entity");
		return;
	}

	angles[0] = entity[PEOriginalAngles][0];
	angles[1] = entity[PEOriginalAngles][1];
	angles[2] = entity[PEOriginalAngles][2];

	TeleportEntity(index, NULL_VECTOR, angles, NULL_VECTOR);
	SetEntityRenderColor(index, entity[PEOriginalRenderColor][0], entity[PEOriginalRenderColor][1], entity[PEOriginalRenderColor][2], entity[PEOriginalRenderColor][3] / 2);
	SetEntityRenderMode(index, RENDER_TRANSALPHA);

	DataPack data = new DataPack();

	data.WriteCell(entity[PERef]);
	data.WriteCell(entity[PEOriginalCollisionGroup]);
	data.WriteCell(entity[PEOriginalRenderColor][0]);
	data.WriteCell(entity[PEOriginalRenderColor][1]);
	data.WriteCell(entity[PEOriginalRenderColor][2]);
	data.WriteCell(entity[PEOriginalRenderColor][3]);
	data.WriteCell(entity[PEOriginalRenderMode]);
	
	CreateTimer(3.0, ResetCollision, data);
}

public Action ResetCollision(Handle timer, DataPack data) {
	data.Reset();

	int entity = EntRefToEntIndex(data.ReadCell()),
		collisionGroup = data.ReadCell(),
		r = data.ReadCell(),
		g = data.ReadCell(),
		b = data.ReadCell(),
		a = data.ReadCell();

	RenderMode renderMode = data.ReadCell();

	if(entity != INVALID_ENT_REFERENCE) {
		SetEntProp(entity, Prop_Send, "m_CollisionGroup", collisionGroup);

		//FIXME: Own buildings have no collision after dropping

		SetEntityRenderColor(entity, r, g, b, a);
		SetEntityRenderMode(entity, renderMode);
	}

	return Plugin_Continue;
}

public int CreateMeasure() {
	int entity = CreateEntityByName("logic_measure_movement");

	DispatchKeyValue(entity, "MeasureReference", "worldspawn");
	DispatchKeyValue(entity, "TargetReference", "worldspawn");
	DispatchKeyValue(entity, "TargetScale", "1.0");
	DispatchKeyValue(entity, "MeasureType", "1");

	return entity;
}

public void CreateInfoTarget(int client) {
	float position[3];
	float eyes[3];
	float fwd[3];
	float right[3];
	int entity = CreateEntityByName("info_target");

	char name[16];

	Format(name, sizeof(name), "client-%d", client);

	DispatchKeyValue(entity, "targetname", name);
	DispatchSpawn(entity);

	GetClientAbsOrigin(client, position);	
	GetClientEyeAngles(client, eyes);

	GetAngleVectors(eyes, fwd, right, NULL_VECTOR);
	ScaleVector(fwd, -10.0);
	AddVectors(position, fwd, position);
	TeleportEntity(entity, position, eyes, NULL_VECTOR);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client, client);

	SetVariantString("flag");
	AcceptEntityInput(entity, "SetParentAttachment", client, client);

	gInfoTargets[client] = entity;
}


public bool TraceEntityFilterPlayers(int entity, int contentsMask) {
 	return entity >= MAXPLAYERS;
}

public bool TraceEntityFilterSelfAndChildren(int target, int contentsMask, any client) {
 	if(target == client) {
 		return false;
 	}

 	if(gCarrying[client].FindValue(target) > -1) {
 		return false;
 	}

	return true;
}

public int GetClientAimTargetEx(int client, float pos[3]) {
	if(client < 1) {
		return -1;
	}

	float vAngles[3];
	float vOrigin[3];
	
	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);
	
	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, (MASK_ALL & ~MASK_WATER), RayType_Infinite, TraceEntityFilterPlayers);
	
	if(TR_DidHit(trace)) {
		TR_GetEndPosition(pos, trace);
		
		int entity = TR_GetEntityIndex(trace);
		trace.Close();
		
		return entity;
	}
	
	trace.Close();
	
	return -1;
}

public int GetClientAimTargetIncludePlayers(int client, float pos[3]) {
	if(client < 1) {
		return -1;
	}

	float vAngles[3];
	float vOrigin[3];
	
	GetClientEyePosition(client,vOrigin);
	GetClientEyeAngles(client, vAngles);
	
	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, (MASK_ALL & ~MASK_WATER), RayType_Infinite, TraceEntityFilterSelfAndChildren, client);
	
	if(TR_DidHit(trace)) {
		TR_GetEndPosition(pos, trace);
		
		int entity = TR_GetEntityIndex(trace);
		trace.Close();
		
		return entity;
	}
	
	trace.Close();
	
	return -1;
}
