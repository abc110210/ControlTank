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
ConVar g_cvarTime;
bool g_bTankSpawning = false;
Handle g_hTankTimer = null;
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

    g_cvarTime = CreateConVar(
        "shan_controltank_time",
        "0",
        "Tank控制权时间（单位：秒，设置为0时无限制）",
        FCVAR_NOTIFY,
        true, 0.0,
        true, 9999.0
    );

    // 自动生成配置文件
    AutoExecConfig(true, "controltank");

    // 钩住Tank生成事件
    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_bot_replace", Event_PlayerBotReplace);
    HookEvent("bot_player_replace", Event_BotPlayerReplace);

    // 注册测试命令
    RegConsoleCmd("sm_tanktest", Command_TankTest, "测试Tank选择功能");
    RegConsoleCmd("sm_tankdebug", Command_TankDebug, "显示调试信息");

    PrintToServer("[寄寄之家-ControlTank] 插件已加载!");
}

public void OnMapStart()
{
    g_bTankSpawning = false;
    g_iCurrentTank = -1;
}

public void OnMapEnd()
{
    if (g_hTankTimer != null)
    {
        delete g_hTankTimer;
        g_hTankTimer = null;
    }
    g_iCurrentTank = -1;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    if (g_hTankTimer != null)
    {
        delete g_hTankTimer;
        g_hTankTimer = null;
    }
    g_iCurrentTank = -1;
    g_bTankSpawning = false;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client == g_iCurrentTank)
    {
        if (g_hTankTimer != null)
        {
            delete g_hTankTimer;
            g_hTankTimer = null;
        }
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

    // 移除所有AI Tank
    RemoveAllAITanks();

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

    // 清理之前的定时器
    if (g_hTankTimer != null)
    {
        delete g_hTankTimer;
        g_hTankTimer = null;
    }

    // 记录当前Tank玩家
    g_iCurrentTank = client;

    // 获取控制权时间
    int timeSeconds = g_cvarTime.IntValue;

    // 覆盖原版沮丧值系统
    ConVar frustrationCvar = FindConVar("z_frustration_lifetime");
    if (frustrationCvar != null)
    {
        if (timeSeconds > 0)
        {
            frustrationCvar.SetInt(timeSeconds);
        }
        else
        {
            frustrationCvar.SetInt(0);
        }
    }

    // 使用left4dhooks直接转换玩家为Tank
    L4D_ReplaceWithBot(client); // 将玩家替换为bot（玩家进入幽灵模式）

    CreateTimer(0.3, Timer_SpawnTankForPlayer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SpawnTankForPlayer(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    // 生成AI Tank
    int tank = L4D2_SpawnTank(NULL_VECTOR, NULL_VECTOR);

    if (tank > 0)
    {
        // 找到刚生成的Tank bot
        int tankBot = FindTankBot();

        if (tankBot > 0)
        {
            // 让玩家接管这个Tank bot
            L4D_TakeOverZombieBot(client, tankBot);

            // 设置Tank血量
            SetEntProp(client, Prop_Send, "m_iHealth", 4000);
            SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

            // 显示控制时间信息
            int timeSeconds = g_cvarTime.IntValue;
            if (timeSeconds > 0)
            {
                PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04%d \x01秒的Tank控制时间！", timeSeconds);
                g_hTankTimer = CreateTimer(float(timeSeconds), Timer_TankTimeExpired, userid, TIMER_FLAG_NO_MAPCHANGE);
            }
            else
            {
                PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04无限制\x01 的Tank控制时间!");
            }

            PrintToServer("[寄寄之家-ControlTank] 成功将玩家 %d 转换为Tank", client);
        }
        else
        {
            PrintToServer("[寄寄之家-ControlTank] 警告：未找到Tank bot");
            PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01转换失败，未找到Tank bot");
            g_iCurrentTank = -1;
        }
    }
    else
    {
        PrintToServer("[寄寄之家-ControlTank] 警告：L4D2_SpawnTank 失败");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01转换失败，无法生成Tank");
        g_iCurrentTank = -1;
    }

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

public Action Timer_TankTimeExpired(Handle timer, int userid)
{
    g_hTankTimer = null;

    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    if (IsPlayerAlive(client) && GetClientTeam(client) == 3)
    {
        int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        if (zClass == 8)
        {
            char playerName[MAX_NAME_LENGTH];
            GetClientName(client, playerName, sizeof(playerName));
            PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01的Tank控制时间已到期！", playerName);

            ForcePlayerSuicide(client);
            g_iCurrentTank = -1;
        }
    }
    else
    {
        g_iCurrentTank = -1;
    }

    return Plugin_Stop;
}

// 测试命令
public Action Command_TankTest(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    if (!g_cvarEnabled.BoolValue)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 插件未启用");
        return Plugin_Handled;
    }

    if (!IsClientInGame(client))
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 你不在游戏中");
        return Plugin_Handled;
    }

    if (GetClientTeam(client) != 2)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 你必须在幸存者队伍");
        return Plugin_Handled;
    }

    // 重置状态
    g_bTankSpawning = false;
    g_iCurrentTank = -1;

    ReplyToCommand(client, "[寄寄之家-ControlTank] 正在测试Tank转换...");
    TransformPlayerToTank(client);

    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));
    PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01被选中成为 \x04Tank! (测试)", playerName);

    return Plugin_Handled;
}

// 调试命令
public Action Command_TankDebug(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "========== [寄寄之家-ControlTank] 调试信息 ==========");
    ReplyToCommand(client, "插件状态: %s", g_cvarEnabled.BoolValue ? "✓ 启用" : "✗ 禁用");
    ReplyToCommand(client, "控制时间: %d 秒", g_cvarTime.IntValue);
    ReplyToCommand(client, "当前Tank: %s", g_iCurrentTank > 0 ? "有" : "无");
    ReplyToCommand(client, "正在处理: %s", g_bTankSpawning ? "是" : "否");
    ReplyToCommand(client, "定时器运行: %s", g_hTankTimer != null ? "是" : "否");
    ReplyToCommand(client, "是否合作模式: %s", IsCoopMode() ? "是" : "否");
    ReplyToCommand(client, "有玩家Tank: %s", HasPlayerControlledTank() ? "是" : "否");

    ReplyToCommand(client, "---------- 所有玩家 ----------");
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            char name[MAX_NAME_LENGTH];
            GetClientName(i, name, sizeof(name));
            int team = GetClientTeam(i);
            bool alive = IsPlayerAlive(i);
            bool fake = IsFakeClient(i);
            int zClass = (team == 3) ? GetEntProp(i, Prop_Send, "m_zombieClass") : 0;

            ReplyToCommand(client, "[%d] %s - 队伍:%d 存活:%d 假人:%d 类别:%d",
                i, name, team, alive, fake, zClass);
        }
    }
    ReplyToCommand(client, "====================================");

    return Plugin_Handled;
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
