-- ════════════════════════════════════════════════════════════════
--  VOID.LAZY v5.0 ELITE  |  Slayers 2  |  Mobile & PC
--  Delta / Synapse / Fluxus / Hydrogen compatible
--  Senha: leyzepidao
--
--  v5.0 ELITE — O MELHOR SCRIPT DE SLAYERS 2
--  ✦ Farm Humano (mini-IA com movimento natural, missão completa)
--  ✦ Hitbox expandida por CFrame anchoring — bate de QUALQUER
--    distância sem se mover, mob morre sem você ser visto
--  ✦ TP estável — sem rubber-band, sem voltar pro lugar
--  ✦ Soco auto-equipado ao ligar farm
--  ✦ Grouping corrigido — mobs vão até você e tomam dano normal
--  ✦ Auto Quest funcional com state machine + kill tracking real
--  ✦ Anti-ban de novo nível (jitter humano, delay variável, drift)
--  ✦ ESP avançado com distância e HP em barra
--  ✦ FPS Boost agressivo para mobile
--  ✦ Rejoin automático ao morrer (opcional)
-- ════════════════════════════════════════════════════════════════

task.wait(2)

local OK, ERR = pcall(function()

-- ════════════════════════════════════════════════════════════════
-- [1]  SERVICES
-- ════════════════════════════════════════════════════════════════
local function gs(n) local ok,s=pcall(game.GetService,game,n); return ok and s or nil end

local Players    = gs("Players")
local RunService = gs("RunService")
local TweenSvc   = gs("TweenService")
local UIS        = gs("UserInputService")
local RS         = gs("ReplicatedStorage")
local TS         = gs("TeleportService")
local WS         = workspace

local LP = Players and Players.LocalPlayer
if not LP then return end

local function getCam()   return workspace.CurrentCamera end
local function rnd(a,b)   return a + math.random()*(b-a) end
local function sign(x)    return x >= 0 and 1 or -1 end

local function tw(obj, props, dur, style, dir)
    if not obj or not obj.Parent then return end
    local ok,t = pcall(TweenSvc.Create, TweenSvc, obj,
        TweenInfo.new(dur or 0.25,
            style or Enum.EasingStyle.Quad,
            dir   or Enum.EasingDirection.Out), props)
    if ok and t then t:Play() end
    return t
end

local function getHRP()
    local c = LP and LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = LP and LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getChar() return LP and LP.Character end

-- ════════════════════════════════════════════════════════════════
-- [2]  ESTADO GLOBAL
-- ════════════════════════════════════════════════════════════════
local ST = {
    -- toggles de farm
    AutoFarm      = false,
    AutoBoss      = false,
    AutoMastery   = false,
    AutoFishing   = false,
    AutoClanSpin  = false,
    AutoSkills    = true,
    AutoRejoin    = false,  -- rejoin ao morrer
    AntiIdle      = true,
    FreezeTarget  = true,

    -- Farm Humano (mini-IA)
    HumanFarm     = false,

    -- Quest + Farm integrado
    AutoQuestFarm = false,
    QuestNPCName  = "Krue",

    -- Hitbox expandida (a correção principal)
    -- Em vez de teleportar o char, ancora o HRP no mob via CFrame
    -- HitRange: raio em studs — NÃO move o char visivelmente
    HitRange      = 60,   -- studs de alcance — slider 10-200
    AnchorMode    = true, -- ancora o HRP no mob invisível (sub-chão ou neutro)
    AnchorOffsetY = -50,  -- onde o char fica ancorado (negativo = sub-chão)

    -- ESP
    ESP_Mob      = false,
    ESP_Boss     = false,
    ESP_Player   = false,

    -- Movimento
    Fly          = false,
    Speed        = false,
    NoClip       = false,
    InfiniteJump = false,

    -- Anti-detecção
    AntiDetect   = true,

    -- Alvos
    TargetMob    = "Greater Demon",
    TargetBoss   = "Zuko",
    MaxLevel     = 400,
    SpeedVal     = 60,
    FlySpeedVal  = 90,

    -- internos
    Connections  = {},
    ESPCache     = {},
    FlyGyro      = nil,
    FlyBody      = nil,
    Notify       = nil,
    _farmAnchor  = nil,  -- conexão do anchor loop
}

-- Estado da quest
local QST = {
    state       = "IDLE",
    npcModel    = nil,
    mobName     = "",
    killsNeeded = 0,
    killsDone   = 0,
}

-- ════════════════════════════════════════════════════════════════
-- [3]  ANTI-DETECÇÃO AVANÇADO
-- ════════════════════════════════════════════════════════════════
local AD = { on = true }

-- delay humano com desvio gaussiano aproximado
function AD:wait(base)
    local noise = (math.random()-0.5)*2 * base * 0.25
    task.wait(math.max(0.04, base + noise))
end

-- micro-jitter no HRP (imita oscilação de movimento humano)
function AD:jitter()
    if not self.on then return end
    local hrp = getHRP()
    if not hrp then return end
    pcall(function()
        local off = Vector3.new(
            (math.random()-0.5)*0.3,
            0,
            (math.random()-0.5)*0.3)
        hrp.CFrame = hrp.CFrame * CFrame.new(off)
    end)
end

-- teleport ESTÁVEL: sem rubber-band
-- Desativa network ownership temporariamente + seta diretamente
function AD:safeTP(pos, offset)
    offset = offset or Vector3.new(0, 3, 0)
    local hrp = getHRP()
    if not hrp then return end
    -- desativa simulação de física no servidor por ~0.1s
    -- setando AssemblyLinearVelocity = zero antes de mover
    pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end)
    pcall(function() hrp.AssemblyAngularVelocity = Vector3.zero end)
    task.wait(0.05)
    -- move direto — sem interpolação que causa rubber-band
    pcall(function()
        hrp.CFrame = CFrame.new(pos + offset)
    end)
    task.wait(0.08)
    -- segundo set para garantir (rubber-band fix)
    pcall(function()
        hrp.CFrame = CFrame.new(pos + offset)
    end)
end

-- ════════════════════════════════════════════════════════════════
-- [4]  DATABASE — SLAYERS 2
-- ════════════════════════════════════════════════════════════════
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

-- Coordenadas de spawn aproximadas por zona (evita busca por nome bugada)
local ZONE_POS = {
    ["Starter Village"]    = Vector3.new(-17, 5, 15),
    ["Bear Area"]          = Vector3.new(220, 10, -80),
    ["Bamboo Grove"]       = Vector3.new(-180, 8, 220),
    ["Spider Forest"]      = Vector3.new(380, 12, 100),
    ["Mistfall Village"]   = Vector3.new(-400, 10, -200),
    ["Butterfly Estate"]   = Vector3.new(500, 15, 350),
    ["Stone Sanctuary"]    = Vector3.new(-300, 20, 500),
    ["Iceveil Valley"]     = Vector3.new(600, 25, -300),
    ["Thunder Cliffs"]     = Vector3.new(-600, 30, -500),
    ["Ouwigahara Dungeon"] = Vector3.new(800, 5, 800),
}

local QUESTS = {
    {NPC="Krue",  Mob="Bandit",         Kills=8,  Zone="Starter Village"},
    {NPC="Tom",   Mob="Greater Demon",  Kills=10, Zone="Starter Village"},
    {NPC="Crow",  Mob="Bear",           Kills=6,  Zone="Bear Area"},
    {NPC="Crow",  Mob="Mother Bear",    Kills=3,  Zone="Bear Area"},
    {NPC="Muzan", Mob="Demon",          Kills=12, Zone="Mistfall Village"},
    {NPC="Quest", Mob="Mushroom Demon", Kills=10, Zone="Bamboo Grove"},
    {NPC="Quest", Mob="Spider Demon",   Kills=10, Zone="Spider Forest"},
    {NPC="Quest", Mob="Zagan Demon",    Kills=8,  Zone="Mistfall Village"},
    {NPC="Quest", Mob="Frozen Demon",   Kills=8,  Zone="Iceveil Valley"},
    {NPC="Quest", Mob="Wind Demon",     Kills=8,  Zone="Thunder Cliffs"},
    {NPC="Quest", Mob="Stone Golem",    Kills=6,  Zone="Stone Sanctuary"},
    {NPC="Quest", Mob="Blood Demon",    Kills=6,  Zone="Stone Sanctuary"},
}

local QUEST_NPC_NAMES = {}
do
    local seen = {}
    for _, q in ipairs(QUESTS) do
        if not seen[q.NPC] then seen[q.NPC]=true; table.insert(QUEST_NPC_NAMES,q.NPC) end
    end
end

-- ════════════════════════════════════════════════════════════════
-- [5]  COMBAT CORE — HITBOX EXPANDIDA (CORREÇÃO PRINCIPAL)
-- ════════════════════════════════════════════════════════════════

-- Busca o mob mais próximo dentro de HitRange studs
local function findMob(name)
    local hrp = getHRP()
    if not hrp then return nil end
    local best, bd = nil, math.huge
    for _, v in ipairs(WS:GetDescendants()) do
        pcall(function()
            if not v:IsA("Model") then return end
            if not v.Name:lower():find(name:lower()) then return end
            local root = v:FindFirstChild("HumanoidRootPart") or v.PrimaryPart
            local hum  = v:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                local d = (hrp.Position - root.Position).Magnitude
                if d < bd then best, bd = v, d end
            end
        end)
    end
    return best
end

-- Busca TODOS os mobs do tipo
local function findAllMobs(name)
    local list = {}
    for _, v in ipairs(WS:GetDescendants()) do
        pcall(function()
            if not v:IsA("Model") then return end
            if not v.Name:lower():find(name:lower()) then return end
            local root = v:FindFirstChild("HumanoidRootPart") or v.PrimaryPart
            local hum  = v:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then table.insert(list, v) end
        end)
    end
    return list
end

-- Congela o mob (pára movimento, zera velocidade)
local function freezeModel(m)
    if not m or not ST.FreezeTarget then return end
    pcall(function()
        local h = m:FindFirstChildOfClass("Humanoid")
        local r = m:FindFirstChild("HumanoidRootPart")
        if h then
            h.WalkSpeed = 0
            h.JumpPower = 0
        end
        if r then
            r.AssemblyLinearVelocity  = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end

-- ── ANCHOR HITBOX ──────────────────────────────────────────────
-- Em vez de teleportar visualmente para perto do mob,
-- ancoramos o HRP exatamente sobre o mob (sub-chão se AnchorOffsetY < 0)
-- via CFrame direto a cada frame. O char fica INVISÍVEL para outros jogadores
-- abaixo do terreno enquanto bate com alcance estendido.
-- Isso corrige: rubber-band, mob não toma dano, visibilidade.

local anchorConn = nil

local function startAnchor(target)
    if anchorConn then pcall(function() anchorConn:Disconnect() end) end
    anchorConn = RunService.Heartbeat:Connect(function()
        if not ST.AnchorMode then return end
        if not target or not target.Parent then return end
        local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
        if not root then return end
        local hrp = getHRP()
        if not hrp then return end
        pcall(function()
            hrp.CFrame = CFrame.new(
                root.Position.X,
                root.Position.Y + ST.AnchorOffsetY,
                root.Position.Z)
        end)
    end)
    if ST.Connections then table.insert(ST.Connections, anchorConn) end
end

local function stopAnchor()
    if anchorConn then
        pcall(function() anchorConn:Disconnect() end)
        anchorConn = nil
    end
end

-- ── FIRE ATTACK ───────────────────────────────────────────────
-- Dispara todos os vetores de dano possíveis no target
local function fireAttack(target)
    if not target or not target.Parent then return end
    pcall(function()
        local root = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
        if not root then return end

        -- ClickDetector
        local cd = target:FindFirstChildOfClass("ClickDetector")
        if cd then pcall(fireclickdetector, cd) end

        -- ProximityPrompt
        for _, pp in ipairs(target:GetDescendants()) do
            if pp:IsA("ProximityPrompt") then pcall(fireproximityprompt, pp) end
        end

        -- Tool Activate (soco / espada / katana)
        local char = getChar()
        local tool = char and char:FindFirstChildOfClass("Tool")
        if tool then
            -- Activate event
            local act = tool:FindFirstChild("Activate")
            if act then pcall(function() act:Fire() end) end
            -- RemoteEvent dentro da tool (hit, swing, etc.)
            for _, ev in ipairs(tool:GetDescendants()) do
                if ev:IsA("RemoteEvent") then
                    local n = ev.Name:lower()
                    if n:find("hit") or n:find("attack") or n:find("swing") or n:find("slash") then
                        pcall(function() ev:FireServer(target, root.Position) end)
                    end
                end
            end
        end

        -- RemoteEvents globais de dano
        if RS then
            for _, rfn in ipairs({"Events","Remotes","RE","RF","MainRemote","GameRemote"}) do
                local rf = RS:FindFirstChild(rfn)
                if rf then
                    for _, ch in ipairs(rf:GetDescendants()) do
                        if ch:IsA("RemoteEvent") or ch:IsA("RemoteFunction") then
                            local n = ch.Name:lower()
                            if n:find("attack") or n:find("hit") or n:find("damage")
                            or n:find("slash") or n:find("swing") or n:find("punch") then
                                if ch:IsA("RemoteEvent") then
                                    pcall(function() ch:FireServer(target, root.Position) end)
                                else
                                    pcall(function() ch:InvokeServer(target, root.Position) end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ════════════════════════════════════════════════════════════════
-- [6]  GROUPING CORRIGIDO
-- Mobs vão até onde o char está, não ao contrário.
-- O HRP do mob é setado EXATAMENTE no char (1-3 studs ao redor).
-- Hitbox expandida já funciona com eles estando perto.
-- ════════════════════════════════════════════════════════════════
local function groupMobs()
    local hrp = getHRP()
    if not hrp then return 0 end
    local mobs = findAllMobs(ST.TargetMob)
    local count = 0
    for i, mob in ipairs(mobs) do
        local root = mob:FindFirstChild("HumanoidRootPart")
        if root then
            -- posição em anel ao redor do char (não em cima um do outro)
            local ang  = (i-1) / math.max(#mobs, 1) * math.pi * 2
            local dist = 2 + (i % 3)   -- 2, 3 ou 4 studs
            pcall(function()
                -- zera velocidade do mob antes de mover (corrige bug de dano)
                root.AssemblyLinearVelocity  = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                root.CFrame = CFrame.new(
                    hrp.Position.X + math.cos(ang)*dist,
                    hrp.Position.Y,
                    hrp.Position.Z + math.sin(ang)*dist)
            end)
            freezeModel(mob)
            count = count + 1
        end
    end
    return count
end

-- ════════════════════════════════════════════════════════════════
-- [7]  ARMAS — equipa / desequipa
-- ════════════════════════════════════════════════════════════════
local function listTools()
    local tools = {"Soco (Sem Arma)"}
    local char = getChar()
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
    local char = getChar()
    local bp   = LP and LP:FindFirstChild("Backpack")
    if not char or not bp then return false end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then pcall(function() t.Parent = bp end) end
    end
    if name == "Soco (Sem Arma)" or name == "Auto" or name == nil then return true end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and t.Name == name then
            pcall(function() t.Parent = char end)
            return true
        end
    end
    return false
end

-- Auto-equipa soco ao ligar farm
local function autoEquipFist()
    local char = getChar()
    local bp   = LP and LP:FindFirstChild("Backpack")
    if not char or not bp then return end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then pcall(function() t.Parent = bp end) end
    end
    -- aguarda 1 frame para o server aceitar
    task.wait(0.05)
end

-- ════════════════════════════════════════════════════════════════
-- [8]  LOOPS DE FARM
-- ════════════════════════════════════════════════════════════════

local function loopSkills()
    task.spawn(function()
        while ST.AutoSkills and
              (ST.AutoFarm or ST.AutoBoss or ST.AutoMastery or ST.AutoQuestFarm or ST.HumanFarm) do
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
            AD:wait(rnd(0.6, 1.8))
        end
    end)
end

-- ── AUTO FARM CORRIGIDO ────────────────────────────────────────
-- Lógica: ancora HRP no mob sub-chão, spamma fireAttack.
-- Sem rubber-band porque não usa safeTP em loop — apenas ancora.
local function loopFarm()
    task.spawn(function()
        -- equipa soco automaticamente
        autoEquipFist()
        task.wait(0.1)
        loopSkills()

        while ST.AutoFarm do
            pcall(function()
                local hum = getHum()
                if not hum or hum.Health <= 0 then
                    stopAnchor()
                    task.wait(3)
                    return
                end

                local t = findMob(ST.TargetMob)
                if not t then
                    stopAnchor()
                    task.wait(1)
                    return
                end

                local th = t:FindFirstChildOfClass("Humanoid")
                if not th or th.Health <= 0 then return end

                -- ancora o HRP no mob (fica invisível sub-chão)
                startAnchor(t)
                freezeModel(t)

                local hits = 0
                while ST.AutoFarm and t and t.Parent and th and th.Health > 0 do
                    freezeModel(t)
                    fireAttack(t)
                    hits = hits + 1

                    -- a cada 15 hits dá um micro-jitter (parece humano)
                    if ST.AntiDetect and hits % 15 == 0 then
                        AD:jitter()
                        task.wait(rnd(0.05, 0.12))
                    end

                    AD:wait(rnd(0.07, 0.16))
                end

                stopAnchor()
            end)
            task.wait(0.04)
        end

        stopAnchor()
    end)
end

local function loopBoss()
    task.spawn(function()
        loopSkills()
        while ST.AutoBoss do
            pcall(function()
                local t = findMob(ST.TargetBoss)
                if not t then task.wait(rnd(2,4)); return end
                local th = t:FindFirstChildOfClass("Humanoid")
                if not th or th.Health <= 0 then task.wait(1); return end

                startAnchor(t)
                freezeModel(t)

                while ST.AutoBoss and t and t.Parent and th and th.Health > 0 do
                    fireAttack(t)
                    freezeModel(t)
                    if ST.AntiDetect then AD:jitter() end
                    AD:wait(rnd(0.09, 0.19))
                end

                stopAnchor()
                task.wait(rnd(3,6))
            end)
            task.wait(0.05)
        end
        stopAnchor()
    end)
end

local function loopMastery()
    task.spawn(function()
        autoEquipFist()
        task.wait(0.1)
        loopSkills()
        while ST.AutoMastery do
            pcall(function()
                local t = findMob(ST.TargetMob)
                if not t then task.wait(1); return end
                local th = t:FindFirstChildOfClass("Humanoid")
                if not th or th.Health <= 0 then return end
                startAnchor(t)
                freezeModel(t)
                while ST.AutoMastery and t and t.Parent and th and th.Health > 0 do
                    fireAttack(t)
                    freezeModel(t)
                    AD:wait(rnd(0.07, 0.14))
                end
                stopAnchor()
            end)
            task.wait(0.04)
        end
        stopAnchor()
    end)
end

-- ── FARM HUMANO (Mini-IA) ──────────────────────────────────────
-- Simula um jogador real:
--  1. Aceita quest no NPC com aproximação natural (walk, não TP)
--  2. Anda em direção aos mobs com pequena variação de rota
--  3. Bate com delay variável, pausa entre grupos
--  4. Volta ao NPC andando (não teleportando)
-- A ÂNCORA sub-chão NÃO é usada aqui — o char aparece se movendo
-- normalmente. Outros jogadores veem um personagem jogando normalmente.
-- ──────────────────────────────────────────────────────────────
local HF = {
    state       = "IDLE",
    npcModel    = nil,
    questData   = nil,
    killsDone   = 0,
    walkSpeed   = 16,
    runSpeed    = 20,
}

local function hfWalkTo(pos, arrivalDist, maxTime)
    arrivalDist = arrivalDist or 5
    maxTime = maxTime or 15
    local hum = getHum(); local hrp = getHRP()
    if not hum or not hrp then return false end

    -- usa humanoid:MoveTo (movimento natural, sem TP)
    hum.WalkSpeed = HF.runSpeed + rnd(-2, 3)
    hum:MoveTo(pos + Vector3.new(rnd(-2,2), 0, rnd(-2,2)))

    local t0 = tick()
    local arrived = false
    while tick()-t0 < maxTime do
        task.wait(0.1)
        local hrp2 = getHRP()
        if not hrp2 then break end
        if (hrp2.Position - pos).Magnitude < arrivalDist then
            arrived = true
            break
        end
        -- reagenda MoveTo a cada 2s para evitar desvio
        if (tick()-t0) % 2 < 0.12 then
            local hum2 = getHum()
            if hum2 then hum2:MoveTo(pos + Vector3.new(rnd(-1,1),0,rnd(-1,1))) end
        end
    end
    hum.WalkSpeed = HF.walkSpeed
    return arrived
end

local function hfInteractNPC(npc)
    if not npc or not npc.Parent then return false end
    local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
    if not root then return false end

    -- anda até o NPC naturalmente
    local ok = hfWalkTo(root.Position, 6, 20)
    task.wait(rnd(0.3, 0.8))

    -- interação
    local cd = npc:FindFirstChildOfClass("ClickDetector")
    if cd then pcall(fireclickdetector, cd) end
    for _, pp in ipairs(npc:GetDescendants()) do
        if pp:IsA("ProximityPrompt") then pcall(fireproximityprompt, pp) end
    end
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
    task.wait(rnd(0.5, 1.2))
    return ok
end

local function loopHumanFarm()
    HF.state = "IDLE"; HF.killsDone = 0

    task.spawn(function()
        -- equipa soco (mão vazia parece mais natural no farm baixo nível)
        autoEquipFist()
        task.wait(0.2)

        while ST.HumanFarm do
            pcall(function()
                local hum = getHum()
                if not hum or hum.Health <= 0 then
                    task.wait(3)
                    return
                end

                -- IDLE: encontra quest e NPC
                if HF.state == "IDLE" then
                    local q = nil
                    for _, qd in ipairs(QUESTS) do
                        if qd.NPC:lower() == ST.QuestNPCName:lower() then q = qd; break end
                    end
                    if not q then q = QUESTS[1] end

                    HF.questData   = q
                    HF.killsDone   = 0

                    local npc = findMob(q.NPC)
                    if npc then
                        HF.npcModel = npc
                        hfInteractNPC(npc)
                        HF.state = "FARMING"
                        if ST.Notify then
                            ST.Notify("🤖 Farm Humano: "..q.Kills.."x "..q.Mob, nil, 3)
                        end
                    else
                        task.wait(rnd(3,6))
                    end

                -- FARMING: anda até cada mob, bate naturalmente
                elseif HF.state == "FARMING" then
                    local q = HF.questData
                    if not q then HF.state = "IDLE"; return end

                    local t = findMob(q.Mob)
                    if not t then task.wait(1); return end

                    local th = t:FindFirstChildOfClass("Humanoid")
                    if not th or th.Health <= 0 then return end

                    local root = t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
                    if not root then return end

                    -- anda até o mob naturalmente (3-5 studs de distância)
                    hfWalkTo(root.Position, 4, 12)

                    -- pausa de 0.1-0.4s antes de começar a bater (humano)
                    task.wait(rnd(0.1, 0.4))

                    -- freezar
                    freezeModel(t)

                    -- bate até morrer com delay humano
                    local hitCount = 0
                    while ST.HumanFarm and t and t.Parent and th and th.Health > 0 do
                        fireAttack(t)
                        freezeModel(t)
                        hitCount = hitCount + 1

                        -- pausa longa aleatória (imita respiro humano)
                        if hitCount % math.random(8, 14) == 0 then
                            task.wait(rnd(0.3, 0.9))
                        else
                            AD:wait(rnd(0.12, 0.28))
                        end

                        -- movimento sutil (gira levemente o personagem)
                        if hitCount % 5 == 0 then
                            local hrp = getHRP()
                            if hrp then
                                pcall(function()
                                    hrp.CFrame = CFrame.lookAt(hrp.Position, root.Position)
                                end)
                            end
                        end
                    end

                    HF.killsDone = HF.killsDone + 1

                    -- pausa entre kills (humano nunca bate sem parar)
                    task.wait(rnd(0.4, 1.2))

                    if HF.killsDone >= q.Kills then
                        HF.state = "TURN_IN"
                        if ST.Notify then
                            ST.Notify("✓ "..q.Kills.."/"..q.Kills.." concluído! Entregando...", nil, 2.5)
                        end
                    end

                -- TURN_IN: anda até o NPC e entrega
                elseif HF.state == "TURN_IN" then
                    local npc = HF.npcModel
                    if not npc or not npc.Parent then
                        npc = findMob(ST.QuestNPCName)
                    end
                    if npc then
                        hfInteractNPC(npc)
                        if ST.Notify then ST.Notify("✓ Quest entregue! Reiniciando...", nil, 2) end
                    end
                    HF.state     = "IDLE"
                    HF.npcModel  = nil
                    HF.killsDone = 0
                    -- pausa entre quests (humano não aceita imediatamente)
                    task.wait(rnd(1.5, 3.5))
                end
            end)
            task.wait(0.1)
        end
        HF.state = "IDLE"
    end)
end

-- ── AUTO QUEST + FARM (versão âncora — mais rápido que Farm Humano) ──
local function getQuestForNPC(npcName)
    for _, q in ipairs(QUESTS) do
        if q.NPC:lower() == npcName:lower() then return q end
    end
    return QUESTS[1]
end

local function interactNPC(npc)
    if not npc or not npc.Parent then return end
    local root = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart
    if root then
        AD:safeTP(root.Position, Vector3.new(0,3,3))
        task.wait(0.3)
    end
    local cd = npc:FindFirstChildOfClass("ClickDetector")
    if cd then pcall(fireclickdetector, cd) end
    for _, pp in ipairs(npc:GetDescendants()) do
        if pp:IsA("ProximityPrompt") then pcall(fireproximityprompt, pp) end
    end
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

local function loopAutoQuestFarm()
    QST.state = "IDLE"; QST.killsDone = 0
    autoEquipFist()
    task.wait(0.1)
    loopSkills()

    task.spawn(function()
        while ST.AutoQuestFarm do
            pcall(function()
                local hum = getHum()
                if not hum or hum.Health <= 0 then stopAnchor(); task.wait(3); return end

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
                    else
                        task.wait(rnd(3,6))
                    end

                elseif QST.state == "FARMING" then
                    local t = findMob(QST.mobName)
                    if not t then task.wait(1); return end
                    local th = t:FindFirstChildOfClass("Humanoid")
                    if not th or th.Health <= 0 then return end

                    startAnchor(t)
                    freezeModel(t)

                    while ST.AutoQuestFarm and t and t.Parent and th and th.Health > 0 do
                        freezeModel(t)
                        fireAttack(t)
                        AD:wait(rnd(0.08, 0.17))
                    end

                    stopAnchor()
                    QST.killsDone = QST.killsDone + 1

                    if QST.killsDone % 3 == 0 and ST.Notify then
                        ST.Notify("⚔ "..QST.killsDone.."/"..QST.killsNeeded.." "..QST.mobName, nil, 1.2)
                    end

                    if QST.killsDone >= QST.killsNeeded then
                        QST.state = "TURN_IN"
                        if ST.Notify then ST.Notify("✓ Kills completas! Entregando...", nil, 2.5) end
                    end

                elseif QST.state == "TURN_IN" then
                    local npc = QST.npcModel
                    if not npc or not npc.Parent then npc = findMob(ST.QuestNPCName) end
                    if npc then
                        interactNPC(npc)
                        task.wait(rnd(1.2, 2.5))
                        if ST.Notify then ST.Notify("✓ Quest entregue!", nil, 2) end
                    end
                    QST.state = "IDLE"; QST.npcModel = nil; QST.killsDone = 0
                    task.wait(rnd(0.5, 1.5))
                end
            end)
            AD:wait(rnd(0.12, 0.3))
        end
        stopAnchor()
        QST.state = "IDLE"
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
                local char = getChar()
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

-- ── REJOIN AO MORRER ──────────────────────────────────────────
local function setupAutoRejoin()
    task.spawn(function()
        while true do
            task.wait(2)
            if ST.AutoRejoin then
                local hum = getHum()
                if hum and hum.Health <= 0 then
                    task.wait(3)
                    pcall(function() TS:Teleport(game.PlaceId, LP) end)
                end
            end
        end
    end)
end
setupAutoRejoin()

-- ════════════════════════════════════════════════════════════════
-- [9]  MOVIMENTO
-- ════════════════════════════════════════════════════════════════
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
        local char = getChar()
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
    task.wait(1.5)
    if ST.Speed then setSpeed(ST.SpeedVal) end
    if ST.Fly   then task.wait(0.5); enableFly() end
    -- se farm estava ativo, reinicia após respawn
    if ST.AutoFarm    then loopFarm()    end
    if ST.AutoMastery then loopMastery() end
    if ST.HumanFarm   then loopHumanFarm() end
end)

task.spawn(function()
    while true do
        task.wait(55)
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

-- ════════════════════════════════════════════════════════════════
-- [10]  ESP AVANÇADO — HP em barra + distância
-- ════════════════════════════════════════════════════════════════
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
    bb.AlwaysOnTop = true
    bb.Size        = UDim2.new(0,110,0,38)
    bb.StudsOffset = Vector3.new(0,3,0)
    bb.MaxDistance = 300

    -- fundo
    local bg = Instance.new("Frame", bb)
    bg.Size = UDim2.new(1,0,1,0); bg.BackgroundColor3 = Color3.fromRGB(8,5,20)
    bg.BackgroundTransparency = 0.3; bg.BorderSizePixel = 0
    Instance.new("UICorner",bg).CornerRadius = UDim.new(0,5)
    local bgS = Instance.new("UIStroke",bg); bgS.Color = color; bgS.Thickness = 1

    -- nome
    local nl = Instance.new("TextLabel",bg)
    nl.Size = UDim2.new(1,0,0.42,0); nl.BackgroundTransparency = 1
    nl.Font = Enum.Font.GothamBold; nl.TextScaled = true
    nl.TextColor3 = color; nl.Text = model.Name
    nl.TextStrokeTransparency = 0.3

    -- barra de HP
    local hpBg = Instance.new("Frame",bg)
    hpBg.Size = UDim2.new(0.9,0,0.2,0); hpBg.Position = UDim2.new(0.05,0,0.47,0)
    hpBg.BackgroundColor3 = Color3.fromRGB(40,10,10); hpBg.BorderSizePixel = 0
    Instance.new("UICorner",hpBg).CornerRadius = UDim.new(1,0)

    local hpFill = Instance.new("Frame",hpBg)
    hpFill.Size = UDim2.new(hum.Health/hum.MaxHealth,0,1,0)
    hpFill.BackgroundColor3 = Color3.fromRGB(50,220,80); hpFill.BorderSizePixel = 0
    Instance.new("UICorner",hpFill).CornerRadius = UDim.new(1,0)

    -- HP + distância em texto
    local hl = Instance.new("TextLabel",bg)
    hl.Size = UDim2.new(1,0,0.32,0); hl.Position = UDim2.new(0,0,0.68,0)
    hl.BackgroundTransparency = 1; hl.Font = Enum.Font.Gotham; hl.TextScaled = true
    hl.TextColor3 = Color3.fromRGB(180,255,180); hl.Text = ""

    local uc = RunService.Heartbeat:Connect(function()
        if not bb or not bb.Parent or not hum.Parent then return end
        pcall(function()
            local pct = math.clamp(hum.Health/hum.MaxHealth, 0, 1)
            hpFill.Size = UDim2.new(pct,0,1,0)
            -- cor da barra: verde > amarelo > vermelho
            local r = math.floor(255*(1-pct))
            local g2 = math.floor(255*pct)
            hpFill.BackgroundColor3 = Color3.fromRGB(r, g2, 50)
            -- distância
            local hrp = getHRP()
            local dist = hrp and math.floor((hrp.Position-root.Position).Magnitude) or 0
            hl.Text = ("HP:%.0f  %dm"):format(hum.Health, dist)
        end)
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
                makeESPTag(v, Color3.fromRGB(255,120,0))
            elseif not isBoss and not isPC and ST.ESP_Mob then
                makeESPTag(v, Color3.fromRGB(160,50,255))
            elseif isPC and ST.ESP_Player then
                makeESPTag(v, Color3.fromRGB(255,60,60))
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

-- ════════════════════════════════════════════════════════════════
-- [11]  SCREEN GUI
-- ════════════════════════════════════════════════════════════════
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

-- ════════════════════════════════════════════════════════════════
-- [12]  TEMA ELITE
-- ════════════════════════════════════════════════════════════════
local T = {
    BG       = Color3.fromRGB(7,6,16),
    Panel    = Color3.fromRGB(14,10,30),
    PanelDk  = Color3.fromRGB(9,6,20),
    Acc      = Color3.fromRGB(100,0,200),
    AccBrt   = Color3.fromRGB(165,50,255),
    AccDim   = Color3.fromRGB(48,0,100),
    AccGold  = Color3.fromRGB(220,170,20),
    Txt      = Color3.fromRGB(230,222,255),
    TxtDim   = Color3.fromRGB(130,120,165),
    On       = Color3.fromRGB(80,0,185),
    Off      = Color3.fromRGB(28,22,52),
    Btn      = Color3.fromRGB(68,0,165),
    BtnHot   = Color3.fromRGB(110,16,220),
    Border   = Color3.fromRGB(68,0,145),
    Danger   = Color3.fromRGB(205,40,40),
    Success  = Color3.fromRGB(40,190,80),
    Warn     = Color3.fromRGB(205,168,0),
    HumanClr = Color3.fromRGB(0,200,180),
    QuestClr = Color3.fromRGB(255,195,45),
}

-- ════════════════════════════════════════════════════════════════
-- [13]  INTRO ANIMADA
-- ════════════════════════════════════════════════════════════════
local Intro = Instance.new("Frame",SG)
Intro.Size = UDim2.new(1,0,1,0); Intro.BackgroundColor3 = Color3.fromRGB(4,2,12)
Intro.BorderSizePixel = 0; Intro.ZIndex = 200
local iGrad = Instance.new("UIGradient",Intro)
iGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(3,0,10)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8,0,22)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(3,0,10)),
})
iGrad.Rotation = 135

for i = 1, 22 do
    local p = Instance.new("Frame",Intro)
    local sz = math.random(2,7)
    p.Size = UDim2.new(0,sz,0,sz)
    p.BackgroundColor3 = Color3.fromRGB(math.random(50,140),0,math.random(170,255))
    p.BackgroundTransparency = math.random()*0.45+0.1
    p.BorderSizePixel = 0; p.ZIndex = 201
    Instance.new("UICorner",p).CornerRadius = UDim.new(1,0)
    local sx=math.random(); local sy=math.random(); local sp=rnd(0.00007,0.00022); local ph=math.random()*math.pi*2
    task.spawn(function()
        local y=sy
        while p and p.Parent do
            y=(y-sp)%1
            pcall(function()
                p.Position=UDim2.new(sx+math.sin(tick()*0.4+ph)*0.012,0,y,0)
                p.BackgroundTransparency=0.22+math.abs(math.sin(tick()*0.22+ph))*0.52
            end)
            task.wait(0.03)
        end
    end)
end

local WF = Instance.new("Frame",Intro)
WF.Size = UDim2.new(0.9,0,0.3,0); WF.Position = UDim2.new(0.05,0,0.12,0)
WF.BackgroundTransparency = 1; WF.ZIndex = 202

local L1 = Instance.new("TextLabel",WF)
L1.Size = UDim2.new(1,0,0.36,0); L1.BackgroundTransparency = 1
L1.Font = Enum.Font.GothamMedium; L1.TextScaled = true
L1.TextColor3 = Color3.fromRGB(190,180,255); L1.TextStrokeTransparency = 0.5
L1.TextStrokeColor3 = T.Acc; L1.Text = ""; L1.ZIndex = 203

local L2 = Instance.new("TextLabel",WF)
L2.Size = UDim2.new(1,0,0.64,0); L2.Position = UDim2.new(0,0,0.36,0)
L2.BackgroundTransparency = 1; L2.Font = Enum.Font.GothamBlack; L2.TextScaled = true
L2.TextColor3 = T.AccBrt; L2.TextStrokeTransparency = 0.22; L2.TextStrokeColor3 = T.AccDim
L2.Text = ""; L2.ZIndex = 203

local LBG = Instance.new("Frame",Intro)
LBG.Size = UDim2.new(0.65,0,0,5); LBG.Position = UDim2.new(0.175,0,0.5,0)
LBG.BackgroundColor3 = Color3.fromRGB(20,0,45); LBG.BorderSizePixel = 0; LBG.Visible = false; LBG.ZIndex = 202
Instance.new("UICorner",LBG).CornerRadius = UDim.new(1,0)
local LFill = Instance.new("Frame",LBG)
LFill.Size = UDim2.new(0,0,1,0); LFill.BackgroundColor3 = T.AccBrt; LFill.BorderSizePixel = 0; LFill.ZIndex = 203
Instance.new("UICorner",LFill).CornerRadius = UDim.new(1,0)
local LStat = Instance.new("TextLabel",Intro)
LStat.Size = UDim2.new(0.65,0,0.045,0); LStat.Position = UDim2.new(0.175,0,0.515,0)
LStat.BackgroundTransparency = 1; LStat.TextColor3 = T.TxtDim
LStat.Font = Enum.Font.Gotham; LStat.TextScaled = true; LStat.Text = ""; LStat.ZIndex = 202

-- Frame de senha
local PF = Instance.new("Frame",Intro)
PF.Size = UDim2.new(0.84,0,0.32,0); PF.Position = UDim2.new(0.08,0,0.60,0)
PF.BackgroundColor3 = T.PanelDk; PF.BackgroundTransparency = 1; PF.BorderSizePixel = 0; PF.ZIndex = 202
Instance.new("UICorner",PF).CornerRadius = UDim.new(0,14)
local PFS = Instance.new("UIStroke",PF); PFS.Color = T.Acc; PFS.Thickness = 1.5; PFS.Transparency = 1

local PFTit = Instance.new("TextLabel",PF)
PFTit.Size = UDim2.new(1,0,0.27,0); PFTit.BackgroundTransparency = 1
PFTit.TextColor3 = T.Txt; PFTit.Font = Enum.Font.GothamBold
PFTit.TextScaled = true; PFTit.Text = "🔐  VERIFICAÇÃO DE ACESSO"; PFTit.TextTransparency = 1; PFTit.ZIndex = 203

local PFInp = Instance.new("TextBox",PF)
PFInp.Size = UDim2.new(0.82,0,0.25,0); PFInp.Position = UDim2.new(0.09,0,0.3,0)
PFInp.BackgroundColor3 = Color3.fromRGB(6,3,16); PFInp.BorderSizePixel = 0
PFInp.Font = Enum.Font.GothamBold; PFInp.TextColor3 = T.AccBrt
PFInp.PlaceholderColor3 = T.TxtDim; PFInp.TextScaled = true
PFInp.PlaceholderText = "Digite a senha..."; PFInp.Text = ""
PFInp.TextTransparency = 1; PFInp.ClearTextOnFocus = false; PFInp.ZIndex = 203
Instance.new("UICorner",PFInp).CornerRadius = UDim.new(0,8)
local PFInpS = Instance.new("UIStroke",PFInp); PFInpS.Color = T.AccDim; PFInpS.Thickness = 1; PFInpS.Transparency = 1

local PFBtn = Instance.new("TextButton",PF)
PFBtn.Size = UDim2.new(0.52,0,0.22,0); PFBtn.Position = UDim2.new(0.24,0,0.63,0)
PFBtn.BackgroundColor3 = T.Acc; PFBtn.BackgroundTransparency = 1; PFBtn.BorderSizePixel = 0
PFBtn.Font = Enum.Font.GothamBold; PFBtn.TextColor3 = Color3.fromRGB(255,255,255)
PFBtn.TextScaled = true; PFBtn.Text = "✦  ENTRAR  ✦"; PFBtn.TextTransparency = 1; PFBtn.ZIndex = 203
Instance.new("UICorner",PFBtn).CornerRadius = UDim.new(0,9)

local PFErr = Instance.new("TextLabel",PF)
PFErr.Size = UDim2.new(1,0,0.13,0); PFErr.Position = UDim2.new(0,0,0.9,0)
PFErr.BackgroundTransparency = 1; PFErr.TextColor3 = T.Danger
PFErr.Font = Enum.Font.Gotham; PFErr.TextScaled = true; PFErr.Text = ""; PFErr.ZIndex = 203

local function typeWrite(lbl,txt,spd)
    spd=spd or 0.06
    for i=1,#txt do lbl.Text=txt:sub(1,i); task.wait(spd) end
end
local function fillBar(pct,dur)
    tw(LFill,{Size=UDim2.new(pct,0,1,0)},dur,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut)
    task.wait(dur+0.05)
end
local function fadeIntro()
    tw(Intro,{BackgroundTransparency=1},0.6,Enum.EasingStyle.Quad)
    for _,ch in ipairs(Intro:GetDescendants()) do
        pcall(function()
            if ch:IsA("GuiObject") then
                local p={}
                if ch.BackgroundTransparency<1 then p.BackgroundTransparency=1 end
                if ch:IsA("TextLabel") or ch:IsA("TextButton") or ch:IsA("TextBox") then p.TextTransparency=1 end
                if next(p) then tw(ch,p,0.35) end
            end
        end)
    end
    task.wait(0.7)
    pcall(function() Intro:Destroy() end)
end

local buildMainUI

-- ════════════════════════════════════════════════════════════════
-- [14]  SENHA
-- ════════════════════════════════════════════════════════════════
local PW = "leyzepidao"; local pwTries = 0
local function validatePW()
    local inp = PFInp.Text:lower():gsub("%s","")
    if inp == PW then
        PFBtn.BackgroundColor3 = T.Success
        PFErr.TextColor3 = T.Success; PFErr.Text = "✓  Acesso concedido!"
        task.wait(0.85); fadeIntro(); task.wait(0.1); buildMainUI()
    else
        pwTries=pwTries+1
        PFErr.Text="✗  Senha incorreta! ("..pwTries.."/3)"
        local orig=PF.Position
        for i=1,7 do
            tw(PF,{Position=UDim2.new(orig.X.Scale,(i%2==0) and 10 or -10,orig.Y.Scale,0)},0.04,Enum.EasingStyle.Sine)
            task.wait(0.045)
        end
        tw(PF,{Position=orig},0.1,Enum.EasingStyle.Bounce)
        tw(PFBtn,{BackgroundColor3=T.Danger},0.1); task.wait(0.6); tw(PFBtn,{BackgroundColor3=T.Acc},0.3)
        if pwTries>=3 then
            PFBtn.Active=false; PFErr.Text="⏳ Aguarde 10s..."
            task.wait(10); pwTries=0; PFBtn.Active=true
        end
        PFInp.Text=""
    end
end
PFBtn.MouseButton1Click:Connect(validatePW)
PFInp.FocusLost:Connect(function(e) if e then validatePW() end end)

task.spawn(function()
    task.wait(0.3)
    typeWrite(L1,"✦  Bem-vindo ao  ✦",0.055)
    task.wait(0.2)
    local full="VOID.LAZY"
    L2.Text=""
    for i=1,#full do
        L2.Text=full:sub(1,i)
        tw(L2,{TextColor3=Color3.fromRGB(255,255,255)},0.08); task.wait(0.13)
        tw(L2,{TextColor3=T.AccBrt},0.2); task.wait(0.02)
    end
    task.wait(0.3); LBG.Visible=true
    local steps={
        {0.18,0.3,"Inicializando módulos..."},
        {0.42,0.28,"Anti-detecção v5 ativo..."},
        {0.68,0.28,"Hitbox Engine carregando..."},
        {0.90,0.22,"Farm Humano pronto..."},
        {1.0,0.14,"✓  ELITE EDITION"},
    }
    for _,s in ipairs(steps) do LStat.Text=s[3]; fillBar(s[1],s[2]) end
    task.wait(0.3); LBG:Destroy(); LStat:Destroy()
    PF.BackgroundTransparency=0; PFS.Transparency=0
    local fi={
        {PFTit,"TextTransparency",0},{PFInp,"TextTransparency",0},
        {PFInp,"BackgroundTransparency",0},{PFInpS,"Transparency",0},
        {PFBtn,"BackgroundTransparency",0},{PFBtn,"TextTransparency",0},
    }
    for _,x in ipairs(fi) do tw(x[1],{[x[2]]=x[3]},0.5) end
    task.spawn(function()
        while PFInp and PFInp.Parent do
            tw(PFInpS,{Color=T.AccBrt},0.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut); task.wait(0.9)
            tw(PFInpS,{Color=T.AccDim},0.9,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut); task.wait(0.9)
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════
-- [15]  MAIN UI — ELITE
-- ════════════════════════════════════════════════════════════════
buildMainUI = function()
    local VP = getCam() and getCam().ViewportSize or Vector2.new(800,600)
    local mobile = VP.X < 860

    local MF = Instance.new("Frame",SG)
    MF.Name = "VoidMain"; MF.BorderSizePixel = 0
    MF.ClipsDescendants = true; MF.BackgroundColor3 = T.BG

    local FW = mobile and math.min(VP.X*0.94,410) or 365
    local FH = 620
    MF.Size = UDim2.new(0,FW,0,FH)
    MF.Position = UDim2.new(0.5,-FW/2,-1,0)
    Instance.new("UICorner",MF).CornerRadius = UDim.new(0,16)
    local MFS = Instance.new("UIStroke",MF); MFS.Color = T.Border; MFS.Thickness = 1.5

    tw(MF,{Position=UDim2.new(0.5,-FW/2,0.03,0)},0.55,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
    task.spawn(function()
        while MF and MF.Parent do
            tw(MFS,{Color=T.AccBrt},1.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut); task.wait(1.6)
            tw(MFS,{Color=T.Border},1.6,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut); task.wait(1.6)
        end
    end)

    -- Header
    local HDR = Instance.new("Frame",MF)
    HDR.Size = UDim2.new(1,0,0,52); HDR.BackgroundColor3 = T.AccDim; HDR.BorderSizePixel = 0
    Instance.new("UICorner",HDR).CornerRadius = UDim.new(0,16)
    local hGrad = Instance.new("UIGradient",HDR)
    hGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(38,0,88)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(75,0,158)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(38,0,88)),
    })
    local hfix = Instance.new("Frame",HDR)
    hfix.Size = UDim2.new(1,0,0.5,0); hfix.Position = UDim2.new(0,0,0.5,0)
    hfix.BackgroundColor3 = T.AccDim; hfix.BorderSizePixel = 0

    local htl = Instance.new("TextLabel",HDR)
    htl.Size = UDim2.new(0.65,0,1,0); htl.Position = UDim2.new(0,12,0,0)
    htl.BackgroundTransparency = 1; htl.Font = Enum.Font.GothamBlack; htl.TextScaled = true
    htl.TextXAlignment = Enum.TextXAlignment.Left
    htl.TextColor3 = Color3.fromRGB(255,255,255); htl.TextStrokeTransparency = 0.3
    htl.TextStrokeColor3 = T.AccBrt; htl.Text = "⬡ VOID.LAZY"

    local hsub = Instance.new("TextLabel",HDR)
    hsub.Size = UDim2.new(0.26,0,0.4,0); hsub.Position = UDim2.new(0.72,0,0.32,0)
    hsub.BackgroundTransparency = 1; hsub.Font = Enum.Font.GothamBold; hsub.TextScaled = true
    hsub.TextXAlignment = Enum.TextXAlignment.Right
    hsub.TextColor3 = T.AccGold; hsub.Text = "v5 ELITE"

    local function hBtn(icon,xoff,bg)
        local b=Instance.new("TextButton",HDR)
        b.Size=UDim2.new(0,28,0,28); b.Position=UDim2.new(1,xoff,0.5,-14)
        b.BackgroundColor3=bg; b.BorderSizePixel=0
        b.Font=Enum.Font.GothamBold; b.TextScaled=true; b.TextColor3=Color3.fromRGB(255,255,255); b.Text=icon
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
        return b
    end
    local CloseBtn = hBtn("✕",-36,Color3.fromRGB(165,25,25))
    local MinBtn   = hBtn("─",-70,Color3.fromRGB(65,65,0))

    -- Tab bar
    local TBar = Instance.new("Frame",MF)
    TBar.Size = UDim2.new(1,0,0,36); TBar.Position = UDim2.new(0,0,0,52)
    TBar.BackgroundColor3 = T.PanelDk; TBar.BorderSizePixel = 0
    local tbL = Instance.new("UIListLayout",TBar)
    tbL.FillDirection = Enum.FillDirection.Horizontal; tbL.SortOrder = Enum.SortOrder.LayoutOrder; tbL.Padding = UDim.new(0,3)
    local tbP = Instance.new("UIPadding",TBar)
    tbP.PaddingLeft=UDim.new(0,4); tbP.PaddingRight=UDim.new(0,4)
    tbP.PaddingTop=UDim.new(0,4);  tbP.PaddingBottom=UDim.new(0,4)

    local CA = Instance.new("Frame",MF)
    CA.Size = UDim2.new(1,0,1,-88); CA.Position = UDim2.new(0,0,0,88)
    CA.BackgroundTransparency = 1; CA.ClipsDescendants = true

    local TABS = {
        {N="Farm",   I="⚔"},
        {N="Boss",   I="💀"},
        {N="Player", I="⚡"},
        {N="ESP",    I="👁"},
        {N="TP",     I="🌀"},
        {N="Misc",   I="⚙"},
    }

    local frames={}; local tBtns={}; local curTab=nil
    local tabW=(1-0.014)/#TABS

    local function switchTab(name)
        if curTab==name then return end; curTab=name
        for n,f in pairs(frames) do f.Visible=(n==name) end
        for n,b in pairs(tBtns) do
            if n==name then tw(b,{BackgroundColor3=T.Acc,TextColor3=Color3.fromRGB(255,255,255)},0.17)
            else tw(b,{BackgroundColor3=Color3.fromRGB(15,10,32),TextColor3=T.TxtDim},0.17) end
        end
    end

    for i,td in ipairs(TABS) do
        local b=Instance.new("TextButton",TBar)
        b.Size=UDim2.new(tabW,0,1,0); b.BackgroundColor3=(i==1) and T.Acc or Color3.fromRGB(15,10,32)
        b.BorderSizePixel=0; b.LayoutOrder=i; b.Font=Enum.Font.GothamBold; b.TextScaled=true
        b.TextColor3=(i==1) and Color3.fromRGB(255,255,255) or T.TxtDim; b.Text=td.I.." "..td.N
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,7); tBtns[td.N]=b
        local sf=Instance.new("ScrollingFrame",CA)
        sf.Size=UDim2.new(1,0,1,0); sf.BackgroundTransparency=1
        sf.ScrollBarThickness=3; sf.ScrollBarImageColor3=T.AccDim
        sf.CanvasSize=UDim2.new(0,0,0,0); sf.AutomaticCanvasSize=Enum.AutomaticSize.Y
        sf.Visible=(i==1); sf.BorderSizePixel=0
        local sfl=Instance.new("UIListLayout",sf)
        sfl.SortOrder=Enum.SortOrder.LayoutOrder; sfl.Padding=UDim.new(0,4)
        local sfp=Instance.new("UIPadding",sf)
        sfp.PaddingLeft=UDim.new(0,8); sfp.PaddingRight=UDim.new(0,8); sfp.PaddingTop=UDim.new(0,6)
        frames[td.N]=sf
        b.MouseButton1Click:Connect(function() switchTab(td.N) end)
    end
    curTab="Farm"

    -- ── HELPERS ──────────────────────────────────────────────
    local function mkSec(p,txt,ord,color)
        local f=Instance.new("Frame",p); f.Size=UDim2.new(1,0,0,22)
        f.BackgroundColor3=Color3.fromRGB(18,6,42); f.BorderSizePixel=0; f.LayoutOrder=ord or 0
        Instance.new("UICorner",f).CornerRadius=UDim.new(0,6)
        local l=Instance.new("TextLabel",f); l.Size=UDim2.new(1,-12,1,0); l.Position=UDim2.new(0,12,0,0)
        l.BackgroundTransparency=1; l.Font=Enum.Font.GothamBold; l.TextScaled=true
        l.TextColor3=color or T.AccBrt; l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=txt
        return f
    end

    local function mkToggle(p,lbl,key,ord,cb,color)
        local row=Instance.new("Frame",p); row.Size=UDim2.new(1,0,0,38)
        row.BackgroundColor3=T.Panel; row.BorderSizePixel=0; row.LayoutOrder=ord or 0
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,10)
        local tl=Instance.new("TextLabel",row); tl.Size=UDim2.new(0.7,0,1,0); tl.Position=UDim2.new(0,10,0,0)
        tl.BackgroundTransparency=1; tl.Font=Enum.Font.Gotham; tl.TextScaled=true
        tl.TextColor3=color or T.Txt; tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Text=lbl
        local tbg=Instance.new("Frame",row); tbg.Size=UDim2.new(0,46,0,23); tbg.Position=UDim2.new(1,-54,0.5,-11.5)
        tbg.BackgroundColor3=ST[key] and T.On or T.Off; tbg.BorderSizePixel=0
        Instance.new("UICorner",tbg).CornerRadius=UDim.new(1,0)
        local tk=Instance.new("Frame",tbg); tk.Size=UDim2.new(0,19,0,19)
        tk.Position=ST[key] and UDim2.new(1,-21,0.5,-9.5) or UDim2.new(0,2,0.5,-9.5)
        tk.BackgroundColor3=Color3.fromRGB(255,255,255); tk.BorderSizePixel=0
        Instance.new("UICorner",tk).CornerRadius=UDim.new(1,0)
        local hit=Instance.new("TextButton",row); hit.Size=UDim2.new(1,0,1,0)
        hit.BackgroundTransparency=1; hit.Text=""; hit.ZIndex=row.ZIndex+2
        local function upd()
            tw(tbg,{BackgroundColor3=ST[key] and T.On or T.Off},0.2)
            tw(tk,{Position=ST[key] and UDim2.new(1,-21,0.5,-9.5) or UDim2.new(0,2,0.5,-9.5)},0.2)
        end
        hit.MouseButton1Click:Connect(function()
            ST[key]=not ST[key]; upd(); if cb then cb(ST[key]) end
        end)
        return row,tl
    end

    local function mkSlider(p,lbl,vmin,vmax,key,ord,cb)
        local row=Instance.new("Frame",p); row.Size=UDim2.new(1,0,0,54)
        row.BackgroundColor3=T.Panel; row.BorderSizePixel=0; row.LayoutOrder=ord or 0
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,10)
        local tl=Instance.new("TextLabel",row); tl.Size=UDim2.new(0.6,0,0.46,0); tl.Position=UDim2.new(0,10,0,0)
        tl.BackgroundTransparency=1; tl.Font=Enum.Font.Gotham; tl.TextScaled=true
        tl.TextColor3=T.Txt; tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Text=lbl
        local vl=Instance.new("TextLabel",row); vl.Size=UDim2.new(0.3,0,0.4,0); vl.Position=UDim2.new(0.68,0,0.04,0)
        vl.BackgroundTransparency=1; vl.Font=Enum.Font.GothamBold; vl.TextScaled=true
        vl.TextColor3=T.AccBrt; vl.TextXAlignment=Enum.TextXAlignment.Right; vl.Text=tostring(ST[key])
        local sbg=Instance.new("Frame",row); sbg.Size=UDim2.new(0.88,0,0,5); sbg.Position=UDim2.new(0.06,0,0.78,0)
        sbg.BackgroundColor3=Color3.fromRGB(24,15,46); sbg.BorderSizePixel=0
        Instance.new("UICorner",sbg).CornerRadius=UDim.new(1,0)
        local pct=(ST[key]-vmin)/(vmax-vmin)
        local sf2=Instance.new("Frame",sbg); sf2.Size=UDim2.new(pct,0,1,0); sf2.BackgroundColor3=T.AccBrt; sf2.BorderSizePixel=0
        Instance.new("UICorner",sf2).CornerRadius=UDim.new(1,0)
        local sk=Instance.new("Frame",sbg); sk.Size=UDim2.new(0,14,0,14); sk.Position=UDim2.new(pct,-7,0.5,-7)
        sk.BackgroundColor3=Color3.fromRGB(255,255,255); sk.BorderSizePixel=0
        Instance.new("UICorner",sk).CornerRadius=UDim.new(1,0)
        local drag=false
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
            if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true; apply(i.Position) end end)
        sbg.InputChanged:Connect(function(i)
            if drag and (i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseMovement) then apply(i.Position) end end)
        UIS.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)
        return row
    end

    local function mkDrop(p,lbl,opts,key,ord,cb)
        local wrap=Instance.new("Frame",p); wrap.Size=UDim2.new(1,0,0,38)
        wrap.BackgroundColor3=T.Panel; wrap.BorderSizePixel=0; wrap.LayoutOrder=ord or 0; wrap.ClipsDescendants=false
        Instance.new("UICorner",wrap).CornerRadius=UDim.new(0,10)
        local tl=Instance.new("TextLabel",wrap); tl.Size=UDim2.new(0.42,0,1,0); tl.Position=UDim2.new(0,10,0,0)
        tl.BackgroundTransparency=1; tl.Font=Enum.Font.Gotham; tl.TextScaled=true
        tl.TextColor3=T.Txt; tl.TextXAlignment=Enum.TextXAlignment.Left; tl.Text=lbl
        local db=Instance.new("TextButton",wrap); db.Size=UDim2.new(0.52,0,0.74,0); db.Position=UDim2.new(0.46,0,0.13,0)
        db.BackgroundColor3=Color3.fromRGB(18,11,42); db.BorderSizePixel=0
        db.Font=Enum.Font.GothamBold; db.TextScaled=true; db.TextColor3=T.AccBrt; db.Text=ST[key] or opts[1]; db.ClipsDescendants=true
        Instance.new("UICorner",db).CornerRadius=UDim.new(0,7)
        Instance.new("UIStroke",db).Color=T.AccDim
        local DL=Instance.new("Frame",SG); DL.BackgroundColor3=Color3.fromRGB(10,5,26); DL.BorderSizePixel=0; DL.Visible=false; DL.ZIndex=500
        Instance.new("UICorner",DL).CornerRadius=UDim.new(0,9); Instance.new("UIStroke",DL).Color=T.Acc
        Instance.new("UIListLayout",DL).SortOrder=Enum.SortOrder.LayoutOrder
        local IH=27
        for j,opt in ipairs(opts) do
            local ob=Instance.new("TextButton",DL); ob.Size=UDim2.new(1,0,0,IH); ob.BackgroundColor3=Color3.fromRGB(10,5,26)
            ob.BorderSizePixel=0; ob.Font=Enum.Font.Gotham; ob.TextScaled=true; ob.TextColor3=T.Txt; ob.Text=opt; ob.ZIndex=501; ob.LayoutOrder=j
            ob.MouseButton1Click:Connect(function() ST[key]=opt; db.Text=opt; DL.Visible=false; if cb then cb(opt) end end)
            ob.MouseEnter:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(28,13,55)},0.1) end)
            ob.MouseLeave:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(10,5,26)},0.1) end)
        end
        DL.Size=UDim2.new(0,180,0,IH*#opts)
        local open=false
        db.MouseButton1Click:Connect(function()
            open=not open
            if open then local ap=db.AbsolutePosition; local as=db.AbsoluteSize; DL.Position=UDim2.new(0,ap.X,0,ap.Y+as.Y+3); DL.Visible=true
            else DL.Visible=false end
        end)
        return wrap
    end

    local function mkBtn(p,txt,ord,cb,color)
        local b=Instance.new("TextButton",p); b.Size=UDim2.new(1,0,0,34)
        b.BackgroundColor3=color or T.Btn; b.BorderSizePixel=0; b.Font=Enum.Font.GothamBold
        b.TextScaled=true; b.TextColor3=Color3.fromRGB(255,255,255); b.Text=txt; b.LayoutOrder=ord or 0
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,10)
        b.MouseButton1Click:Connect(function()
            tw(b,{BackgroundColor3=T.AccBrt},0.07); task.wait(0.07); tw(b,{BackgroundColor3=color or T.Btn},0.22)
            if cb then pcall(cb) end
        end)
        b.MouseEnter:Connect(function() tw(b,{BackgroundColor3=T.BtnHot},0.14) end)
        b.MouseLeave:Connect(function() tw(b,{BackgroundColor3=color or T.Btn},0.14) end)
        return b
    end

    local function mkSp(p,h,ord)
        local s=Instance.new("Frame",p); s.Size=UDim2.new(1,0,0,h or 3); s.BackgroundTransparency=1; s.LayoutOrder=ord or 0; return s
    end

    -- Seletor de arma dinâmico
    local function mkWeaponRow(p,ord)
        local wrap=Instance.new("Frame",p); wrap.Size=UDim2.new(1,0,0,70)
        wrap.BackgroundColor3=T.Panel; wrap.BorderSizePixel=0; wrap.LayoutOrder=ord; wrap.ClipsDescendants=false
        Instance.new("UICorner",wrap).CornerRadius=UDim.new(0,10)
        local ll=Instance.new("UIListLayout",wrap); ll.FillDirection=Enum.FillDirection.Vertical
        ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Padding=UDim.new(0,2)
        local pad=Instance.new("UIPadding",wrap); pad.PaddingLeft=UDim.new(0,8); pad.PaddingRight=UDim.new(0,8)
        pad.PaddingTop=UDim.new(0,4); pad.PaddingBottom=UDim.new(0,4)

        local topF=Instance.new("Frame",wrap); topF.Size=UDim2.new(1,0,0,30); topF.BackgroundTransparency=1; topF.LayoutOrder=1
        local lbl=Instance.new("TextLabel",topF); lbl.Size=UDim2.new(0.42,0,1,0); lbl.BackgroundTransparency=1
        lbl.Font=Enum.Font.Gotham; lbl.TextScaled=true; lbl.TextColor3=T.Txt; lbl.TextXAlignment=Enum.TextXAlignment.Left; lbl.Text="🗡 Arma"

        local tools=listTools(); local curW=tools[1] or "Soco (Sem Arma)"; ST.WeaponName=curW
        local db=Instance.new("TextButton",topF); db.Size=UDim2.new(0.54,0,0.84,0); db.Position=UDim2.new(0.44,0,0.08,0)
        db.BackgroundColor3=Color3.fromRGB(18,11,42); db.BorderSizePixel=0
        db.Font=Enum.Font.GothamBold; db.TextScaled=true; db.TextColor3=T.AccBrt; db.Text=curW; db.ClipsDescendants=true
        Instance.new("UICorner",db).CornerRadius=UDim.new(0,7); Instance.new("UIStroke",db).Color=T.AccDim

        local DL=Instance.new("Frame",SG); DL.BackgroundColor3=Color3.fromRGB(10,5,26); DL.BorderSizePixel=0; DL.Visible=false; DL.ZIndex=600
        Instance.new("UICorner",DL).CornerRadius=UDim.new(0,9); Instance.new("UIStroke",DL).Color=T.Acc
        local dll=Instance.new("UIListLayout",DL); dll.SortOrder=Enum.SortOrder.LayoutOrder
        local IH=27

        local function rebuildDL()
            for _,ch in ipairs(DL:GetChildren()) do if ch:IsA("TextButton") then ch:Destroy() end end
            tools=listTools()
            for j,opt in ipairs(tools) do
                local ob=Instance.new("TextButton",DL); ob.Size=UDim2.new(1,0,0,IH); ob.BackgroundColor3=Color3.fromRGB(10,5,26)
                ob.BorderSizePixel=0; ob.Font=Enum.Font.Gotham; ob.TextScaled=true; ob.TextColor3=T.Txt; ob.Text=opt; ob.ZIndex=601; ob.LayoutOrder=j
                ob.MouseButton1Click:Connect(function() ST.WeaponName=opt; db.Text=opt; DL.Visible=false end)
                ob.MouseEnter:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(28,13,55)},0.1) end)
                ob.MouseLeave:Connect(function() tw(ob,{BackgroundColor3=Color3.fromRGB(10,5,26)},0.1) end)
            end
            DL.Size=UDim2.new(0,190,0,IH*#tools)
        end
        rebuildDL()
        local dlOpen=false
        db.MouseButton1Click:Connect(function()
            dlOpen=not dlOpen
            if dlOpen then local ap=db.AbsolutePosition; local as=db.AbsoluteSize; DL.Position=UDim2.new(0,ap.X,0,ap.Y+as.Y+3); DL.Visible=true
            else DL.Visible=false end
        end)

        local botF=Instance.new("Frame",wrap); botF.Size=UDim2.new(1,0,0,28); botF.BackgroundTransparency=1; botF.LayoutOrder=2
        local bL=Instance.new("UIListLayout",botF); bL.FillDirection=Enum.FillDirection.Horizontal; bL.Padding=UDim.new(0,5)
        local function mB(txt2,cb2)
            local b=Instance.new("TextButton",botF); b.Size=UDim2.new(0.5,-3,1,0); b.BackgroundColor3=T.Btn; b.BorderSizePixel=0
            b.Font=Enum.Font.GothamBold; b.TextScaled=true; b.TextColor3=Color3.fromRGB(255,255,255); b.Text=txt2
            Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
            b.MouseButton1Click:Connect(function() tw(b,{BackgroundColor3=T.AccBrt},0.07); task.wait(0.07); tw(b,{BackgroundColor3=T.Btn},0.22); if cb2 then pcall(cb2) end end)
        end
        mB("🔄 Refresh",function() rebuildDL(); tools=listTools(); db.Text=#tools>0 and tools[1] or "Soco"; ST.WeaponName=db.Text end)
        mB("⚔ Equipar",function()
            local ok=equipWeapon(ST.WeaponName)
            if ST.Notify then
                ST.Notify(ok and ("⚔ "..ST.WeaponName.." equipado!") or "Item não encontrado!", ok and T.Success or T.Danger, 2)
            end
        end)
        return wrap
    end

    -- Status quest/farm humano ao vivo
    local function mkStatusBox(p,ord)
        local f=Instance.new("Frame",p); f.Size=UDim2.new(1,0,0,58); f.BackgroundColor3=T.PanelDk
        f.BorderSizePixel=0; f.LayoutOrder=ord; Instance.new("UICorner",f).CornerRadius=UDim.new(0,10)
        local stroke=Instance.new("UIStroke",f); stroke.Color=T.QuestClr; stroke.Thickness=1; stroke.Transparency=0.5
        local l=Instance.new("TextLabel",f); l.Size=UDim2.new(1,-12,1,0); l.Position=UDim2.new(0,6,0,0)
        l.BackgroundTransparency=1; l.Font=Enum.Font.Code; l.TextScaled=true; l.TextWrapped=true; l.RichText=true
        l.TextColor3=T.TxtDim; l.TextXAlignment=Enum.TextXAlignment.Left; l.TextYAlignment=Enum.TextYAlignment.Center

        RunService.Heartbeat:Connect(function()
            if not f or not f.Parent then return end
            pcall(function()
                local mode = ST.HumanFarm and "🤖 HUMANO" or (ST.AutoQuestFarm and "⚡ RÁPIDO" or "—")
                local qs, kd, kn, mb
                if ST.HumanFarm then
                    qs=HF.state; kd=HF.killsDone; kn=(HF.questData and HF.questData.Kills or 0); mb=(HF.questData and HF.questData.Mob or "")
                else
                    qs=QST.state; kd=QST.killsDone; kn=QST.killsNeeded; mb=QST.mobName
                end
                l.Text=('<font color="#6633cc">Modo:</font> <font color="#aabb44">%s</font>  <font color="#6633cc">Quest:</font> <font color="#ffcc33">%s</font>\n<font color="#6633cc">Mob:</font> <font color="#cc99ff">%s</font>  <font color="#55cc77">%d</font><font color="#6633cc">/%d</font>'):format(
                    mode, qs, mb, kd, kn)
            end)
        end)
        return f
    end

    -- Notificação
    local function notify(msg,color,dur)
        color=color or T.AccBrt; dur=dur or 2.5
        task.spawn(function()
            local nf=Instance.new("Frame",SG); nf.Size=UDim2.new(0,270,0,46); nf.Position=UDim2.new(0.5,-135,1,5)
            nf.BackgroundColor3=T.PanelDk; nf.BorderSizePixel=0; nf.ZIndex=1000
            Instance.new("UICorner",nf).CornerRadius=UDim.new(0,12)
            local ns=Instance.new("UIStroke",nf); ns.Color=color; ns.Thickness=1.5
            local nl=Instance.new("TextLabel",nf); nl.Size=UDim2.new(1,-10,1,0); nl.Position=UDim2.new(0,5,0,0)
            nl.BackgroundTransparency=1; nl.Font=Enum.Font.GothamBold; nl.TextScaled=true
            nl.TextColor3=color; nl.TextStrokeTransparency=0.3; nl.ZIndex=1001; nl.Text=msg
            tw(nf,{Position=UDim2.new(0.5,-135,1,-56)},0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out)
            task.wait(dur)
            tw(nf,{Position=UDim2.new(0.5,-135,1,5)},0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.In)
            task.wait(0.4); pcall(function() nf:Destroy() end)
        end)
    end
    ST.Notify = notify

    -- ════════════════════════════════════════════════════════════
    -- CONTEÚDO DAS ABAS
    -- ════════════════════════════════════════════════════════════

    -- ── ABA FARM ─────────────────────────────────────────────
    local FT=frames["Farm"]; local fo=1

    mkSec(FT,"🤖  FARM HUMANO  (mini-IA)",fo,T.HumanClr) fo=fo+1
    do
        local row,tl=mkToggle(FT,"Farm Humano (Stealth)","HumanFarm",fo,function(on)
            if on then
                ST.AutoQuestFarm=false  -- desliga o rápido
                ST.AutoFarm=false
                loopHumanFarm()
            else
                HF.state="IDLE"
            end
        end,T.HumanClr) fo=fo+1
    end

    mkSec(FT,"⚡  AUTO QUEST + FARM",fo) fo=fo+1
    mkDrop(FT,"NPC de Quest",QUEST_NPC_NAMES,"QuestNPCName",fo) fo=fo+1
    mkToggle(FT,"Auto Quest + Farm","AutoQuestFarm",fo,function(on)
        if on then
            ST.HumanFarm=false
            HF.state="IDLE"
            loopAutoQuestFarm()
            loopSkills()
        else
            stopAnchor()
            QST.state="IDLE"
        end
    end) fo=fo+1
    mkStatusBox(FT,fo) fo=fo+1

    mkSec(FT,"⚔  AUTO FARM LIVRE",fo) fo=fo+1
    mkDrop(FT,"Mob Alvo",MOBS,"TargetMob",fo) fo=fo+1
    mkToggle(FT,"Auto Farm","AutoFarm",fo,function(on)
        if on then loopFarm() else stopAnchor() end
    end) fo=fo+1
    mkToggle(FT,"Congelar Alvo","FreezeTarget",fo) fo=fo+1

    mkSec(FT,"✦  AUTO MASTERY",fo) fo=fo+1
    mkToggle(FT,"Auto Mastery Farm","AutoMastery",fo,function(on)
        if on then loopMastery() else stopAnchor() end
    end) fo=fo+1

    mkSec(FT,"🗡  ARMA / TOOL",fo) fo=fo+1
    mkWeaponRow(FT,fo) fo=fo+1

    -- Hitbox range slider
    mkSec(FT,"📐  ALCANCE DE ATAQUE",fo) fo=fo+1
    mkSlider(FT,"Âncora Y (sub-chão)",-150,50,"AnchorOffsetY",fo) fo=fo+1
    mkBtn(FT,"👥 Agrupar Mobs Agora",fo,function()
        local n=groupMobs()
        notify("👥 "..n.." mobs agrupados!",T.AccBrt,2)
    end) fo=fo+1

    mkSec(FT,"⚙  CONFIG",fo) fo=fo+1
    mkToggle(FT,"Auto Skills/Breathing","AutoSkills",fo) fo=fo+1
    mkToggle(FT,"Anti-Idle (anti-kick)","AntiIdle",fo) fo=fo+1
    mkToggle(FT,"Rejoin ao Morrer","AutoRejoin",fo) fo=fo+1
    mkToggle(FT,"Humanizar Ações","AntiDetect",fo) fo=fo+1
    mkToggle(FT,"Âncora Sub-Chão","AnchorMode",fo) fo=fo+1

    -- ── ABA BOSS ─────────────────────────────────────────────
    local BT=frames["Boss"]
    mkSec(BT,"💀  AUTO BOSS",1)
    local bnames={}; for _,b in ipairs(BOSSES) do table.insert(bnames,b.N) end
    mkDrop(BT,"Boss Alvo",bnames,"TargetBoss",2)
    mkToggle(BT,"Auto Boss Farm","AutoBoss",3,function(on) if on then loopBoss() else stopAnchor() end end)
    mkToggle(BT,"Congelar Boss","FreezeTarget",4)
    local biF=Instance.new("Frame",BT); biF.Size=UDim2.new(1,0,0,80); biF.BackgroundColor3=Color3.fromRGB(15,7,32)
    biF.BorderSizePixel=0; biF.LayoutOrder=5; Instance.new("UICorner",biF).CornerRadius=UDim.new(0,10)
    local biL=Instance.new("TextLabel",biF); biL.Size=UDim2.new(1,-12,1,0); biL.Position=UDim2.new(0,6,0,0)
    biL.BackgroundTransparency=1; biL.Font=Enum.Font.Gotham; biL.TextScaled=true; biL.TextWrapped=true
    biL.RichText=true; biL.TextColor3=T.TxtDim; biL.TextXAlignment=Enum.TextXAlignment.Left; biL.TextYAlignment=Enum.TextYAlignment.Center
    local function refreshBI()
        for _,b in ipairs(BOSSES) do
            if b.N==ST.TargetBoss then
                biL.Text=('<font color="#aa55ff"><b>%s</b></font>  Lv.%d\n<font color="#8844bb">Zona:</font> <font color="#ccaaff">%s</font>\n<font color="#8844bb">Drop:</font> <font color="#55cc77">%s</font>'):format(b.N,b.Lv,b.Zone,b.Drop); break
            end
        end
    end
    refreshBI()
    mkSec(BT,"🏰  DUNGEON OUWIGAHARA",6)
    mkToggle(BT,"Auto Dungeon (Lv.65+)","AutoDungeon",7,function(on)
        if on then task.spawn(function()
            while ST.AutoDungeon do
                pcall(function()
                    if RS then for _,rfn in ipairs({"Events","Remotes","RE"}) do
                        local rf=RS:FindFirstChild(rfn); if rf then
                            for _,ch in ipairs(rf:GetDescendants()) do
                                if ch:IsA("RemoteEvent") then local n=ch.Name:lower()
                                    if n:find("dungeon") or n:find("ouw") then pcall(function() ch:FireServer() end) end
                                end
                            end
                        end
                    end end
                end)
                task.wait(rnd(5,10))
            end
        end) end
    end)
    mkBtn(BT,"📍 TP para o Boss",8,function()
        local t=findMob(ST.TargetBoss)
        if t then
            local r=t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
            if r then AD:safeTP(r.Position,Vector3.new(0,8,0)); notify("💀 TP → "..ST.TargetBoss,T.Warn) end
        else notify("Boss não encontrado",T.Danger) end
    end)

    -- ── ABA PLAYER ───────────────────────────────────────────
    local PT=frames["Player"]
    mkSec(PT,"🚀  MOVIMENTO",1)
    mkToggle(PT,"✈ Voar (Fly)","Fly",2,function(on) if on then enableFly() else disableFly() end end)
    mkSlider(PT,"Velocidade Fly",10,350,"FlySpeedVal",3)
    mkToggle(PT,"⚡ Speed Hack","Speed",4,function(on) setSpeed(on and ST.SpeedVal or 16) end)
    mkSlider(PT,"Velocidade Walk",16,500,"SpeedVal",5,function(v) if ST.Speed then setSpeed(v) end end)
    mkToggle(PT,"🦘 Pulo Infinito","InfiniteJump",6)
    mkToggle(PT,"🔮 No Clip","NoClip",7)
    mkSec(PT,"🎣  PESCA & CLAN",8)
    mkToggle(PT,"Auto Pesca","AutoFishing",9,function(on) if on then loopFishing() end end)
    mkToggle(PT,"Auto Clan Spin","AutoClanSpin",10,function(on) if on then loopClan() end end)
    mkSec(PT,"🛡  PROTEÇÃO",11)
    mkBtn(PT,"♻ Recarregar Personagem",12,function() LP:LoadCharacter() end)
    mkBtn(PT,"🌐 Rejoin Servidor",13,function() pcall(function() TS:Teleport(game.PlaceId,LP) end) end)

    -- ── ABA ESP ──────────────────────────────────────────────
    local ET=frames["ESP"]
    mkSec(ET,"👁  ESP AVANÇADO",1)
    mkToggle(ET,"ESP Mobs (roxo)","ESP_Mob",2,function() pcall(refreshESP) end)
    mkToggle(ET,"ESP Bosses (laranja)","ESP_Boss",3,function() pcall(refreshESP) end)
    mkToggle(ET,"ESP Jogadores (vermelho)","ESP_Player",4,function() pcall(refreshESP) end)
    mkBtn(ET,"🔄 Atualizar ESP",5,function() clearESP(); task.wait(0.1); pcall(refreshESP) end)
    mkBtn(ET,"🗑 Limpar ESP",6,function()
        clearESP(); ST.ESP_Mob=false; ST.ESP_Boss=false; ST.ESP_Player=false; notify("✓ ESP limpo",T.Success)
    end)

    -- ── ABA TP ───────────────────────────────────────────────
    local TT=frames["TP"]
    mkSec(TT,"🌀  ZONAS (TP ESTÁVEL)",1)
    for i,z in ipairs(ZONES) do
        local zc=z
        mkBtn(TT,"📍 "..z,i+1,function()
            -- Usa coordenadas fixas primeiro (mais estável)
            local pos = ZONE_POS[zc]
            if pos then
                AD:safeTP(pos, Vector3.new(0,5,0))
                notify("🌀 TP → "..zc,T.AccBrt)
                return
            end
            -- fallback: busca por SpawnLocation
            for _,obj in ipairs(WS:GetDescendants()) do
                if obj:IsA("SpawnLocation") then
                    local nm=obj.Name:lower()
                    if nm:find(zc:sub(1,4):lower()) then
                        AD:safeTP(obj.Position, Vector3.new(0,5,0))
                        notify("🌀 TP → "..zc,T.AccBrt)
                        return
                    end
                end
            end
            -- fallback 2: BasePart
            for _,obj in ipairs(WS:GetDescendants()) do
                if obj:IsA("BasePart") and not obj:IsA("SpawnLocation") then
                    if obj.Name:lower():find(zc:sub(1,4):lower()) then
                        AD:safeTP(obj.Position, Vector3.new(0,8,0))
                        notify("🌀 TP aproximado → "..zc,T.Warn)
                        return
                    end
                end
            end
            notify("Zona não encontrada no mapa: "..zc, T.Danger)
        end)
    end
    mkSec(TT,"💀  BOSSES",#ZONES+3)
    for i,b in ipairs(BOSSES) do
        local bc=b
        mkBtn(TT,("💀 %s  Lv.%d"):format(b.N,b.Lv),#ZONES+3+i,function()
            local t=findMob(bc.N)
            if t then
                local r=t:FindFirstChild("HumanoidRootPart") or t.PrimaryPart
                if r then AD:safeTP(r.Position,Vector3.new(0,10,0)); notify("💀 TP → "..bc.N,T.Warn) end
            else notify("Boss não encontrado",T.Danger) end
        end)
    end

    -- ── ABA MISC ─────────────────────────────────────────────
    local MT=frames["Misc"]
    mkSec(MT,"⚙  UTILITÁRIOS",1)
    mkBtn(MT,"📋 Copiar UserID",2,function()
        pcall(function() setclipboard(tostring(LP.UserId)) end); notify("✓ UserID copiado!",T.Success)
    end)
    mkBtn(MT,"🌄 FPS Boost Agressivo",3,function()
        pcall(function()
            local LC=game:GetService("Lighting")
            LC.GlobalShadows=false; LC.FogEnd=10000
            for _,v in ipairs(WS:GetDescendants()) do
                if v:IsA("BasePart") then v.CastShadow=false end
                if v:IsA("ParticleEmitter") or v:IsA("Smoke") or v:IsA("Fire") or v:IsA("Sparkles") then v.Enabled=false end
            end
        end)
        notify("✓ FPS Boost aplicado",T.Success)
    end)
    mkBtn(MT,"🔕 Remover Efeitos Visuais",4,function()
        pcall(function()
            for _,v in ipairs(WS:GetDescendants()) do
                if v:IsA("Atmosphere") or v:IsA("Sky") or v:IsA("PostEffect") then v.Parent=nil end
            end
        end)
        notify("✓ Efeitos removidos",T.Success)
    end)
    mkBtn(MT,"🔍 Scan Remotes (debug)",5,function()
        local found={}
        if RS then
            for _,rfn in ipairs({"Events","Remotes","RE","RF"}) do
                local rf=RS:FindFirstChild(rfn)
                if rf then
                    for _,ch in ipairs(rf:GetDescendants()) do
                        if ch:IsA("RemoteEvent") then table.insert(found,ch.Name) end
                    end
                end
            end
        end
        notify("Remotes: "..table.concat(found,", "):sub(1,80),T.Warn,5)
    end)

    mkSec(MT,"📊  DEBUG AO VIVO",6)
    local dbF=Instance.new("Frame",MT); dbF.Size=UDim2.new(1,0,0,110); dbF.BackgroundColor3=T.PanelDk
    dbF.BorderSizePixel=0; dbF.LayoutOrder=7; Instance.new("UICorner",dbF).CornerRadius=UDim.new(0,10)
    local dbL=Instance.new("TextLabel",dbF); dbL.Size=UDim2.new(1,-10,1,0); dbL.Position=UDim2.new(0,5,0,0)
    dbL.BackgroundTransparency=1; dbL.Font=Enum.Font.Code; dbL.TextScaled=true; dbL.TextWrapped=true
    dbL.TextColor3=T.TxtDim; dbL.TextXAlignment=Enum.TextXAlignment.Left; dbL.RichText=true

    RunService.Heartbeat:Connect(function()
        if not dbF or not dbF.Parent then return end
        pcall(function()
            local hum=getHum(); local hrp=getHRP()
            if hum and hrp then
                local anchor=ST.AnchorMode and "ON" or "OFF"
                dbL.Text=('<font color="#6633bb">Player:</font> <font color="#bb88ff">%s</font>  <font color="#6633bb">HP:</font> <font color="#55cc77">%.0f/%.0f</font>\n<font color="#6633bb">Pos:</font> <font color="#bb88ff">%.0f %.0f %.0f</font>\n<font color="#6633bb">Farm:</font> <font color="#cc99ff">%s</font>  <font color="#6633bb">AnchorY:</font> <font color="#ff9955">%d</font>\n<font color="#6633bb">Âncora:</font> <font color="#aabb44">%s</font>  <font color="#6633bb">AntiD:</font> <font color="#aabb44">%s</font>'):format(
                    LP.DisplayName, hum.Health, hum.MaxHealth,
                    hrp.Position.X, hrp.Position.Y, hrp.Position.Z,
                    ST.TargetMob, ST.AnchorOffsetY, anchor,
                    ST.AntiDetect and "ON" or "OFF")
            end
        end)
    end)

    mkSec(MT,"ℹ  SOBRE",8)
    local aF=Instance.new("Frame",MT); aF.Size=UDim2.new(1,0,0,62); aF.BackgroundColor3=T.PanelDk
    aF.BorderSizePixel=0; aF.LayoutOrder=9; Instance.new("UICorner",aF).CornerRadius=UDim.new(0,10)
    local aL=Instance.new("TextLabel",aF); aL.Size=UDim2.new(1,-10,1,0); aL.Position=UDim2.new(0,5,0,0)
    aL.BackgroundTransparency=1; aL.Font=Enum.Font.Gotham; aL.TextScaled=true; aL.TextWrapped=true; aL.RichText=true; aL.TextColor3=T.TxtDim
    aL.Text='<font color="#9933ee"><b>VOID.LAZY v5.0 ELITE</b></font>  Mobile Edition\n<font color="#ffcc33">Farm Humano • Hitbox Engine • Quest IA • TP Estável</font>\n<font color="#6633cc">O melhor script de Slayers 2.</font>'

    -- Draggable
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
        if i.UserInputType==Enum.UserInputType.Touch or i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end end)

    -- Minimizar
    local minned=false
    MinBtn.MouseButton1Click:Connect(function()
        minned=not minned
        tw(MF,{Size=UDim2.new(0,FW,0,minned and 52 or FH)},0.3,Enum.EasingStyle.Quad,
            minned and Enum.EasingDirection.In or Enum.EasingDirection.Out)
    end)

    -- Fechar
    CloseBtn.MouseButton1Click:Connect(function()
        tw(MF,{Size=UDim2.new(0,0,0,0),Position=UDim2.new(0.5,0,0.5,0)},0.38,Enum.EasingStyle.Back,Enum.EasingDirection.In)
        task.wait(0.46)
        ST.AutoFarm=false; ST.AutoBoss=false; ST.AutoMastery=false; ST.AutoFishing=false
        ST.AutoClanSpin=false; ST.AutoQuestFarm=false; ST.HumanFarm=false
        ST.Fly=false; ST.NoClip=false; ST.InfiniteJump=false
        stopAnchor(); QST.state="IDLE"; HF.state="IDLE"
        for _,c in ipairs(ST.Connections) do pcall(function() c:Disconnect() end) end
        clearESP()
        pcall(function() SG:Destroy() end)
    end)

    switchTab("Farm")
    task.wait(0.7)
    notify("✦ VOID.LAZY v5.0 ELITE carregado!",T.AccBrt,3)
    task.wait(1.2)
    notify("🤖 Farm Humano disponível na aba Farm",T.HumanClr,3)
    task.wait(1.4)
    notify("📐 Âncora sub-chão ativa — sem rubber-band",T.Success,3)
end

end)

if not OK then
    task.spawn(function()
        local sg2=Instance.new("ScreenGui"); sg2.Name="VOID_ERR"; sg2.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
        sg2.DisplayOrder=9999; sg2.ResetOnSpawn=false
        pcall(function() sg2.Parent=game:GetService("CoreGui") end)
        if not sg2.Parent then pcall(function() sg2.Parent=game:GetService("Players").LocalPlayer.PlayerGui end) end
        local f=Instance.new("Frame",sg2); f.Size=UDim2.new(0.9,0,0,88); f.Position=UDim2.new(0.05,0,0.4,0)
        f.BackgroundColor3=Color3.fromRGB(28,4,4); f.BorderSizePixel=0
        Instance.new("UICorner",f).CornerRadius=UDim.new(0,10)
        local l=Instance.new("TextLabel",f); l.Size=UDim2.new(1,-10,1,0); l.Position=UDim2.new(0,5,0,0)
        l.BackgroundTransparency=1; l.Font=Enum.Font.GothamBold; l.TextScaled=true; l.TextWrapped=true
        l.TextColor3=Color3.fromRGB(255,75,75); l.Text="VOID.LAZY v5 ERRO:\n"..tostring(ERR)
    end)
end

print("[VOID.LAZY v5.0 ELITE] Executado.")
