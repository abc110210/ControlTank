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
    version = "2.0.0",
    url = ""
};

ConVar g_cvarEnabled;
ConVar g_cvarTankHP;
ConVar g_cvarFrustrationEnabled;

bool g_bTankSpawning = false;
bool g_bIsManualTest = false;
float g_fLastTankSpawnTime = 0.0;
bool g_bPlayerLostControl = false;

// AFK检测
float g_fLastActivityTime[MAXPLAYERS + 1];

public void OnPluginStart()
{
    g_cvarEnabled = CreateConVar("shan_controltank_enabled", "1", "是否启用Tank随机选择功能", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvarTankHP = CreateConVar("shan_controltank_hp", "4000", "Tank血量设置", FCVAR_NOTIFY, true, 1.0, true, 120000.0);
    g_cvarFrustrationEnabled = CreateConVar("shan_controltank_frustration", "1", "Tank挫折度系统(0=关闭/永久控制, 1=开启)", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    AutoExecConfig(true, "controltank");
    HookConVarChange(g_cvarTankHP, OnConVarChanged);
    HookConVarChange(g_cvarFrustrationEnabled, OnConVarChanged);

    HookEvent("tank_spawn", Event_TankSpawn);
    HookEvent("round_end", Event_RoundEnd);
    HookEvent("player_bot_replace", Event_PlayerBotReplace);

    RegConsoleCmd("sm_test2", Command_Test, "测试接管AI Tank");
    RegConsoleCmd("sm_tankinfo", Command_TankInfo, "显示Tank配置信息");

    CreateTimer(5.0, Timer_CheckAFK, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPostAdminCheck(int client)
{
    if (IsClientInGame(client) && !IsFakeClient(client))
    {
        g_fLastActivityTime[client] = GetGameTime();
    }
}

public void OnClientDisconnect(int client)
{
    g_fLastActivityTime[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client))
    {
        if (buttons != 0 || vel[0] != 0.0 || vel[1] != 0.0)
        {
            g_fLastActivityTime[client] = GetGameTime();
        }
    }
    return Plugin_Continue;
}

public Action Timer_CheckAFK(Handle timer)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            float pos[3];
            GetClientAbsOrigin(i, pos);

            float lastPos[3];
            GetEntPropVector(i, Prop_Send, "m_vecOrigin", lastPos);

            if (GetVectorDistance(lastPos, pos) > 10.0)
            {
                g_fLastActivityTime[i] = GetGameTime();
            }
        }
    }
    return Plugin_Continue;
}

public void OnMapStart()
{
    g_bTankSpawning = false;
    g_fLastTankSpawnTime = 0.0;
    g_bPlayerLostControl = false;
    ApplyServerSettings();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar == g_cvarTankHP)
    {
        ApplyServerSettings();
    }
    else if (convar == g_cvarFrustrationEnabled)
    {
        UpdateTankFrustration();
    }
}

public Action L4D_OnSetTankFrustration(int tank, int &frustration)
{
    if (tank > 0 && tank <= MaxClients && IsClientInGame(tank) && !IsFakeClient(tank))
    {
        if (!g_cvarFrustrationEnabled.BoolValue)
        {
            frustration = 0;
            return Plugin_Changed;
        }
    }
    return Plugin_Continue;
}

void ApplyServerSettings()
{
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

void UpdateTankFrustration()
{
    int tank = FindCurrentTank();
    if (tank > 0 && IsClientInGame(tank))
    {
        if (g_cvarFrustrationEnabled.BoolValue)
        {
            SetEntProp(tank, Prop_Send, "m_frustration", 0);
            SetEntProp(tank, Prop_Send, "m_frustrationRemaining", 100);
        }
        else
        {
            SetEntProp(tank, Prop_Send, "m_frustration", 0);
            SetEntProp(tank, Prop_Send, "m_frustrationRemaining", 0);
        }
    }
}

public void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    int bot = GetClientOfUserId(event.GetInt("bot"));

    if (FindCurrentTank() == player && player > 0 && IsClientInGame(player))
    {
        // 检查bot是否还活着
        if (bot > 0 && bot <= MaxClients && IsClientInGame(bot) && IsPlayerAlive(bot))
        {
            // 玩家失去控制权，设置标志跳过下一次tank_spawn
            g_bPlayerLostControl = true;
        }

        // 只切换阵营，其他交给系统处理
        ChangeClientTeam(player, 2);
    }
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_bTankSpawning = false;
    g_bPlayerLostControl = false;
}

public void Event_TankSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_cvarEnabled.BoolValue || !IsCoopMode() || g_bIsManualTest || g_bTankSpawning)
        return;

    // 如果玩家刚失去控制权，跳过这次tank_spawn事件（防止循环）
    if (g_bPlayerLostControl)
    {
        g_bPlayerLostControl = false; // 重置标志，下次tank_spawn正常处理
        return;
    }

    // 防止重复生成Tank：10秒内只处理一次tank_spawn事件
    float currentTime = GetGameTime();
    if (currentTime - g_fLastTankSpawnTime < 10.0)
        return;

    g_fLastTankSpawnTime = currentTime;
    g_bTankSpawning = true;
    CreateTimer(0.5, Timer_SelectTank, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_SelectTank(Handle timer)
{
    if (HasPlayerTank())
    {
        g_bTankSpawning = false;
        return Plugin_Stop;
    }

    int target = SelectSurvivor();
    if (target > 0)
    {
        TransformToTank(target);
        char name[MAX_NAME_LENGTH];
        GetClientName(target, name, sizeof(name));
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01玩家 \x04%s \x01被选中成为 \x04Tank", name);
    }
    else
    {
        PrintToChatAll("\x03[寄寄之家-ControlTank] \x01Tank失去控制权，将由 \x04AI \x01控制");
    }

    g_bTankSpawning = false;
    return Plugin_Stop;
}

bool HasPlayerTank()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
        {
            if (GetEntProp(i, Prop_Send, "m_zombieClass") == 8)
                return true;
        }
    }
    return false;
}

int FindCurrentTank()
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

bool IsPlayerAFK(int client)
{
    if (g_fLastActivityTime[client] == 0.0)
    {
        g_fLastActivityTime[client] = GetGameTime();
        return false;
    }
    return (GetGameTime() - g_fLastActivityTime[client]) > 60.0;
}

int SelectSurvivor()
{
    ArrayList survivors = new ArrayList();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
        {
            if (!IsPlayerAFK(i))
                survivors.Push(i);
        }
    }

    int selected = -1;
    if (survivors.Length > 0)
    {
        selected = survivors.Get(GetRandomInt(0, survivors.Length - 1));
    }
    else
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
                survivors.Push(i);
        }
        if (survivors.Length > 0)
            selected = survivors.Get(GetRandomInt(0, survivors.Length - 1));
    }

    delete survivors;
    return selected;
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

void TransformToTank(int client)
{
    if (!IsClientInGame(client))
        return;

    int tankBot = FindTankBot();
    if (tankBot <= 0)
        return;

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
        tankBot = FindTankBot();
        if (tankBot <= 0)
        {
            delete data;
            return Plugin_Stop;
        }
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

    g_bPlayerLostControl = false; // 玩家成功接管Tank，重置标志
    ApplyTankSettings(client);
    return Plugin_Stop;
}

void ApplyTankSettings(int client)
{
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

    if (g_cvarFrustrationEnabled.BoolValue)
    {
        SetEntProp(client, Prop_Send, "m_frustration", 0);
        SetEntProp(client, Prop_Send, "m_frustrationRemaining", 100);
    }
    else
    {
        SetEntProp(client, Prop_Send, "m_frustration", 0);
        SetEntProp(client, Prop_Send, "m_frustrationRemaining", 0);
    }
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

public Action Command_Test(int client, int args)
{
    if (client == 0 || !IsClientInGame(client))
        return Plugin_Handled;

    g_bIsManualTest = true;

    int tankBot = FindTankBot();
    bool needSpawn = false;

    if (tankBot <= 0)
    {
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
    CreateTimer(delay, Timer_TestTakeover, data, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Handled;
}

public Action Timer_TestTakeover(Handle timer, DataPack data)
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

    if (GetClientTeam(client) != 3)
        ChangeClientTeam(client, 3);

    CreateTimer(0.3, Timer_TestTakeoverPhase2, data, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_TestTakeoverPhase2(Handle timer, DataPack data)
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

    g_bPlayerLostControl = false; // 玩家成功接管Tank，重置标志
    ApplyTankSettings(client);
    ReplyToCommand(client, "[寄寄之家-ControlTank] ✓ 已转换为 Tank");

    g_bIsManualTest = false;
    return Plugin_Stop;
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
    ReplyToCommand(client, "挫折度系统: %s", g_cvarFrustrationEnabled.BoolValue ? "开启" : "关闭 (永久控制)");

    int currentTank = FindCurrentTank();
    if (currentTank > 0 && IsClientInGame(currentTank))
    {
        ReplyToCommand(client, "当前Tank: 有");
        char name[MAX_NAME_LENGTH];
        GetClientName(currentTank, name, sizeof(name));
        ReplyToCommand(client, "Tank玩家: %s", name);
    }
    else
    {
        ReplyToCommand(client, "当前Tank: 无");
    }

    ReplyToCommand(client, "====================================");

    return Plugin_Handled;
}
