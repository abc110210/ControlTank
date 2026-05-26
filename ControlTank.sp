#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "Control Tank",
    author = "Shan",
    description = "在合作战役模式中，Tank出现时随机选择一名玩家变成Tank",
    version = "2.1.0",
    url = ""
};

ConVar g_cvarEnabled;
ConVar g_cvarTankTime;

bool g_bTankSpawning = false;
float g_fLastTankSpawnTime = 0.0;

// 记录当前控制Tank的玩家UserID
int g_iCurrentTankUserId = 0;

public void OnPluginStart()
{
    g_cvarEnabled = CreateConVar("shan_controltank_enabled", "1", "是否启用Tank随机选择功能 (0=禁用, 1=启用)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, 0.0, true, 1.0);
    g_cvarTankTime = CreateConVar("shan_controltank_time", "100", "Tank控制权时长 (-1=永久控制, 1~100=控制权秒数)", FCVAR_NOTIFY|FCVAR_PRINTABLEONLY, true, -1.0, true, 100.0);

    AutoExecConfig(true, "controltank");

    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("map_transition", Event_MapTransition);

    RegConsoleCmd("sm_tankinfo", Command_TankInfo, "显示Tank信息");
}

public void OnMapStart()
{
    g_bTankSpawning = false;
    g_fLastTankSpawnTime = 0.0;
    g_iCurrentTankUserId = 0;
}

public void OnConfigsExecuted()
{
    PrintToServer("[寄寄之家 - ControlTank] 该插件已重载成功");
}

bool IsCoopMode()
{
    ConVar gameMode = FindConVar("mp_gamemode");
    if (gameMode != null)
    {
        char mode[32];
        gameMode.GetString(mode, sizeof(mode));
        return StrEqual(mode, "coop", false);
    }
    return false;
}

int FindTankBot()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
        {
            if (GetEntProp(i, Prop_Send, "m_zombieClass") == 8)
                return i;
        }
    }
    return -1;
}

int FindCurrentTankPlayer()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
        {
            if (GetEntProp(i, Prop_Send, "m_zombieClass") == 8)
                return i;
        }
    }
    return -1;
}

bool HasPlayerTank()
{
    return FindCurrentTankPlayer() > 0;
}

int SelectRandomPlayer()
{
    ArrayList players = new ArrayList();

    // 优先选择活着的幸存者
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i))
        {
            players.Push(i);
        }
    }

    // 如果没有活着的幸存者，选择死亡的幸存者
    if (players.Length == 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2)
            {
                players.Push(i);
            }
        }
    }

    int selected = -1;
    if (players.Length > 0)
    {
        selected = players.Get(GetRandomInt(0, players.Length - 1));
    }

    delete players;
    return selected;
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvarEnabled.BoolValue || !IsCoopMode() || g_bTankSpawning)
        return;

    float currentTime = GetGameTime();

    // 30秒内只处理一次tank_spawn事件
    if (currentTime - g_fLastTankSpawnTime < 30.0)
        return;

    // 如果已经有玩家控制的Tank，跳过
    if (HasPlayerTank())
        return;

    g_fLastTankSpawnTime = currentTime;
    g_bTankSpawning = true;

    CreateTimer(1.0, Timer_SelectPlayer, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SelectPlayer(Handle timer)
{
    // 再次检查是否已有玩家Tank
    if (HasPlayerTank())
    {
        g_bTankSpawning = false;
        return Plugin_Stop;
    }

    int target = SelectRandomPlayer();
    if (target > 0)
    {
        TransformToTank(target);
        char name[MAX_NAME_LENGTH];
        GetClientName(target, name, sizeof(name));
        PrintToChatAll("\x03[寄寄之家 - ControlTank] \x01玩家 \x04%s \x01被选择作为 \x04Tank \x01操控者", name);
    }
    else
    {
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01没有可用的玩家，Tank由 \x04AI \x01控制");
    }

    g_bTankSpawning = false;
    return Plugin_Stop;
}

void TransformToTank(int client)
{
    if (!IsClientInGame(client))
        return;

    int tankBot = FindTankBot();
    if (tankBot <= 0)
        return;

    DataPack data = new DataPack();
    data.WriteCell(GetClientUserId(client));
    data.WriteCell(tankBot);

    // 如果玩家活着，先自杀
    if (IsPlayerAlive(client))
    {
        ForcePlayerSuicide(client);
    }

    CreateTimer(0.5, Timer_Takeover, data, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Takeover(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client))
    {
        delete data;
        return Plugin_Stop;
    }

    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        delete data;
        return Plugin_Stop;
    }

    ChangeClientTeam(client, 3);
    CreateTimer(0.2, Timer_TakeoverPhase2, data, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_TakeoverPhase2(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client))
    {
        delete data;
        return Plugin_Stop;
    }

    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        delete data;
        return Plugin_Stop;
    }

    L4D_TakeOverZombieBot(client, tankBot);
    delete data;

    // 记录当前控制Tank的玩家
    g_iCurrentTankUserId = GetClientUserId(client);

    // 设置挫折度系统
    ApplyTankFrustration();

    return Plugin_Stop;
}

void ApplyTankFrustration()
{
    int tankTime = g_cvarTankTime.IntValue;

    // 100以上全部都是100
    if (tankTime > 100)
    {
        tankTime = 100;
    }

    // 设置控制台变量 z_frustration_lifetime
    ConVar zFrustrationLifetime = FindConVar("z_frustration_lifetime");
    if (zFrustrationLifetime != null)
    {
        zFrustrationLifetime.SetInt(tankTime);
    }
}

// 当玩家控制的Tank死亡时
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client > 0 && client <= MaxClients && IsClientInGame(client))
    {
        // 检查死亡的是否是玩家控制的Tank
        if (GetClientTeam(client) == 3)
        {
            int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
            if (zClass == 8)
            {
                // 清除记录
                g_iCurrentTankUserId = 0;

                // 玩家控制的Tank死亡，切换回幸存者阵营
                ChangeClientTeam(client, 2);
            }
        }
    }
}

public void OnGameFrame()
{
    // 检查之前控制Tank的玩家是否变成了Ghost状态（挫折度满了）
    if (g_iCurrentTankUserId > 0)
    {
        int player = GetClientOfUserId(g_iCurrentTankUserId);
        if (player > 0 && player <= MaxClients && IsClientInGame(player))
        {
            // 检查玩家是否在感染者队伍且是Ghost状态
            if (GetClientTeam(player) == 3)
            {
                bool isGhost = view_as<bool>(GetEntProp(player, Prop_Send, "m_isGhost"));
                if (isGhost)
                {
                    // 玩家因挫折度满了变成Ghost，切换回幸存者阵营
                    g_iCurrentTankUserId = 0;
                    ChangeClientTeam(player, 2);
                }
            }
            else
            {
                // 玩家不在感染者队伍了，清除记录
                g_iCurrentTankUserId = 0;
            }
        }
        else
        {
            // 玩家不存在了，清除记录
            g_iCurrentTankUserId = 0;
        }
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bTankSpawning = false;
    g_iCurrentTankUserId = 0;
}

public void Event_MapTransition(Event event, const char[] name, bool dontBroadcast)
{
    g_bTankSpawning = false;
    g_iCurrentTankUserId = 0;
}

public Action Command_TankInfo(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    // 查找当前Tank
    int tankEntity = -1;
    int tankClient = -1;
    bool isPlayerControlled = false;

    // 查找玩家控制的Tank
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
        {
            if (GetEntProp(i, Prop_Send, "m_zombieClass") == 8)
            {
                if (!IsFakeClient(i))
                {
                    tankClient = i;
                    isPlayerControlled = true;
                    break;
                }
            }
        }
    }

    // 如果没有玩家控制的Tank，查找AI控制的Tank
    if (!isPlayerControlled)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
            {
                if (GetEntProp(i, Prop_Send, "m_zombieClass") == 8)
                {
                    tankEntity = i;
                    break;
                }
            }
        }
    }

    PrintToChat(client, "\x01========== \x03[寄寄之家 - ControlTank]\x01==========");

    // 显示Tank血量（读取本局Tank设置的血量）
    ConVar zTankHP = FindConVar("z_tank_health");
    int tankHP = 0;
    if (zTankHP != null)
    {
        tankHP = zTankHP.IntValue;
    }

    // 如果有Tank实体，优先使用实体的最大血量
    int tankEnt = isPlayerControlled ? tankClient : tankEntity;
    if (tankEnt > 0)
    {
        int maxHealth = GetEntProp(tankEnt, Prop_Send, "m_iMaxHealth");
        if (maxHealth > 0)
        {
            tankHP = maxHealth;
        }
    }

    PrintToChat(client, "\x01Tank血量: \x04%d", tankHP);

    // 显示Tank控制时间
    int tankTime = g_cvarTankTime.IntValue;
    if (tankTime == -1)
    {
        PrintToChat(client, "\x01Tank控制时间: \x04无限时间");
    }
    else
    {
        PrintToChat(client, "\x01Tank控制时间: \x04%d \x01秒", tankTime);
    }

    // 显示Tank操控者
    if (isPlayerControlled && tankClient > 0)
    {
        char name[MAX_NAME_LENGTH];
        GetClientName(tankClient, name, sizeof(name));
        PrintToChat(client, "\x01Tank操控者: \x04%s", name);
    }
    else if (tankEntity > 0)
    {
        PrintToChat(client, "\x01Tank操控者: \x04AI");
    }
    else
    {
        PrintToChat(client, "\x01Tank操控者: \x04无");
    }

    PrintToChat(client, "\x01====================================");

    return Plugin_Handled;
}
