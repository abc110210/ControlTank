#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "Control Tank",
    author = "Shan",
    description = "在合作战役模式中，Tank出现时随机选择一名玩家变成Tank",
    version = "1.0.0",
    url = ""
};

public Plugin myinfo =
{
    name = "Control Tank",
    author = "Shan",
    description = "在合作战役模式中，Tank出现时随机选择一名玩家变成Tank",
    version = "1.0.0",
    url = ""
};

ConVar g_cvarEnabled;
ConVar g_cvarTankHP;
ConVar g_cvarTankFrustrationTime;
bool g_bTankSpawning = false;
bool g_bIsManualTest = false;
int g_iCurrentTank = -1;

public void OnPluginStart()
{
    g_cvarEnabled = CreateConVar("shan_controltank_enabled", "1", "是否启用Tank随机选择功能", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvarTankHP = CreateConVar("shan_controltank_hp", "4000", "Tank血量设置", FCVAR_NOTIFY, true, 1.0, true, 120000.0);
    g_cvarTankFrustrationTime = CreateConVar("shan_controltank_time", "0", "Tank挫折度系统(0=关闭/永久控制, 1=开启/系统默认)", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    AutoExecConfig(true, "controltank");
    HookConVarChange(g_cvarTankHP, OnTankHPChanged);

    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_bot_replace", Event_PlayerBotReplace);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);

    RegConsoleCmd("sm_test2", Command_Test2, "测试接管AI Tank");
}

public void OnMapStart()
{
    g_bTankSpawning = false;
    g_iCurrentTank = -1;

    // 设置Tank血量
    int tankHP = g_cvarTankHP.IntValue;
    if (tankHP > 0)
    {
        ConVar zTankHP = FindConVar("z_tank_health");
        if (zTankHP != null)
        {
            zTankHP.SetInt(tankHP);
        }
    }
}

public void OnTankHPChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    int newHP = StringToInt(newValue);
    if (newHP > 0)
    {
        ConVar zTankHP = FindConVar("z_tank_health");
        if (zTankHP != null)
        {
            zTankHP.SetInt(newHP);
        }
    }
}

// 监控Tank挫折度设置
public Action L4D_OnSetTankFrustration(int tank, int &frustration)
{
    if (tank > 0 && tank <= MaxClients && IsClientInGame(tank))
    {
        // 只处理玩家控制的Tank
        if (!IsFakeClient(tank))
        {
            int frustrationTime = g_cvarTankFrustrationTime.IntValue;

            if (frustrationTime == 0)
            {
                // 0 = 关闭挫折度系统，永久控制
                frustration = 0;
            }
            // 1 = 开启挫折度系统，使用游戏默认值
            // 不需要修改 frustration，让游戏自然增长
        }
    }
    return Plugin_Continue;
}

public void OnMapEnd()
{
    g_iCurrentTank = -1;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_iCurrentTank = -1;
    g_bTankSpawning = false;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == g_iCurrentTank)
    {
        g_iCurrentTank = -1;
    }
}

public void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));

    // 当玩家被bot替换时（玩家失去Tank控制权）
    if (player == g_iCurrentTank)
    {
        g_iCurrentTank = -1;

        // 将玩家放回幸存者阵营（死亡状态，可被复活）
        if (IsClientInGame(player))
        {
            // 先切换到幸存者队伍
            ChangeClientTeam(player, 2);

            // 等待队伍切换完成后，检查并确保玩家处于死亡状态
            CreateTimer(0.1, Timer_EnsurePlayerDead, GetClientUserId(player), TIMER_FLAG_NO_MAPCHANGE);
        }
    }
}

public Action Timer_EnsurePlayerDead(Handle timer, int userid)
{
    int player = GetClientOfUserId(userid);

    if (!IsClientInGame(player))
        return Plugin_Stop;

    // 如果玩家在幸存者队伍但还活着，杀死他
    if (GetClientTeam(player) == 2 && IsPlayerAlive(player))
    {
        ForcePlayerSuicide(player);
    }

    return Plugin_Stop;
}

public void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));

    if (bot == g_iCurrentTank && player > 0 && player <= MaxClients)
    {
        g_iCurrentTank = player;
    }
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvarEnabled.BoolValue)
        return;

    if (!IsCoopMode())
        return;

    if (g_bIsManualTest)
        return;

    if (g_bTankSpawning)
        return;

    g_bTankSpawning = true;
    CreateTimer(0.5, Timer_SelectAndTransformTank, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SelectAndTransformTank(Handle timer)
{
    if (HasPlayerControlledTank())
    {
        g_bTankSpawning = false;
        return Plugin_Stop;
    }

    int targetClient = SelectRandomSurvivor();

    if (targetClient > 0)
    {
        TransformPlayerToTank(targetClient);

        char playerName[MAX_NAME_LENGTH];
        GetClientName(targetClient, playerName, sizeof(playerName));
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01被选中成为 \x04Tank", playerName);
    }
    else
    {
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01Tank失去控制权，将由 \x04AI \x01控制 \x04Tank");
    }

    g_bTankSpawning = false;
    return Plugin_Stop;
}

bool HasPlayerControlledTank()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 3)
            {
                int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (zClass == 8)
                {
                    return true;
                }
            }
        }
    }
    return false;
}

int SelectRandomSurvivor()
{
    ArrayList survivors = new ArrayList();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 2)
            {
                survivors.Push(i);
            }
        }
    }

    int selected = -1;
    if (survivors.Length > 0)
    {
        int randomIndex = GetRandomInt(0, survivors.Length - 1);
        selected = survivors.Get(randomIndex);
    }

    delete survivors;
    return selected;
}

int FindTankBot()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 3)
            {
                int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (zClass == 8)
                {
                    return i;
                }
            }
        }
    }
    return -1;
}

void TransformPlayerToTank(int client)
{
    if (!IsClientInGame(client))
        return;

    g_iCurrentTank = client;

    int tankBot = FindTankBot();

    if (tankBot <= 0)
    {
        g_iCurrentTank = -1;
        return;
    }

    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    DataPack data = new DataPack();
    data.WriteCell(GetClientUserId(client));
    data.WriteCell(tankBot);
    data.WriteFloat(vPos[0]);
    data.WriteFloat(vPos[1]);
    data.WriteFloat(vPos[2]);
    data.WriteFloat(vAng[0]);
    data.WriteFloat(vAng[1]);
    data.WriteFloat(vAng[2]);

    ForcePlayerSuicide(client);
    CreateTimer(0.5, Timer_TakeoverExistingTank, data, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_TakeoverExistingTank(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();
    float vPos[3], vAng[3];
    vPos[0] = data.ReadFloat();
    vPos[1] = data.ReadFloat();
    vPos[2] = data.ReadFloat();
    vAng[0] = data.ReadFloat();
    vAng[1] = data.ReadFloat();
    vAng[2] = data.ReadFloat();

    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        delete data;
        return Plugin_Stop;
    }

    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        tankBot = FindTankBot();
        if (tankBot <= 0)
        {
            g_iCurrentTank = -1;
            delete data;
            return Plugin_Stop;
        }
    }

    ChangeClientTeam(client, 3);
    CreateTimer(0.2, Timer_TakeoverExistingTank_Phase2, data, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_TakeoverExistingTank_Phase2(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        delete data;
        return Plugin_Stop;
    }

    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        tankBot = FindTankBot();
        if (tankBot <= 0)
        {
            g_iCurrentTank = -1;
            delete data;
            return Plugin_Stop;
        }
    }

    L4D_TakeOverZombieBot(client, tankBot);
    delete data;

    // 应用Tank设置
    ApplyTankSettings(client);

    return Plugin_Stop;
}

// ==================== 测试命令 ====================

public Action Command_Test2(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    g_bIsManualTest = true;

    int tankBot = FindTankBot();
    bool needSpawn = false;

    if (tankBot <= 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 正在生成 Tank...");
        float vPos[3], vAng[3];
        GetClientAbsOrigin(client, vPos);
        GetClientAbsAngles(client, vAng);

        tankBot = L4D2_SpawnTank(vPos, vAng);
        if (tankBot <= 0)
        {
            ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ Tank 生成失败");
            g_bIsManualTest = false;
            return Plugin_Handled;
        }
        needSpawn = true;
    }

    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    DataPack data = new DataPack();
    data.WriteCell(GetClientUserId(client));
    data.WriteCell(tankBot);
    data.WriteCell(needSpawn ? 1 : 0);
    data.WriteFloat(vPos[0]);
    data.WriteFloat(vPos[1]);
    data.WriteFloat(vPos[2]);
    data.WriteFloat(vAng[0]);
    data.WriteFloat(vAng[1]);
    data.WriteFloat(vAng[2]);

    ForcePlayerSuicide(client);

    float delay = needSpawn ? 2.0 : 1.5;
    CreateTimer(delay, Timer_Test2_Takeover, data, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Timer_Test2_Takeover(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();
    int needSpawn = data.ReadCell();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client))
    {
        g_bIsManualTest = false;
        delete data;
        return Plugin_Stop;
    }

    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ Tank已失效");
        g_bIsManualTest = false;
        delete data;
        return Plugin_Stop;
    }

    int currentTeam = GetClientTeam(client);
    if (currentTeam == 3)
    {
        CreateTimer(0.1, Timer_Test2_TakeoverPhase2, data, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    ChangeClientTeam(client, 3);
    CreateTimer(0.3, Timer_Test2_TakeoverPhase2, data, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_Test2_TakeoverPhase2(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client))
    {
        g_bIsManualTest = false;
        delete data;
        return Plugin_Stop;
    }

    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ Tank已失效");
        g_bIsManualTest = false;
        delete data;
        return Plugin_Stop;
    }

    if (GetClientTeam(client) != 3)
    {
        ChangeClientTeam(client, 3);
        CreateTimer(0.2, Timer_Test2_TakeoverPhase2_Retry, data, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    L4D_TakeOverZombieBot(client, tankBot);
    delete data;

    CreateTimer(0.2, Timer_Test2_Finalize, userid, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_Test2_TakeoverPhase2_Retry(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client))
    {
        g_bIsManualTest = false;
        delete data;
        return Plugin_Stop;
    }

    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ Tank已失效");
        g_bIsManualTest = false;
        delete data;
        return Plugin_Stop;
    }

    L4D_TakeOverZombieBot(client, tankBot);
    delete data;

    CreateTimer(0.2, Timer_Test2_Finalize, userid, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_Test2_Finalize(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client))
    {
        g_bIsManualTest = false;
        return Plugin_Stop;
    }

    // 应用Tank设置
    ApplyTankSettings(client);

    ReplyToCommand(client, "[寄寄之家-ControlTank] ✓ 已转换为 Tank");

    g_bIsManualTest = false;
    return Plugin_Stop;
}

void ApplyTankSettings(int client)
{
    // 设置Tank血量（如果需要）
    int tankHP = g_cvarTankHP.IntValue;
    if (tankHP > 0)
    {
        int currentHP = GetEntProp(client, Prop_Send, "m_iHealth");
        if (currentHP < tankHP)
        {
            SetEntProp(client, Prop_Send, "m_iHealth", tankHP);
            SetEntProp(client, Prop_Send, "m_iMaxHealth", tankHP);
        }
    }

    // 设置初始挫折度为0
    SetEntProp(client, Prop_Send, "m_frustration", 0);
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
