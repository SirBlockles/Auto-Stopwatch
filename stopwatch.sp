/*

Auto-Stopwatch - a plugin that automatically manages Stopwatch mode on Payload and Attack/Defend maps for pub servers.
Normally, Stopwatch mode is only available with mp_tournament, and giving every player on the server access to changing team names and
readying/unreadying teams will invariably lead to chaos. This plugin turns on mp_tournament, locks team names and ready state, and
automatically starts the match after the server's waiting for players time, just as a regular server would.
This plugin also has checks in place to ensure that it doesn't alter gameplay in any way when NOT on PL or A/D maps, making it rotation-friendly.
Also includes "smart setup," which reduces setup time based on the presence of engineers or medics (or, more accurately, a lack thereof).

CHANGELOG
1.0 - initial release

TO-DO LIST:

* If the pre-game countdown is initiated, and all players leave their teams, the countdown is cancelled and never restarted, soft-locking the map on the ready-up screen.
Possible solutions:
  1) Watch every round start event, and check if there are any players on either team.
  2) Watch every team change event, and check if there are any players on either team.
  
  In either case, once we determine there's no players on a team, turn off tournament mode to reset the round state, and await a player joining a team as usual.
  We'll also have to make sure that halves are still tracked accurately when resetting the round state - does it assume everyone left and reset to no halves played,
  or do we assume that maybe people just went into spectator and we should stil save that we've already played a half?
  If people go into spectator and back, they can delay a map and play it forever if we reset it,
  but it would only take one person staying on a team to progress to a new half, so it would have to be a unanimous decision among the players to stall the map.
  
* Logs still generate if the logs.tf plugin is installed, since each half is a fully-qualified competitive game. May or may not be a bug depending on your philosophy,
and i wouldn't be able to change it anyway. Just don't use logs.tf concurrently with this plugin.

*/

#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = {
	name = "Auto-Stopwatch",
	author = "muddy",
	description = "Automagically manages Stopwatch mode for pubs.",
	version = PLUGIN_VERSION,
	url = ""
};

new Handle:cvar_enabled;
new Handle:cvar_halves;
new Handle:cvar_firsthalfwaittime;
new Handle:cvar_halfwaittime;
new Handle:cvar_smartsetup;
new Handle:cvar_smartsetupnoengy;
new Handle:cvar_smartsetupnoeither;
new Handle:cvar_fancycountdown;
new downTime = false;
new stopwatchCapable = false;
new halfCount = 0;

public OnPluginStart() {
	cvar_enabled = CreateConVar("sm_stopwatch_enabled", "1", "Enables stopwatch management.", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	cvar_halves = CreateConVar("sm_stopwatch_halves", "2", "How many halves (1 round offense, 1 round defense) should be played per map?", FCVAR_NOTIFY, true, 1.0, true, 12.0);
	cvar_firsthalfwaittime = CreateConVar("sm_stopwatch_halves_firstwaittime", "40", "How many seconds to wait after first player spawns on first half (for map downloaders)", FCVAR_ARCHIVE, true, 10.0, true, 60.0);
	cvar_halfwaittime = CreateConVar("sm_stopwatch_halves_waittime", "30", "How many seconds to wait between halves after the first half", FCVAR_ARCHIVE, true, 10.0, true, 60.0);
	cvar_smartsetup = CreateConVar("sm_stopwatch_smartsetup", "1", "Automatically reduce setup time depending on the presence of medics or engineers", FCVAR_ARCHIVE, true, 0.0, true, 2.0);
	cvar_smartsetupnoengy = CreateConVar("sm_stopwatch_smartsetup_noengies", "40", "Time to set Setup to when there's no engineers (but at least one medic) present", FCVAR_ARCHIVE, true, 5.0, true, 60.0);
	cvar_smartsetupnoeither = CreateConVar("sm_stopwatch_smartsetup_nomedics", "35", "Time to set Setup to when there's no engineers OR medics present", FCVAR_ARCHIVE, true, 5.0, true, 60.0);
	cvar_fancycountdown = CreateConVar("sm_stopwatch_fancy_countdown", "1", "Enable Casual mode pregame lines and music during half countdowns?", FCVAR_ARCHIVE, true, 0.0, true, 1.0);
	HookEvent("teamplay_round_start", round_start);
	HookEvent("tf_game_over", game_end);
	HookEvent("teamplay_game_over", game_end);
	RegConsoleCmd("tournament_readystate", cmd_block);
	RegConsoleCmd("tournament_teamname", cmd_block);
}

public OnMapStart() {
	halfCount = 0; //reset tracked halves to zero on a new map
	stopwatchCapable = false;
	if (!GetConVarBool(cvar_enabled)) return; //halt everything if the plugin CVAR is not enabled
	new iTeam, iEnt = 0;
	
	//check if the map is stopwatch-capable: 
	if(FindEntityByClassname(-1, "func_tracktrain") > -1 && FindEntityByClassname(-1, "tf_multiple_escort") == -1) stopwatchCapable = true; //from what i can tell, there's not actually a proper "tf_logic_escort," so check if there's a tracktrain (payload cart) and NOT payload race
	if(!stopwatchCapable) { //if the payload check hasn't passed, give it a go with control point checks		
		while(FindEntityByClassname(iEnt, "team_control_point") != -1) { //check all points on a map, and see if RED owns all of them, as Attack/Defend is likely to be
			iTeam = GetEntProp(iEnt, Prop_Send, "m_iTeamNum");
			if(iTeam != 2) { stopwatchCapable = false; break; } //any mode with BLU or neutral caps on map start is likely 5CP or some other weird mode from mars
			else stopwatchCapable = true; //if any point doesn't belong to RED we won't reach this line - if we finish all points then the map is stopwatch capable.
			iEnt++;
		}
	}
	if(FindEntityByClassname(-1, "tf_logic_koth") > -1) stopwatchCapable = false; //if we're in koth, it doesn't matter what conclusion our stopwatch check came to. useful for some koth maps that somehow trick our above logic.
}

public OnMapEnd() {
	if (!GetConVarBool(cvar_enabled)) return; //in case the server is using a competitive config and changes map, we don't want to turn off tournament mode on them!
	SetConVarBool(FindConVar("mp_tournament"), false); //disable mp_tournament on map end to reset it for the next map load.
}

public round_start(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!GetConVarBool(cvar_enabled) || !stopwatchCapable) return;
	downTime = false;
	// set team names to RED and BLU each round to prevent RED being named BLU and vice versa
	SetConVarString(FindConVar("mp_tournament_blueteamname"), "BLU");
	SetConVarString(FindConVar("mp_tournament_redteamname"), "RED");
	
	// here comes the magic trick. since we turn off tournament mode, we take advantage of the fact that waiting for players is considered a round start, and turn on tournament mode and all that during then.
	// after turning on tournament mode, we mp_restartgame to start our pre-game countdown. if tournament mode is manually enabled before a player joins a team, the game will be soft-locked.
	// once we've set up our round, when the countdown finishes and the first round proper starts (and fires this event again), tournament mode will already be on and it won't re-initiate our map setup routine.
	
	if (!GetConVarBool(FindConVar("mp_tournament"))) {
		//maybe we should print this in the first round of the first half of the map, instead of when the first player joins a team, so that more people would see it...
		PrintToChatAll("[Stopwatch] This map is running in STOPWATCH MODE. One team plays the map normally, then the other team has to cap the same points in less time!");
		downTime = true;
		// set cvars
		SetConVarBool(FindConVar("mp_tournament"), true);
		SetConVarBool(FindConVar("mp_tournament_allow_non_admin_restart"), false);
		SetConVarBool(FindConVar("mp_tournament_stopwatch"), true);
		// for stopwatch mode, remove the win limit and set 2 max rounds - one full half per "match," which we then restart for as many halves as set via CVAR
		SetConVarInt(FindConVar("mp_winlimit"), 0);
		SetConVarInt(FindConVar("mp_maxrounds"), 2);
		SetConVarInt(FindConVar("mp_timelimit"), 0);
		//since round start events are only fired once at least one player spawns in, this will guarantee that the map doesn't sit empty and start off the round.
		//once a player has spawned, perform mp_restartgame, which forcefully starts the game countdown as if both teams had readied up, with the added bonus of setting the countdown time in seconds.
		ServerCommand("mp_restartgame %i", GetConVarInt(cvar_firsthalfwaittime));
		
		//this last bit does voicelines and music, a la valve casual mode, and *should* remain accurate even when thrown custom countdown times
		if(GetConVarBool(cvar_fancycountdown)) { //ignore this entire bit if the fancy countdown is disabled
			if(GetConVarInt(cvar_firsthalfwaittime) == 60) { //only announce 60 second line if there are 60 seconds... duh
				for(new i = 1; i <= MaxClients; i++) { 
					if(!IsClientInGame(i)) continue;
					ClientCommand(i, "playgamesound Announcer.CompGame1Begins60Seconds"); //playgamesound is a built-in command that plays one of the possible variations automatically, without having to hard-code playing sounds directly. it's the future!
				}
			}
			//if the first half's wait time is less than 30 seconds, don't even bother playing "begins in 30 seconds" line, since that would be inaccurate
			//then just throw the handling off into a function because timers are weird
			if(GetConVarInt(cvar_firsthalfwaittime) >= 30) CreateTimer((GetConVarFloat(cvar_firsthalfwaittime) - 29.5), Speak30Sec); //make sure we time this right - make it fire slightly later since 30.0 exactly seems to make it happen while the countdown's still on 31
			if(GetConVarInt(cvar_firsthalfwaittime) >= 10) CreateTimer((GetConVarFloat(cvar_firsthalfwaittime) - 9.5), PlayPregameMusic); //same displaced timing for the same reason
		}
	}
	
	//"Smart Setup" logic. Reduces time in Setup phase if no medics or engineers are present after the first 6 seconds of Setup time starting.
	if(GetConVarInt(cvar_smartsetup) != 0 && !downTime) {
		new roundTimer = FindEntityByClassname(-1, "team_round_timer");
		if (roundTimer > -1)
		{
			CreateTimer(6.0, AttemptSmartSetup, roundTimer); //wait 6 seconds into the round to account for class changes
		} else { //if we somehow don't have a round timer, take note of it. This plugin should automatically detect that we're not on a stopwatch map, and reaching this point means the map confused the plugin.
			PrintToChatAll("[Stopwatch] Could not find round timer! Are you playing on a map without one?");
		}
	}
}

public game_end(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!GetConVarBool(cvar_enabled)) return;
	halfCount++; //we just finished a half, increment this from zero each time the match ends
	if(halfCount >= GetConVarInt(cvar_halves)) { //we've now hit the defined half limit, or it was lowered by an admin during the course of the last half
		PrintToChatAll("[Stopwatch] Reached half limit for map! Cycling to next map...");
		SetConVarBool(FindConVar("mp_tournament"), false); //turn off tournament mode, and the game handles end-of-game map change automatically, like it would any other map end
	} else {
		PrintToChatAll("[Stopwatch] Reached half %i/%i. New half begins in %i seconds...", halfCount, GetConVarInt(cvar_halves), GetConVarInt(cvar_halfwaittime));
		if(GetConVarInt(cvar_fancycountdown)) {
			if(GetConVarInt(cvar_halfwaittime) == 60) {
				for(new i = 1; i <= MaxClients; i++) {
					if(!IsClientInGame(i)) continue;
					ClientCommand(i, "playgamesound Announcer.CompGame1Begins60Seconds");
				}
			}
			if(GetConVarInt(cvar_halfwaittime) >= 30) CreateTimer((GetConVarFloat(cvar_halfwaittime) - 29.5), Speak30Sec);
			if(GetConVarInt(cvar_halfwaittime) >= 10) CreateTimer((GetConVarFloat(cvar_halfwaittime) - 9.5), PlayPregameMusic);
		}
		//we have our own "between half wait time," in case server admins want intial wait time longer to allow people to load in.
		ServerCommand("mp_restartgame %i", GetConVarInt(cvar_halfwaittime));
		downTime = true;
	}
}

public Action AttemptSmartSetup(Handle timer, entityTimer) {
	new bool:leastOneEngy = false;
	new bool:leastOneMedic = false;
	
	for(new i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) continue;
		if(TF2_GetPlayerClass(i) == TFClass_Engineer) { leastOneEngy = true; break; } //if there's at least one engy, end the loop since we're not reducing setup at all and there's no point in checking further
		if(TF2_GetPlayerClass(i) == TFClass_Medic) { leastOneMedic = true; } //don't break here in case there's still an engineer we haven't found yet
	}
	if((!leastOneEngy && leastOneMedic) && GetConVarInt(cvar_smartsetup) != 2) { //if there's any medics present, but not engineers, reduce setup time by a different amount. set smart setup to 2 to ignore this check
		PrintToChatAll("[Stopwatch] No engineers present! Reducing setup time to %i seconds...", GetConVarInt(cvar_smartsetupnoengy));
		SetVariantInt(GetConVarInt(cvar_smartsetupnoengy) + 1); //0 is counted as a second on the round timer, so if our cvar is set to 40, make it 41 sec to achieve 0:40 on the setup timer
		AcceptEntityInput(entityTimer, "SetTime");
	} else if ((!leastOneEngy && !leastOneMedic) || (!leastOneEngy && GetConVarInt(cvar_smartsetup) == 2)) { //if there's not any medics OR engineers present, reduce setup time, unless we set the cvar to 2 in which case ignore the medic check
		if(GetConVarInt(cvar_smartsetup) != 2) PrintToChatAll("[Stopwatch] No engineers or medics present! Reducing setup time to %i seconds...", GetConVarInt(cvar_smartsetupnoeither));
		else PrintToChatAll("[Stopwatch] No engineers present! Reducing setup time to %i seconds...", GetConVarInt(cvar_smartsetupnoeither));
		SetVariantInt(GetConVarInt(cvar_smartsetupnoeither) + 1);
		AcceptEntityInput(entityTimer, "SetTime");
	}
}

//same logic as the "begins in 60 seconds" voice lines, just thrown off into a function because timers
public Action Speak30Sec(Handle timer) {
	for(new i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) { continue; }
		ClientCommand(i, "playgamesound Announcer.CompGame1Begins30Seconds");
	}
}

//mp_restartgame automatically does "mission begins in 10..." and below, so instead of playing a fancy casual mode line, play the music from a casual match starting to compliment the default voicelines.
public Action PlayPregameMusic(Handle timer) {
	for(new i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i)) { continue; }
		ClientCommand(i, "playgamesound MatchMaking.RoundStartCasual");
	}
}

//this is one of the only remaining remnants of the old auto-stopwatch plugin that this one was derived from.
//i don't know shit about bitwise logic, but tweaking this, i've made it so if the map is determined to not be stopwatch capable, it shouldn't block mp_tournament commands,
//so you can at least ready up on koth if this plugin is still active. i dunno.
public Action cmd_block(client, args) {
	return (stopwatchCapable ? Plugin_Handled : Plugin_Continue);
}