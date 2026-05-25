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
Handle g_hTankSpawnTimer = null;
int g_iTargetClient = -1;  // 目标玩家

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
        "1200",
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

    // 注册测试命令
    RegConsoleCmd("sm_tanktest", Command_TankTest, "测试Tank选择功能");
    RegConsoleCmd("sm_tankdebug", Command_TankDebug, "显示调试信息");

    PrintToServer("[寄寄之家-ControlTank] 插件已加载!");
}

public void OnMapStart()
{
    g_bTankSpawning = false;
}

public void OnMapEnd()
{
    // 清理定时器
    if (g_hTankTimer != null)
    {
        delete g_hTankTimer;
        g_hTankTimer = null;
    }
    if (g_hTankSpawnTimer != null)
    {
        delete g_hTankSpawnTimer;
        g_hTankSpawnTimer = null;
    }
    g_iCurrentTank = -1;
    g_iTargetClient = -1;
}

// 回合结束事件
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    // 清理定时器
    if (g_hTankTimer != null)
    {
        delete g_hTankTimer;
        g_hTankTimer = null;
    }
    if (g_hTankSpawnTimer != null)
    {
        delete g_hTankSpawnTimer;
        g_hTankSpawnTimer = null;
    }
    g_iCurrentTank = -1;
    g_iTargetClient = -1;
}

// 玩家死亡事件
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);

    // 如果当前Tank玩家死亡，清理定时器
    if (client == g_iCurrentTank)
    {
        if (g_hTankTimer != null)
        {
            delete g_hTankTimer;
            g_hTankTimer = null;
        }
        g_iCurrentTank = -1;
    }

    // 如果是目标玩家死亡，触发Tank转换
    if (client == g_iTargetClient)
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 目标玩家死亡，准备转换为Tank");

        // 延迟后转换
        CreateTimer(0.1, Timer_TransformDeadPlayer, userid, TIMER_FLAG_NO_MAPCHANGE);
    }
}

// Tank生成事件
public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    PrintToServer("[寄寄之家-ControlTank] DEBUG: Tank生成事件被触发!");

    // 检查插件是否启用
    if (!g_cvarEnabled.BoolValue)
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 插件未启用");
        return;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 插件已启用");

    // 检查是否是合作模式
    if (!IsCoopMode())
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 不是合作模式");
        return;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 是合作模式");

    // 防止重复触发
    if (g_bTankSpawning)
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 正在处理中，跳过");
        return;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 开始选择玩家...");
    g_bTankSpawning = true;
    CreateTimer(1.0, Timer_SelectTankPlayer, _, TIMER_FLAG_NO_MAPCHANGE);
}

// 延迟选择玩家（避免与AI Tank生成冲突）
public Action Timer_SelectTankPlayer(Handle timer)
{
    PrintToServer("[寄寄之家-ControlTank] DEBUG: Timer_SelectTankPlayer 被调用");

    // 检查是否已经有玩家控制的Tank
    if (HasPlayerTank())
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 已有玩家Tank，跳过");
        g_bTankSpawning = false;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 没有玩家Tank，继续");

    // 随机选择一名玩家变成Tank
    int targetClient = SelectRandomPlayer();
    PrintToServer("[寄寄之家-ControlTank] DEBUG: 目标玩家 = %d", targetClient);

    if (targetClient > 0)
    {
        // 将玩家变成Tank
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 将玩家 %d 变成Tank", targetClient);
        TransformPlayerToTank(targetClient);

        char playerName[MAX_NAME_LENGTH];
        GetClientName(targetClient, playerName, sizeof(playerName));
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01被选中成为 \x04Tank!", playerName);
    }
    else
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 没有找到合适的玩家");
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01没有找到合适的玩家，将由 AI 控制 Tank");
    }

    g_bTankSpawning = false;
    return Plugin_Stop;
}

// 检查是否是合作模式
bool IsCoopMode()
{
    // 获取游戏模式
    ConVar gameMode = FindConVar("mp_gamemode");
    if (gameMode != null)
    {
        char mode[32];
        gameMode.GetString(mode, sizeof(mode));

        // 检查是否是合作模式
        if (StrEqual(mode, "coop", false) || StrEqual(mode, "cooperative", false))
        {
            return true;
        }
    }

    return false;
}

// 检查是否有玩家控制的Tank
bool HasPlayerTank()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i))
        {
            int team = GetClientTeam(i);
            if (team == 3) // 感染者队伍
            {
                int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
                if (zClass == 8) // 8 = Tank
                {
                    return true;
                }
            }
        }
    }
    return false;
}

// 随机选择一名玩家
int SelectRandomPlayer()
{
    ArrayList eligiblePlayers = new ArrayList();

    // 收集所有符合条件的幸存者玩家
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) &&
            IsPlayerAlive(i) &&
            !IsFakeClient(i) &&
            GetClientTeam(i) == 2) // 2 = 幸存者队伍
        {
            char name[64];
            GetClientName(i, name, sizeof(name));
            PrintToServer("[寄寄之家-ControlTank] DEBUG: 找到符合条件的玩家: %s (%d)", name, i);
            eligiblePlayers.Push(i);
        }
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 找到 %d 个符合条件的玩家", eligiblePlayers.Length);

    int selected = -1;

    if (eligiblePlayers.Length > 0)
    {
        // 随机选择
        int randomIndex = GetRandomInt(0, eligiblePlayers.Length - 1);
        selected = eligiblePlayers.Get(randomIndex);
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 随机选择了索引 %d，玩家 %d", randomIndex, selected);
    }

    delete eligiblePlayers;
    return selected;
}

// 将玩家变成Tank
void TransformPlayerToTank(int client)
{
    if (!IsClientInGame(client))
    {
        return;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: TransformPlayerToTank 开始，玩家 %d", client);

    // 清理之前的定时器
    if (g_hTankTimer != null)
    {
        delete g_hTankTimer;
        g_hTankTimer = null;
    }
    if (g_hTankSpawnTimer != null)
    {
        delete g_hTankSpawnTimer;
        g_hTankSpawnTimer = null;
    }

    // 覆盖原版沮丧值系统
    int timeSeconds = g_cvarTime.IntValue;
    ConVar frustrationCvar = FindConVar("z_frustration_lifetime");
    if (frustrationCvar != null)
    {
        if (timeSeconds > 0)
        {
            frustrationCvar.SetInt(timeSeconds);
            PrintToServer("[寄寄之家-ControlTank] DEBUG: 设置沮丧值为 %d 秒", timeSeconds);
        }
        else
        {
            frustrationCvar.SetInt(0);
            PrintToServer("[寄寄之家-ControlTank] DEBUG: 禁用沮丧值系统");
        }
    }

    // 步骤1: 设置目标玩家
    g_iTargetClient = client;
    PrintToServer("[寄寄之家-ControlTank] DEBUG: 步骤1: 设置目标玩家为 %d", client);

    // 步骤2: 杀死玩家（触发死亡事件）
    ForcePlayerSuicide(client);
    PrintToServer("[寄寄之家-ControlTank] DEBUG: 步骤2: 玩家已杀死，等待死亡事件");
}

// 转换已死亡的玩家为Tank
public Action Timer_TransformDeadPlayer(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 玩家已离开");
        g_iTargetClient = -1;
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 步骤3: 生成AI Tank");

    // 生成AI Tank
    ServerCommand("z_spawn tank auto");
    PrintToServer("[寄寄之家-ControlTank] DEBUG: z_spawn tank auto 已执行");

    // 延迟后让玩家接管AI Tank
    CreateTimer(1.0, Timer_TakeOverTank, userid, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Stop;
}

// 让玩家接管AI Tank
public Action Timer_TakeOverTank(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iTargetClient = -1;
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 步骤4: 查找AI Tank");

    // 查找AI Tank
    int tankBot = -1;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
        {
            int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
            if (zClass == 8 && IsFakeClient(i))  // AI Tank
            {
                tankBot = i;
                break;
            }
        }
    }

    if (tankBot == -1)
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 未找到AI Tank");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01未找到AI Tank，转换失败");
        g_iTargetClient = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 找到AI Tank: %d", tankBot);

    // 使用left4dhooks让玩家接管AI Tank
    PrintToServer("[寄寄之家-ControlTank] DEBUG: 使用 L4D_TakeOverZombieBot");
    L4D_TakeOverZombieBot(client, tankBot);

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 玩家已接管AI Tank");

    // 延迟后验证
    CreateTimer(0.3, Timer_VerifyTankSpawn, userid, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Stop;
}

// 验证Tank生成并完成设置
public Action Timer_VerifyTankSpawn(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iTargetClient = -1;
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    bool isAlive = IsPlayerAlive(client);
    int team = GetClientTeam(client);
    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 验证结果 - 存活: %d, 队伍: %d, 类别: %d", isAlive, team, zClass);

    if (isAlive && team == 3 && zClass == 8)
    {
        // 成功成为Tank
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 成功！玩家已变为Tank");

        g_iCurrentTank = client;
        g_iTargetClient = -1;

        // 设置Tank血量
        SetEntProp(client, Prop_Send, "m_iHealth", 4000);
        SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

        // 获取控制权时间
        int timeSeconds = g_cvarTime.IntValue;

        // 显示提示信息
        if (timeSeconds > 0)
        {
            char playerName[MAX_NAME_LENGTH];
            GetClientName(client, playerName, sizeof(playerName));
            PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04%d \x01秒的Tank控制时间！", timeSeconds);
            g_hTankTimer = CreateTimer(float(timeSeconds), Timer_TankTimeExpired, userid, TIMER_FLAG_NO_MAPCHANGE);
        }
        else
        {
            PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04无限制\x01 的Tank控制时间!");
        }
    }
    else if (!isAlive && team == 3 && zClass == 8)
    {
        // 玩家在感染者队伍，是Tank类别，但是死亡状态
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 玩家已死亡，尝试强制复活");

        // 强制设置为存活状态
        SetEntProp(client, Prop_Send, "m_lifeState", 1);  // LIFE_ALIVE
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 已设置m_lifeState为1");

        // 再次验证
        CreateTimer(0.1, Timer_FinalVerify, userid, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 转换失败，状态不符预期");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01转换失败，请重试");
        g_iTargetClient = -1;
    }

    return Plugin_Stop;
}

// 最终验证
public Action Timer_FinalVerify(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iTargetClient = -1;
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    bool isAlive = IsPlayerAlive(client);
    int team = GetClientTeam(client);
    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");

    PrintToServer("[寄寄之家-ControlTank] DEBUG: 最终验证 - 存活: %d, 队伍: %d, 类别: %d", isAlive, team, zClass);

    if (isAlive && team == 3 && zClass == 8)
    {
        // 成功！
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 强制复活成功！");

        g_iCurrentTank = client;
        g_iTargetClient = -1;

        // 设置Tank血量
        SetEntProp(client, Prop_Send, "m_iHealth", 4000);
        SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

        // 获取控制权时间
        int timeSeconds = g_cvarTime.IntValue;

        // 显示提示信息
        if (timeSeconds > 0)
        {
            char playerName[MAX_NAME_LENGTH];
            GetClientName(client, playerName, sizeof(playerName));
            PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04%d \x01秒的Tank控制时间！", timeSeconds);
            g_hTankTimer = CreateTimer(float(timeSeconds), Timer_TankTimeExpired, userid, TIMER_FLAG_NO_MAPCHANGE);
        }
        else
        {
            PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04无限制\x01 的Tank控制时间!");
        }
    }
    else
    {
        PrintToServer("[寄寄之家-ControlTank] DEBUG: 强制复活也失败了");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01转换失败，respawn命令在L4D2中可能不生效");
        g_iTargetClient = -1;
    }

    return Plugin_Stop;
}

// Tank控制时间到期回调
public Action Timer_TankTimeExpired(Handle timer, any userid)
{
    g_hTankTimer = null;

    int client = GetClientOfUserId(userid);

    // 检查玩家是否还在游戏中
    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    // 检查玩家是否还是Tank
    int team = GetClientTeam(client);
    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");

    if (team == 3 && zClass == 8 && IsPlayerAlive(client))
    {
        char playerName[MAX_NAME_LENGTH];
        GetClientName(client, playerName, sizeof(playerName));

        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01的Tank控制时间已到期！", playerName);

        // 剥夺Tank控制权 - 杀死玩家Tank
        ForcePlayerSuicide(client);

        g_iCurrentTank = -1;
    }
    else
    {
        g_iCurrentTank = -1;
    }

    return Plugin_Stop;
}

// 测试命令：手动触发Tank选择
public Action Command_TankTest(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    // 检查插件是否启用
    if (!g_cvarEnabled.BoolValue)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 插件未启用，请先启用插件");
        return Plugin_Handled;
    }

    // 检查玩家是否在游戏中
    if (!IsClientInGame(client))
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 你不在游戏中");
        return Plugin_Handled;
    }

    // 检查玩家是否是幸存者
    if (GetClientTeam(client) != 2)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 你必须在幸存者队伍才能测试");
        return Plugin_Handled;
    }

    // 检查是否已有玩家Tank
    if (HasPlayerTank())
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 已经有玩家控制的Tank，无法测试");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[寄寄之家-ControlTank] 正在测试Tank选择...");

    // 直接将玩家变成Tank
    TransformPlayerToTank(client);

    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));
    PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01被选中成为 \x04Tank! (测试)", playerName);

    return Plugin_Handled;
}

// 调试命令：显示插件状态
public Action Command_TankDebug(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    // 显示插件状态
    ReplyToCommand(client, "========== [寄寄之家-ControlTank] 调试信息 ==========");
    ReplyToCommand(client, "插件状态: %s", g_cvarEnabled.BoolValue ? "✓ 启用" : "✗ 禁用");
    ReplyToCommand(client, "控制时间: %d 秒", g_cvarTime.IntValue);
    ReplyToCommand(client, "当前Tank玩家: %s", g_iCurrentTank > 0 ? "有" : "无");
    ReplyToCommand(client, "正在处理: %s", g_bTankSpawning ? "是" : "否");
    ReplyToCommand(client, "定时器运行: %s", g_hTankTimer != null ? "是" : "否");
    ReplyToCommand(client, "是否合作模式: %s", IsCoopMode() ? "是" : "否");
    ReplyToCommand(client, "有玩家Tank: %s", HasPlayerTank() ? "是" : "否");

    // 显示玩家信息
    ReplyToCommand(client, "---------- 玩家信息 ----------");
    ReplyToCommand(client, "你的队伍: %d (1=观察, 2=幸存, 3=感染)", GetClientTeam(client));
    ReplyToCommand(client, "是否存活: %s", IsPlayerAlive(client) ? "是" : "否");
    ReplyToCommand(client, "是否在游戏: %s", IsClientInGame(client) ? "是" : "否");

    // 显示服务器信息
    ConVar gameMode = FindConVar("mp_gamemode");
    if (gameMode != null)
    {
        char mode[32];
        gameMode.GetString(mode, sizeof(mode));
        ReplyToCommand(client, "游戏模式: %s", mode);
    }

    ReplyToCommand(client, "====================================");

    return Plugin_Handled;
}
