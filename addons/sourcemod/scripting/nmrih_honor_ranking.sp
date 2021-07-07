#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <autoexecconfig>
#include <dbi>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_AUTHOR "Ulreth*"
#define PLUGIN_VERSION "1.0.0" // 1-07-2020
#define PLUGIN_NAME "[NMRiH] Honor Ranking"

// CVARS
ConVar cvar_PluginEnabled;
ConVar cvar_DebugEnabled;
ConVar cvar_TimeShared;
ConVar cvar_MultipleVotes;
// GLOBAL DATABASE VARIABLES
Database g_Database = null;
// PLAYERS DATA
char g_SteamID[10][32];
char g_PlayerName[10][32];
int g_FriendlyCount[10];
int g_CoopCount[10];
int g_LeaderCount[10];
int g_MapFriendlyCount[10];
int g_MapCoopCount[10];
int g_MapLeaderCount[10];
// MATRIX STORING TIME SHARED IN SECONDS
int g_TimeShared[10][10];
int g_VotesDone[10];
// DISPLAY MESSAGES
char g_MenuFriendlyMessages[100][64];
char g_MenuCoopMessages[100][64];
char g_MenuLeaderMessages[100][64];
// MESSAGES VARIABLES
int g_FriendlyRecords = 0;
int g_CoopRecords = 0;
int g_LeaderRecords = 0;

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = "Allows players to give honor once per map extraction to teammates depending on their behaviour.",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/groups/lunreth-laboratory"
};

public void OnPluginStart()
{
	LoadTranslations("nmrih_honor_ranking.phrases");
	AutoExecConfig_SetFile("nmrih_honor_ranking");
	AutoExecConfig_SetCreateFile(true);
	AutoExecConfig_CreateConVar("sm_honor_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NONE);
	cvar_PluginEnabled = AutoExecConfig_CreateConVar("sm_honor_enabled", "1.0", "Enable or disable NMRiH Honor Ranking plugin", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_DebugEnabled = AutoExecConfig_CreateConVar("sm_honor_debug", "0.0", "Will spam messages in console and log about any SQL action", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_TimeShared = AutoExecConfig_CreateConVar("sm_honor_timeshared", "600.0", "Minimum time shared required between players (in seconds) to pop up honor voting menu.", FCVAR_NONE, true, 60.0, true, 3600.0);
	cvar_MultipleVotes = AutoExecConfig_CreateConVar("sm_honor_multiple_votes", "1.0", "Set to 1 if you want players to use all their votes in one single user.", FCVAR_NONE, true, 0.0, true, 1.0);
	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
	
	if (GetConVarFloat(cvar_PluginEnabled) != 1.0) return;
	HookEvent("player_leave", Event_PlayerLeave);
	HookEvent("new_wave", Event_NewWave);
	HookEvent("objective_complete", Event_ObjectiveComplete);
	HookEvent("extraction_begin", Event_ExtractionBegin);
	HookEvent("player_extracted", Event_PlayerExtracted);
	RegConsoleCmd("sm_honor", Menu_Main);
	RegConsoleCmd("sm_lideres", Menu_Main);
	RegConsoleCmd("sm_friendly", Menu_Main);
	RegConsoleCmd("sm_leaders", Menu_Main);
	RegConsoleCmd("sm_veterans", Menu_Main);
	RegConsoleCmd("sm_honorrank", Menu_Main);
	RegConsoleCmd("sm_honorstats", Menu_Main);
	RegConsoleCmd("sm_rankhonor", Menu_Main);
	RegConsoleCmd("sm_statshonor", Menu_Main);
	//
	RegAdminCmd("sm_honor_reset", Command_ResetTable, ADMFLAG_ROOT);
	RegAdminCmd("sm_honor_player_reset", Command_DeletePlayer, ADMFLAG_ROOT);
	//
	Database.Connect(T_Connect, "nmrih_honor");
	CreateTimer(1.0, Timer_Global, _,TIMER_REPEAT);
}

public void T_Connect(Database db, const char[] error, any data)
{
	if(db == null)
	{
		LogError("T_Connect returned invalid Database Handle");
		return;
	}
	g_Database = db;
	char query[512];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS 'players_honor' (steam_id TEXT PRIMARY KEY, player_name TEXT, friendly_count INTEGER, coop_count INTEGER, leader_count INTEGER);");
	db.Query(T_Generic, query);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[Honor Ranking] Successfully connected to database.");
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[Honor Ranking] successfully connected to database.");
}

public void OnClientPostAdminCheck(int client)
{
	if(!IsFakeClient(client))
	{
		g_VotesDone[client] = 0;
		for (int j = 1; j <= MaxClients; j++)
		{
			g_TimeShared[client][j] = 0;
			g_TimeShared[j][client] = 0;
		}
		if(g_Database == null)
		{
			return;
		}
		char escape_steam_id[72];
		GetClientAuthId(client, AuthId_Steam2, g_SteamID[client], sizeof(g_SteamID[]));
		g_Database.Escape(g_SteamID[client], escape_steam_id, sizeof(escape_steam_id));
		// PERSONAL RECORDS QUERY
		char query[512];
		Format(query, sizeof(query), "SELECT * FROM 'players_honor' WHERE steam_id = '%s';", escape_steam_id);
		g_Database.Query(T_LoadPlayer, query, GetClientUserId(client));
	}
}

public void T_LoadPlayer(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadPlayer returned error: %s", error);
		return;
	}
	
	int client = GetClientOfUserId(data);
	if (client == 0)
	{
		return;
	}
	GetClientName(client, g_PlayerName[client], sizeof(g_PlayerName[]));
	GetClientAuthId(client, AuthId_Steam2, g_SteamID[client], sizeof(g_SteamID[]));
	char query[512];
	char escape_player_name[72];
	char escape_steam_id[72];
	db.Escape(g_PlayerName[client], escape_player_name, sizeof(escape_player_name));
	db.Escape(g_SteamID[client], escape_steam_id, sizeof(escape_steam_id));
	// Row found in table
	if(results.FetchRow())
    {
		char DBPlayerName[32];
		results.FetchString(1, DBPlayerName, sizeof(DBPlayerName));
		if (StrEqual(DBPlayerName,g_PlayerName[client]))
		{
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[Honor Ranking] Name of %s matches with DB.", g_PlayerName[client]);
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[Honor Ranking] Name of %s matches with DB.", g_PlayerName[client]);
		}
		else
		{
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[Honor Ranking] Updating name of %s", g_PlayerName[client]);
			if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[Honor Ranking] Updating name of %s", g_PlayerName[client]);
			Format(query, sizeof(query), "UPDATE 'players_honor' SET player_name = '%s' WHERE steam_id = '%s';", escape_player_name, escape_steam_id);
			db.Query(T_Generic, query);
		}
		g_FriendlyCount[client] = results.FetchInt(2);
		g_CoopCount[client] = results.FetchInt(3);
		g_LeaderCount[client] = results.FetchInt(4);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[Honor Ranking] Stats for %s successfully loaded.", g_PlayerName[client]);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[Honor Ranking] Stats for %s successfully loaded.", g_PlayerName[client]);
    }
	else
    {
		// Inserting new data
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[Honor Ranking] %s has no records in DB, creating new row.", g_PlayerName[client]);
		if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[Honor Ranking] %s has no records in DB, creating new row.", g_PlayerName[client]);
		Format(query, sizeof(query), "INSERT INTO 'players_honor' (steam_id, player_name, friendly_count, coop_count, leader_count) VALUES ('%s', '%s', 0, 0, 0);", escape_steam_id, escape_player_name);
		db.Query(T_Generic, query);
    }
	// ALL FRIENDLY PLAYERS QUERY
	char query2[512];
	Format(query2, sizeof(query2), "SELECT player_name, friendly_count FROM 'players_honor' WHERE friendly_count > 0 ORDER BY friendly_count DESC LIMIT 100;");
	g_Database.Query(T_LoadFriendlyPlayers, query2);
}

public void T_LoadFriendlyPlayers(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadFriendlyPlayers returned error: %s", error);
		return;
	}
	g_FriendlyRecords = 0;
	char i_player_name[32];
	while (results.FetchRow())
	{
		results.FetchString(0, i_player_name, sizeof(i_player_name));
		int i_friendly_count = results.FetchInt(1);
		Format(g_MenuFriendlyMessages[g_FriendlyRecords], sizeof(g_MenuFriendlyMessages[]), "%s  --  %d", i_player_name, i_friendly_count);
		g_FriendlyRecords++;
	}
	// ALL COOP PLAYERS QUERY
	char query[512];
	Format(query, sizeof(query), "SELECT player_name, coop_count FROM 'players_honor' WHERE coop_count > 0 ORDER BY coop_count DESC LIMIT 100;");
	g_Database.Query(T_LoadCoopPlayers, query);
}

public void T_LoadCoopPlayers(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadCoopPlayers returned error: %s", error);
		return;
	}
	g_CoopRecords = 0;
	char i_player_name[32];
	while (results.FetchRow())
	{
		results.FetchString(0, i_player_name, sizeof(i_player_name));
		int i_coop_count = results.FetchInt(1);
		Format(g_MenuCoopMessages[g_CoopRecords], sizeof(g_MenuCoopMessages[]), "%s  --  %d", i_player_name, i_coop_count);
		g_CoopRecords++;
	}
	// ALL VETERANS QUERY
	char query[512];
	Format(query, sizeof(query), "SELECT player_name, leader_count FROM 'players_honor' WHERE leader_count > 0 ORDER BY leader_count DESC LIMIT 100;");
	g_Database.Query(T_LoadVeteranPlayers, query);
}

public void T_LoadVeteranPlayers(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_LoadVeteranPlayers returned error: %s", error);
		return;
	}
	g_LeaderRecords = 0;
	char i_player_name[32];
	while (results.FetchRow())
	{
		results.FetchString(0, i_player_name, sizeof(i_player_name));
		int i_leader_count = results.FetchInt(1);
		Format(g_MenuLeaderMessages[g_LeaderRecords], sizeof(g_MenuLeaderMessages[]), "%s  --  %d", i_player_name, i_leader_count);
		g_LeaderRecords++;
	}
}

public Action Menu_Main(int client, int args)
{
	Menu hMenu = new Menu(Callback_Menu_Main, MENU_ACTIONS_ALL);
	char display[128];
	
	Format(display, sizeof(display), "[Honor Ranking] \n Version: %s - Author: Ulreth \n", PLUGIN_VERSION);
	hMenu.SetTitle(display);
	
	//Format(display, sizeof(display), "My Honor Stats");
	Format(display, sizeof(display), "%T", "my_honor_stats", client);
	hMenu.AddItem("my_stats", display, ITEMDRAW_DEFAULT);
	
	//Format(display, sizeof(display), "Online Players");
	Format(display, sizeof(display), "%T", "online_players", client);
	hMenu.AddItem("online_players", display, ITEMDRAW_DEFAULT);
	
	//Format(display, sizeof(display), "Top Friendly Players");
	Format(display, sizeof(display), "%T", "top_friendly", client);
	hMenu.AddItem("top_friendly", display, ITEMDRAW_DEFAULT);
	
	//Format(display, sizeof(display), "Top Cooperative Players");
	Format(display, sizeof(display), "%T", "top_coop", client);
	hMenu.AddItem("top_coop", display, ITEMDRAW_DEFAULT);
	
	//Format(display, sizeof(display), "Top Leaders & Veterans");
	Format(display, sizeof(display), "%T", "top_leader", client);
	hMenu.AddItem("top_leader", display, ITEMDRAW_DEFAULT);
	
	hMenu.AddItem("space", "",ITEMDRAW_SPACER);
	hMenu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int Callback_Menu_Main(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_DrawItem:
		{
			char info[32];
			int style;
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Select:
		{
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info));
			if (StrEqual(info,"my_stats"))			Menu_MyStats(param1);
			else if (StrEqual(info,"online_players"))	Menu_OnlinePlayers(param1);
			else if (StrEqual(info,"top_friendly"))	Menu_TopFriendly(param1);
			else if (StrEqual(info,"top_coop"))		Menu_TopCoop(param1);
			else if (StrEqual(info,"top_leader"))	Menu_TopLeader(param1);
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
 	return 0;
}

public void Menu_MyStats(int client)
{
	Menu hMenu = new Menu(Callback_Menu_MyStats, MENU_ACTIONS_ALL);
	char display[256];
	//Format(display, sizeof(display), "[Honor Ranking] My Stats \n");
	Format(display, sizeof(display), "[Honor Ranking] %T \n", "my_stats", client);
	hMenu.SetTitle(display);
	Format(display, sizeof(display), "Steam ID = %s", g_SteamID[client]);
	hMenu.AddItem("personal_steam", display, ITEMDRAW_DISABLED);
	//Format(display, sizeof(display), "Name = %s", g_PlayerName[client]);
	Format(display, sizeof(display), "%T", "my_name", client, g_PlayerName[client]);
	hMenu.AddItem("personal_name", display, ITEMDRAW_DISABLED);
	//Format(display, sizeof(display), "Friendly: %d votes", g_FriendlyCount[client]);
	Format(display, sizeof(display), "%T", "my_friendly_votes", client, g_FriendlyCount[client]);
	hMenu.AddItem("personal_friendly", display, ITEMDRAW_DISABLED);
	//Format(display, sizeof(display), "Cooperative: %d votes", g_CoopCount[client]);
	Format(display, sizeof(display), "%T", "my_coop_votes", client, g_CoopCount[client]);
	hMenu.AddItem("personal_coop", display, ITEMDRAW_DISABLED);
	//Format(display, sizeof(display), "Leader: %d votes", g_LeaderCount[client]);
	Format(display, sizeof(display), "%T", "my_leader_votes", client, g_LeaderCount[client]);
	hMenu.AddItem("personal_leader", display, ITEMDRAW_DISABLED);
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_MyStats(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public void Menu_OnlinePlayers(int client)
{
	Menu hMenu = new Menu(Callback_Menu_OnlinePlayers, MENU_ACTIONS_ALL);
	char display[256];
	//Format(display, sizeof(display), "[Honor Ranking] Online Players \n");
	Format(display, sizeof(display), "[Honor Ranking] %T \n", "online_players", client);
	hMenu.SetTitle(display);
	for (int j = 1; j <= MaxClients; j++)
	{
		if ((client != j) && (IsClientInGame(j)))
		{
			Format(display, sizeof(display), "%s", g_PlayerName[j]);
			hMenu.AddItem(display, display, ITEMDRAW_DEFAULT);
		}
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_OnlinePlayers(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Select:
		{
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info));
			for (int j = 1; j <= MaxClients; j++)
			{
				if (StrEqual(info, g_PlayerName[j]))
				{
					Menu_OnlineStats(param1, j);
					break;
				}
			}
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public void Menu_OnlineStats(int client, int target)
{
	Menu hMenu = new Menu(Callback_Menu_OnlineStats, MENU_ACTIONS_ALL);
	char display[256];
	Format(display, sizeof(display), "[Honor Ranking] %s \n", g_PlayerName[target]);
	hMenu.SetTitle(display);
	Format(display, sizeof(display), "Steam ID = %s", g_SteamID[target]);
	hMenu.AddItem("online_steam", display, ITEMDRAW_DISABLED);
	//Format(display, sizeof(display), "Friendly: %d votes", g_FriendlyCount[target]);
	Format(display, sizeof(display), "%T", "my_friendly_votes", client, g_FriendlyCount[target]);
	hMenu.AddItem("online_friendly", display, ITEMDRAW_DISABLED);
	//Format(display, sizeof(display), "Cooperative: %d votes", g_CoopCount[target]);
	Format(display, sizeof(display), "%T", "my_coop_votes", client, g_CoopCount[target]);
	hMenu.AddItem("online_coop", display, ITEMDRAW_DISABLED);
	//Format(display, sizeof(display), "Leader: %d votes", g_LeaderCount[target]);
	Format(display, sizeof(display), "%T", "my_leader_votes", client, g_LeaderCount[target]);
	hMenu.AddItem("online_leader", display, ITEMDRAW_DISABLED);
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_OnlineStats(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_OnlinePlayers(param1);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public void Menu_TopFriendly(int client)
{
	Menu hMenu = new Menu(Callback_Menu_TopFriendly, MENU_ACTIONS_ALL);
	char display[256];
	//Format(display, sizeof(display), "[Honor] Top Friendly Players \n <Player Name>  --  <Friendly Votes>");
	Format(display, sizeof(display), "[Honor] %T \n <%T>  --  <%T>", "top_friendly", client, "player_name", client, "friendly_votes", client);
	hMenu.SetTitle(display);
	for (int i = 0; i < g_FriendlyRecords; i++)
	{
		hMenu.AddItem(g_MenuFriendlyMessages[i], g_MenuFriendlyMessages[i], ITEMDRAW_DISABLED);
	}
	if (hMenu.ItemCount == 0)
	{
		PrintToChat(client, "[Honor] No data found.");
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_TopFriendly(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public void Menu_TopCoop(int client)
{
	Menu hMenu = new Menu(Callback_Menu_TopCoop, MENU_ACTIONS_ALL);
	char display[256];
	//Format(display, sizeof(display), "[Honor] Top Cooperative Players \n <Player Name>  --  <Coop Votes>");
	Format(display, sizeof(display), "[Honor] %T \n <%T>  --  <%T>", "top_coop", client, "player_name", client, "coop_votes", client);
	hMenu.SetTitle(display);
	for (int i = 0; i < g_CoopRecords; i++)
	{
		hMenu.AddItem(g_MenuCoopMessages[i], g_MenuCoopMessages[i], ITEMDRAW_DISABLED);
	}
	if (hMenu.ItemCount == 0)
	{
		PrintToChat(client, "[Honor] No data found.");
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_TopCoop(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public void Menu_TopLeader(int client)
{
	Menu hMenu = new Menu(Callback_Menu_TopLeader, MENU_ACTIONS_ALL);
	char display[256];
	//Format(display, sizeof(display), "[Honor] Top Leaders \n <Player Name>  --  <Leader Votes>");
	Format(display, sizeof(display), "[Honor] %T \n <%T>  --  <%T>", "top_leader", client, "player_name", client, "leader_votes", client);
	hMenu.SetTitle(display);
	for (int i = 0; i < g_LeaderRecords; i++)
	{
		hMenu.AddItem(g_MenuLeaderMessages[i], g_MenuLeaderMessages[i], ITEMDRAW_DISABLED);
	}
	if (hMenu.ItemCount == 0)
	{
		PrintToChat(client, "[Honor] No data found.");
	}
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_TopLeader(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DrawItem:
		{
			int style;
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack) Menu_Main(param1, 0);
		}
		case MenuAction_End:delete hMenu;
	}
	return 0;
}

public Action Event_PlayerLeave(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetEventInt(event, "index");
	// People that shared time with this leaving player no longer counts
	g_VotesDone[client] = 0;
	for (int j = 1; j <= MaxClients; j++)
	{
		g_TimeShared[client][j] = 0;
		g_TimeShared[j][client] = 0;
	}
	return Plugin_Continue;
}

public void Event_NewWave(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		for (int j = 1; j <= MaxClients; j++)
		{
			if (((g_TimeShared[i][j] > GetConVarFloat(cvar_TimeShared)) && (i != j)) && (g_VotesDone[i] < 3))
			{
				Menu_Main_Vote(i,0);
				break;
			}
		}
	}
}

public void Event_ObjectiveComplete(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		for (int j = 1; j <= MaxClients; j++)
		{
			if (((g_TimeShared[i][j] > GetConVarFloat(cvar_TimeShared)) && (i != j)) && (g_VotesDone[i] < 3))
			{
				Menu_Main_Vote(i,0);
				break;
			}
		}
	}
}

public void Event_PlayerExtracted(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetEventInt(event, "player_id");
	if (client < 1) return;
	// People that shared time with this leaving player no longer counts
	for (int i = 1; i <= MaxClients; i++)
	{
		if ((g_TimeShared[client][i] > GetConVarFloat(cvar_TimeShared)) && (client != i) && (g_VotesDone[client] < 3))
		{
			Menu_Main_Vote(client,0);
			break;
		}
	}
}

public Action Menu_Main_Vote(int client, int args)
{
	Menu hMenu = new Menu(Callback_Menu_Main_Vote, MENU_ACTIONS_ALL);
	char display[128];
	
	if (g_VotesDone[client] == 0)
	{
		//Format(display, sizeof(display), "[Honor Ranking] \n Pick the most friendly player in this round \n");
		Format(display, sizeof(display), "[Honor Ranking] \n %T \n", "pick_friendly_player", client);
	}
	if (g_VotesDone[client] == 1)
	{
		//Format(display, sizeof(display), "[Honor Ranking] \n Pick the most cooperative player in this round \n");
		Format(display, sizeof(display), "[Honor Ranking] \n %T \n", "pick_coop_player", client);
	}
	if (g_VotesDone[client] == 2)
	{
		//Format(display, sizeof(display), "[Honor Ranking] \n Pick the most valuable leader in this round \n");
		Format(display, sizeof(display), "[Honor Ranking] \n %T \n", "pick_leader_player", client);
	}
	hMenu.SetTitle(display);
	
	//Format(display, sizeof(display), "Skip vote");
	Format(display, sizeof(display), "%T", "skip_vote", client);
	hMenu.AddItem("skip_vote", display, ITEMDRAW_DEFAULT);
	for (int j = 1; j <= MaxClients; j++)
	{
		if ((client != j) && (IsClientInGame(j)))
		{
			Format(display, sizeof(display), "%s", g_PlayerName[j]);
			if (g_TimeShared[client][j] >= GetConVarFloat(cvar_TimeShared))
			{
				hMenu.AddItem(display, display, ITEMDRAW_DEFAULT);
			}
			else
			{
				hMenu.AddItem(display, display, ITEMDRAW_DISABLED);
			}
		}
	}
	hMenu.AddItem("space", "",ITEMDRAW_SPACER);
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int Callback_Menu_Main_Vote(Menu hMenu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_DrawItem:
		{
			char info[32];
			int style;
			hMenu.GetItem(param2, info, sizeof(info), style);
			return style;
		}
		case MenuAction_Select:
		{
			char info[32];
			hMenu.GetItem(param2, info, sizeof(info));
			char query[512];
			char escape_steam_id[72];
			g_VotesDone[param1]++;
			if (StrEqual(info, "skip_vote"))
			{
				if (g_VotesDone[param1] == 1)
				{
					//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] Friendly vote discarded.");
					if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "friendly_vote_discarded", param1);
					Menu_Main_Vote(param1,0);
				}
				if (g_VotesDone[param1] == 2)
				{
					//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] Cooperative vote discarded.");
					if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "coop_vote_discarded", param1);
					Menu_Main_Vote(param1,0);
				}
				if (g_VotesDone[param1] == 3)
				{
					//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] Leader vote discarded.");
					if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "leader_vote_discarded", param1);
				}
			}
			else
			{
				for (int j = 1; j <= MaxClients; j++)
				{
					if ((StrEqual(info, g_PlayerName[j])) && (g_VotesDone[param1] == 1))
					{
						g_FriendlyCount[j]++;
						g_MapFriendlyCount[j]++;
						if (GetConVarFloat(cvar_MultipleVotes) != 1.0) g_TimeShared[param1][j] = 0;
						//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] You picked %s as friendly player in this round.", g_PlayerName[j]);
						//if (IsClientInGame(j)) PrintToChat(j, "[Honor Ranking] Someone voted for you as friendly player! \n Type !honor to see your stats.");
						if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "friendly_player_picked", param1, g_PlayerName[j]);
						if (IsClientInGame(j)) PrintToChat(j, "[Honor Ranking] %T", "someone_picked_friendly", j);
						g_Database.Escape(g_SteamID[j], escape_steam_id, sizeof(escape_steam_id));
						Format(query, sizeof(query), "UPDATE 'players_honor' SET friendly_count = friendly_count+1 WHERE steam_id = '%s';", escape_steam_id);
						g_Database.Query(T_Generic, query);
						Menu_Main_Vote(param1,0);
						break;
					}
				}
				for (int j = 1; j <= MaxClients; j++)
				{
					if ((StrEqual(info, g_PlayerName[j])) && (g_VotesDone[param1] == 2))
					{
						g_CoopCount[j]++;
						g_MapCoopCount[j]++;
						if (GetConVarFloat(cvar_MultipleVotes) != 1.0) g_TimeShared[param1][j] = 0;
						//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] You picked %s as cooperative player in this round.", g_PlayerName[j]);
						//if (IsClientInGame(j)) PrintToChat(j, "[Honor Ranking] Someone voted for you as cooperative player! \n Type !honor to see your stats.");
						if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "coop_player_picked", param1, g_PlayerName[j]);
						if (IsClientInGame(j)) PrintToChat(j, "[Honor Ranking] %T", "someone_picked_coop", j);
						g_Database.Escape(g_SteamID[j], escape_steam_id, sizeof(escape_steam_id));
						Format(query, sizeof(query), "UPDATE 'players_honor' SET coop_count = coop_count+1 WHERE steam_id = '%s';", escape_steam_id);
						g_Database.Query(T_Generic, query);
						Menu_Main_Vote(param1,0);
						break;
					}
				}
				for (int j = 1; j <= MaxClients; j++)
				{
					if ((StrEqual(info, g_PlayerName[j])) && (g_VotesDone[param1] == 3))
					{
						g_LeaderCount[j]++;
						g_MapLeaderCount[j]++;
						if (GetConVarFloat(cvar_MultipleVotes) != 1.0) g_TimeShared[param1][j] = 0;
						//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] You picked %s as your favorite leader in this round.", g_PlayerName[j]);
						//if (IsClientInGame(j)) PrintToChat(j, "[Honor Ranking] Someone picked you as favorite leader! \n Type !honor to see your stats.");
						if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "leader_player_picked", param1, g_PlayerName[j]);
						if (IsClientInGame(j)) PrintToChat(j, "[Honor Ranking] %T", "someone_picked_leader", j);
						g_Database.Escape(g_SteamID[j], escape_steam_id, sizeof(escape_steam_id));
						Format(query, sizeof(query), "UPDATE 'players_honor' SET leader_count = leader_count+1 WHERE steam_id = '%s';", escape_steam_id);
						g_Database.Query(T_Generic, query);
						break;
					}
				}
				if ((g_VotesDone[param1] >= 3) && (GetConVarFloat(cvar_MultipleVotes) == 1.0))
				{
					for (int j = 1; j <= MaxClients; j++)
					{
						g_TimeShared[param1][j] = 0;
					}
				}
			}
		}
		case MenuAction_Cancel:
		{
			g_VotesDone[param1]++;
			if (g_VotesDone[param1] == 1)
			{
				//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] Friendly vote discarded.");
				if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "friendly_vote_discarded", param1);
				Menu_Main_Vote(param1,0);
			}
			if (g_VotesDone[param1] == 2)
			{
				//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] Cooperative vote discarded.");
				if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "coop_vote_discarded", param1);
				Menu_Main_Vote(param1,0);
			}
			if (g_VotesDone[param1] == 3)
			{
				//if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] Leader vote discarded.");
				if (IsClientInGame(param1)) PrintToChat(param1, "[Honor Ranking] %T", "leader_vote_discarded", param1);
			}
		}
		case MenuAction_End:
		{
			delete hMenu;
		}
	}
 	return 0;
}

public void Event_ExtractionBegin(Event event, const char[] name, bool dontBroadcast)
{
	int max_friendly_count = 0;
	int max_coop_count = 0;
	int max_leader_count = 0;
	char friendly_winner[32];
	char coop_winner[32];
	char leader_winner[32];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_MapFriendlyCount[i] > 0)
		{
			if (g_MapFriendlyCount[i] > max_friendly_count)
			{
				max_friendly_count = g_MapFriendlyCount[i];
				friendly_winner = g_PlayerName[i];
			}
		}
		if (g_MapCoopCount[i] > 0)
		{
			if (g_MapCoopCount[i] > max_coop_count)
			{
				max_coop_count = g_MapCoopCount[i];
				coop_winner = g_PlayerName[i];
			}
		}
		if (g_MapLeaderCount[i] > 0)
		{
			if (g_MapLeaderCount[i] > max_leader_count)
			{
				max_leader_count = g_MapLeaderCount[i];
				leader_winner = g_PlayerName[i];
			}
		}
	}
	//if (max_friendly_count > 0) PrintToChatAll("[Honor Awards] Most friendly player in this round: %s (+%d votes)", friendly_winner, max_friendly_count);
	//if (max_coop_count > 0) PrintToChatAll("[Honor Awards] Most cooperative player in this round: %s (+%d votes)", coop_winner, max_coop_count);
	//if (max_leader_count > 0)PrintToChatAll("[Honor Awards] Favorite survivor leader in this round: %s (+%d votes)", leader_winner, max_leader_count);
	if (max_friendly_count > 0)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i)) PrintToChat(i, "[Honor Awards] %T", "most_friendly_player", i, friendly_winner, max_friendly_count);
		}
	}
	if (max_coop_count > 0)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i)) PrintToChat(i, "[Honor Awards] %T", "most_cooperative_player", i, coop_winner, max_coop_count);
		}
	}
	if (max_leader_count > 0)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i)) PrintToChat(i, "[Honor Awards] %T", "best_leader", i, leader_winner, max_leader_count);
		}
	}
	max_friendly_count = 0;
	max_coop_count = 0;
	max_leader_count = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_MapFriendlyCount[i] = 0;
		g_MapCoopCount[i] = 0;
		g_MapLeaderCount[i] = 0;
	}
}

public Action Command_ResetTable(int client, int args)
{
	char query[512];
	Format(query, sizeof(query), "DROP TABLE IF EXISTS 'players_honor'");
	g_Database.Query(T_TableReset, query);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[Honor SQL] Table players_honor reset, cleared and ready to use.");
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[Honor SQL] Table players_honor reset, cleared and ready to use");
	return Plugin_Handled;
}

public Action Command_DeletePlayer(int client, int args)
{
	if (args < 1)
	{
		PrintToConsole(client, "Usage: sm_deleteplayer <STEAM_1:0:0000000>");
		return Plugin_Handled;
	}
	char steam_id_erased[32];
	GetCmdArg(1, steam_id_erased, sizeof(steam_id_erased));
	char query[512];
	char escape_steam_id[72];
	g_Database.Escape(steam_id_erased, escape_steam_id, sizeof(escape_steam_id));
	Format(query, sizeof(query), "DELETE FROM 'players_honor' WHERE steam_id = '%s';", escape_steam_id);
	g_Database.Query(T_Generic, query);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	LogMessage("[Honor SQL] Player deleted from database: %s", steam_id_erased);
	if (GetConVarFloat(cvar_DebugEnabled) == 1.0)	PrintToServer("[Honor SQL] Player deleted from database: %s", steam_id_erased);
	return Plugin_Handled;
}

public void T_Generic(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_Generic returned error: %s", error);
		return;
	}
}

public void T_TableReset(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_Generic returned error: %s", error);
		return;
	}
	char query[512];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS 'players_honor' (steam_id TEXT PRIMARY KEY, player_name TEXT, friendly_count INTEGER, coop_count INTEGER, leader_count INTEGER);");
	db.Query(T_RefreshPlayers, query);
}

public void T_RefreshPlayers(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null)
	{
		LogError("T_Generic returned error: %s", error);
		return;
	}
	// PERSONAL RECORDS QUERY FOR ALL PLAYERS IN-GAME
	char query[512];
	char escape_steam_id[72];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			GetClientAuthId(i, AuthId_Steam2, g_SteamID[i], sizeof(g_SteamID[]));
			g_Database.Escape(g_SteamID[i], escape_steam_id, sizeof(escape_steam_id));
			Format(query, sizeof(query), "SELECT * FROM 'players_honor' WHERE steam_id = '%s';", escape_steam_id);
			g_Database.Query(T_LoadPlayer, query, GetClientUserId(i));
		}
	}
}

public Action Timer_Global(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			// Player was active this second
			for (int j = 1; j <= MaxClients; j++)
			{
				if ((IsClientInGame(j)) && (j != i))
				{
					// Players shared a second of game time
					g_TimeShared[i][j]++;
				}
			}
		}
	}
	return Plugin_Continue;
}