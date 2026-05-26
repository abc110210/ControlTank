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
    RegConsoleCmd("sm_tankinfo", Command_TankInfo, "显示Tank配置信息");
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
    if (tank > 0 && tank <= MaxClients && IsClientInGame(tank) && !IsFakeClient(tank))
    {
        int frustrationTime = g_cvarTankFrustrationTime.IntValue;
        PrintToServer("[ControlTank] L4D_OnSetTankFrustration - Tank: %N, 配置: %d, 设置值: %d", tank, frustrationTime, frustration);

        // 0 = 禁用挫折度系统（永久控制）
        // 1 = 启用默认挫折度系统
        if (frustrationTime == 0)
        {
            frustration = 0;
            PrintToServer("[ControlTank] 配置为0，强制挫折度=0，返回Plugin_Changed");
            return Plugin_Changed;  // 告诉引擎我们修改了值
        }
        else
        {
            PrintToServer("[ControlTank] 配置为1，返回Plugin_Continue使用默认值");
        }
    }

    return Plugin_Continue;  // 使用默认行为
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

    char playerInfo[64], botInfo[64], tankInfo[64];
    if (player > 0 && player <= MaxClients && IsClientInGame(player))
    {
        Format(playerInfo, sizeof(playerInfo), "%N", player);
    }
    else
    {
        Format(playerInfo, sizeof(playerInfo), "invalid(%d)", player);
    }

    if (bot > 0 && bot <= MaxClients && IsClientInGame(bot))
    {
        Format(botInfo, sizeof(botInfo), "%N", bot);
    }
    else
    {
        Format(botInfo, sizeof(botInfo), "invalid(%d)", bot);
    }

    if (g_iCurrentTank > 0 && g_iCurrentTank <= MaxClients && IsClientInGame(g_iCurrentTank))
    {
        Format(tankInfo, sizeof(tankInfo), "%N", g_iCurrentTank);
    }
    else
    {
        Format(tankInfo, sizeof(tankInfo), "invalid(%d)", g_iCurrentTank);
    }

    PrintToServer("[ControlTank] player_bot_replace - 玩家: %s, Bot: %s, 当前Tank: %s", playerInfo, botInfo, tankInfo);

    // 当玩家被bot替换时（玩家失去Tank控制权）
    if (player == g_iCurrentTank)
    {
        PrintToServer("[ControlTank] 检测到Tank玩家被替换，重置g_iCurrentTank");
        g_iCurrentTank = -1;

        // 将玩家放回幸存者阵营（死亡状态，可被复活）
        if (player > 0 && player <= MaxClients && IsClientInGame(player))
        {
            int currentTeam = GetClientTeam(player);
            PrintToServer("[ControlTank] 玩家当前队伍: %d, 准备切换到队伍2(幸存者)", currentTeam);
            ChangeClientTeam(player, 2);

            PrintToServer("[ControlTank] 已调用ChangeClientTeam，创建定时器检查玩家状态");
            CreateTimer(0.1, Timer_EnsurePlayerDead, GetClientUserId(player), TIMER_FLAG_NO_MAPCHANGE);
        }
        else
        {
            PrintToServer("[ControlTank] 玩家索引无效，跳过队伍切换");
        }
    }
    else
    {
        PrintToServer("[ControlTank] 被替换的玩家不是当前Tank，跳过处理");
    }
}

public Action Timer_EnsurePlayerDead(Handle timer, int userid)
{
    int player = GetClientOfUserId(userid);

    if (player <= 0 || player > MaxClients || !IsClientInGame(player))
    {
        PrintToServer("[ControlTank] 玩家不在游戏中，中止");
        return Plugin_Stop;
    }

    char playerName[MAX_NAME_LENGTH];
    GetClientName(player, playerName, sizeof(playerName));
    PrintToServer("[ControlTank] Timer_EnsurePlayerDead 触发 - 玩家: %s", playerName);

    int team = GetClientTeam(player);
    bool alive = IsPlayerAlive(player);
    PrintToServer("[ControlTank] 玩家状态 - 队伍: %d, 存活: %d", team, alive);

    // 如果玩家不在幸存者队伍，先切换过去
    if (team != 2)
    {
        PrintToServer("[ControlTank] 玩家不在幸存者队伍(当前:%d)，切换到队伍2", team);
        ChangeClientTeam(player, 2);

        // 再次检查并确保死亡
        CreateTimer(0.1, Timer_EnsurePlayerDead_Final, userid, TIMER_FLAG_NO_MAPCHANGE);
    }
    else if (alive)
    {
        // 如果玩家在幸存者队伍但还活着，杀死他
        PrintToServer("[ControlTank] 玩家在幸存者队伍且存活，执行 ForcePlayerSuicide");
        ForcePlayerSuicide(player);
        PrintToServer("[ControlTank] ForcePlayerSuicide 完成");
    }
    else
    {
        PrintToServer("[ControlTank] 玩家已在幸存者队伍且死亡，无需处理");
    }

    PrintToServer("[ControlTank] 处理完成");
    return Plugin_Stop;
}

public Action Timer_EnsurePlayerDead_Final(Handle timer, int userid)
{
    int player = GetClientOfUserId(userid);

    if (player <= 0 || player > MaxClients || !IsClientInGame(player))
    {
        PrintToServer("[ControlTank] Final: 玩家不在游戏中，中止");
        return Plugin_Stop;
    }

    char playerName[MAX_NAME_LENGTH];
    GetClientName(player, playerName, sizeof(playerName));
    PrintToServer("[ControlTank] Timer_EnsurePlayerDead_Final 触发 - 玩家: %s", playerName);

    int team = GetClientTeam(player);
    bool alive = IsPlayerAlive(player);
    PrintToServer("[ControlTank] Final状态 - 队伍: %d, 存活: %d", team, alive);

    // 最终确认：确保玩家在幸存者队伍且是死亡状态
    if (team != 2)
    {
        PrintToServer("[ControlTank] Final警告: 玩家仍不在幸存者队伍(队伍:%d)", team);
    }
    else if (alive)
    {
        PrintToServer("[ControlTank] Final: 玩家仍存活，执行 ForcePlayerSuicide");
        ForcePlayerSuicide(player);
    }
    else
    {
        PrintToServer("[ControlTank] Final: 玩家状态正确(队伍2, 死亡)");
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

    // 根据配置设置挫折度
    int frustrationTime = g_cvarTankFrustrationTime.IntValue;
    if (frustrationTime == 0)
    {
        // 禁用挫折度系统（永久控制）
        SetEntProp(client, Prop_Send, "m_frustration", 0);
    }
    // 如果配置为1，不设置挫折度，让游戏使用默认系统
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

public Action Command_TankInfo(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "========== [寄寄之家-ControlTank] 配置信息 ==========");
    ReplyToCommand(client, "插件启用: %s", g_cvarEnabled.BoolValue ? "是" : "否");
    ReplyToCommand(client, "Tank血量: %d", g_cvarTankHP.IntValue);
    ReplyToCommand(client, "挫折度系统: %s", g_cvarTankFrustrationTime.IntValue == 0 ? "关闭 (永久控制)" : "开启 (系统默认)");
    ReplyToCommand(client, "当前Tank: %s", g_iCurrentTank > 0 ? "有" : "无");
    if (g_iCurrentTank > 0 && IsClientInGame(g_iCurrentTank))
    {
        char name[MAX_NAME_LENGTH];
        GetClientName(g_iCurrentTank, name, sizeof(name));
        ReplyToCommand(client, "Tank玩家: %s", name);
    }
    ReplyToCommand(client, "====================================");

    return Plugin_Handled;
}
