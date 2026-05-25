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

    // 注册测试命令
    RegConsoleCmd("sm_tankdebug", Command_TankDebug, "显示调试信息");
    RegConsoleCmd("sm_tankspawn", Command_TankSpawn, "测试生成Tank");

    // 多种转换方法测试命令
    RegConsoleCmd("sm_test1", Command_Test1, "方法1: 直接转换");
    RegConsoleCmd("sm_test2", Command_Test2, "方法2: L4D2_SpawnTank + 接管");
    RegConsoleCmd("sm_test3", Command_Test3, "方法3: z_spawn + 接管");
    RegConsoleCmd("sm_test4", Command_Test4, "方法4: L4D_ReplaceTank");
    RegConsoleCmd("sm_test5", Command_Test5, "方法5: L4D_ReplaceWithBot + 接管");
    RegConsoleCmd("sm_test6", Command_Test6, "方法6: 复活后设置类别");

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

    PrintToServer("[寄寄之家-ControlTank] 开始直接转换方法");

    // 保存玩家当前位置
    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    // 准备数据包
    DataPack data = new DataPack();
    data.WriteCell(GetClientUserId(client));
    data.WriteFloat(vPos[0]);
    data.WriteFloat(vPos[1]);
    data.WriteFloat(vPos[2]);
    data.WriteFloat(vAng[0]);
    data.WriteFloat(vAng[1]);
    data.WriteFloat(vAng[2]);

    // 步骤1：杀死玩家
    PrintToServer("[寄寄之家-ControlTank] 步骤1：杀死玩家");
    ForcePlayerSuicide(client);

    // 步骤2：等待后直接转换（单一定时器完成所有操作）
    PrintToServer("[寄寄之家-ControlTank] 创建定时器，延迟 1.0 秒后转换");
    CreateTimer(1.0, Timer_ConvertToTank, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public Action Timer_ConvertToTank(Handle timer, DataPack data)
{
    PrintToServer("[寄寄之家-ControlTank] Timer_ConvertToTank 被调用");

    data.Reset();
    int userid = data.ReadCell();
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

    PrintToServer("[寄寄之家-ControlTank] 步骤2：玩家已死亡，开始转换流程");

    // 步骤3：使用 L4D2_SpawnTank 生成一个 Tank bot
    PrintToServer("[寄寄之家-ControlTank] 步骤3：生成 Tank bot");
    int tankBot = L4D2_SpawnTank(vPos, vAng);

    if (tankBot > 0)
    {
        PrintToServer("[寄寄之家-ControlTank] Tank bot 生成成功，索引: %d", tankBot);

        // 等待 bot 生成完成
        CreateTimer(0.5, Timer_TakeoverTankBot, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    }
    else
    {
        PrintToServer("[寄寄之家-ControlTank] Tank bot 生成失败，尝试备用方法");

        // 备用方法：切换到感染者队伍并设置类别
        PrintToServer("[寄寄之家-ControlTank] 步骤4：切换到感染者队伍");
        ChangeClientTeam(client, 3);

        PrintToServer("[寄寄之家-ControlTank] 步骤5：复活玩家");
        L4D_RespawnPlayer(client);

        PrintToServer("[寄寄之家-ControlTank] 步骤6：使用 L4D_SetClass 设置为 Tank");
        L4D_SetClass(client, 8);

        vPos[2] += 50.0;
        PrintToServer("[寄寄之家-ControlTank] 步骤7：传送到位置 (%.2f, %.2f, %.2f)", vPos[0], vPos[1], vPos[2]);
        TeleportEntity(client, vPos, vAng, NULL_VECTOR);

        PrintToServer("[寄寄之家-ControlTank] 步骤8：实体化");
        L4D_BecomeGhost(client);
        L4D_MaterializeFromGhost(client);

        PrintToServer("[寄寄之家-ControlTank] 步骤9：设置血量");
        SetEntProp(client, Prop_Send, "m_iHealth", 4000);
        SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

        PrintToServer("[寄寄之家-ControlTank] 转换完成，当前类别: %d, 存活: %d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    }

    return Plugin_Stop;
}

public Action Timer_TakeoverTankBot(Handle timer, DataPack data)
{
    PrintToServer("[寄寄之家-ControlTank] Timer_TakeoverTankBot 被调用");

    data.Reset();
    int userid = data.ReadCell();
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

    // 查找 Tank bot
    int tankBot = FindTankBot();

    if (tankBot <= 0)
    {
        PrintToServer("[寄寄之家-ControlTank] 错误：未找到 Tank bot");
        g_iCurrentTank = -1;
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 步骤4：找到 Tank bot，索引: %d", tankBot);

    // 切换到感染者队伍
    PrintToServer("[寄寄之家-ControlTank] 步骤5：切换到感染者队伍");
    ChangeClientTeam(client, 3);

    // 接管 Tank bot
    PrintToServer("[寄寄之家-ControlTank] 步骤6：接管 Tank bot");
    L4D_TakeOverZombieBot(client, tankBot);

    // 设置 Tank 血量
    PrintToServer("[寄寄之家-ControlTank] 步骤7：设置血量");
    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 转换完成，当前类别: %d, 存活: %d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));

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
    ReplyToCommand(client, "当前Tank: %s", g_iCurrentTank > 0 ? "有" : "无");
    ReplyToCommand(client, "正在处理: %s", g_bTankSpawning ? "是" : "否");
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

// ==================== 测试方法1：直接转换 ====================
public Action Command_Test1(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    ReplyToCommand(client, "[寄寄之家-ControlTank] ========== 方法1：直接转换 ==========");

    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    ReplyToCommand(client, "[寄寄之家-ControlTank] 杀死玩家...");
    ForcePlayerSuicide(client);

    DataPack data = new DataPack();
    data.WriteCell(GetClientUserId(client));
    data.WriteFloat(vPos[0]);
    data.WriteFloat(vPos[1]);
    data.WriteFloat(vPos[2]);
    data.WriteFloat(vAng[0]);
    data.WriteFloat(vAng[1]);
    data.WriteFloat(vAng[2]);

    CreateTimer(1.0, Timer_Test1_Convert, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    return Plugin_Handled;
}

public Action Timer_Test1_Convert(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    float vPos[3], vAng[3];
    vPos[0] = data.ReadFloat(); vPos[1] = data.ReadFloat(); vPos[2] = data.ReadFloat();
    vAng[0] = data.ReadFloat(); vAng[1] = data.ReadFloat(); vAng[2] = data.ReadFloat();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;

    PrintToServer("[寄寄之家-ControlTank] 方法1 - 步骤1：切换队伍");
    ChangeClientTeam(client, 3);

    PrintToServer("[寄寄之家-ControlTank] 方法1 - 步骤2：复活");
    L4D_RespawnPlayer(client);

    PrintToServer("[寄寄之家-ControlTank] 方法1 - 步骤3：设置类别");
    L4D_SetClass(client, 8);

    vPos[2] += 50.0;
    PrintToServer("[寄寄之家-ControlTank] 方法1 - 步骤4：传送");
    TeleportEntity(client, vPos, vAng, NULL_VECTOR);

    PrintToServer("[寄寄之家-ControlTank] 方法1 - 步骤5：实体化");
    L4D_BecomeGhost(client);
    L4D_MaterializeFromGhost(client);

    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 方法1 - 完成，类别:%d 存活:%d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    return Plugin_Stop;
}

// ==================== 测试方法2：L4D2_SpawnTank + 接管 ====================
public Action Command_Test2(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    ReplyToCommand(client, "[寄寄之家-ControlTank] ========== 方法2：L4D2_SpawnTank + 接管 ==========");

    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    ReplyToCommand(client, "[寄寄之家-ControlTank] 生成 Tank bot...");
    int tankBot = L4D2_SpawnTank(vPos, vAng);

    if (tankBot > 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] Tank bot 生成成功，索引: %d", tankBot);
        CreateTimer(0.5, Timer_Test2_Takeover, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ Tank bot 生成失败");
    }

    return Plugin_Handled;
}

public Action Timer_Test2_Takeover(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;

    int tankBot = FindTankBot();
    if (tankBot <= 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ 未找到 Tank bot");
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 方法2 - 切换队伍");
    ChangeClientTeam(client, 3);

    PrintToServer("[寄寄之家-ControlTank] 方法2 - 接管 Tank bot");
    L4D_TakeOverZombieBot(client, tankBot);

    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 方法2 - 完成，类别:%d 存活:%d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    return Plugin_Stop;
}

// ==================== 测试方法3：z_spawn + 接管 ====================
public Action Command_Test3(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    ReplyToCommand(client, "[寄寄之家-ControlTank] ========== 方法3：z_spawn + 接管 ==========");

    ReplyToCommand(client, "[寄寄之家-ControlTank] 使用 z_spawn 生成 Tank...");
    ServerCommand("z_spawn tank auto");

    CreateTimer(1.0, Timer_Test3_Takeover, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Timer_Test3_Takeover(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;

    int tankBot = FindTankBot();
    if (tankBot <= 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ 未找到 Tank bot");
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 方法3 - 切换队伍");
    ChangeClientTeam(client, 3);

    PrintToServer("[寄寄之家-ControlTank] 方法3 - 接管 Tank bot");
    L4D_TakeOverZombieBot(client, tankBot);

    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 方法3 - 完成，类别:%d 存活:%d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    return Plugin_Stop;
}

// ==================== 测试方法4：L4D_ReplaceTank ====================
public Action Command_Test4(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    ReplyToCommand(client, "[寄寄之家-ControlTank] ========== 方法4：L4D_ReplaceTank ==========");

    int tankBot = FindTankBot();
    if (tankBot <= 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ 未找到 Tank bot，请先用 sm_test3 生成");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[寄寄之家-ControlTank] 使用 L4D_ReplaceTank 替换...");
    L4D_ReplaceTank(tankBot, client);

    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 方法4 - 完成，类别:%d 存活:%d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    return Plugin_Handled;
}

// ==================== 测试方法5：L4D_ReplaceWithBot + 接管 ====================
public Action Command_Test5(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    ReplyToCommand(client, "[寄寄之家-ControlTank] ========== 方法5：L4D_ReplaceWithBot + 接管 ==========");

    ReplyToCommand(client, "[寄寄之家-ControlTank] 替换为 bot...");
    L4D_ReplaceWithBot(client);

    CreateTimer(0.5, Timer_Test5_Convert, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Timer_Test5_Convert(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;

    int tankBot = FindTankBot();
    if (tankBot <= 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ 未找到 Tank bot，先生成...");
        ServerCommand("z_spawn tank auto");
        CreateTimer(1.0, Timer_Test5_Takeover, userid, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 方法5 - 找到 Tank bot: %d", tankBot);
    CreateTimer(0.1, Timer_Test5_Takeover, userid, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_Test5_Takeover(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;

    int tankBot = FindTankBot();
    if (tankBot <= 0)
    {
        ReplyToCommand(client, "[寄寄之家-ControlTank] ✗ 未找到 Tank bot");
        return Plugin_Stop;
    }

    PrintToServer("[寄寄之家-ControlTank] 方法5 - 切换队伍");
    ChangeClientTeam(client, 3);

    PrintToServer("[寄寄之家-ControlTank] 方法5 - 接管 Tank bot");
    L4D_TakeOverZombieBot(client, tankBot);

    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 方法5 - 完成，类别:%d 存活:%d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
    return Plugin_Stop;
}

// ==================== 测试方法6：复活后设置类别 ====================
public Action Command_Test6(int client, int args)
{
    if (client == 0) return Plugin_Handled;
    if (!IsClientInGame(client)) return Plugin_Handled;

    ReplyToCommand(client, "[寄寄之家-ControlTank] ========== 方法6：复活后设置类别 ==========");

    float vPos[3], vAng[3];
    GetClientAbsOrigin(client, vPos);
    GetClientAbsAngles(client, vAng);

    ReplyToCommand(client, "[寄寄之家-ControlTank] 杀死玩家...");
    ForcePlayerSuicide(client);

    DataPack data = new DataPack();
    data.WriteCell(GetClientUserId(client));
    data.WriteFloat(vPos[0]);
    data.WriteFloat(vPos[1]);
    data.WriteFloat(vPos[2]);
    data.WriteFloat(vAng[0]);
    data.WriteFloat(vAng[1]);
    data.WriteFloat(vAng[2]);

    CreateTimer(1.0, Timer_Test6_Convert, data, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    return Plugin_Handled;
}

public Action Timer_Test6_Convert(Handle timer, DataPack data)
{
    data.Reset();
    int userid = data.ReadCell();
    float vPos[3], vAng[3];
    vPos[0] = data.ReadFloat(); vPos[1] = data.ReadFloat(); vPos[2] = data.ReadFloat();
    vAng[0] = data.ReadFloat(); vAng[1] = data.ReadFloat(); vAng[2] = data.ReadFloat();

    int client = GetClientOfUserId(userid);
    if (!IsClientInGame(client)) return Plugin_Stop;

    PrintToServer("[寄寄之家-ControlTank] 方法6 - 步骤1：复活");
    L4D_RespawnPlayer(client);

    PrintToServer("[寄寄之家-ControlTank] 方法6 - 步骤2：切换队伍");
    ChangeClientTeam(client, 3);

    PrintToServer("[寄寄之家-ControlTank] 方法6 - 步骤3：设置类别");
    L4D_SetClass(client, 8);

    vPos[2] += 50.0;
    PrintToServer("[寄寄之家-ControlTank] 方法6 - 步骤4：传送");
    TeleportEntity(client, vPos, vAng, NULL_VECTOR);

    PrintToServer("[寄寄之家-ControlTank] 方法6 - 步骤5：实体化");
    L4D_BecomeGhost(client);
    L4D_MaterializeFromGhost(client);

    SetEntProp(client, Prop_Send, "m_iHealth", 4000);
    SetEntProp(client, Prop_Send, "m_iMaxHealth", 4000);

    PrintToServer("[寄寄之家-ControlTank] 方法6 - 完成，类别:%d 存活:%d", GetEntProp(client, Prop_Send, "m_zombieClass"), IsPlayerAlive(client));
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
