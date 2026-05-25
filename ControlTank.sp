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
    RegConsoleCmd("sm_tankspawn", Command_TankSpawn, "测试生成Tank");

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

    PrintToServer("[寄寄之家-ControlTank] 开始转换流程...");

    // 保存玩家当前位置
    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    // 步骤1：生成 AI Tank
    PrintToServer("[寄寄之家-ControlTank] 步骤1：生成 AI Tank");
    int tank = L4D2_SpawnTank(NULL_VECTOR, NULL_VECTOR);

    if (tank <= 0)
    {
        PrintToServer("[寄寄之家-ControlTank] 错误：生成 Tank 失败");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01生成 Tank 失败");
        g_iCurrentTank = -1;
        return;
    }

    PrintToServer("[寄寄之家-ControlTank] Tank 实体: %d", tank);

    // 步骤2：等待 Tank 完全生成
    CreateTimer(0.5, Timer_ReplaceTank, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ReplaceTank(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    // 查找 Tank bot
    int tankBot = FindTankBot();

    if (tankBot <= 0)
    {
        PrintToServer("[寄寄之家-ControlTank] 错误：未找到 Tank bot");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01未找到 Tank bot");
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 步骤2：找到 Tank bot: %d, 玩家: %d", tankBot, client);

    // 传送到 Tank 位置
    float vPos[3], vAng[3];
    GetClientAbsOrigin(tankBot, vPos);
    GetClientAbsAngles(tankBot, vAng);
    TeleportEntity(client, vPos, vAng, NULL_VECTOR);

    // 步骤3：使用 L4D_ReplaceTank 直接替换
    PrintToServer("[寄寄之家-ControlTank] 步骤3：调用 L4D_ReplaceTank(%d, %d)", tankBot, client);
    L4D_ReplaceTank(tankBot, client);

    // 等待验证
    CreateTimer(0.3, Timer_VerifyTakeover, userid, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Stop;
}

public Action Timer_SpawnAndTakeover(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int timeSeconds = data.ReadCell();

    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 步骤3：使用 z_spawn 生成 Tank");

    // 使用 z_spawn 命令生成 Tank（这样生成的 bot 更容易被接管）
    ServerCommand("z_spawn tank auto");

    // 等待 Tank 生成后接管，创建新的 DataPack
    DataPack takeoverData = new DataPack();
    takeoverData.WriteCell(userid);
    takeoverData.WriteCell(timeSeconds);
    CreateTimer(1.0, Timer_TakeoverTank, takeoverData, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);

    return Plugin_Stop;
}

public Action Timer_TakeoverTank(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int timeSeconds = data.ReadCell();

    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 开始查找 Tank bot...");

    // 查找AI Tank bot
    int tankBot = FindTankBot();

    PrintToServer("[寄寄之家-ControlTank] FindTankBot 返回: %d", tankBot);

    if (tankBot > 0)
    {
        PrintToServer("[寄寄之家-ControlTank] 找到 Tank bot，开始接管流程...");

    // 直接开始接管流程（不使用 L4D_ReplaceWithBot）
    DataPack takeoverData = new DataPack();
    takeoverData.WriteCell(userid);
    takeoverData.WriteCell(timeSeconds);
    takeoverData.WriteCell(tankBot);  // 保存 Tank bot 的索引
    CreateTimer(0.1, Timer_TakeoverZombieBot, takeoverData, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    }
    else
    {
        PrintToServer("[寄寄之家-ControlTank] 第一次未找到 Tank bot，1秒后重试...");
        // 重试一次
        DataPack retryData = new DataPack();
        retryData.WriteCell(userid);
        retryData.WriteCell(timeSeconds);
        retryData.WriteCell(1);  // 重试次数
        CreateTimer(1.0, Timer_RetryTakeover, retryData, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    }

    return Plugin_Stop;
}

public Action Timer_TakeoverZombieBot(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int timeSeconds = data.ReadCell();
    int tankBot = data.ReadCell();

    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] Tank bot: %d, 客户端: %d", tankBot, client);

    // 检查 Tank bot 是否还存活
    if (!IsClientInGame(tankBot) || !IsPlayerAlive(tankBot))
    {
        PrintToServer("[寄寄之家-ControlTank] 错误：Tank bot 已无效");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01转换失败，Tank bot 已无效");
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 玩家当前队伍: %d, 存活: %d", GetClientTeam(client), IsPlayerAlive(client));

    // 如果玩家还在幸存者队伍，需要先替换
    if (GetClientTeam(client) == 2)
    {
        PrintToServer("[寄寄之家-ControlTank] 玩家在幸存者队伍，执行替换...");

        // 先传送到 Tank 位置
        float vPos[3], vAng[3];
        GetClientAbsOrigin(tankBot, vPos);
        GetClientAbsAngles(tankBot, vAng);
        TeleportEntity(client, vPos, vAng, NULL_VECTOR);

        // 使用 L4D_ReplaceTank 直接替换
        PrintToServer("[寄寄之家-ControlTank] 调用 L4D_ReplaceTank(%d, %d)", tankBot, client);
        L4D_ReplaceTank(tankBot, client);
    }
    else if (GetClientTeam(client) == 1)
    {
        // 玩家在观察者模式
        PrintToServer("[寄寄之家-ControlTank] 玩家在观察者模式，切换到感染者队伍...");

        // 切换到感染者队伍
        ChangeClientTeam(client, 3);

        // 设置为 Tank 类别
        L4D_SetClass(client, 8);

        // 实体化
        L4D_MaterializeFromGhost(client);

        // 接管 Tank
        L4D_TakeOverZombieBot(client, tankBot);
    }
    else
    {
        // 玩家已经在感染者队伍
        PrintToServer("[寄寄之家-ControlTank] 玩家在感染者队伍，直接接管...");
        L4D_TakeOverZombieBot(client, tankBot);
    }

    // 等待接管完成
    CreateTimer(0.5, Timer_VerifyTakeover, userid, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Stop;
}

public Action Timer_RetryTakeover(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    int timeSeconds = data.ReadCell();
    int retryCount = data.ReadCell();

    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 重试第 %d 次，查找 Tank bot...", retryCount);

    int tankBot = FindTankBot();

    if (tankBot > 0)
    {
        PrintToServer("[寄寄之家-ControlTank] 重试成功，找到 Tank bot");

        // 直接开始接管流程
        DataPack takeoverData = new DataPack();
        takeoverData.WriteCell(userid);
        takeoverData.WriteCell(timeSeconds);
        takeoverData.WriteCell(tankBot);  // 保存 Tank bot 索引
        CreateTimer(0.1, Timer_TakeoverZombieBot, takeoverData, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    }
    else if (retryCount < 3)
    {
        PrintToServer("[寄寄之家-ControlTank] 重试失败，再试一次...");
        DataPack retryData = new DataPack();
        retryData.WriteCell(userid);
        retryData.WriteCell(timeSeconds);
        retryData.WriteCell(retryCount + 1);
        CreateTimer(1.0, Timer_RetryTakeover, retryData, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    }
    else
    {
        PrintToServer("[寄寄之家-ControlTank] 错误：多次重试后仍未找到 Tank bot");
        PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01转换失败，未找到 Tank bot");
        g_iCurrentTank = -1;
    }

    return Plugin_Stop;
}

public Action Timer_VerifyTakeover(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (!IsClientInGame(client))
    {
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    // 验证玩家是否已经成为 Tank
    if (GetClientTeam(client) == 3 && IsPlayerAlive(client))
    {
        int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
        if (zClass == 8)
        {
            PrintToServer("[寄寄之家-ControlTank] 验证成功，玩家已成为 Tank");

            // 设置Tank血量
            SetEntProp(client, Prop_Send, "m_iHealth", 4000);
            SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

            // 获取控制时间
            int timeSeconds = g_cvarTime.IntValue;

            // 显示控制时间信息
            if (timeSeconds > 0)
            {
                PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04%d \x01秒的Tank控制时间！", timeSeconds);
                g_hTankTimer = CreateTimer(float(timeSeconds), Timer_TankTimeExpired, userid, TIMER_FLAG_NO_MAPCHANGE);
            }
            else
            {
                PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01你有 \x04无限制\x01 的Tank控制时间!");
            }

            return Plugin_Stop;
        }
    }

    PrintToServer("[寄寄之家-ControlTank] 警告：接管验证失败");
    PrintToChat(client, "\x04[寄寄之家-ControlTank] \x01转换可能失败，请检查");
    g_iCurrentTank = -1;
    return Plugin_Stop;
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

// 生成 Tank 测试命令
public Action Command_TankSpawn(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] 此命令只能由玩家使用");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[寄寄之家-ControlTank] 正在生成 Tank...");

    // 使用 NULL_VECTOR 让游戏自动选择生成位置
    int tank = L4D2_SpawnTank(NULL_VECTOR, NULL_VECTOR);

    ReplyToCommand(client, "[寄寄之家-ControlTank] L4D2_SpawnTank 返回: %d", tank);

    if (tank > 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✓ Tank 实体创建成功 (索引: %d)", tank);
    }
    else
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ Tank 实体创建失败");

        // 尝试使用 z_spawn 作为备用方法
        ReplyToCommand(client, "[寄寄之家-ControlTank] 尝试备用方法: z_spawn tank");
        ServerCommand("z_spawn tank");
    }

    // 等待后检查
    CreateTimer(1.0, Timer_CheckTankSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Handled;
}

public Action Timer_CheckTankSpawn(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (client > 0 && IsClientInGame(client))
    {
        int tankBot = FindTankBot();
        ReplyToCommand(client, "[寄寄之家-ControlTank] Tank bot 查找结果: %d", tankBot);

        if (tankBot > 0)
        {
            ReplyToCommand(client, "[寄寄之家-ControlTank] ✓ Tank 生成成功！Tank bot 索引: %d", tankBot);
        }
        else
        {
            ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ Tank 生成失败或未找到");

            // 列出所有感染者 bot
            ReplyToCommand(client, "---------- 感染者列表 ----------");
            for (int i = 1; i <= MaxClients; i++)
            {
                if (IsClientInGame(i) && IsFakeClient(i))
                {
                    if (GetClientTeam(i) == 3)
                    {
                        int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
                        char className[16];
                        switch (zClass)
                        {
                            case 1: className = "Smoker";
                            case 2: className = "Boomer";
                            case 3: className = "Hunter";
                            case 4: className = "Spitter";
                            case 5: className = "Jockey";
                            case 6: className = "Charger";
                            case 7: className = "未使用";
                            case 8: className = "Tank";
                            default: className = "未知";
                        }
                        ReplyToCommand(client, "[%d] %s - 存活:%d", i, className, IsPlayerAlive(i));
                    }
                }
            }
        }
    }

    return Plugin_Stop;
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
