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
bool g_bTankSpawning = false;
int g_iCurrentTank = -1;

public void OnPluginStart()
{
    // 创建ConVar
    g_cvarEnabled = CreateConVar(
        "shan_controltank_enabled",
        "1",
        "是否启用Tank随机选择功能 (1=启用, 0=禁用)",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 1.0
    );

    // 自动生成配置文件
    AutoExecConfig(true, "controltank");

    // 钩住Tank生成事件
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_bot_replace", Event_PlayerBotReplace);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);

    // 注册命令
    RegConsoleCmd("sm_test2", Command_Test2, "测试接管AI Tank");

    PrintToServer("[寄寄之家-ControlTank] 插件已加载!");
}

public void OnMapStart()
{
    g_bTankSpawning = false;
    g_iCurrentTank = -1;
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

// 当玩家被bot替换时（玩家离开，bot接管）
public void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
    int bot = GetClientOfUserId(event.GetInt("bot"));

    if (bot == g_iCurrentTank)
    {
        g_iCurrentTank = -1;
    }
}

// 当bot被玩家替换时（玩家加入，接管bot）
public void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));

    // 如果bot是当前Tank，更新为玩家
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

    if (g_bTankSpawning)
        return;

    g_bTankSpawning = true;
    CreateTimer(0.5, Timer_SelectAndTransformTank, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SelectAndTransformTank(Handle timer)
{
    // 检查是否已经有玩家控制的Tank
    if (HasPlayerControlledTank())
    {
        g_bTankSpawning = false;
        return Plugin_Stop;
    }

    // 不移除 AI Tank，直接选择玩家转换

    // 随机选择一名幸存者玩家
    int targetClient = SelectRandomSurvivor();

    if (targetClient > 0)
    {
        TransformPlayerToTank(targetClient);

        char playerName[MAX_NAME_LENGTH];
        GetClientName(targetClient, playerName, sizeof(playerName));
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01被选中成为 \x04Tank!", playerName);
    }
    else
    {
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01没有找到合适的玩家，将由 AI 控制 Tank");
    }

    g_bTankSpawning = false;
    return Plugin_Stop;
}

// 检查是否有玩家控制的Tank
bool HasPlayerControlledTank()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 3)
            {
                int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (zClass == 8) // Tank
                {
                    return true;
                }
            }
        }
    }
    return false;
}

// 移除所有AI Tank
void RemoveAllAITanks()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 3)
            {
                int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (zClass == 8) // Tank
                {
                    ForcePlayerSuicide(i);
                }
            }
        }
    }
}

// 随机选择一名幸存者玩家
int SelectRandomSurvivor()
{
    ArrayList survivors = new ArrayList();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 2) // 幸存者队伍
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

// 将玩家转换为Tank
void TransformPlayerToTank(int client)
{
    if (!IsClientInGame(client))
        return;

    // 记录当前Tank玩家
    g_iCurrentTank = client;

    PrintToServer("[寄寄之家-ControlTank] 开始接管现有AI Tank");

    // 查找已存在的AI Tank（由tank_spawn事件生成的）
    int tankBot = FindTankBot();

    if (tankBot <= 0)
    {
        PrintToServer("[寄寄之家-ControlTank] 错误：未找到AI Tank，无法转换");
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01未找到 Tank，转换失败");
        g_iCurrentTank = -1;
        return;
    }

    PrintToServer("[寄寄之家-ControlTank] 找到AI Tank，索引: %d", tankBot);

    // 保存玩家当前位置（用于传送）
    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    // 准备数据包
    DataPack data = new DataPack();
    data.WriteCell(GetClientUserId(client));
    data.WriteCell(tankBot);
    data.WriteFloat(vPos[0]);
    data.WriteFloat(vPos[1]);
    data.WriteFloat(vPos[2]);
    data.WriteFloat(vAng[0]);
    data.WriteFloat(vAng[1]);
    data.WriteFloat(vAng[2]);

    // 步骤1：杀死玩家
    PrintToServer("[寄寄之家-ControlTank] 步骤1：杀死玩家");
    ForcePlayerSuicide(client);

    // 步骤2：等待后接管AI Tank
    PrintToServer("[寄寄之家-ControlTank] 创建定时器，延迟 0.5 秒后接管");
    CreateTimer(0.5, Timer_TakeoverExistingTank, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public Action Timer_TakeoverExistingTank(Handle timer, DataPack data)
{
    PrintToServer("[寄寄之家-ControlTank] Timer_TakeoverExistingTank 被调用");

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
        PrintToServer("[寄寄之家-ControlTank] 玩家不在游戏中，中止转换");
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    // 验证AI Tank仍然存在
    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        PrintToServer("[寄寄之家-ControlTank] AI Tank不再有效，查找替代Tank");
        tankBot = FindTankBot();
        if (tankBot <= 0)
        {
            PrintToServer("[寄寄之家-ControlTank] 未找到可用的Tank，转换失败");
            g_iCurrentTank = -1;
            return Plugin_Stop;
        }
    }

    PrintToServer("[寄寄之家-ControlTank] 步骤2：切换到感染者队伍");
    ChangeClientTeam(client, 3);

    PrintToServer("[寄寄之家-ControlTank] 步骤3：接管AI Tank (索引: %d)", tankBot);
    L4D_TakeOverZombieBot(client, tankBot);

    PrintToServer("[寄寄之家-ControlTank] 步骤4：设置血量");
    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 转换完成！当前类别: %d, 存活: %d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));

    return Plugin_Stop;
}

public Action Timer_ConvertToTank(Handle timer, DataPack data)
{
    // 此函数已弃用，保留以避免编译错误
    return Plugin_Stop;
}

public Action Timer_TakeoverTankBot(Handle timer, DataPack data)
{
    // 此函数已弃用，保留以避免编译错误
    return Plugin_Stop;
}

// 查找Tank bot
int FindTankBot()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsFakeClient(i) && IsPlayerAlive(i))
        {
            if (GetClientTeam(i) == 3)
            {
                int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (zClass == 8) // Tank
                {
                    return i;
                }
            }
        }
    }
    return -1;
}

// ==================== 测试方法2：接管现有AI Tank ====================
public Action Command_Test2(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    ReplyToCommand(client, "[寄寄之家-ControlTank] ========== 接管现有AI Tank ==========");

    // 查找现有的AI Tank
    int tankBot = FindTankBot();
    if (tankBot <= 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ 未找到AI Tank");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[寄寄之家-ControlTank] 找到AI Tank (索引: %d)，准备接管...", tankBot);

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

    ReplyToCommand(client, "[寄寄之家-ControlTank] 杀死玩家...");
    ForcePlayerSuicide(client);

    CreateTimer(0.5, Timer_Test2_Takeover, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    return Plugin_Handled;
}

public Action Timer_Test2_Takeover(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int tankBot = data.ReadCell();
    float vPos[3], vAng[3];
    vPos[0] = data.ReadFloat(); vPos[1] = data.ReadFloat(); vPos[2] = data.ReadFloat();
    vAng[0] = data.ReadFloat(); vAng[1] = data.ReadFloat(); vAng[2] = data.ReadFloat();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;

    // 验证AI Tank仍然存在
    if (!IsClientInGame(tankBot) || !IsFakeClient(tankBot) || !IsPlayerAlive(tankBot))
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ AI Tank不再有效");
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 方法2 - 切换队伍");
    ChangeClientTeam(client, 3);

    PrintToServer("[寄寄之家-ControlTank] 方法2 - 接管 AI Tank (索引: %d)", tankBot);
    L4D_TakeOverZombieBot(client, tankBot);

    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 方法2 - 完成，类别:%d 存活:%d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    ReplyToCommand(client, "[寄寄之家-ControlTank] ✓ 转换完成！当前类别: %d, 存活: %d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    return Plugin_Stop;
}

// 检查是否是合作模式
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
