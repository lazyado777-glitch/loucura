-- ============================================================
--  VOID.LAZY v4.0 | Slayers 2 | MOBILE FIX EDITION
--  Delta Executor Compatible | Crash-proof | Anti-ban
--  Senha: leyzepidao
--  NOVIDADES v4.0:
--    + Auto Quest + Farm integrado (state machine)
--    + Seletor de arma do inventário (Soco/Espada/etc)
--    + Hitbox Y slider: bate por cima, do lado, ABAIXO DO CHÃO
--    + Agrupar mobs (puxa todos pra perto de uma vez)
--    + Presets de posição rápidos
-- ============================================================

task.wait(2)

local OK, ERR = pcall(function()

-- ============================================================
-- [1] SERVICES
-- ============================================================
local function gs(name)
    local ok, svc = pcall(game.GetService, game, name)
    return ok and svc or nil
end

local Players    = gs("Players")
local RunService = gs("RunService")
local TweenService = gs("TweenService")
local UIS        = gs("UserInputService")
local RS         = gs("ReplicatedStorage")
local TS         = gs("TeleportService")
local WS         = workspace

local LP = Players and Players.LocalPlayer
if not LP then return end

local function getCam()  return workspace.CurrentCamera end
local function rnd(a,b) return a + math.random()*(b-a) end

local function tw(obj, props, dur, style, dir)
    if not obj or not obj.Parent then return end
    local ok, t = pcall(TweenService.Create, TweenService, obj,
        TweenInfo.new(dur or 0.25,
            style or Enum.EasingStyle.Quad,
            dir   or Enum.EasingDirection.Out), props)
    if ok and t then t:Play() end
    return t
end

local function getChar() return LP and (LP.Character or LP.CharacterAdded:Wait()) end
local function getHRP()
    local c = LP and LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = LP and LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

-- ============================================================
-- [2] ESTADO GLOBAL
-- ============================================================
local ST = {
    -- Farm
    AutoFarm     = false, AutoBoss     = false,
    AutoMastery  = false, AutoQuest    = false,
    AutoDungeon  = false, AutoFishing  = false,
    AutoClanSpin = false, AutoSkills   = true,
    FreezeTarget = true,  AntiIdle     = true,
    -- Quest integrado (NOVO)
    AutoQuestFarm = false,
    QuestNPCName  = "Krue",
    -- Hitbox / posição (NOVO)
    HitboxOffsetY = 4,      -- -150 = abaixo do chão, 0 = normal, 50 = acima
    HitboxOffsetX = 0,      -- offset lateral
    -- Arma (NOVO)
    WeaponName    = "Auto", -- "Auto" usa o que estiver equipado
    -- Agrupamento (NOVO)
    GroupMobs     = false,
    GroupInterval = 2,
    -- ESP
    ESP_Mob      = false, ESP_Boss  = false, ESP_Player = false,
    -- Movimento
    Fly          = false, Speed     = false,
    NoClip       = false, InfiniteJump = false,
    -- Anti
    AntiDetect   = true,
    -- Alvos
    TargetMob    = "Greater Demon",
    TargetBoss   = "Zuko",
    MaxLevel     = 400,
    SpeedVal     = 60,
    FlySpeedVal  = 90,
    -- Interno
    Connections  = {},
    ESPCache     = {},
    FlyGyro      = nil,
    FlyBody      = nil,
    Notify       = nil,
}

-- Estado da quest (separado para não poluir ST)
local QST = {
    state      = "IDLE",  -- IDLE | ACCEPT | FARMING | TURN_IN
    npcModel   = nil,
    mobName    = "",
    killsNeeded = 0,
    killsDone  = 0,
    lastNotify = 0,
}

-- ============================================================
-- [3] ANTI-DETECÇÃO
-- ============================================================
local AD = { on = true }

function AD:wait(base)
    if self.on then
        task.wait(base + (math.random()*2-1)*(base*0.2))
    else
        task.wait(base)
    end
end

function AD:drift()
    if not self.on then return end
    local hrp = getHRP()
    if hrp then
        pcall(function()
            hrp.CFrame = hrp.CFrame * CFrame.new(
                (math.random()-.5)*.5, 0, (math.random()-.5)*.5)
        end)
    end
end

function AD:safeTP(pos)
    local hrp = getHRP()
    if not hrp then return end
    if self.on then
        local o = hrp.Position
        for i = 1, math.random(4,6) do
            pcall(function()
                hrp.CFrame = CFrame.new(o:Lerp(pos + Vector3.new(0,4,0), i/6))
            end)
            task.wait(0.04)
        end
    else
        pcall(function() hrp.CFrame = CFrame.new(pos + Vector3.new(0,4,0)) end)
    end
end

-- ============================================================
-- [4] DATABASE — SLAYERS 2
-- ============================================================
local MOBS = {
    "Bandit","Greater Demon","Bear","Mother Bear",
    "Demon","Mushroom Demon","Spider Demon","Zagan Demon",
    "Frozen Demon","Wind Demon","Stone Golem","Blood Demon",
    "Dungeon Demon",
}

local BOSSES = {
    {N="Zuko",        Lv=7,  Zone="Starter Village", Drop="Cutlass 20%"},
    {N="Mother Bear", Lv=18, Zone="Bear Area",        Drop="Bear Pelt"},
    {N="Rengu",       Lv=30, Zone="Mistfall Village", Drop="Flame Katana 5%"},
    {N="Zentaro",     Lv=28, Zone="Thunder Cliffs",   Drop="Thunder Katana 5%"},
    {N="Giyen",       Lv=32, Zone="Bamboo Grove",     Drop="Water Katana 5%"},
    {N="Saneri",      Lv=35, Zone="Iceveil Valley",   Drop="Wind Katana 5%"},
    {N="Shinora",     Lv=38, Zone="Butterfly Estate", Drop="Insect Katana 5%"},
    {N="Obari",       Lv=36, Zone="Starter Cliffs",   Drop="Serpent Katana 5%"},
    {N="Gyorei",      Lv=40, Zone="Stone Sanctuary",  Drop="Stone Katana 5%"},
    {N="Tengai",      Lv=42, Zone="Iceveil Valley",   Drop="Sound Katana 5%"},
}

local ZONES = {
    "Starter Village","Bear Area","Bamboo Grove","Spider Forest",
    "Mistfall Village","Butterfly Estate","Stone Sanctuary",
    "Iceveil Valley","Thunder Cliffs","Ouwigahara Dungeon",
}

-- Tabela de quests conhecidas do Slayers 2
-- NPC = quem aceita/entrega | Mob = o que matar | Kills = quantidade
local QUESTS = {
    {NPC="Krue",      Mob="Bandit",        Kills=8,  Zone="Starter Village"},
    {NPC="Tom",       Mob="Greater Demon", Kills=10, Zone="Starter Village"},
    {NPC="Crow",      Mob="Bear",          Kills=6,  Zone="Bear Area"},
    {NPC="Crow",      Mob="Mother Bear",   Kills=3,  Zone="Bear Area"},
    {NPC="Muzan",     Mob="Demon",         Kills=12, Zone="Mistfall Village"},
    {NPC="Quest",     Mob="Mushroom Demon",Kills=10, Zone="Bamboo Grove"},
    {NPC="Quest",     Mob="Spider Demon",  Kills=10, Zone="Spider Forest"},
    {NPC="Quest",     Mob="Zagan Demon",   Kills=8,  Zone="Mistfall Village"},
    {NPC="Quest",     Mob="Frozen Demon",  Kills=8,  Zone="Iceveil Valley"},
    {NPC="Quest",     Mob="Wind Demon",    Kills=8,  Zone="Thunder Cliffs"},
    {NPC="Quest",     Mob="Stone Golem",   Kills=6,  Zone="Stone Sanctuary"},
    {NPC="Quest",     Mob="Blood Demon",   Kills=6,  Zone="Stone Sanctuary"},
}

-- Nomes de NPCs de quest únicos para dropdown
local QUEST_NPC_NAMES = {}
do
    local seen = {}
    for _, q in ipairs(QUESTS) do
        if not seen[q.NPC] then
            seen[q.NPC] = true
            table.insert(QUEST_NPC_NAMES, q.NPC)
        end
    end
end

-- ============================================================
-- [5] COMBAT HELPERS
-- ============================================================
local function findMob(name)
    local hrp = getHRP()
    if not hrp then return nil end
    local best, bd = nil, math.huge

    local function check(v)
        if not v:IsA("Model") then return end
        if not v.Name:lower():find(name:lower()) then return end
        local root = v:FindFirstChild("HumanoidRootPart") or v.PrimaryPart
        local hum  = v:FindFirstChildOfClass("Humanoid")
        if root and hum and hum.Health > 0 then
            local d = (hrp.Position - root.Position).Magnitude
            if d < bd then best, bd = v, d end
        end
    end

    for _, v in ipairs(WS:GetDescendants()) do pcall(check, v) end
    return best
end

local function findAllMobs(name)
    local list = {}
    for _, v in ipairs(WS:GetDescendants()) do
        pcall(function()
            if not v:IsA("Model") then return end
            if not v.Name:lower():find(name:lower()) then return end
            local root = v:FindFirstChild("HumanoidRootPart") or v.PrimaryPart
            local hum  = v:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                table.insert(list, v)
            end
        end)
    end
    return list
end

local function freezeModel(m)
    if not m or not ST.FreezeTarget then return end
    pcall(function()
        local h = m:FindFirstChildOfClass("Humanoid")
        local r = m:FindFirstChild("HumanoidRootPart")
        if h then h.WalkSpeed = 0; h.JumpPower = 0 end
        if r then r.AssemblyLinearVelocity = Vector3.zero end
    end)
end

local function fireAttack(target)
    if not target then return end
    pcall(function()
        local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
        if not root then return end

        local cd = target:FindFirstChildOfClass("ClickDetector")
        if cd then pcall(fireclickdetector, cd) end

        for _, pp in ipairs(target:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then pcall(fireproximityprompt, pp) end
        end

        local char = LP and LP.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
        if tool then
            local act = tool:FindFirstChild("Activate")
            if act then pcall(function() act:Fire() end) end
        end

        if RS then
            for _, rfn in ipairs({"Events","Remotes","RE","RF"}) do
                local rf = RS:FindFirstChild(rfn)
                if rf then
                    for _, ch in ipairs(rf:GetDescendants()) do
                        if ch:IsA("RemoteEvent") then
                            local n = ch.Name:lower()
                            if n:find("attack") or n:find("hit") or n:find("damage") then
                                pcall(function() ch:FireServer(target, root.Position) end)
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- randPos ATUALIZADO — usa HitboxOffsetY e HitboxOffsetX
local function randPos(target, v)
    v = v or 1.5
    local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
    if not root then return Vector3.zero end
    return root.Position + Vector3.new(
        ST.HitboxOffsetX + (math.random()-.5)*v*2,
        ST.HitboxOffsetY,
        (math.random()-.5)*v*2)
end

-- ============================================================
-- [6] GROUPING — agrupa mobs do alvo ao redor do char  (NOVO)
-- ============================================================
local function groupMobs()
    local hrp = getHRP()
    if not hrp then return 0 end
    local mobs = findAllMobs(ST.TargetMob)
    local count = 0
    for _, mob in ipairs(mobs) do
        local root = mob:FindFirstChild("HumanoidRootPart")
        if root then
            local ang  = (count / math.max(#mobs,1)) * math.pi * 2
            local dist = math.random(1, 3)
            pcall(function()
                root.CFrame = CFrame.new(
                    hrp.Position + Vector3.new(
                        math.cos(ang)*dist, 0, math.sin(ang)*dist))
            end)
            count = count + 1
        end
    end
    return count
end

-- loop que agrupa automaticamente enquanto faz farm
local function loopGroupMobs()
    task.spawn(function()
        while ST.GroupMobs and (ST.AutoFarm or ST.AutoMastery or ST.AutoQuestFarm) do
            pcall(groupMobs)
            task.wait(ST.GroupInterval)
        end
    end)
end

-- ============================================================
-- [7] ARMAS — lista e equipa do inventário  (NOVO)
-- ============================================================
local function listTools()
    local tools = {"Soco (Sem Arma)"}
    local char = LP and LP.Character
    local bp   = LP and LP:FindFirstChild("Backpack")
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") then table.insert(tools, t.Name) end
        end
    end
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") then table.insert(tools, t.Name) end
        end
    end
    return tools
end

local function equipWeapon(name)
    local char = LP and LP.Character
    local bp   = LP and LP:FindFirstChild("Backpack")
    if not char or not bp then return false end
    -- desequipa tudo que o char tiver
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then pcall(function() t.Parent = bp end) end
    end
    if name == "Soco (Sem Arma)" or name == "Auto" then
        return true  -- só desequipou, certo
    end
    -- procura no backpack
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and t.Name == name then
            pcall(function() t.Parent = char end)
            return true
        end
    end
    return false
end

-- ============================================================
-- [8] LOOPS DE FARM
-- ============================================================
local function loopSkills()
    task.spawn(function()
        while ST.AutoSkills and (ST.AutoFarm or ST.AutoBoss or ST.AutoMastery or ST.AutoQuestFarm) do
            pcall(function()
                if RS then
                    for _, rfn in ipairs({"Events","Remotes","RE"}) do
                        local rf = RS:FindFirstChild(rfn)
                        if rf then
                            for _, ch in ipairs(rf:GetDescendants()) do
                                if ch:IsA("RemoteEvent") then
                                    local n = ch.Name:lower()
                                    if n:find("skill") or n:find("ability") or n:find("breath") then
                                        pcall(function() ch:FireServer() end)
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            task.wait(rnd(0.5, 1.5))
        end
    end)
end

local function loopFarm()
    task.spawn(function()
        while ST.AutoFarm do
            pcall(function()
                local hum = getHum()
                if not hum or hum.Health <= 0 then task.wait(3); return end

                local t = findMob(ST.TargetMob)
                if not t then task.wait(1); return end

                local th = t:FindFirstChildOfClass("Humanoid")
                if not th or th.Health <= 0 then return end

                local hrp = getHRP()
                if hrp then hrp.CFrame = CFrame.new(randPos(t)) end
                freezeModel(t)

                local hits = 0
                while ST.AutoFarm and th and th.Health > 0 do
                    freezeModel(t)
                    fireAttack(t)
                    hits = hits + 1
                    if hits % math.random(5,10) == 0 then
                        local h2 = getHRP()
                        if h2 and t.Parent then
                            h2.CFrame = CFrame.new(randPos(t, 2))
                        end
                    end
                    AD:wait(rnd(0.08, 0.18))
                end
            end)
            task.wait(0.05)
        end
    end)
end

local function loopBoss()
    task.spawn(function()
        while ST.AutoBoss do
            pcall(function()
                local t = findMob(ST.TargetBoss)
                if not t then task.wait(rnd(2,4)); return end
                local th = t:FindFirstChildOfClass("Humanoid")
                if not th or th.Health <= 0 then task.wait(1); return end
                local hrp = getHRP()
                if hrp then hrp.CFrame = CFrame.new(randPos(t, 2.5)) end
                freezeModel(t)
                while ST.AutoBoss and th and th.Health > 0 do
                    fireAttack(t)
                    freezeModel(t)
                    local h2 = getHRP()
                    if h2 and t.Parent then h2.CFrame = CFrame.new(randPos(t, 2)) end
                    AD:wait(rnd(0.1, 0.2))
                end
                task.wait(rnd(4,7))
            end)
            task.wait(0.1)
        end
    end)
end

local function loopMastery()
    task.spawn(function()
        while ST.AutoMastery do
            pcall(function()
                local t = findMob(ST.TargetMob)
                if not t then task.wait(1); return end
                local th = t:FindFirstChildOfClass("Humanoid")
                if not th or th.Health <= 0 then return end
                local hrp = getHRP()
                if hrp then hrp.CFrame = CFrame.new(randPos(t)) end
                freezeModel(t)
                while ST.AutoMastery and th and th.Health > 0 do
                    fireAttack(t)
                    freezeModel(t)
                    AD:wait(rnd(0.08, 0.15))
                end
            end)
            task.wait(0.05)
        end
    end)
end

-- AUTO QUEST + FARM — state machine (NOVO)
local function interactNPC(npc)
    if not npc or not npc.Parent then return end
    local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
    if root then
        local hrp = getHRP()
        if hrp then hrp.CFrame = root.CFrame + Vector3.new(0, 3, 3) end
    end
    task.wait(0.3)
    local cd = npc:FindFirstChildOfClass("ClickDetector")
    if cd then pcall(fireclickdetector, cd) end
    for _, pp in ipairs(npc:GetDescendants()) do
        if pp:IsA("ProximityPrompt") then pcall(fireproximityprompt, pp) end
    end
    -- tenta remotes de quest
    if RS then
        for _, rfn in ipairs({"Events","Remotes","RE"}) do
            local rf = RS:FindFirstChild(rfn)
            if rf then
                for _, ch in ipairs(rf:GetDescendants()) do
                    if ch:IsA("RemoteEvent") then
                        local n = ch.Name:lower()
                        if n:find("quest") or n:find("accept") or n:find("claim") or n:find("turn") then
                            pcall(function() ch:FireServer(npc) end)
                        end
                    end
                end
            end
        end
    end
    task.wait(0.5)
end

local function getQuestForNPC(npcName)
    for _, q in ipairs(QUESTS) do
        if q.NPC:lower() == npcName:lower() then return q end
    end
    -- fallback: primeira quest disponível
    return QUESTS[1]
end

local function loopAutoQuestFarm()
    QST.state     = "IDLE"
    QST.killsDone = 0

    task.spawn(function()
        while ST.AutoQuestFarm do
            pcall(function()
                local hum = getHum()
                if not hum or hum.Health <= 0 then task.wait(3); return end

                -- IDLE: encontra o NPC e aceita quest
                if QST.state == "IDLE" then
                    local quest = getQuestForNPC(ST.QuestNPCName)
                    local npc   = findMob(ST.QuestNPCName)
                    if npc then
                        QST.npcModel    = npc
                        QST.mobName     = quest.Mob
                        QST.killsNeeded = quest.Kills
                        QST.killsDone   = 0
                        interactNPC(npc)
                        QST.state = "FARMING"
                        if ST.Notify then
                            ST.Notify("📋 Quest: "..quest.Kills.."x "..quest.Mob, nil, 3)
                        end
                        -- auto-equipa arma se configurado
                        if ST.WeaponName ~= "Auto" then
                            equipWeapon(ST.WeaponName)
                        end
                    else
                        -- NPC não está no mapa, espera
                        task.wait(rnd(3, 6))
                    end

                -- FARMING: mata os mobs do objetivo
                elseif QST.state == "FARMING" then
                    local t = findMob(QST.mobName)
                    if not t then task.wait(1); return end

                    local th = t:FindFirstChildOfClass("Humanoid")
                    if not th or th.Health <= 0 then return end

                    local hrp = getHRP()
                    if hrp then hrp.CFrame = CFrame.new(randPos(t)) end
                    freezeModel(t)

                    -- agrupa outros do mesmo tipo enquanto mata
                    if ST.GroupMobs then pcall(groupMobs) end

                    -- bate até o mob morrer
                    while ST.AutoQuestFarm and th and th.Health > 0 do
                        freezeModel(t)
                        fireAttack(t)
                        AD:wait(rnd(0.08, 0.18))
                    end

                    -- mob morreu — contabiliza
                    QST.killsDone = QST.killsDone + 1

                    -- notifica progresso a cada 3 kills
                    if QST.killsDone % 3 == 0 and ST.Notify then
                        ST.Notify(
                            "⚔ "..QST.killsDone.."/"..QST.killsNeeded.." "..QST.mobName,
                            nil, 1.5)
                    end

                    if QST.killsDone >= QST.killsNeeded then
                        QST.state = "TURN_IN"
                        if ST.Notify then ST.Notify("✓ Objetivo completo! Entregando...", nil, 2.5) end
                    end

                -- TURN_IN: volta ao NPC e entrega
                elseif QST.state == "TURN_IN" then
                    local npc = QST.npcModel
                    -- tenta achar de novo se sumiu
                    if not npc or not npc.Parent then
                        npc = findMob(ST.QuestNPCName)
                    end
                    if npc then
                        interactNPC(npc)
                        task.wait(rnd(1.5, 2.5))
                        if ST.Notify then ST.Notify("✓ Quest entregue! Recomeçando...", nil, 2) end
                    end
                    -- reseta para IDLE independente se achou NPC ou não
                    QST.state     = "IDLE"
                    QST.npcModel  = nil
                    QST.killsDone = 0
                    task.wait(rnd(0.5, 1.5))
                end
            end)
            AD:wait(rnd(0.15, 0.35))
        end
        QST.state = "IDLE"
    end)
end

local function loopQuest()
    task.spawn(function()
        while ST.AutoQuest do
            pcall(function()
                for _, nname in ipairs({"Krue","Tom","Quest","Crow","Muzan"}) do
                    local npc = findMob(nname)
                    if npc then
                        local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
                        if root then
                            local hrp = getHRP()
                            if hrp then hrp.CFrame = root.CFrame + Vector3.new(0,2,3) end
                            local cd = npc:FindFirstChildOfClass("ClickDetector")
                            if cd then pcall(fireclickdetector, cd) end
                            for _, pp in ipairs(npc:GetDescendants()) do
                                if pp:IsA("ProximityPrompt") then pcall(fireproximityprompt, pp) end
                            end
                        end
                    end
                end
            end)
            task.wait(rnd(2,4))
        end
    end)
end

local function loopFishing()
    task.spawn(function()
        while ST.AutoFishing do
            pcall(function()
                if RS then
                    for _, rfn in ipairs({"Events","Remotes","RE"}) do
                        local rf = RS:FindFirstChild(rfn)
                        if rf then
                            for _, ch in ipairs(rf:GetDescendants()) do
                                if ch:IsA("RemoteEvent") and ch.Name:lower():find("fish") then
                                    pcall(function() ch:FireServer() end)
                                end
                            end
                        end
                    end
                end
                local char = LP and LP.Character
                local rod  = char and char:FindFirstChild("Fishing Rod")
                if rod then
                    local act = rod:FindFirstChild("Activate")
                    if act then pcall(function() act:Fire() end) end
                end
            end)
            task.wait(rnd(3,6))
        end
    end)
end

local function loopClan()
    task.spawn(function()
        while ST.AutoClanSpin do
            pcall(function()
                if RS then
                    for _, rfn in ipairs({"Events","Remotes","RE"}) do
                        local rf = RS:FindFirstChild(rfn)
                        if rf then
                            for _, ch in ipairs(rf:GetDescendants()) do
                                if ch:IsA("RemoteEvent") then
                                    local n = ch.Name:lower()
                                    if n:find("clan") or n:find("spin") or n:find("roll") then
                                        pcall(function() ch:FireServer() end)
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            task.wait(rnd(1,2))
        end
    end)
end

-- ============================================================
-- [9] MOVIMENTO
-- ============================================================
local function enableFly()
    pcall(function()
        local hrp = getHRP()
        if not hrp then return end
        if ST.FlyGyro then pcall(function() ST.FlyGyro:Destroy() end) end
        if ST.FlyBody then pcall(function() ST.FlyBody:Destroy() end) end
        local g  = Instance.new("BodyGyro", hrp)
        g.MaxTorque = Vector3.new(1e9,1e9,1e9); g.P = 1e6; g.D = 50
        local bv = Instance.new("BodyVelocity", hrp)
        bv.MaxForce = Vector3.new(1e9,1e9,1e9); bv.Velocity = Vector3.zero
        ST.FlyGyro = g; ST.FlyBody = bv
        local conn = RunService.Heartbeat:Connect(function()
            if not ST.Fly then
                pcall(function() g:Destroy() end)
                pcall(function() bv:Destroy() end)
                ST.FlyGyro = nil; ST.FlyBody = nil
                return
            end
            local cam = getCam(); local hrp2 = getHRP()
            if not cam or not hrp2 or not hrp2.Parent then return end
            pcall(function()
                g.CFrame = cam.CFrame
                local rv  = hrp2.AssemblyLinearVelocity
                local fwd = cam.CFrame.LookVector
                local rgt = cam.CFrame.RightVector
                local hz  = Vector3.new(rv.X,0,rv.Z)
                if hz.Magnitude > 1 then
                    local dir = (fwd*-rv.Z + rgt*rv.X).Unit
                    if dir == dir then bv.Velocity = dir*ST.FlySpeedVal end
                else
                    bv.Velocity = bv.Velocity*0.82
                end
            end)
        end)
        table.insert(ST.Connections, conn)
    end)
end

local function disableFly()
    ST.Fly = false
    if ST.FlyGyro then pcall(function() ST.FlyGyro:Destroy() end); ST.FlyGyro = nil end
    if ST.FlyBody then pcall(function() ST.FlyBody:Destroy() end); ST.FlyBody = nil end
end

local ncConn = RunService.Stepped:Connect(function()
    if not ST.NoClip then return end
    pcall(function()
        local char = LP and LP.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end)
end)
table.insert(ST.Connections, ncConn)

local ijConn = UIS.JumpRequest:Connect(function()
    if not ST.InfiniteJump then return end
    pcall(function()
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end)
table.insert(ST.Connections, ijConn)

local function setSpeed(v)
    pcall(function()
        local hum = getHum()
        if hum then hum.WalkSpeed = v end
    end)
end

LP.CharacterAdded:Connect(function()
    task.wait(1.2)
    if ST.Speed then setSpeed(ST.SpeedVal) end
    if ST.Fly   then task.wait(0.5); enableFly() end
end)

task.spawn(function()
    while true do
        task.wait(60)
        if ST.AntiIdle then
            pcall(function()
                local hrp = getHRP()
                if hrp then
                    hrp.CFrame = hrp.CFrame * CFrame.new(0.1,0,0)
                    task.wait(0.1)
                    hrp.CFrame = hrp.CFrame * CFrame.new(-0.1,0,0)
                end
            end)
        end
    end
end)

-- ============================================================
-- [10] ESP
-- ============================================================
local function clearESP()
    for _, v in ipairs(ST.ESPCache) do
        pcall(function()
            if typeof(v)=="RBXScriptConnection" then v:Disconnect()
            elseif v and v.Parent then v:Destroy() end
        end)
    end
    ST.ESPCache = {}
end

local function makeESPTag(model, color)
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    local hum  = model:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return end
    local bb = Instance.new("BillboardGui", root)
    bb.AlwaysOnTop = true; bb.Size = UDim2.new(0,6,0,6)
    bb.StudsOffset = Vector3.new(0,2.5,0); bb.MaxDistance = 250
    local bg = Instance.new("Frame", bb)
    bg.Size = UDim2.new(1,0,1,0); bg.BackgroundColor3 = color
    bg.BackgroundTransparency = 0.4; bg.BorderSizePixel = 0
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0,2)
    local nl = Instance.new("TextLabel", bb)
    nl.Size = UDim2.new(3,0,0.5,0); nl.Position = UDim2.new(-1,0,-0.8,0)
    nl.BackgroundTransparency = 1; nl.Font = Enum.Font.GothamBold
    nl.TextColor3 = color; nl.TextScaled = true
    nl.TextStrokeTransparency = 0.2; nl.Text = model.Name
    local hl = Instance.new("TextLabel", bb)
    hl.Size = UDim2.new(3,0,0.45,0); hl.Position = UDim2.new(-1,0,-0.3,0)
    hl.BackgroundTransparency = 1; hl.Font = Enum.Font.Gotham
    hl.TextColor3 = Color3.fromRGB(60,220,110); hl.TextScaled = true
    hl.Text = "HP: "..math.floor(hum.Health)
    local uc = RunService.Heartbeat:Connect(function()
        if not bb or not bb.Parent or not hum.Parent then return end
        hl.Text = "HP: "..math.floor(hum.Health)
    end)
    table.insert(ST.ESPCache, uc)
    table.insert(ST.ESPCache, bb)
end

local function refreshESP()
    clearESP()
    if not ST.ESP_Mob and not ST.ESP_Boss and not ST.ESP_Player then return end
    local bossSet = {}
    for _, b in ipairs(BOSSES) do bossSet[b.N:lower()] = true end
    for _, v in ipairs(WS:GetDescendants()) do
        pcall(function()
            if not v:IsA("Model") or v == LP.Character then return end
            local hum = v:FindFirstChildOfClass("Humanoid")
            if not hum or hum.Health <= 0 then return end
            local isBoss = bossSet[v.Name:lower()]
            local isPC   = false
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl.Character == v then isPC = true; break end
            end
            if isBoss and ST.ESP_Boss then
                makeESPTag(v, Color3.fromRGB(255,100,20))
            elseif not isBoss and not isPC and ST.ESP_Mob then
                makeESPTag(v, Color3.fromRGB(155,40,255))
            elseif isPC and ST.ESP_Player then
                makeESPTag(v, Color3.fromRGB(255,50,50))
            end
        end)
    end
end

task.spawn(function()
    while true do
        task.wait(3)
        if ST.ESP_Mob or ST.ESP_Boss or ST.ESP_Player then pcall(refreshESP) end
    end
end)

-- ============================================================
-- [11] SCREEN GUI
-- ============================================================
local SG
pcall(function() SG = game:GetService("CoreGui"):FindFirstChild("VOID_LAZY") end)
if SG then SG:Destroy() end

SG = Instance.new("ScreenGui")
SG.Name = "VOID_LAZY"; SG.ResetOnSpawn = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SG.DisplayOrder = 999; SG.IgnoreGuiInset = true

local parentOk = false
pcall(function() SG.Parent = game:GetService("CoreGui"); parentOk = true end)
if not parentOk then
    pcall(function() SG.Parent = LP.PlayerGui; parentOk = true end)
end
if not parentOk then return end

-- ============================================================
-- [12] TEMA
-- ============================================================
local T = {
    BG      = Color3.fromRGB(9,8,20),
    Panel   = Color3.fromRGB(17,13,37),
    PanelDk = Color3.fromRGB(11,8,24),
    Acc     = Color3.fromRGB(105,0,205),
    AccBrt  = Color3.fromRGB(170,55,255),
    AccDim  = Color3.fromRGB(52,0,108),
    Txt     = Color3.fromRGB(235,228,255),
    TxtDim  = Color3.fromRGB(138,128,172),
    On      = Color3.fromRGB(85,0,185),
    Off     = Color3.fromRGB(32,25,58),
    Btn     = Color3.fromRGB(72,0,170),
    BtnHot  = Color3.fromRGB(115,18,225),
    Border  = Color3.fromRGB(72,0,152),
    Danger  = Color3.fromRGB(210,42,42),
    Success = Color3.fromRGB(42,195,85),
    Warn    = Color3.fromRGB(210,172,0),
    QuestClr= Color3.fromRGB(255,200,50),
}

-- ============================================================
-- [13] INTRO
-- ============================================================
local Intro = Instance.new("Frame", SG)
Intro.Size = UDim2.new(1,0,1,0)
Intro.BackgroundColor3 = Color3.fromRGB(5,3,14)
Intro.BorderSizePixel  = 0; Intro.ZIndex = 200

local iGrad = Instance.new("UIGradient", Intro)
iGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(4,0,12)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(10,0,28)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(4,0,12)),
})
iGrad.Rotation = 135

for i = 1, 18 do
    local p  = Instance.new("Frame", Intro)
    local sz = math.random(2,6)
    p.Size = UDim2.new(0,sz,0,sz)
    p.BackgroundColor3 = Color3.fromRGB(math.random(55,150),0,math.random(175,255))
    p.BackgroundTransparency = math.random()*0.45+0.1
    p.BorderSizePixel = 0; p.ZIndex = 201
    Instance.new("UICorner",p).CornerRadius = UDim.new(1,0)
    local startX = math.random(); local startY = math.random()
    local speed = rnd(0.00008,0.00022); local phase = math.random()*math.pi*2
    task.spawn(function()
        local y = startY
        while p and p.Parent do
            y = (y-speed)%1
            pcall(function()
                p.Position = UDim2.new(startX+math.sin(tick()*0.4+phase)*0.012, 0, y, 0)
                p.BackgroundTransparency = 0.25+math.abs(math.sin(tick()*0.25+phase))*0.5
            end)
            task.wait(0.03)
        end
    end)
end

local WFrame = Instance.new("Frame", Intro)
WFrame.Size = UDim2.new(0.88,0,0.28,0); WFrame.Position = UDim2.new(0.06,0,0.14,0)
WFrame.BackgroundTransparency = 1; WFrame.ZIndex = 202

local L1 = Instance.new("TextLabel", WFrame)
L1.Size = UDim2.new(1,0,0.38,0); L1.BackgroundTransparency = 1
L1.Font = Enum.Font.GothamMedium; L1.TextScaled = true
L1.TextColor3 = Color3.fromRGB(195,188,255); L1.TextStrokeTransparency = 0.5
L1.TextStrokeColor3 = T.Acc; L1.Text = ""; L1.ZIndex = 203

local L2 = Instance.new("TextLabel", WFrame)
L2.Size = UDim2.new(1,0,0.62,0); L2.Position = UDim2.new(0,0,0.38,0)
L2.BackgroundTransparency = 1; L2.Font = Enum.Font.GothamBlack
L2.TextScaled = true; L2.TextColor3 = T.AccBrt
L2.TextStrokeTransparency = 0.25; L2.TextStrokeColor3 = T.AccDim
L2.Text = ""; L2.ZIndex = 203

local LBG = Instance.new("Frame", Intro)
LBG.Size = UDim2.new(0.65,0,0,5); LBG.Position = UDim2.new(0.175,0,0.5,0)
LBG.BackgroundColor3 = Color3.fromRGB(22,0,50); LBG.BorderSizePixel = 0
LBG.Visible = false; LBG.ZIndex = 202
Instance.new("UICorner",LBG).CornerRadius = UDim.new(1,0)

local LFill = Instance.new("Frame", LBG)
LFill.Size = UDim2.new(0,0,1,0); LFill.BackgroundColor3 = T.AccBrt
LFill.BorderSizePixel = 0; LFill.ZIndex = 203
Instance.new("UICorner",LFill).CornerRadius = UDim.new(1,0)

local LStat = Instance.new("TextLabel", Intro)
LStat.Size = UDim2.new(0.65,0,0.045,0); LStat.Position = UDim2.new(0.175,0,0.515,0)
LStat.BackgroundTransparency = 1; LStat.TextColor3 = T.TxtDim
LStat.Font = Enum.Font.Gotham; LStat.TextScaled = true; LStat.Text = ""; LStat.ZIndex = 202

local PF = Instance.new("Frame", Intro)
PF.Size = UDim2.new(0.82,0,0.34,0); PF.Position = UDim2.new(0.09,0,0.59,0)
PF.BackgroundColor3 = T.PanelDk; PF.BackgroundTransparency = 1
PF.BorderSizePixel = 0; PF.ZIndex = 202
Instance.new("UICorner",PF).CornerRadius = UDim.new(0,14)
local PFStroke = Instance.new("UIStroke",PF)
PFStroke.Color = T.Acc; PFStroke.Thickness = 1.5; PFStroke.Transparency = 1

local PFTit = Instance.new("TextLabel",PF)
PFTit.Size = UDim2.new(1,0,0.27,0); PFTit.BackgroundTransparency = 1
PFTit.TextColor3 = T.Txt; PFTit.Font = Enum.Font.GothamBold
PFTit.TextScaled = true; PFTit.Text = "🔐  VERIFICAÇÃO DE ACESSO"
PFTit.TextTransparency = 1; PFTit.ZIndex = 203

local PFInp = Instance.new("TextBox",PF)
PFInp.Size = UDim2.new(0.82,0,0.25,0); PFInp.Position = UDim2.new(0.09,0,0.3,0)
PFInp.BackgroundColor3 = Color3.fromRGB(7,4,18); PFInp.BorderSizePixel = 0
PFInp.Font = Enum.Font.GothamBold; PFInp.TextColor3 = T.AccBrt
PFInp.PlaceholderColor3 = T.TxtDim; PFInp.TextScaled = true
PFInp.PlaceholderText = "Digite a senha..."; PFInp.Text = ""
PFInp.TextTransparency = 1; PFInp.ClearTextOnFocus = false; PFInp.ZIndex = 203
Instance.new("UICorner",PFInp).CornerRadius = UDim.new(0,8)
local PFInpS = Instance.new("UIStroke",PFInp)
PFInpS.Color = T.AccDim; PFInpS.Thickness = 1; PFInpS.Transparency = 1

local PFBtn = Instance.new("TextButton",PF)
PFBtn.Size = UDim2.new(0.52,0,0.23,0); PFBtn.Position = UDim2.new(0.24,0,0.63,0)
PFBtn.BackgroundColor3 = T.Acc; PFBtn.BackgroundTransparency = 1
PFBtn.BorderSizePixel = 0; PFBtn.Font = Enum.Font.GothamBold
PFBtn.TextColor3 = Color3.fromRGB(255,255,255); PFBtn.TextScaled = true
PFBtn.Text = "✦  ENTRAR  ✦"; PFBtn.TextTransparency = 1; PFBtn.ZIndex = 203
Instance.new("UICorner",PFBtn).CornerRadius = UDim.new(0,9)

local PFErr = Instance.new("TextLabel",PF)
PFErr.Size = UDim2.new(1,0,0.14,0); PFErr.Position = UDim2.new(0,0,0.9,0)
PFErr.BackgroundTransparency = 1; PFErr.TextColor3 = T.Danger
PFErr.Font = Enum.Font.Gotham; PFErr.TextScaled = true; PFErr.Text = ""; PFErr.ZIndex = 203

local function typeWrite(lbl, txt, spd)
    spd = spd or 0.065
    for i = 1, #txt do lbl.Text = txt:sub(1,i); task.wait(spd) end
end

local function fillBar(pct, dur)
    tw(LFill,{Size=UDim2.new(pct,0,1,0)},dur,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
    task.wait(dur+0.05)
end

local function fadeIntro()
    tw(Intro,{BackgroundTransparency=1},0.65,Enum.EasingStyle.Quad)
    for _, ch in ipairs(Intro:GetDescendants()) do
        pcall(function()
            if ch:IsA("GuiObject") then
                local p = {}
                if ch.BackgroundTransparency < 1 then p.BackgroundTransparency = 1 end
                if ch:IsA("TextLabel") or ch:IsA("TextButton") or ch:IsA("TextBox") then
                    p.TextTransparency = 1
                end
                if next(p) then tw(ch,p,0.38) end
            end
        end)
    end
    task.wait(0.75)
    pcall(function() Intro:Destroy() end)
end

local buildMainUI

-- ============================================================
-- [14] VALIDAÇÃO DE SENHA
-- ============================================================
local PW = "leyzepidao"; local pwTries = 0

local function validatePW()
    local inp = PFInp.Text:lower():gsub("%s","")
    if inp == PW then
        PFBtn.BackgroundColor3 = T.Success
        PFErr.TextColor3 = T.Success; PFErr.Text = "✓  Acesso concedido!"
        task.wait(0.9); fadeIntro(); task.wait(0.1); buildMainUI()
    else
        pwTries = pwTries+1
        PFErr.Text = "✗  Senha incorreta! ("..pwTries.."/3)"
        local orig = PF.Position
        for i = 1,7 do
            local off = (i%2==0) and 10 or -10
            tw(PF,{Position=UDim2.new(orig.X.Scale,off,orig.Y.Scale,0)},0.04,Enum.EasingStyle.Sine)
            task.wait(0.045)
        end
        tw(PF,{Position=orig},0.1,Enum.EasingStyle.Bounce)
        tw(PFBtn,{BackgroundColor3=T.Danger},0.1); task.wait(0.6)
        tw(PFBtn,{BackgroundColor3=T.Acc},0.3)
        if pwTries >= 3 then
            PFBtn.Active = false; PFErr.Text = "⏳ Muitas tentativas. Aguarde 10s..."
            task.wait(10); pwTries = 0; PFBtn.Active = true
        end
        PFInp.Text = ""
    end
end

PFBtn.MouseButton1Click:Connect(validatePW)
PFInp.FocusLost:Connect(function(enter) if enter then validatePW() end end)

task.spawn(function()
    task.wait(0.3)
    typeWrite(L1,"✦  Bem-vindo a  ✦",0.055)
    task.wait(0.2)
    local full = "VOID.LAZY"
    L2.Text = ""
    for i = 1, #full do
        L2.Text = full:sub(1,i)
        tw(L2,{TextColor3=Color3.fromRGB(255,255,255)},0.08)
        task.wait(0.13)
        tw(L2,{TextColor3=T.AccBrt},0.2); task.wait(0.02)
    end
    task.wait(0.35); LBG.Visible = true
    local steps = {
        {0.2,  0.32, "Carregando módulos..."},
        {0.45, 0.28, "Anti-detecção ativado..."},
        {0.72, 0.30, "Conectando ao servidor..."},
        {0.92, 0.22, "Preparando interface v4.0..."},
        {1.0,  0.15, "Pronto. ✓"},
    }
    for _, s in ipairs(steps) do LStat.Text = s[3]; fillBar(s[1],s[2]) end
    task.wait(0.3); LBG:Destroy(); LStat:Destroy()
    PF.BackgroundTransparency = 0; PFStroke.Transparency = 0
    local fi = {
        {PFTit,"TextTransparency",0},{PFInp,"TextTransparency",0},
        {PFInp,"BackgroundTransparency",0},{PFInpS,"Transparency",0},
        {PFBtn,"BackgroundTransparency",0},{PFBtn,"TextTransparency",0},
    }
    for _, x in ipairs(fi) do tw(x[1],{[x[2]]=x[3]},0.5) end
    task.spawn(function()
        while PFInp and PFInp.Parent do
            tw(PFInpS,{Color=T.AccBrt},0.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
            task.wait(0.9)
            tw(PFInpS,{Color=T.AccDim},0.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
            task.wait(0.9)
        end
    end)
end)

-- ============================================================
-- [15] MAIN UI
-- ============================================================
buildMainUI = function()
    local VP     = getCam() and getCam().ViewportSize or Vector2.new(800,600)
    local mobile = VP.X < 860

    local MF = Instance.new("Frame",SG)
    MF.Name = "VoidMain"; MF.BorderSizePixel = 0
    MF.ClipsDescendants = true; MF.BackgroundColor3 = T.BG

    local FW = mobile and math.min(VP.X*0.93,400) or 355
    local FH = 600
    MF.Size = UDim2.new(0,FW,0,FH)
    MF.Position = UDim2.new(0.5,-FW/2,-1,0)
    Instance.new("UICorner",MF).CornerRadius = UDim.new(0,15)
    local MFS = Instance.new("UIStroke",MF)
    MFS.Color = T.Border; MFS.Thickness = 1.5

    local tgtPos = UDim2.new(0.5,-FW/2,0.04,0)
    tw(MF,{Position=tgtPos},0.55,Enum.EasingStyle.Back,Enum.EasingDirection.Out)

    task.spawn(function()
        while MF and MF.Parent do
            tw(MFS,{Color=T.AccBrt},1.5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
            task.wait(1.5)
            tw(MFS,{Color=T.Border},1.5,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
            task.wait(1.5)
        end
    end)

    -- Header
    local HDR = Instance.new("Frame",MF)
    HDR.Size = UDim2.new(1,0,0,50); HDR.BackgroundColor3 = T.AccDim; HDR.BorderSizePixel = 0
    Instance.new("UICorner",HDR).CornerRadius = UDim.new(0,15)
    Instance.new("UIGradient",HDR).Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(40,0,90)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(78,0,162)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(40,0,90)),
    })
    local hfix = Instance.new("Frame",HDR)
    hfix.Size = UDim2.new(1,0,0.5,0); hfix.Position = UDim2.new(0,0,0.5,0)
    hfix.BackgroundColor3 = T.AccDim; hfix.BorderSizePixel = 0
    local htl = Instance.new("TextLabel",HDR)
    htl.Size = UDim2.new(0.62,0,1,0); htl.Position = UDim2.new(0,12,0,0)
    htl.BackgroundTransparency = 1; htl.Font = Enum.Font.GothamBlack
    htl.TextScaled = true; htl.TextXAlignment = Enum.TextXAlignment.Left
    htl.TextColor3 = Color3.fromRGB(255,255,255)
    htl.TextStrokeTransparency = 0.35; htl.TextStrokeColor3 = T.AccBrt
    htl.Text = "⬡ VOID.LAZY"
    local hsub = Instance.new("TextLabel",HDR)
    hsub.Size = UDim2.new(0.28,0,0.42,0); hsub.Position = UDim2.new(0.7,0,0.3,0)
    hsub.BackgroundTransparency = 1; hsub.Font = Enum.Font.GothamBold
    hsub.TextScaled = true; hsub.TextXAlignment = Enum.TextXAlignment.Right
    hsub.TextColor3 = T.TxtDim; hsub.Text = "v4.0"

    local function hBtn(icon, xoff, bg)
        local b = Instance.new("TextButton",HDR)
        b.Size = UDim2.new(0,27,0,27); b.Position = UDim2.new(1,xoff,0.5,-13)
        b.BackgroundColor3 = bg; b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold; b.TextScaled = true
        b.TextColor3 = Color3.fromRGB(255,255,255); b.Text = icon
        Instance.new("UICorner",b).CornerRadius = UDim.new(0,6)
        return b
    end
    local CloseBtn = hBtn("✕",-34,Color3.fromRGB(170,28,28))
    local MinBtn   = hBtn("─",-67,Color3.fromRGB(68,68,0))

    -- Tab bar
    local TBar = Instance.new("Frame",MF)
    TBar.Size = UDim2.new(1,0,0,35); TBar.Position = UDim2.new(0,0,0,50)
    TBar.BackgroundColor3 = T.PanelDk; TBar.BorderSizePixel = 0
    local tbL = Instance.new("UIListLayout",TBar)
    tbL.FillDirection = Enum.FillDirection.Horizontal
    tbL.SortOrder = Enum.SortOrder.LayoutOrder; tbL.Padding = UDim.new(0,3)
    local tbP = Instance.new("UIPadding",TBar)
    tbP.PaddingLeft=UDim.new(0,4); tbP.PaddingRight=UDim.new(0,4)
    tbP.PaddingTop=UDim.new(0,4);  tbP.PaddingBottom=UDim.new(0,4)

    local CA = Instance.new("Frame",MF)
    CA.Size = UDim2.new(1,0,1,-85); CA.Position = UDim2.new(0,0,0,85)
    CA.BackgroundTransparency = 1; CA.ClipsDescendants = true

    local TABS = {
        {N="Farm",   I="⚔"},
        {N="Boss",   I="💀"},
        {N="Player", I="⚡"},
        {N="ESP",    I="👁"},
        {N="TP",     I="🌀"},
        {N="Misc",   I="⚙"},
    }

    local frames = {}; local tBtns = {}; local curTab = nil
    local tabW = (1-0.012)/#TABS

    local function switchTab(name)
        if curTab == name then return end
        curTab = name
        for n,f in pairs(frames) do f.Visible = (n==name) end
        for n,b in pairs(tBtns) do
            if n==name then tw(b,{BackgroundColor3=T.Acc,TextColor3=Color3.fromRGB(255,255,255)},0.17)
            else tw(b,{BackgroundColor3=Color3.fromRGB(17,12,36),TextColor3=T.TxtDim},0.17) end
        end
    end

    for i,td in ipairs(TABS) do
        local b = Instance.new("TextButton",TBar)
        b.Size = UDim2.new(tabW,0,1,0)
        b.BackgroundColor3 = (i==1) and T.Acc or Color3.fromRGB(17,12,36)
        b.BorderSizePixel = 0; b.LayoutOrder = i
        b.Font = Enum.Font.GothamBold; b.TextScaled = true
        b.TextColor3 = (i==1) and Color3.fromRGB(255,255,255) or T.TxtDim
        b.Text = td.I.." "..td.N
        Instance.new("UICorner",b).CornerRadius = UDim.new(0,6)
        tBtns[td.N] = b
        local sf = Instance.new("ScrollingFrame",CA)
        sf.Size = UDim2.new(1,0,1,0); sf.BackgroundTransparency = 1
        sf.ScrollBarThickness = 3; sf.ScrollBarImageColor3 = T.AccDim
        sf.CanvasSize = UDim2.new(0,0,0,0)
        sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
        sf.Visible = (i==1); sf.BorderSizePixel = 0
        local sfl = Instance.new("UIListLayout",sf)
        sfl.SortOrder = Enum.SortOrder.LayoutOrder; sfl.Padding = UDim.new(0,4)
        local sfp = Instance.new("UIPadding",sf)
        sfp.PaddingLeft=UDim.new(0,8); sfp.PaddingRight=UDim.new(0,8); sfp.PaddingTop=UDim.new(0,6)
        frames[td.N] = sf
        b.MouseButton1Click:Connect(function() switchTab(td.N) end)
    end
    curTab = "Farm"

    -- ── HELPERS ──────────────────────────────────────────────
    local function mkSec(p,txt,ord)
        local f=Instance.new("Frame",p); f.Size=UDim2.new(1,0,0,22)
        f.BackgroundColor3=Color3.fromRGB(20,7,45); f.BorderSizePixel=0; f.LayoutOrder=ord or 0
        Instance.new("UICorner",f).CornerRadius=UDim.new(0,6)
        local l=Instance.new("TextLabel",f); l.Size=UDim2.new(1,-12,1,0); l.Position=UDim2.new(0,12,0,0)
        l.BackgroundTransparency=1; l.Font=Enum.Font.GothamBold; l.TextScaled=true
        l.TextColor3=T.AccBrt; l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=txt
        return f
    end

    local function mkToggle(p,lbl,key,ord,cb)
        local row=Instance.new("Frame",p); row.Size=UDim2.new(1,0,0,36)
        row.BackgroundColor3=T.Panel; row.BorderSizePixel=0; row.LayoutOrder=ord or 0
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,9)
        local tl=Instance.new("TextLabel",row); tl.Size=UDim2.new(0.7,0,1,0); tl.Position=UDim2.new(0,10,0,0)
        tl.BackgroundTransparency=1; tl.Font=Enum.Font.Gotham; tl.TextScaled=true
        tl.TextColor3=T.Txt; tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Text=lbl
        local tbg=Instance.new("Frame",row); tbg.Size=UDim2.new(0,44,0,22); tbg.Position=UDim2.new(1,-52,0.5,-11)
        tbg.BackgroundColor3=ST[key] and T.On or T.Off; tbg.BorderSizePixel=0
        Instance.new("UICorner",tbg).CornerRadius=UDim.new(1,0)
        local tk=Instance.new("Frame",tbg); tk.Size=UDim2.new(0,18,0,18)
        tk.Position=ST[key] and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)
        tk.BackgroundColor3=Color3.fromRGB(255,255,255); tk.BorderSizePixel=0
        Instance.new("UICorner",tk).CornerRadius=UDim.new(1,0)
        local hit=Instance.new("TextButton",row); hit.Size=UDim2.new(1,0,1,0)
        hit.BackgroundTransparency=1; hit.Text=""; hit.ZIndex=row.ZIndex+2
        local function upd()
            tw(tbg,{BackgroundColor3=ST[key] and T.On or T.Off},0.2)
            tw(tk,{Position=ST[key] and UDim2.new(1,-20,0.5,-9) or UDim2.new(0,2,0.5,-9)},0.2)
        end
        hit.MouseButton1Click:Connect(function()
            ST[key]=not ST[key]; upd(); if cb then cb(ST[key]) end
        end)
        return row
    end

    local function mkSlider(p,lbl,vmin,vmax,key,ord,cb)
        local row=Instance.new("Frame",p); row.Size=UDim2.new(1,0,0,52)
        row.BackgroundColor3=T.Panel; row.BorderSizePixel=0; row.LayoutOrder=ord or 0
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,9)
        local tl=Instance.new("TextLabel",row); tl.Size=UDim2.new(0.6,0,0.46,0); tl.Position=UDim2.new(0,10,0,0)
        tl.BackgroundTransparency=1; tl.Font=Enum.Font.Gotham; tl.TextScaled=true
        tl.TextColor3=T.Txt; tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Text=lbl
        local vl=Instance.new("TextLabel",row); vl.Size=UDim2.new(0.3,0,0.4,0); vl.Position=UDim2.new(0.68,0,0.04,0)
        vl.BackgroundTransparency=1; vl.Font=Enum.Font.GothamBold; vl.TextScaled=true
        vl.TextColor3=T.AccBrt; vl.TextXAlignment=Enum.TextXAlignment.Right; vl.Text=tostring(ST[key])
        local sbg=Instance.new("Frame",row); sbg.Size=UDim2.new(0.88,0,0,5); sbg.Position=UDim2.new(0.06,0,0.77,0)
        sbg.BackgroundColor3=Color3.fromRGB(26,17,50); sbg.BorderSizePixel=0
        Instance.new("UICorner",sbg).CornerRadius=UDim.new(1,0)
        local pct=(ST[key]-vmin)/(vmax-vmin)
        local sf2=Instance.new("Frame",sbg); sf2.Size=UDim2.new(pct,0,1,0)
        sf2.BackgroundColor3=T.AccBrt; sf2.BorderSizePixel=0
        Instance.new("UICorner",sf2).CornerRadius=UDim.new(1,0)
        local sk=Instance.new("Frame",sbg); sk.Size=UDim2.new(0,14,0,14); sk.Position=UDim2.new(pct,-7,0.5,-7)
        sk.BackgroundColor3=Color3.fromRGB(255,255,255); sk.BorderSizePixel=0
        Instance.new("UICorner",sk).CornerRadius=UDim.new(1,0)
        local dragging=false
        local function apply(pos)
            local abs=sbg.AbsolutePosition; local sz=sbg.AbsoluteSize
            local rel=math.clamp((pos.X-abs.X)/sz.X,0,1)
            local val=math.floor(vmin+(vmax-vmin)*rel)
            ST[key]=val; vl.Text=tostring(val)
            tw(sf2,{Size=UDim2.new(rel,0,1,0)},0.05,Enum.EasingStyle.Linear)
            tw(sk,{Position=UDim2.new(rel,-7,0.5,-7)},0.05,Enum.EasingStyle.Linear)
            if cb then cb(val) end
        end
        sbg.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
                dragging=true; apply(i.Position) end end)
        sbg.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then
                apply(i.Position) end end)
        UIS.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
                dragging=false end end)
        return row
    end

    local function mkDrop(p,lbl,opts,key,ord,cb)
        local wrap=Instance.new("Frame",p); wrap.Size=UDim2.new(1,0,0,36)
        wrap.BackgroundColor3=T.Panel; wrap.BorderSizePixel=0; wrap.LayoutOrder=ord or 0
        wrap.ClipsDescendants=false
        Instance.new("UICorner",wrap).CornerRadius=UDim.new(0,9)
        local tl=Instance.new("TextLabel",wrap); tl.Size=UDim2.new(0.43,0,1,0); tl.Position=UDim2.new(0,10,0,0)
        tl.BackgroundTransparency=1; tl.Font=Enum.Font.Gotham; tl.TextScaled=true
        tl.TextColor3=T.Txt; tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Text=lbl
        local db=Instance.new("TextButton",wrap); db.Size=UDim2.new(0.5,0,0.72,0); db.Position=UDim2.new(0.48,0,0.14,0)
        db.BackgroundColor3=Color3.fromRGB(20,13,45); db.BorderSizePixel=0
        db.Font=Enum.Font.GothamBold; db.TextScaled=true; db.TextColor3=T.AccBrt
        db.Text=ST[key] or opts[1]; db.ClipsDescendants=true
        Instance.new("UICorner",db).CornerRadius=UDim.new(0,7)
        local ds=Instance.new("UIStroke",db); ds.Color=T.AccDim; ds.Thickness=1
        local DL=Instance.new("Frame",SG); DL.BackgroundColor3=Color3.fromRGB(12,7,30)
        DL.BorderSizePixel=0; DL.Visible=false; DL.ZIndex=500
        Instance.new("UICorner",DL).CornerRadius=UDim.new(0,9)
        local dls=Instance.new("UIStroke",DL); dls.Color=T.Acc; dls.Thickness=1
        local dll=Instance.new("UIListLayout",DL); dll.SortOrder=Enum.SortOrder.LayoutOrder
        local IH=26
        for j,opt in ipairs(opts) do
            local ob=Instance.new("TextButton",DL); ob.Size=UDim2.new(1,0,0,IH)
            ob.BackgroundColor3=Color3.fromRGB(12,7,30); ob.BorderSizePixel=0
            ob.Font=Enum.Font.Gotham; ob.TextScaled=true; ob.TextColor3=T.Txt
            ob.Text=opt; ob.ZIndex=501; ob.LayoutOrder=j
            ob.MouseButton1Click:Connect(function() ST[key]=opt; db.Text=opt; DL.Visible=false; if cb then cb(opt) end end)
            ob.MouseEnter:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(32,16,62)},0.1) end)
            ob.MouseLeave:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(12,7,30)},0.1) end)
        end
        DL.Size=UDim2.new(0,175,0,IH*#opts)
        local open=false
        db.MouseButton1Click:Connect(function()
            open=not open
            if open then
                local ap=db.AbsolutePosition; local as=db.AbsoluteSize
                DL.Position=UDim2.new(0,ap.X,0,ap.Y+as.Y+3); DL.Visible=true
            else DL.Visible=false end
        end)
        return wrap
    end

    local function mkBtn(p,txt,ord,cb)
        local b=Instance.new("TextButton",p); b.Size=UDim2.new(1,0,0,33)
        b.BackgroundColor3=T.Btn; b.BorderSizePixel=0; b.Font=Enum.Font.GothamBold
        b.TextScaled=true; b.TextColor3=Color3.fromRGB(255,255,255); b.Text=txt; b.LayoutOrder=ord or 0
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,9)
        b.MouseButton1Click:Connect(function()
            tw(b,{BackgroundColor3=T.AccBrt},0.08); task.wait(0.08); tw(b,{BackgroundColor3=T.Btn},0.22)
            if cb then pcall(cb) end
        end)
        b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=T.BtnHot},0.14) end)
        b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=T.Btn},0.14) end)
        return b
    end

    local function mkSp(p,h,ord)
        local s=Instance.new("Frame",p); s.Size=UDim2.new(1,0,0,h or 3)
        s.BackgroundTransparency=1; s.LayoutOrder=ord or 0; return s
    end

    -- Botões de preset de hitbox (3 no mesmo row)
    local function mkPresetRow(p, ord)
        local row = Instance.new("Frame",p)
        row.Size = UDim2.new(1,0,0,34)
        row.BackgroundTransparency = 1; row.LayoutOrder = ord or 0
        local ll = Instance.new("UIListLayout",row)
        ll.FillDirection = Enum.FillDirection.Horizontal
        ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Padding = UDim.new(0,4)

        local presets = {
            {lbl="⬆ Cima",   y=50,  x=0},
            {lbl="• Normal",  y=4,   x=0},
            {lbl="⬇ Chão",   y=-50, x=0},
            {lbl="↔ Lado",   y=0,   x=8},
        }
        local btnW = (1 - 0.012) / #presets

        for _, pr in ipairs(presets) do
            local prv = pr
            local b = Instance.new("TextButton", row)
            b.Size = UDim2.new(btnW,0,1,0)
            b.BackgroundColor3 = Color3.fromRGB(35,12,70); b.BorderSizePixel = 0
            b.Font = Enum.Font.GothamBold; b.TextScaled = true
            b.TextColor3 = T.AccBrt; b.Text = prv.lbl; b.LayoutOrder = _
            Instance.new("UICorner",b).CornerRadius = UDim.new(0,7)
            b.MouseButton1Click:Connect(function()
                ST.HitboxOffsetY = prv.y; ST.HitboxOffsetX = prv.x
                tw(b,{BackgroundColor3=T.Acc},0.12); task.wait(0.12); tw(b,{BackgroundColor3=Color3.fromRGB(35,12,70)},0.2)
            end)
            b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=Color3.fromRGB(55,20,110)},0.1) end)
            b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=Color3.fromRGB(35,12,70)},0.1) end)
        end
        return row
    end

    -- Seletor de arma com refresh ao vivo  (NOVO)
    local function mkWeaponSelector(p, ord)
        local wrap = Instance.new("Frame",p)
        wrap.Size = UDim2.new(1,0,0,66)
        wrap.BackgroundColor3 = T.Panel; wrap.BorderSizePixel = 0; wrap.LayoutOrder = ord or 0
        wrap.ClipsDescendants = false
        Instance.new("UICorner",wrap).CornerRadius = UDim.new(0,9)

        local topRow = Instance.new("Frame",wrap)
        topRow.Size = UDim2.new(1,0,0,33); topRow.BackgroundTransparency = 1

        local lbl = Instance.new("TextLabel",topRow)
        lbl.Size = UDim2.new(0.42,0,1,0); lbl.Position = UDim2.new(0,10,0,0)
        lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.Gotham; lbl.TextScaled = true
        lbl.TextColor3 = T.Txt; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.Text = "🗡 Arma"

        local tools = listTools()
        local curWeapon = tools[1] or "Soco (Sem Arma)"
        ST.WeaponName = curWeapon

        local db = Instance.new("TextButton",topRow)
        db.Size = UDim2.new(0.52,0,0.82,0); db.Position = UDim2.new(0.46,0,0.09,0)
        db.BackgroundColor3 = Color3.fromRGB(20,13,45); db.BorderSizePixel = 0
        db.Font = Enum.Font.GothamBold; db.TextScaled = true; db.TextColor3 = T.AccBrt
        db.Text = curWeapon; db.ClipsDescendants = true
        Instance.new("UICorner",db).CornerRadius = UDim.new(0,7)
        local ds = Instance.new("UIStroke",db); ds.Color = T.AccDim; ds.Thickness = 1

        -- dropdown list (sobre SG para não clipar)
        local DL = Instance.new("Frame",SG)
        DL.BackgroundColor3 = Color3.fromRGB(12,7,30); DL.BorderSizePixel = 0
        DL.Visible = false; DL.ZIndex = 600
        Instance.new("UICorner",DL).CornerRadius = UDim.new(0,9)
        Instance.new("UIStroke",DL).Color = T.Acc
        local dll = Instance.new("UIListLayout",DL); dll.SortOrder = Enum.SortOrder.LayoutOrder
        local IH = 26

        local function rebuildDL()
            for _, ch in ipairs(DL:GetChildren()) do
                if ch:IsA("TextButton") then ch:Destroy() end
            end
            tools = listTools()
            for j, opt in ipairs(tools) do
                local ob = Instance.new("TextButton",DL)
                ob.Size = UDim2.new(1,0,0,IH); ob.BackgroundColor3 = Color3.fromRGB(12,7,30)
                ob.BorderSizePixel = 0; ob.Font = Enum.Font.Gotham; ob.TextScaled = true
                ob.TextColor3 = T.Txt; ob.Text = opt; ob.ZIndex = 601; ob.LayoutOrder = j
                ob.MouseButton1Click:Connect(function()
                    ST.WeaponName = opt; db.Text = opt; DL.Visible = false
                end)
                ob.MouseEnter:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(32,16,62)},0.1) end)
                ob.MouseLeave:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(12,7,30)},0.1) end)
            end
            DL.Size = UDim2.new(0,185,0,IH*#tools)
        end

        rebuildDL()
        local dlOpen = false
        db.MouseButton1Click:Connect(function()
            dlOpen = not dlOpen
            if dlOpen then
                local ap = db.AbsolutePosition; local as = db.AbsoluteSize
                DL.Position = UDim2.new(0,ap.X,0,ap.Y+as.Y+3); DL.Visible = true
            else DL.Visible = false end
        end)

        -- Linha inferior: botões Refresh + Equipar
        local botRow = Instance.new("Frame",wrap)
        botRow.Size = UDim2.new(1,0,0,28); botRow.Position = UDim2.new(0,0,0,36)
        botRow.BackgroundTransparency = 1
        local bL = Instance.new("UIListLayout",botRow)
        bL.FillDirection = Enum.FillDirection.Horizontal; bL.SortOrder = Enum.SortOrder.LayoutOrder
        bL.Padding = UDim.new(0,5)
        local bP = Instance.new("UIPadding",botRow)
        bP.PaddingLeft=UDim.new(0,8); bP.PaddingRight=UDim.new(0,8)

        local function mkMiniBtn(txt, cb2)
            local b = Instance.new("TextButton",botRow)
            b.Size = UDim2.new(0.5,-5,1,0); b.BackgroundColor3 = T.Btn; b.BorderSizePixel = 0
            b.Font = Enum.Font.GothamBold; b.TextScaled = true
            b.TextColor3 = Color3.fromRGB(255,255,255); b.Text = txt
            Instance.new("UICorner",b).CornerRadius = UDim.new(0,7)
            b.MouseButton1Click:Connect(function()
                tw(b,{BackgroundColor3=T.AccBrt},0.08); task.wait(0.08); tw(b,{BackgroundColor3=T.Btn},0.22)
                if cb2 then pcall(cb2) end
            end)
            return b
        end

        mkMiniBtn("🔄 Refresh", function()
            rebuildDL()
            local t2 = listTools()
            db.Text = #t2 > 0 and t2[1] or "Soco"
            ST.WeaponName = db.Text
        end)
        mkMiniBtn("⚔ Equipar", function()
            local ok = equipWeapon(ST.WeaponName)
            if ST.Notify then
                if ok then ST.Notify("⚔ "..ST.WeaponName.." equipado!", T.Success, 2)
                else ST.Notify("Item não encontrado!", T.Danger, 2) end
            end
        end)

        return wrap
    end

    -- Label de status da quest (NOVO)
    local function mkQuestStatus(p, ord)
        local f = Instance.new("Frame",p)
        f.Size = UDim2.new(1,0,0,54); f.BackgroundColor3 = Color3.fromRGB(20,12,8)
        f.BorderSizePixel = 0; f.LayoutOrder = ord or 0
        Instance.new("UICorner",f).CornerRadius = UDim.new(0,9)
        local stroke = Instance.new("UIStroke",f)
        stroke.Color = T.QuestClr; stroke.Thickness = 1; stroke.Transparency = 0.4
        local l = Instance.new("TextLabel",f)
        l.Size = UDim2.new(1,-12,1,0); l.Position = UDim2.new(0,6,0,0)
        l.BackgroundTransparency = 1; l.Font = Enum.Font.Gotham; l.TextScaled = true
        l.TextWrapped = true; l.RichText = true; l.TextColor3 = T.TxtDim
        l.TextXAlignment = Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Center

        RunService.Heartbeat:Connect(function()
            if not f or not f.Parent then return end
            pcall(function()
                if QST.state == "IDLE" then
                    l.Text = '<font color="#aa7700">⏳ Aguardando NPC de quest...</font>'
                elseif QST.state == "FARMING" then
                    l.Text = ('<font color="#ffcc33">⚔ Farmando: %s</font>\n<font color="#55cc77">%d</font><font color="#aa9944"> / </font><font color="#ffcc33">%d kills</font>'):format(
                        QST.mobName, QST.killsDone, QST.killsNeeded)
                elseif QST.state == "TURN_IN" then
                    l.Text = '<font color="#55cc77">✓ Entregando quest ao NPC...</font>'
                end
            end)
        end)
        return f
    end

    -- Notificação
    local function notify(msg, color, dur)
        color = color or T.AccBrt; dur = dur or 2.5
        task.spawn(function()
            local nf=Instance.new("Frame",SG); nf.Size=UDim2.new(0,265,0,44)
            nf.Position=UDim2.new(0.5,-132,1,5)
            nf.BackgroundColor3=T.PanelDk; nf.BorderSizePixel=0; nf.ZIndex=1000
            Instance.new("UICorner",nf).CornerRadius=UDim.new(0,11)
            local ns=Instance.new("UIStroke",nf); ns.Color=color; ns.Thickness=1.5
            local nl=Instance.new("TextLabel",nf); nl.Size=UDim2.new(1,-10,1,0); nl.Position=UDim2.new(0,5,0,0)
            nl.BackgroundTransparency=1; nl.Font=Enum.Font.GothamBold; nl.TextScaled=true
            nl.TextColor3=color; nl.TextStrokeTransparency=0.3; nl.ZIndex=1001; nl.Text=msg
            tw(nf,{Position=UDim2.new(0.5,-132,1,-54)},0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
            task.wait(dur)
            tw(nf,{Position=UDim2.new(0.5,-132,1,5)},0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
            task.wait(0.38); pcall(function() nf:Destroy() end)
        end)
    end
    ST.Notify = notify

    -- ================================================================
    -- CONTEÚDO DAS ABAS
    -- ================================================================

    -- ── FARM ────────────────────────────────────────────────
    local FT = frames["Farm"]
    local fo = 1  -- ordem sequencial

    mkSec(FT,"⚔  AUTO FARM",fo) fo=fo+1
    mkDrop(FT,"Mob Alvo",MOBS,"TargetMob",fo) fo=fo+1
    mkToggle(FT,"Auto Farm","AutoFarm",fo, function(on)
        if on then loopFarm(); loopSkills() end
    end) fo=fo+1
    mkToggle(FT,"Congelar Alvo","FreezeTarget",fo) fo=fo+1

    mkSec(FT,"✦  AUTO MASTERY",fo) fo=fo+1
    mkToggle(FT,"Auto Mastery Farm","AutoMastery",fo, function(on)
        if on then loopMastery() end
    end) fo=fo+1

    -- SEÇÃO ARMA (NOVO)
    mkSec(FT,"🗡  ARMA / TOOL",fo) fo=fo+1
    mkWeaponSelector(FT, fo) fo=fo+1

    -- SEÇÃO HITBOX / POSIÇÃO (NOVO)
    mkSec(FT,"📐  HITBOX / POSIÇÃO",fo) fo=fo+1

    -- Slider Y: -150 (abaixo do chão) a 50 (acima)
    do
        local row = Instance.new("Frame",FT)
        row.Size = UDim2.new(1,0,0,62); row.BackgroundColor3 = T.Panel
        row.BorderSizePixel = 0; row.LayoutOrder = fo
        Instance.new("UICorner",row).CornerRadius = UDim.new(0,9)
        fo=fo+1

        local tl = Instance.new("TextLabel",row)
        tl.Size = UDim2.new(0.55,0,0,22); tl.Position = UDim2.new(0,10,0,2)
        tl.BackgroundTransparency = 1; tl.Font = Enum.Font.Gotham; tl.TextScaled = true
        tl.TextColor3 = T.Txt; tl.TextXAlignment = Enum.TextXAlignment.Left; tl.Text = "Altura Y"

        local vl = Instance.new("TextLabel",row)
        vl.Size = UDim2.new(0.35,0,0,22); vl.Position = UDim2.new(0.62,0,0,2)
        vl.BackgroundTransparency = 1; vl.Font = Enum.Font.GothamBold; vl.TextScaled = true
        vl.TextColor3 = T.AccBrt; vl.TextXAlignment = Enum.TextXAlignment.Right
        vl.Text = tostring(ST.HitboxOffsetY)

        local hint = Instance.new("TextLabel",row)
        hint.Size = UDim2.new(1,-16,0,14); hint.Position = UDim2.new(0,8,0,24)
        hint.BackgroundTransparency = 1; hint.Font = Enum.Font.Gotham; hint.TextScaled = true
        hint.TextColor3 = T.TxtDim; hint.TextXAlignment = Enum.TextXAlignment.Left
        hint.Text = "-150 = sub-chão  |  0 = nível  |  50 = acima"

        local sbg = Instance.new("Frame",row)
        sbg.Size = UDim2.new(0.88,0,0,5); sbg.Position = UDim2.new(0.06,0,0,46)
        sbg.BackgroundColor3 = Color3.fromRGB(26,17,50); sbg.BorderSizePixel = 0
        Instance.new("UICorner",sbg).CornerRadius = UDim.new(1,0)

        local vmin, vmax = -150, 50
        local pct0 = (ST.HitboxOffsetY - vmin)/(vmax - vmin)
        local sff = Instance.new("Frame",sbg); sff.Size = UDim2.new(pct0,0,1,0)
        sff.BackgroundColor3 = T.AccBrt; sff.BorderSizePixel = 0
        Instance.new("UICorner",sff).CornerRadius = UDim.new(1,0)
        local skk = Instance.new("Frame",sbg); skk.Size = UDim2.new(0,14,0,14); skk.Position = UDim2.new(pct0,-7,0.5,-7)
        skk.BackgroundColor3 = Color3.fromRGB(255,255,255); skk.BorderSizePixel = 0
        Instance.new("UICorner",skk).CornerRadius = UDim.new(1,0)

        local draggingY = false
        local function applyY(pos)
            local abs = sbg.AbsolutePosition; local sz = sbg.AbsoluteSize
            local rel = math.clamp((pos.X-abs.X)/sz.X, 0, 1)
            local val = math.floor(vmin + (vmax-vmin)*rel)
            ST.HitboxOffsetY = val; vl.Text = tostring(val)
            tw(sff,{Size=UDim2.new(rel,0,1,0)},0.05,Enum.EasingStyle.Linear)
            tw(skk,{Position=UDim2.new(rel,-7,0.5,-7)},0.05,Enum.EasingStyle.Linear)
            -- muda cor conforme posição
            if val < -10 then
                tw(sff,{BackgroundColor3=Color3.fromRGB(80,180,255)},0.1) -- azul = sub-chão
            elseif val > 20 then
                tw(sff,{BackgroundColor3=Color3.fromRGB(255,165,0)},0.1)  -- laranja = acima
            else
                tw(sff,{BackgroundColor3=T.AccBrt},0.1)                   -- roxo = normal
            end
        end
        sbg.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
                draggingY=true; applyY(i.Position) end end)
        sbg.InputChanged:Connect(function(i)
            if draggingY and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then
                applyY(i.Position) end end)
        UIS.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
                draggingY=false end end)
    end

    -- Presets de posição
    mkPresetRow(FT, fo) fo=fo+1

    -- Toggle agrupar + botão manual (NOVO)
    mkSec(FT,"👥  AGRUPAR MOBS",fo) fo=fo+1
    mkToggle(FT,"Auto Agrupar (loop)","GroupMobs",fo, function(on)
        if on then loopGroupMobs() end
    end) fo=fo+1
    mkBtn(FT,"👥 Agrupar Agora",fo, function()
        local count = groupMobs()
        notify("👥 "..count.." mobs agrupados!", T.AccBrt, 2)
    end) fo=fo+1

    -- SEÇÃO QUEST + FARM INTEGRADO (NOVO)
    mkSec(FT,"📋  AUTO QUEST + FARM",fo) fo=fo+1
    mkDrop(FT,"NPC de Quest", QUEST_NPC_NAMES, "QuestNPCName", fo) fo=fo+1
    mkToggle(FT,"Auto Quest + Farm","AutoQuestFarm",fo, function(on)
        if on then
            loopAutoQuestFarm()
            loopSkills()
        else
            QST.state = "IDLE"
        end
    end) fo=fo+1
    mkQuestStatus(FT, fo) fo=fo+1

    mkSec(FT,"⚙  CONFIG",fo) fo=fo+1
    mkSlider(FT,"Nível Máximo",1,1000,"MaxLevel",fo) fo=fo+1
    mkToggle(FT,"Auto Skills/Breathing","AutoSkills",fo) fo=fo+1
    mkToggle(FT,"Anti-Idle (anti-kick)","AntiIdle",fo) fo=fo+1

    -- ── BOSS ────────────────────────────────────────────────
    local BT = frames["Boss"]
    mkSec(BT,"💀  AUTO BOSS",1)
    local bnames={}; for _,b in ipairs(BOSSES) do table.insert(bnames,b.N) end
    mkDrop(BT,"Boss Alvo",bnames,"TargetBoss",2)
    mkToggle(BT,"Auto Boss Farm","AutoBoss",3, function(on) if on then loopBoss() end end)
    mkToggle(BT,"Congelar Boss","FreezeTarget",4)

    local biF=Instance.new("Frame",BT); biF.Size=UDim2.new(1,0,0,82); biF.BackgroundColor3=Color3.fromRGB(17,9,36)
    biF.BorderSizePixel=0; biF.LayoutOrder=5; Instance.new("UICorner",biF).CornerRadius=UDim.new(0,9)
    local biL=Instance.new("TextLabel",biF); biL.Size=UDim2.new(1,-12,1,0); biL.Position=UDim2.new(0,6,0,0)
    biL.BackgroundTransparency=1; biL.Font=Enum.Font.Gotham; biL.TextScaled=true; biL.TextWrapped=true
    biL.RichText=true; biL.TextColor3=T.TxtDim; biL.TextXAlignment=Enum.TextXAlignment.Left; biL.TextYAlignment=Enum.TextYAlignment.Center

    local function refreshBI()
        for _,b in ipairs(BOSSES) do
            if b.N==ST.TargetBoss then
                biL.Text=('<font color="#aa55ff"><b>%s</b></font>  Lv.%d\n<font color="#8844bb">Zona:</font> <font color="#ccaaff">%s</font>\n<font color="#8844bb">Drop:</font> <font color="#55cc77">%s</font>'):format(b.N,b.Lv,b.Zone,b.Drop)
                break
            end
        end
    end
    refreshBI()

    mkSec(BT,"🏰  DUNGEON OUWIGAHARA",6)
    mkToggle(BT,"Auto Dungeon (Lv.65+)","AutoDungeon",7, function(on)
        if on then
            task.spawn(function()
                while ST.AutoDungeon do
                    pcall(function()
                        if RS then
                            for _,rfn in ipairs({"Events","Remotes","RE"}) do
                                local rf=RS:FindFirstChild(rfn)
                                if rf then
                                    for _,ch in ipairs(rf:GetDescendants()) do
                                        if ch:IsA("RemoteEvent") then
                                            local n=ch.Name:lower()
                                            if n:find("dungeon") or n:find("ouw") then pcall(function() ch:FireServer() end) end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                    task.wait(rnd(5,10))
                end
            end)
        end
    end)
    mkBtn(BT,"📍 TP para o Boss",8, function()
        local t=findMob(ST.TargetBoss)
        if t then
            local r=t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
            if r then local hrp=getHRP(); if hrp then hrp.CFrame=r.CFrame+Vector3.new(0,10,0) end; notify("💀 TP → "..ST.TargetBoss,T.Warn) end
        else notify("Boss não encontrado no servidor",T.Danger) end
    end)

    -- ── PLAYER ──────────────────────────────────────────────
    local PT = frames["Player"]
    mkSec(PT,"🚀  MOVIMENTO",1)
    mkToggle(PT,"✈ Voar (Fly)","Fly",2, function(on)
        if on then enableFly() else disableFly() end
    end)
    mkSlider(PT,"Velocidade Fly",10,350,"FlySpeedVal",3)
    mkToggle(PT,"⚡ Speed Hack","Speed",4, function(on) setSpeed(on and ST.SpeedVal or 16) end)
    mkSlider(PT,"Velocidade Walk",16,500,"SpeedVal",5, function(v) if ST.Speed then setSpeed(v) end end)
    mkToggle(PT,"🦘 Pulo Infinito","InfiniteJump",6)
    mkToggle(PT,"🔮 No Clip","NoClip",7)
    mkSec(PT,"🎣  PESCA & CLAN",8)
    mkToggle(PT,"Auto Pesca","AutoFishing",9, function(on) if on then loopFishing() end end)
    mkToggle(PT,"Auto Clan Spin","AutoClanSpin",10, function(on) if on then loopClan() end end)
    mkSec(PT,"🛡  ANTI-DETECÇÃO",11)
    mkToggle(PT,"Humanizar Ações","AntiDetect",12, function(on) AD.on=on end)
    mkBtn(PT,"♻ Recarregar Personagem",13, function() LP:LoadCharacter() end)
    mkBtn(PT,"🌐 Rejoin Servidor",14, function()
        pcall(function() TS:Teleport(game.PlaceId,LP) end)
    end)

    -- ── ESP ─────────────────────────────────────────────────
    local ET = frames["ESP"]
    mkSec(ET,"👁  ESP",1)
    mkToggle(ET,"ESP Mobs (roxo)","ESP_Mob",2, function() pcall(refreshESP) end)
    mkToggle(ET,"ESP Bosses (laranja)","ESP_Boss",3, function() pcall(refreshESP) end)
    mkToggle(ET,"ESP Jogadores (vermelho)","ESP_Player",4, function() pcall(refreshESP) end)
    mkBtn(ET,"🔄 Atualizar ESP",5, function() clearESP(); task.wait(0.1); pcall(refreshESP) end)
    mkBtn(ET,"🗑 Limpar ESP",6, function()
        clearESP(); ST.ESP_Mob=false; ST.ESP_Boss=false; ST.ESP_Player=false
        notify("✓ ESP limpo",T.Success)
    end)

    -- ── TP ──────────────────────────────────────────────────
    local TT = frames["TP"]
    mkSec(TT,"🌀  ZONAS",1)
    for i,z in ipairs(ZONES) do
        local zc=z
        mkBtn(TT,"📍 "..z,i+1, function()
            local found=false
            for _,obj in ipairs(WS:GetDescendants()) do
                if obj:IsA("BasePart") or obj:IsA("SpawnLocation") then
                    if obj.Name:lower():find(zc:sub(1,5):lower()) then
                        local hrp=getHRP()
                        if hrp then hrp.CFrame=obj.CFrame+Vector3.new(0,12,0) end
                        found=true; break
                    end
                end
            end
            notify(found and ("🌀 TP → "..zc) or ("Zona não mapeada: "..zc),
                   found and T.AccBrt or T.Warn)
        end)
    end
    mkSec(TT,"💀  BOSSES",#ZONES+3)
    for i,b in ipairs(BOSSES) do
        local bc=b
        mkBtn(TT,("💀 %s  Lv.%d"):format(b.N,b.Lv),#ZONES+3+i, function()
            local t=findMob(bc.N)
            if t then
                local r=t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
                if r then
                    local hrp=getHRP()
                    if hrp then hrp.CFrame=r.CFrame+Vector3.new(0,10,0) end
                    notify("💀 TP → "..bc.N,T.Warn)
                end
            else notify("Boss não encontrado",T.Danger) end
        end)
    end

    -- ── MISC ────────────────────────────────────────────────
    local MT = frames["Misc"]
    mkSec(MT,"⚙  UTILITÁRIOS",1)
    mkBtn(MT,"📋 Copiar UserID",2, function()
        pcall(function() setclipboard(tostring(LP.UserId)) end)
        notify("✓ UserID copiado!",T.Success)
    end)
    mkBtn(MT,"🌄 FPS Boost",3, function()
        pcall(function()
            local LC=game:GetService("Lighting")
            LC.GlobalShadows=false; LC.FogEnd=10000
            for _,v in ipairs(WS:GetDescendants()) do
                if v:IsA("BasePart") then v.CastShadow=false end
            end
        end)
        notify("✓ FPS Boost aplicado",T.Success)
    end)
    mkBtn(MT,"🔕 Remover Efeitos",4, function()
        pcall(function()
            for _,v in ipairs(WS:GetDescendants()) do
                if v:IsA("Atmosphere") or v:IsA("Sky") then v.Parent=nil end
            end
        end)
        notify("✓ Efeitos removidos",T.Success)
    end)

    mkSec(MT,"📊  DEBUG AO VIVO",5)
    local dbF=Instance.new("Frame",MT); dbF.Size=UDim2.new(1,0,0,100); dbF.BackgroundColor3=T.PanelDk
    dbF.BorderSizePixel=0; dbF.LayoutOrder=6; Instance.new("UICorner",dbF).CornerRadius=UDim.new(0,9)
    local dbL=Instance.new("TextLabel",dbF); dbL.Size=UDim2.new(1,-10,1,0); dbL.Position=UDim2.new(0,5,0,0)
    dbL.BackgroundTransparency=1; dbL.Font=Enum.Font.Code; dbL.TextScaled=true; dbL.TextWrapped=true
    dbL.TextColor3=T.TxtDim; dbL.TextXAlignment=Enum.TextXAlignment.Left; dbL.RichText=true

    RunService.Heartbeat:Connect(function()
        if not MT or not MT.Parent then return end
        pcall(function()
            local hum=getHum(); local hrp=getHRP()
            if hum and hrp then
                local qInfo = ""
                if ST.AutoQuestFarm then
                    qInfo = ('\n<font color="#7755aa">Quest:</font> <font color="#ffcc33">%s [%d/%d]</font>'):format(
                        QST.state, QST.killsDone, QST.killsNeeded)
                end
                dbL.Text = ('<font color="#7755aa">Player:</font> <font color="#bb88ff">%s</font>  <font color="#7755aa">HP:</font> <font color="#55cc77">%.0f</font>\n<font color="#7755aa">Pos:</font> <font color="#bb88ff">%.0f %.0f %.0f</font>\n<font color="#7755aa">Mob:</font> <font color="#cc99ff">%s</font>  <font color="#7755aa">Y:</font> <font color="#cc99ff">%d</font>%s'):format(
                    LP.DisplayName, hum.Health,
                    hrp.Position.X, hrp.Position.Y, hrp.Position.Z,
                    ST.TargetMob, ST.HitboxOffsetY, qInfo)
            end
        end)
    end)

    mkSec(MT,"ℹ  SOBRE",7)
    local aF=Instance.new("Frame",MT); aF.Size=UDim2.new(1,0,0,55); aF.BackgroundColor3=T.PanelDk
    aF.BorderSizePixel=0; aF.LayoutOrder=8; Instance.new("UICorner",aF).CornerRadius=UDim.new(0,9)
    local aL=Instance.new("TextLabel",aF); aL.Size=UDim2.new(1,-10,1,0); aL.Position=UDim2.new(0,5,0,0)
    aL.BackgroundTransparency=1; aL.Font=Enum.Font.Gotham; aL.TextScaled=true; aL.TextWrapped=true
    aL.RichText=true; aL.TextColor3=T.TxtDim
    aL.Text='<font color="#9933ee"><b>VOID.LAZY v4.0</b></font>  Mobile Edition\n<font color="#ffcc33">+Quest+Farm +Hitbox +Armas +Grouping</font>'

    -- ── DRAGGABLE ───────────────────────────────────────────
    local drag,dStart,dOrig=false,nil,nil
    HDR.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=true; dStart=i.Position; dOrig=MF.Position end end)
    HDR.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then
            local d=i.Position-dStart
            MF.Position=UDim2.new(dOrig.X.Scale,dOrig.X.Offset+d.X,dOrig.Y.Scale,dOrig.Y.Offset+d.Y)
        end end)
    UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=false end end)

    -- ── MINIMIZAR ───────────────────────────────────────────
    local minned=false
    MinBtn.MouseButton1Click:Connect(function()
        minned=not minned
        tw(MF,{Size=UDim2.new(0,FW,0,minned and 50 or FH)},0.3,Enum.EasingStyle.Quad,
            minned and Enum.EasingDirection.In or Enum.EasingDirection.Out)
    end)

    -- ── FECHAR ──────────────────────────────────────────────
    CloseBtn.MouseButton1Click:Connect(function()
        tw(MF,{Size=UDim2.new(0,0,0,0),Position=UDim2.new(0.5,0,0.5,0)},0.38,Enum.EasingStyle.Back,Enum.EasingDirection.In)
        task.wait(0.45)
        ST.AutoFarm=false; ST.AutoBoss=false; ST.AutoMastery=false
        ST.AutoQuest=false; ST.AutoFishing=false; ST.AutoClanSpin=false
        ST.AutoQuestFarm=false; ST.GroupMobs=false
        ST.Fly=false; ST.NoClip=false; ST.InfiniteJump=false
        QST.state="IDLE"
        for _,c in ipairs(ST.Connections) do pcall(function() c:Disconnect() end) end
        clearESP()
        pcall(function() SG:Destroy() end)
    end)

    -- ── INIT ────────────────────────────────────────────────
    switchTab("Farm")
    task.wait(0.6)
    notify("✦ VOID.LAZY v4.0 carregado!",T.AccBrt,3)
    task.wait(1.1)
    notify("🛡 Anti-Detecção ATIVO",T.Success,2.5)
    task.wait(1.2)
    notify("📋 Quest+Farm | 📐 Hitbox | 🗡 Armas",T.Warn,3)
end

end)

if not OK then
    task.spawn(function()
        local sg2=Instance.new("ScreenGui")
        sg2.Name="VOID_ERR"; sg2.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg2.DisplayOrder=9999
        sg2.ResetOnSpawn=false
        pcall(function() sg2.Parent=game:GetService("CoreGui") end)
        if not sg2.Parent then pcall(function() sg2.Parent=game:GetService("Players").LocalPlayer.PlayerGui end) end
        local f=Instance.new("Frame",sg2); f.Size=UDim2.new(0.9,0,0,80); f.Position=UDim2.new(0.05,0,0.4,0)
        f.BackgroundColor3=Color3.fromRGB(30,5,5); f.BorderSizePixel=0
        Instance.new("UICorner",f).CornerRadius=UDim.new(0,10)
        local l=Instance.new("TextLabel",f); l.Size=UDim2.new(1,-10,1,0); l.Position=UDim2.new(0,5,0,0)
        l.BackgroundTransparency=1; l.Font=Enum.Font.GothamBold; l.TextScaled=true
        l.TextWrapped=true; l.TextColor3=Color3.fromRGB(255,80,80)
        l.Text="VOID.LAZY ERRO:\n"..tostring(ERR)
    end)
end

print("[VOID.LAZY v4.0] Executado.")
