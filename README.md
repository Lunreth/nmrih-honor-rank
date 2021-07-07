# NMRiH - Honor Ranking
Players will be able to give honor votes to friendly, cooperative and veteran users, it also has support for SQLite database and a full menu to display ranking in-game. Use `!honor` command to check your own votes.

https://forums.alliedmods.net/showthread.php?p=2714045

![image](https://i.imgur.com/YD88Y3G.jpeg)
![image](https://i.imgur.com/osTxq6G.jpeg)
![image](https://i.imgur.com/wEpAsjT.jpeg)

# Admin Commands (ROOT FLAG)
- `sm_honor_reset`
  - Reset all stats from database
- `sm_honor_player_reset` <STEAM_1:0:0000000>
  - Deletes a player from database based in STEAMID


# CVars
- sm_honor_enabled (1/0) (Default: 1)
  - Enable or disable NMRiH Honor Ranking
- sm_honor_debug (1/0) (Default: 0)
  - Will spam messages in console and log about any SQL action
- sm_honor_timeshared (1-60000) (Default: 600)
  - Minimum time shared required between players (in seconds) to pop up honor voting menu
- sm_honor_multiple_votes (1/0) (Default: 1)
  - Set to 1 if you want players to use all their votes in one single user

# Install
- Simply copy and merge /addons folder with the one in your game directory
- Edit configs/databases.cfg --> Insert a new keyvalue set like the following example:

`"nmrih_honor"
{
   "driver" "sqlite"
   "database" "nmrih_honor"
}`
