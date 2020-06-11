# Auto-Stopwatch
SourceMod plugin for TF2 that automagically manages Stopwatch mode in non-tournament servers.

This plugin automatically manages Stopwatch mode on Payload and Attack/Defend maps for pub servers. Normally, Stopwatch mode is only available with `mp_tournament`, and to enable that on a public server would give every player access to ready/unready teams, and change team names, which would obviously lead to chaos.

This plugin automatically manages tournament mode, locks team names and ready state, and automatically starts the match after a countdown, just as in regular play. This plugin also has checks in place to ensure that it doesn't alter gameplay in any way when NOT on PL or A/D maps, making it rotation-friendly.

Also includes "smart setup," a simple system I wrote which reduces setup time based on the presence of engineers or medics (or, more accurately, a lack thereof).

### NOTICE ABOUT TOURNAMENT MODE

Since this enables tournament mode, this disables autobalance and team restrictions, and it is heavily recommended to get a third-party autobalancing/team limiting plugin! I will add a simple team restriction system later (ie preventing people from stacking on RED and creating a 3v8), however **I will NOT be writing an autobalance system into this plugin!**

Also, on that note, other tournament-exclusive options work with this plugin, including the built-in class restriction system (`tf_tournament_classlimit_<class>`), and players who are dead/spectating will be able to use the tournament spectator HUD.

Thirdly, If you have the logs.tf plugin, halves played with this plugin *will* generate logs! If you don't want this, disable the logs.tf plugin.

## CVARs

Values in [brackets] are the default value.

`sm_stopwatch_enabled <0/[1]>` - Enables or disables the plugin as a whole.

`sm_stopwatch_halves [2]` - How many halves (1 half = 1 round of defense, 1 round of offense) should be played before changing map? If this value is changed in the middle of a half, the plugin will only catch up once it ends (ie this can be used to add an extra half, but if you lower the halves it will still finish the current half before changing map)

`sm_stopwatch_halves_firstwaittime [40]` - Time in seconds (max 60) for pre-game countdown for first half (to allow map downloads and such). Analagous to the hidden `mp_waitingforplayers_time` CVAR, but explicitly for the first half of a map.

`sm_stopwatch_halves_waittime [30]` - Time in seconds (max 60) for pre-game countdown for subsequent halves (since players have already loaded in at this point). Analagous to the hidden `mp_waitingforplayers_time` CVAR, but explicitly for halves beyond the first one.

`sm_stopwatch_smartsetup <0/[1]/2>` - Performs "smart setup" - a system I made wherein setup time is reduced when there are no Engineers or Medics present within the first few seconds of a round. Setting this to `1` will reduce setup time depending on if there are no Engineers, no Medics, **OR** if it detects a Medic, but no engineers. If this is set to `2`, it will ignore the scenario where there might be a Medic but no Engineer.

`sm_stopwatch_smartsetup_noengies [40]` - Time (in seconds) to set the Setup timer to when there are no Engineers, BUT at least one Medic, present at the start of Setup time. (setting `sm_stopwatch_smartsetup` to `2` will use the value below this one instead in this scenario)

`sm_stopwatch_smartsetup_nomedics [35]` - Time (in seconds) to set the Setup timer to when there are no Engineers OR Medics present at the start of Setup time.

`sm_stopwatch_fancy_countdown <0/[1]>` - Enables fancy countdown with additional announcer voicelines and the game-start music from Casual mode. ("Prepare to compete in 30 seconds...")
