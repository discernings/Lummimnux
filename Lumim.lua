--// Lumim | Auto Collect | Mobile | UI glass escuro

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")

local player = Players.LocalPlayer

----------------------------------------------------------------
-- Estado / opções (ligadas à UI)
----------------------------------------------------------------
local S = {
	enabled = false,
	items = false,          -- workspace.Maps.ItemsSpawnPoints
	potions = false,        -- workspace.Maps.ItemsFolder (Poções, Coins)
	collectAll = false,     -- tudo chamado "Collect" no mapa
	baeusDelay = 10,        -- segundos até tocar o mesmo Baeus de novo
	find = false,           -- Auto Find
	findMode = "Teleport",  -- Teleport / Tween / Remote
	findDelay = 5,          -- segundos até revisitar o mesmo alvo
	findTweenSpeed = 100,   -- studs por segundo (modo Tween do Auto Find)
	baeusMode = "Teleport", -- Teleport / Remote / Tween
	tweenSpeed = 100,       -- studs por segundo (modo Tween)
	espOn = {},             -- toggles de ESP por grupo (id -> bool)
	baeus = false,          -- workspace.Baeus
	stars = false,          -- workspace.Maps.RandomStarPoint
	skipDisabled = false,   -- ignora prompts desativados
	autoInteract = false,  -- interage com todos os prompts ao redor
	interactRange = 30,
	stepDelay = 0.12,
	cooldown = 1.2,
	offsetY = 3,
	order = "Closest",
}

local ESP_GROUPS = {
	{ id = "baeus",      title = "Baeus ESP",             path = { "Baeus" },                                   split = true,  color = Color3.fromRGB(57, 255, 20) },
	{ id = "bedmonster", title = "Bed Monster ESP",       path = { "PUZZLES", "bed monster", "Button" },        split = true,  color = Color3.fromRGB(255, 70, 70) },
	{ id = "easybaeus",  title = "Easy Baeus ESP",        path = { "PUZZLES", "_Easy Baeus", "Buttons" },       split = true,  color = Color3.fromRGB(0, 220, 255) },
	{ id = "specimen9",  title = "Specimen 9 ESP",        path = { "PUZZLES", "Specimen 9", "Buttons" },        split = true,  color = Color3.fromRGB(255, 230, 0) },
	{ id = "sink",       title = "Sink Puzzle ESP",       path = { "PUZZLES", "SinkPuzzle" },                   split = false, color = Color3.fromRGB(70, 130, 255) },
	{ id = "shattered",  title = "Shattered Eternity ESP", path = { "PUZZLES", "Shattered Eternity", "Buttons" }, split = true, color = Color3.fromRGB(255, 0, 200) },
	{ id = "nameless",   title = "Nameless ESP",          path = { "PUZZLES", "Nameless", "Buttons" },          split = true,  color = Color3.fromRGB(255, 150, 0) },
	{ id = "n",          title = "N ESP",                 path = { "PUZZLES", "N", "Button" },                  split = true,  color = Color3.fromRGB(255, 255, 255) },
	{ id = "cyber",      title = "Cyber-Oblivion ESP",    path = { "PUZZLES", "Cyber-Oblivion", "Buttons" },    split = true,  color = Color3.fromRGB(170, 90, 255) },
	{ id = "duskNoir",   title = "Dusk & Noir Baeus ESP", path = { "PUZZLES", "Dusk & Noir Baeus" },            split = false, color = Color3.fromRGB(255, 120, 170) },
	{ id = "geometric",  title = "Geometric ESP",         path = { "PUZZLES", "Geometric" },                    split = false, color = Color3.fromRGB(0, 255, 180) },
}

local findPaths = {} -- paths colados no Auto Find

local collected = 0
local cooldown = setmetatable({}, { __mode = "k" })
local setStatus = function() end
local setCount = function() end

----------------------------------------------------------------
-- Lógica
----------------------------------------------------------------
local function getHRP()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function posOf(inst)
	local cur = inst
	while cur and cur ~= workspace do
		if cur:IsA("Attachment") then
			return cur.WorldPosition
		elseif cur:IsA("BasePart") then
			return cur.Position
		elseif cur:IsA("Model") then
			local ok, cf = pcall(function() return cur:GetPivot() end)
			if ok then return cf.Position end
		end
		cur = cur.Parent
	end
	return nil
end

local function firePrompt(p)
	pcall(function()
		p.HoldDuration = 0
		p.RequiresLineOfSight = false
		p.MaxActivationDistance = math.max(p.MaxActivationDistance, 32)
	end)
	if fireproximityprompt then
		fireproximityprompt(p)
	else
		pcall(function()
			p:InputHoldBegin()
			task.wait(0.05)
			p:InputHoldEnd()
		end)
	end
end

local function touch(part)
	local hrp = getHRP()
	if hrp and firetouchinterest and part:IsA("BasePart") then
		pcall(function()
			firetouchinterest(hrp, part, 0)
			task.wait()
			firetouchinterest(hrp, part, 1)
		end)
	end
end

local function interactWith(inst)
	if inst:IsA("ProximityPrompt") then
		firePrompt(inst)
		return
	end
	if inst:IsA("ClickDetector") then
		if fireclickdetector then pcall(fireclickdetector, inst) end
		return
	end
	if inst:IsA("BasePart") then touch(inst) end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			firePrompt(d)
		elseif d:IsA("ClickDetector") then
			if fireclickdetector then pcall(fireclickdetector, d) end
		elseif d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then
			touch(d)
		end
	end
end

local function gatherTargets()
	local list, seen = {}, {}

	local function add(inst)
		if not seen[inst] then
			seen[inst] = true
			table.insert(list, inst)
		end
	end

	local function addGroup(inst)
		if seen[inst] then return end
		add(inst)
		for _, x in ipairs(inst:GetDescendants()) do seen[x] = true end
	end

	local maps = workspace:FindFirstChild("Maps")
	local spawns = maps and maps:FindFirstChild("ItemsSpawnPoints")
	local stars = maps and maps:FindFirstChild("RandomStarPoint")

	if S.items and spawns then
		for _, d in ipairs(spawns:GetDescendants()) do
			if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
				add(d)
			end
		end
	end

	local function scan(folder)
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Folder") then
				scan(child)
			elseif child:IsA("Model") or child:IsA("BasePart") then
				addGroup(child)
			elseif child:IsA("ProximityPrompt") or child:IsA("ClickDetector") then
				add(child)
			end
		end
	end

	local itemsFolder = maps and maps:FindFirstChild("ItemsFolder")
	if S.potions and itemsFolder then scan(itemsFolder) end

	if S.stars and stars then
		for _, d in ipairs(stars:GetDescendants()) do
			if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
				add(d)
			elseif (d:IsA("Model") or d:IsA("BasePart")) and string.find(string.lower(d.Name), "star") then
				addGroup(d)
			end
		end
	end

	if S.collectAll then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				local pn = d.Parent and d.Parent.Name or ""
				if d.ActionText == "Collect" or d.Name == "Collect" or pn == "Collect" then
					add(d)
				end
			elseif d.Name == "Collect" and (d:IsA("ClickDetector") or d:IsA("Model") or d:IsA("BasePart")) then
				addGroup(d)
			end
		end
	end

	return list
end

local TOUCH_PARTS = {
	"HumanoidRootPart", "Head", "LeftFoot", "RightFoot", "Left Leg", "Right Leg",
	"LowerTorso", "UpperTorso", "Torso",
}

local function fireTouches(parts)
	local char = player.Character
	if not (char and firetouchinterest) then return end
	local mine = {}
	for _, n in ipairs(TOUCH_PARTS) do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then table.insert(mine, p) end
	end
	pcall(function()
		for _, m in ipairs(mine) do
			for _, part in ipairs(parts) do firetouchinterest(m, part, 0) end
		end
		task.wait()
		for _, m in ipairs(mine) do
			for _, part in ipairs(parts) do firetouchinterest(m, part, 1) end
		end
	end)
end

-- Baeus: "imagens" que precisam ser tocadas pelo personagem (badges)
local function touchBaeus()
	local folder = workspace:FindFirstChild("Baeus")
	if not folder then
		setStatus("Baeus folder not found")
		return
	end

	if S.baeusMode == "Remote" and not firetouchinterest then
		setStatus("executor missing firetouchinterest")
		return
	end

	local list = {}
	local function gather(f)
		for _, child in ipairs(f:GetChildren()) do
			if child:IsA("Folder") then
				gather(child)
			elseif child:IsA("Model") or child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
	end
	gather(folder)
	if #list == 0 then
		setStatus("no Baeus found")
		return
	end

	for _, b in ipairs(list) do
		if not S.baeus then return end

		local last = cooldown[b]
		if last and (os.clock() - last) < S.baeusDelay then continue end

		local parts = {}
		if b:IsA("BasePart") then table.insert(parts, b) end
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("BasePart") and #parts < 12 then table.insert(parts, d) end
		end
		if #parts == 0 then continue end

		-- prioriza a peça que tem TouchInterest
		local target = parts[1]
		for _, part in ipairs(parts) do
			if part:FindFirstChildWhichIsA("TouchTransmitter") then
				target = part
				break
			end
		end

		local hrp = getHRP()
		if not hrp then return end

		local mode = S.baeusMode
		setStatus(string.lower(mode) .. " touching " .. b.Name)

		-- Tween: voa até o Baeus na velocidade escolhida
		if mode == "Tween" then
			local goal = target.CFrame
			local dist = (hrp.Position - goal.Position).Magnitude
			local duration = math.max(dist / math.max(S.tweenSpeed, 1), 0.05)

			hrp.Anchored = true
			local tw = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = goal })
			tw:Play()
			local t0 = os.clock()
			while tw.PlaybackState == Enum.PlaybackState.Playing and S.baeus and (os.clock() - t0) < duration + 2 do
				task.wait()
			end
			tw:Cancel()

			hrp = getHRP()
			if hrp then hrp.Anchored = false end
			if not hrp then return end
		end

		-- Teleport / Tween: anda de um lado ao outro da peça, simulando passos (o toque só conta com movimento)
		if mode == "Teleport" or mode == "Tween" then
			local reach = math.clamp(target.Size.X * 0.3, 0.6, 3)
			for i = 1, 8 do
				if not S.baeus then break end
				hrp = getHRP()
				if not hrp then return end
				local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				local dir = (i % 2 == 0) and 1 or -1
				hrp.CFrame = target.CFrame * CFrame.new(-dir * reach, 0, 0)
				if hum then hum:Move(Vector3.new(dir, 0, 0), false) end
				hrp.AssemblyLinearVelocity = Vector3.new(dir * 10, 0, 0)
				task.wait(0.05)
			end
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum:Move(Vector3.zero, false) end
		end

		fireTouches(parts)

		pcall(interactWith, b)

		cooldown[b] = os.clock()
		collected += 1
		setCount(collected)
		task.wait(S.stepDelay)
	end
end

-- Auto Find: converte um path colado em Instance. Aceita:
--   workspace.A.B  |  workspace["A B"].C  |  workspace:FindFirstChild("A")  |  game:GetService("X").Y
local function resolvePath(str)
	if type(str) ~= "string" then return nil end
	str = (str:gsub("^%s+", ""))
	str = (str:gsub("%s+$", ""))
	if str == "" then return nil end

	local first = str:match("^[%a_][%w_]*")
	if not first then return nil end
	local cur
	local low = string.lower(first)
	if low == "workspace" then
		cur = workspace
	elseif low == "game" then
		cur = game
	else
		cur = workspace:FindFirstChild(first)
	end

	local i = #first + 1
	while cur and i <= #str do
		local rest = str:sub(i)
		local tok, name = rest:match('^(%.([%a_][%w_]*))')
		if not tok then tok, name = rest:match('^(%[%s*"([^"]*)"%s*%])') end
		if not tok then tok, name = rest:match("^(%[%s*'([^']*)'%s*%])") end
		if not tok then tok, name = rest:match('^(:%a*[Cc]hild%(%s*"([^"]*)"[^%)]*%))') end
		if not tok then tok, name = rest:match("^(:%a*[Cc]hild%(%s*'([^']*)'[^%)]*%))") end

		if tok then
			cur = cur:FindFirstChild(name)
		else
			local svcTok, svc = rest:match('^(:GetService%(%s*"([^"]*)"%s*%))')
			if not svcTok then svcTok, svc = rest:match("^(:GetService%(%s*'([^']*)'%s*%))") end
			if not svcTok then return nil end
			local ok, res = pcall(game.GetService, game, svc)
			cur = ok and res or nil
			tok = svcTok
		end
		i = i + #tok
	end
	return cur
end

-- alvos de um path: prompts, clicks e peças com TouchInterest
local function findTargets(root)
	local out, seen = {}, {}
	local function add(i)
		if not seen[i] then
			seen[i] = true
			table.insert(out, i)
		end
	end
	local function consider(d)
		if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			add(d)
		elseif d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then
			add(d)
		end
	end

	consider(root)
	for _, d in ipairs(root:GetDescendants()) do consider(d) end

	if #out == 0 then
		if root:IsA("BasePart") or root:IsA("Model") then
			add(root)
		else
			for _, c in ipairs(root:GetChildren()) do
				if c:IsA("BasePart") or c:IsA("Model") then add(c) end
			end
		end
	end
	return out
end

local function findPartOf(inst)
	if inst:IsA("BasePart") then return inst end
	if inst:IsA("Model") then
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") and d:FindFirstChildWhichIsA("TouchTransmitter") then return d end
		end
		return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function findMove(goal, mode, stillOn)
	local hrp = getHRP()
	if not hrp then return false end

	if mode == "Tween" then
		local dist = (hrp.Position - goal.Position).Magnitude
		local duration = math.max(dist / math.max(S.findTweenSpeed, 1), 0.05)
		hrp.Anchored = true
		local tw = TweenService:Create(hrp, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = goal })
		tw:Play()
		local t0 = os.clock()
		while tw.PlaybackState == Enum.PlaybackState.Playing
			and (os.clock() - t0) < duration + 2
			and (not stillOn or stillOn()) do
			task.wait()
		end
		tw:Cancel()
		hrp = getHRP()
		if hrp then hrp.Anchored = false end
		return hrp ~= nil
	end

	hrp.CFrame = goal
	hrp.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- anda de um lado ao outro da peça (o toque só conta com movimento)
local function findStep(part, stillOn)
	local reach = math.clamp(part.Size.X * 0.3, 0.6, 3)
	for i = 1, 8 do
		if stillOn and not stillOn() then break end
		local hrp = getHRP()
		if not hrp then return end
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local dir = (i % 2 == 0) and 1 or -1
		hrp.CFrame = part.CFrame * CFrame.new(-dir * reach, 0, 0)
		if hum then hum:Move(Vector3.new(dir, 0, 0), false) end
		hrp.AssemblyLinearVelocity = Vector3.new(dir * 10, 0, 0)
		task.wait(0.05)
	end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum:Move(Vector3.zero, false) end
end

local findLock = false

local function findVisitInner(inst, mode, stillOn)
	if not getHRP() then return end
	local isObject = inst:IsA("BasePart") or inst:IsA("Model")
	local part = isObject and findPartOf(inst) or nil

	if mode ~= "Remote" then
		if part then
			if not findMove(part.CFrame, mode, stillOn) then return end
			findStep(part, stillOn)
		else
			local pos = posOf(inst)
			if not pos then return end
			if not findMove(CFrame.new(pos + Vector3.new(0, S.offsetY, 0)), mode, stillOn) then return end
			task.wait(0.05)
		end
	end

	if isObject then
		local parts = {}
		if inst:IsA("BasePart") then table.insert(parts, inst) end
		for _, d in ipairs(inst:GetDescendants()) do
			if d:IsA("BasePart") and #parts < 12 and d:FindFirstChildWhichIsA("TouchTransmitter") then
				table.insert(parts, d)
			end
		end
		if #parts > 0 then fireTouches(parts) end
	end
	pcall(interactWith, inst)
end

local function findVisit(inst, mode, stillOn)
	while findLock do task.wait(0.05) end
	findLock = true
	local ok, err = pcall(findVisitInner, inst, mode, stillOn)
	findLock = false
	if not ok then warn("[AutoFind]", err) end
end

local function cycle()
	local hrp = getHRP()
	if not hrp then
		setStatus("waiting for character")
		return
	end

	setStatus("searching items")
	local entries = {}
	local targets = S.enabled and gatherTargets() or {}
	for _, inst in ipairs(targets) do
		local pos = posOf(inst)
		if pos then table.insert(entries, { inst = inst, pos = pos }) end
	end

	local origin = hrp.Position
	if S.order == "Closest" then
		table.sort(entries, function(a, b) return (a.pos - origin).Magnitude < (b.pos - origin).Magnitude end)
	elseif S.order == "Farthest" then
		table.sort(entries, function(a, b) return (a.pos - origin).Magnitude > (b.pos - origin).Magnitude end)
	else
		for i = #entries, 2, -1 do
			local j = math.random(i)
			entries[i], entries[j] = entries[j], entries[i]
		end
	end

	for _, e in ipairs(entries) do
		if not S.enabled then return end
		local inst = e.inst
		if not inst.Parent then continue end
		if S.skipDisabled and inst:IsA("ProximityPrompt") and not inst.Enabled then continue end

		local last = cooldown[inst]
		if last and (os.clock() - last) < S.cooldown then continue end

		hrp = getHRP()
		if not hrp then return end

		local pos = posOf(inst) or e.pos
		setStatus("collecting " .. (inst.Parent and inst.Parent.Name or inst.Name))
		hrp.CFrame = CFrame.new(pos + Vector3.new(0, S.offsetY, 0))
		hrp.AssemblyLinearVelocity = Vector3.zero
		task.wait(0.05)
		pcall(interactWith, inst)
		cooldown[inst] = os.clock()
		collected += 1
		setCount(collected)
		task.wait(S.stepDelay)
	end

	if S.baeus then touchBaeus() end
end

task.spawn(function()
	while true do
		if S.enabled or S.baeus then
			local ok, err = pcall(cycle)
			if not ok then warn("[AutoCollect]", err) end
			task.wait(0.4)
		else
			task.wait(0.25)
		end
	end
end)

----------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------
local C = {
	bg = Color3.fromRGB(58, 56, 54),
	side = Color3.fromRGB(14, 14, 14),
	col = Color3.fromRGB(92, 90, 88),
	card = Color3.fromRGB(20, 20, 20),
	field = Color3.fromRGB(32, 32, 32),
	text = Color3.fromRGB(245, 245, 245),
	muted = Color3.fromRGB(168, 166, 163),
	white = Color3.fromRGB(255, 255, 255),
	black = Color3.fromRGB(0, 0, 0),
	trackOff = Color3.fromRGB(78, 78, 78),
	knobOff = Color3.fromRGB(165, 165, 165),
	cyan = Color3.fromRGB(0, 210, 255),
	blue = Color3.fromRGB(70, 120, 255),
}

local function make(class, props, children)
	local o = Instance.new(class)
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	if parent then o.Parent = parent end
	return o
end

local function corner(r) return make("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(col, t, tr)
	return make("UIStroke", {
		Color = col or C.white, Thickness = t or 1, Transparency = tr or 0.88,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

----------------------------------------------------------------
-- Assets (GitHub): baixa leaf.png do repositório e carrega como imagem
----------------------------------------------------------------
local GITHUB_USER = "SEU_USUARIO"  -- <- coloque aqui seu usuário do GitHub
local GITHUB_REPO = "Lumim"        -- nome do repositório
local GITHUB_BRANCH = "main"       -- branch (confira em Code > branch)

local ASSET_BASE = string.format("https://raw.githubusercontent.com/%s/%s/%s/", GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH)
pcall(function()
	if getgenv and getgenv().LumimBase then ASSET_BASE = getgenv().LumimBase end
end)
local ASSET_DIR = "Lumim"

local function isPng(data)
	return type(data) == "string" and #data > 8 and data:sub(2, 4) == "PNG"
end

local function loadAsset(file)
	local reason
	local ok, result = pcall(function()
		local toAsset = getcustomasset or getsynasset
		if not toAsset then reason = "executor sem getcustomasset" return nil end
		if not (writefile and readfile and isfile) then reason = "executor sem writefile/readfile/isfile" return nil end
		if makefolder and isfolder and not isfolder(ASSET_DIR) then makefolder(ASSET_DIR) end
		local path = ASSET_DIR .. "/" .. file
		-- usa o arquivo em cache se for um PNG válido; senão baixa de novo
		if not (isfile(path) and isPng(readfile(path))) then
			if string.find(ASSET_BASE, "SEU_USUARIO", 1, true) then
				reason = "GITHUB_USER ainda é SEU_USUARIO (troque pelo seu usuário)"
				return nil
			end
			local data = game:HttpGet(ASSET_BASE .. file)
			if not isPng(data) then
				reason = "download não retornou um PNG (confira usuário, repositório, branch e se é público): " .. ASSET_BASE .. file
				return nil
			end
			writefile(path, data)
		end
		return toAsset(path)
	end)
	if ok and result then return result end
	warn("[Lumim] ícone da folha não carregou, usando desenho: " .. tostring(reason or result))
	return nil
end

local LEAF_IMAGE = loadAsset("leaf.png")

-- Ícone folha: traço feito de pontos redondos sobrepostos (sem rotação => sem serrilhado)
local function dot(parent, x, y, th)
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(th, th), BackgroundColor3 = C.white,
		BorderSizePixel = 0, Parent = parent,
	}, { make("UICorner", { CornerRadius = UDim.new(0.5, 0) }) })
end

local function line(parent, x1, y1, x2, y2, th)
	local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
	local n = math.max(1, math.ceil(len / (th * 0.3)))
	for i = 0, n do
		local t = i / n
		dot(parent, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, th)
	end
end

local function bez(p0, p1, p2, p3, t)
	local u = 1 - t
	local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
	return a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1],
		a * p0[2] + b * p1[2] + c * p2[2] + d * p3[2]
end

local function curve(parent, p0, p1, p2, p3, _, tf, th)
	-- comprimento aproximado em pixels
	local len, px, py = 0, tf(bez(p0, p1, p2, p3, 0))
	for i = 1, 24 do
		local x, y = tf(bez(p0, p1, p2, p3, i / 24))
		len += math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
		px, py = x, y
	end
	local n = math.max(2, math.ceil(len * 1.5 / (th * 0.3)))
	for i = 0, n do
		local x, y = tf(bez(p0, p1, p2, p3, i / n))
		dot(parent, x, y, th)
	end
end

local function drawnLeaf(parent, size, pos)
	local root = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos or UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1, Parent = parent,
	})
	local k = size * 0.92 / 325
	local padX, padY = (size - 285 * k) / 2, (size - 325 * k) / 2
	local function tf(x, y) return (x - 80) * k + padX, (y - 15) * k + padY end
	local th = math.max(1.8, size * 0.062)

	-- contorno da folha (esquerda e direita, com abertura embaixo)
	curve(root, { 108, 237 }, { 92, 120 }, { 205, 38 }, { 358, 18 }, 0, tf, th)
	curve(root, { 358, 18 }, { 368, 150 }, { 300, 268 }, { 155, 277 }, 0, tf, th)
	-- caule / nervura central
	curve(root, { 88, 335 }, { 140, 260 }, { 185, 190 }, { 225, 128 }, 0, tf, th)
	local ax, ay = tf(225, 128)
	local bx, by = tf(284, 92)
	line(root, ax, ay, bx, by, th)
	-- bifurcação em Y
	local cx, cy = tf(219, 90)
	line(root, cx, cy, ax, ay, th)
	-- nervura lateral
	local dx, dy = tf(188, 187)
	local ex, ey = tf(276, 180)
	line(root, dx, dy, ex, ey, th)
	return root
end

-- Folha: usa a imagem do GitHub; se não carregar, usa o desenho vetorial acima
local function leafIcon(parent, size, pos)
	if LEAF_IMAGE then
		return make("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = pos or UDim2.new(0.5, 0, 0.5, 0),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1, BorderSizePixel = 0,
			Image = LEAF_IMAGE, ImageColor3 = C.white,
			ScaleType = Enum.ScaleType.Fit, Parent = parent,
		})
	end
	return drawnLeaf(parent, size, pos)
end

-- Ícones da barra lateral (desenhados com frames)
local function buildIcon(kind, parent)
	local root = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, Parent = parent,
	})
	local fills, strokes = {}, {}
	local function fill(x, y, w, h, r, rot)
		local f = make("Frame", {
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Rotation = rot or 0,
			BackgroundColor3 = C.muted, BorderSizePixel = 0, Parent = root,
		}, { corner(r or 0) })
		table.insert(fills, f)
	end
	local function ring(x, y, w, h, r, th, rot)
		local f = make("Frame", {
			Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Rotation = rot or 0,
			BackgroundTransparency = 1, BorderSizePixel = 0, Parent = root,
		}, { corner(r or 0) })
		table.insert(strokes, make("UIStroke", { Color = C.muted, Thickness = th, Parent = f }))
	end

	if kind == "main" then
		fill(3, 4, 4, 14, 2); fill(9, 2, 4, 18, 2); fill(15, 6, 4, 10, 2)
	elseif kind == "items" then
		ring(3, 3, 16, 16, 4, 2); fill(3, 9, 16, 2, 0)
	elseif kind == "stars" then
		ring(5, 5, 12, 12, 2, 2, 45); fill(9, 9, 4, 4, 2)
	elseif kind == "esp" then
		ring(1, 5, 20, 12, 6, 2); fill(8, 8, 6, 6, 3)
	else -- config
		fill(2, 5, 18, 2, 1); fill(2, 15, 18, 2, 1)
		fill(4, 3, 6, 6, 3); fill(12, 13, 6, 6, 3)
	end

	return root, function(col)
		for _, f in ipairs(fills) do f.BackgroundColor3 = col end
		for _, s in ipairs(strokes) do s.Color = col end
	end
end

local function makeDraggable(handle, target, scaleObj, onTap)
	local dragging, dragInput, startPos, startUDim, moved = false, nil, nil, nil, 0
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, dragInput = true, input
			startPos, startUDim, moved = input.Position, target.Position, 0
		end
	end)
	handle.InputEnded:Connect(function(input)
		if input == dragInput then
			dragging = false
			if onTap and moved < 8 then onTap() end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local d = input.Position - startPos
			moved = math.max(moved, d.Magnitude)
			local s = scaleObj and scaleObj.Scale or 1
			target.Position = UDim2.new(
				startUDim.X.Scale, startUDim.X.Offset + d.X / s,
				startUDim.Y.Scale, startUDim.Y.Offset + d.Y / s
			)
		end
	end)
end

----------------------------------------------------------------
-- UI base
----------------------------------------------------------------
local parentGui
pcall(function() parentGui = (gethui and gethui()) or CoreGui end)
if not parentGui then parentGui = player:WaitForChild("PlayerGui") end

local oldGui = parentGui:FindFirstChild("LumimHub")
if oldGui then oldGui:Destroy() end

local gui = make("ScreenGui", {
	Name = "LumimHub",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})

local scale = make("UIScale", { Scale = 1 })
local applyLayout -- definido mais abaixo
local viewMode = "Board"

local window = make("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(560, 330),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.16,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, {
	corner(18), stroke(C.white, 1, 0.84), scale,
	make("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(185, 185, 185)),
		Rotation = 90,
	}),
})

-- Sidebar (ícones)
-- container recorta o fundo arredondado: cantos externos redondos, lado interno reto
local sidebar = make("Frame", {
	Size = UDim2.new(0, 56, 1, 0), BackgroundTransparency = 1,
	BorderSizePixel = 0, ClipsDescendants = true, Parent = window,
})
make("Frame", {
	Size = UDim2.new(0, 80, 1, 0), BackgroundColor3 = C.side,
	BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = sidebar,
}, { corner(18) })
make("Frame", {
	Position = UDim2.new(1, -1, 0, 0), Size = UDim2.new(0, 1, 1, 0),
	BackgroundColor3 = C.white, BackgroundTransparency = 0.9, BorderSizePixel = 0, Parent = sidebar,
})

local logoTile = make("Frame", {
	Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(36, 36),
	BackgroundColor3 = C.black, BackgroundTransparency = 0.1, BorderSizePixel = 0, Parent = sidebar,
}, { corner(10), stroke(C.white, 1, 0.78) })
leafIcon(logoTile, 26)

local tabList = make("Frame", {
	Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 1, -70),
	BackgroundTransparency = 1, Parent = sidebar,
}, {
	make("UIListLayout", {
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}),
})

-- Barra superior
local topbar = make("Frame", {
	Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -56, 0, 52),
	BackgroundTransparency = 1, Parent = window,
})

local searchWrap = make("Frame", {
	Position = UDim2.fromOffset(14, 10), Size = UDim2.fromOffset(220, 32),
	BackgroundColor3 = C.black, BackgroundTransparency = 0.72, BorderSizePixel = 0, Parent = topbar,
}, { corner(10), stroke(C.white, 1, 0.88) })
make("Frame", {
	Position = UDim2.fromOffset(11, 10), Size = UDim2.fromOffset(10, 10),
	BackgroundTransparency = 1, Parent = searchWrap,
}, { corner(5), stroke(C.muted, 1.5, 0) })
make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(22, 21),
	Size = UDim2.fromOffset(6, 2), Rotation = 45,
	BackgroundColor3 = C.muted, BorderSizePixel = 0, Parent = searchWrap,
})
local searchBox = make("TextBox", {
	Text = "", PlaceholderText = "Search", PlaceholderColor3 = C.muted, TextColor3 = C.text,
	Font = Enum.Font.Gotham, TextSize = 13, ClearTextOnFocus = false,
	TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -42, 1, 0), Parent = searchWrap,
})

local minBtn = make("TextButton", {
	Text = "", AutoButtonColor = false,
	BackgroundColor3 = C.black, BackgroundTransparency = 0.72,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -54, 0, 10),
	Size = UDim2.fromOffset(32, 32), Parent = topbar,
}, { corner(10), stroke(C.white, 1, 0.88) })
make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
	Size = UDim2.fromOffset(12, 2), BackgroundColor3 = C.text, BorderSizePixel = 0, Parent = minBtn,
})

local closeBtn = make("TextButton", {
	Text = "", AutoButtonColor = false, BackgroundColor3 = C.white,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10),
	Size = UDim2.fromOffset(32, 32), Parent = topbar,
}, { corner(10) })
for _, rot in ipairs({ 45, -45 }) do
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 2), Rotation = rot,
		BackgroundColor3 = C.black, BorderSizePixel = 0, Parent = closeBtn,
	})
end

-- Título + Board/List
local titleRow = make("Frame", {
	Position = UDim2.fromOffset(70, 58), Size = UDim2.new(1, -84, 0, 30),
	BackgroundTransparency = 1, Parent = window,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
	}),
})
make("TextLabel", {
	LayoutOrder = 1, Text = "Lumim", Font = Enum.Font.GothamBold, TextSize = 20,
	TextColor3 = C.text, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Parent = titleRow,
})

local seg = make("Frame", {
	LayoutOrder = 2, Size = UDim2.fromOffset(104, 26),
	BackgroundColor3 = C.black, BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = titleRow,
}, { corner(9), stroke(C.white, 1, 0.9) })
local segBtns = {}
local function setView(mode)
	viewMode = mode
	for m, b in pairs(segBtns) do
		local on = (m == mode)
		b.BackgroundTransparency = on and 0.8 or 1
		b.TextColor3 = on and C.white or C.muted
	end
	if applyLayout then applyLayout() end
end
for i, m in ipairs({ "Board", "List" }) do
	local b = make("TextButton", {
		Text = m, Font = Enum.Font.GothamMedium, TextSize = 12, AutoButtonColor = false,
		BackgroundColor3 = C.white, BackgroundTransparency = 1, TextColor3 = C.muted,
		Position = UDim2.new((i - 1) * 0.5, i == 1 and 2 or 0, 0, 2),
		Size = UDim2.new(0.5, -2, 1, -4), Parent = seg,
	}, { corner(7) })
	segBtns[m] = b
	b.Activated:Connect(function() setView(m) end)
end

local tabLabel = make("TextLabel", {
	LayoutOrder = 3, Text = "Main", Font = Enum.Font.GothamMedium, TextSize = 13,
	TextColor3 = C.muted, BackgroundTransparency = 1,
	AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Parent = titleRow,
})

-- Conteúdo
local content = make("Frame", {
	Position = UDim2.fromOffset(66, 96), Size = UDim2.new(1, -76, 1, -104),
	BackgroundTransparency = 1, Parent = window,
})

----------------------------------------------------------------
-- Páginas, colunas e componentes
----------------------------------------------------------------
local pages, tabs, cards = {}, {}, {}
local currentPage
local tabCount = 0

local function newPage(name)
	local scroll = make("ScrollingFrame", {
		Visible = false, Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 2, ScrollBarImageColor3 = C.muted,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y, Parent = content,
	})
	local holder = make("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Parent = scroll,
	}, { make("UIPadding", { PaddingBottom = UDim.new(0, 8), PaddingRight = UDim.new(0, 4) }) })
	local holderLayout = make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder, Parent = holder,
	})
	local cols = {}
	for i = 1, 2 do
		cols[i] = make("Frame", {
			LayoutOrder = i, Size = UDim2.new(0.5, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, Parent = holder,
		}, { make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })
	end
	local page = { name = name, scroll = scroll, holderLayout = holderLayout, cols = cols, count = { 0, 0 } }
	pages[name] = page
	return page
end

local function applySearch()
	local q = string.lower(searchBox.Text or "")
	for _, c in ipairs(cards) do
		if c.page == currentPage then
			c.frame.Visible = (q == "") or (string.find(c.key, q, 1, true) ~= nil)
		else
			c.frame.Visible = true
		end
	end
end

local function selectTab(name)
	currentPage = pages[name]
	for n, p in pairs(pages) do p.scroll.Visible = (n == name) end
	for n, t in pairs(tabs) do
		local on = (n == name)
		TweenService:Create(t.btn, TweenInfo.new(0.15), {
			BackgroundTransparency = on and 0.84 or 1,
		}):Play()
		t.ink(on and C.white or C.muted)
	end
	tabLabel.Text = tabs[name].label
	applySearch()
end

local function addTab(name, label)
	tabCount += 1
	local btn = make("TextButton", {
		Text = "", AutoButtonColor = false, LayoutOrder = tabCount,
		BackgroundColor3 = C.white, BackgroundTransparency = 1,
		Size = UDim2.fromOffset(38, 38), Parent = tabList,
	}, { corner(10) })
	local _, ink = buildIcon(name, btn)
	tabs[name] = { btn = btn, ink = ink, label = label }
	btn.Activated:Connect(function() selectTab(name) end)
end

-- coluna estilo "board": cabeçalho com título + contador, controles em cartões escuros
local function newCard(page, col, title)
	page.count[col] += 1
	local f = make("Frame", {
		LayoutOrder = page.count[col], Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.col,
		BackgroundTransparency = 0.5, BorderSizePixel = 0, Parent = page.cols[col],
	}, {
		corner(14), stroke(C.white, 1, 0.88),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
		}),
		make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local c = { frame = f, page = page, n = 1 }

	local head = make("Frame", {
		LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = f,
	}, {
		make("UIPadding", { PaddingLeft = UDim.new(0, 4) }),
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	})
	make("TextLabel", {
		LayoutOrder = 1, Text = title, Font = Enum.Font.GothamMedium, TextSize = 13,
		TextColor3 = C.text, BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 1, 0), Parent = head,
	})
	local badge = make("TextLabel", {
		LayoutOrder = 2, Text = "0", Font = Enum.Font.GothamMedium, TextSize = 11,
		TextColor3 = C.muted, BackgroundColor3 = C.white, BackgroundTransparency = 0.88,
		Size = UDim2.fromOffset(20, 16), Parent = head,
	}, { corner(8) })
	c.badge = badge
	c.order = function()
		c.n += 1
		badge.Text = tostring(c.n - 1)
		return c.n
	end

	table.insert(cards, { frame = f, page = page, key = string.lower(title) })
	return c
end

local function addToggle(c, text, default, cb)
	local row = make("TextButton", {
		LayoutOrder = c.order(), Text = "", AutoButtonColor = false,
		BackgroundColor3 = C.card, BackgroundTransparency = 0.12, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 40), Parent = c.frame,
	}, { corner(10), stroke(C.white, 1, 0.93) })
	make("TextLabel", {
		Text = text, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -66, 1, 0), Parent = row,
	})
	local pill = make("Frame", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(40, 22), BorderSizePixel = 0, Parent = row,
	}, { corner(11) })
	local knob = make("Frame", {
		Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0, Parent = pill,
	}, { corner(8) })

	local value = default
	local function render(animate)
		local info = TweenInfo.new(animate and 0.18 or 0, Enum.EasingStyle.Quad)
		TweenService:Create(pill, info, { BackgroundColor3 = value and C.white or C.trackOff }):Play()
		TweenService:Create(knob, info, {
			BackgroundColor3 = value and C.black or C.knobOff,
			Position = value and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8),
		}):Play()
	end
	render(false)

	local obj = {}
	function obj.set(v, silent)
		value = v
		render(true)
		if not silent then cb(v) end
	end
	row.Activated:Connect(function() obj.set(not value) end)
	return obj
end

local function addCheckbox(c, text, default, cb)
	local row = make("TextButton", {
		LayoutOrder = c.order(), Text = "", AutoButtonColor = false,
		BackgroundColor3 = C.card, BackgroundTransparency = 0.12, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 36), Parent = c.frame,
	}, { corner(10), stroke(C.white, 1, 0.93) })
	local box = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 1, Parent = row,
	}, { corner(6), stroke(C.knobOff, 1.5, 0) })
	local fill = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(10, 10), BackgroundColor3 = C.white, BorderSizePixel = 0, Parent = box,
	}, { corner(3) })
	make("TextLabel", {
		Text = text, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1, Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -46, 1, 0), Parent = row,
	})
	local value = default
	fill.Visible = value
	row.Activated:Connect(function()
		value = not value
		fill.Visible = value
		cb(value)
	end)
end

local function addSlider(c, text, min, max, default, step, fmt, cb)
	local row = make("Frame", {
		LayoutOrder = c.order(), Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.card, BackgroundTransparency = 0.12, BorderSizePixel = 0, Parent = c.frame,
	}, { corner(10), stroke(C.white, 1, 0.93) })
	make("TextLabel", {
		Text = text, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 7),
		Size = UDim2.new(1, -70, 0, 16), Parent = row,
	})
	local valueLabel = make("TextLabel", {
		Text = string.format(fmt, default), Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Right,
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 7), Size = UDim2.fromOffset(52, 16), Parent = row,
	})
	local track = make("Frame", {
		Position = UDim2.new(0, 12, 0, 36), Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = C.trackOff, BorderSizePixel = 0, Parent = row,
	}, { corner(2) })
	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.white, BorderSizePixel = 0, Parent = track,
	}, { corner(2) })
	make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(14, 14), BackgroundColor3 = C.white, BorderSizePixel = 0, Parent = fill,
	}, { corner(7) })

	local function visual(v)
		local rel = (v - min) / (max - min)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		valueLabel.Text = string.format(fmt, v)
	end
	visual(default)

	local hit = make("TextButton", {
		Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
		Position = UDim2.new(0, 6, 0, 24), Size = UDim2.new(1, -12, 0, 28), Parent = row,
	})

	local dragging, dragInput = false, nil
	local function setFromX(x)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local v = min + rel * (max - min)
		v = math.floor(v / step + 0.5) * step
		v = math.clamp(v, min, max)
		visual(v)
		cb(v)
	end
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, dragInput = true, input
			c.page.scroll.ScrollingEnabled = false
			setFromX(input.Position.X)
		end
	end)
	hit.InputEnded:Connect(function(input)
		if input == dragInput then
			dragging = false
			c.page.scroll.ScrollingEnabled = true
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			setFromX(input.Position.X)
		end
	end)
end

local function addDropdown(c, text, options, default, cb)
	local wrap = make("Frame", {
		LayoutOrder = c.order(), Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.card,
		BackgroundTransparency = 0.12, BorderSizePixel = 0, Parent = c.frame,
	}, {
		corner(10), stroke(C.white, 1, 0.93),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
		}),
		make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	make("TextLabel", {
		LayoutOrder = 1, Text = text, Font = Enum.Font.GothamMedium, TextSize = 12,
		TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Parent = wrap,
	})

	local btn = make("TextButton", {
		LayoutOrder = 2, Text = "", AutoButtonColor = false,
		BackgroundColor3 = C.field, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), Parent = wrap,
	}, { corner(8), stroke(C.white, 1, 0.9) })
	local current = make("TextLabel", {
		Text = default, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -30, 1, 0), Parent = btn,
	})
	local arrow = make("TextLabel", {
		Text = "v", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.muted,
		BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(16, 30), Parent = btn,
	})

	local list = make("Frame", {
		LayoutOrder = 3, Visible = false, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = C.field,
		BorderSizePixel = 0, Parent = wrap,
	}, { corner(8), stroke(C.white, 1, 0.9), make("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }) })

	for i, opt in ipairs(options) do
		local ob = make("TextButton", {
			LayoutOrder = i, Text = opt, Font = Enum.Font.Gotham, TextSize = 12,
			TextColor3 = C.text, BackgroundTransparency = 1, AutoButtonColor = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 30), Parent = list,
		}, { make("UIPadding", { PaddingLeft = UDim.new(0, 10) }) })
		ob.Activated:Connect(function()
			current.Text = opt
			list.Visible = false
			arrow.Text = "v"
			cb(opt)
		end)
	end

	btn.Activated:Connect(function()
		list.Visible = not list.Visible
		arrow.Text = list.Visible and "^" or "v"
	end)
end

local function addInfo(c, text)
	return make("TextLabel", {
		LayoutOrder = c.order(), Text = text, Font = Enum.Font.Gotham, TextSize = 12,
		TextColor3 = C.muted, TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.card, BackgroundTransparency = 0.12, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0), Parent = c.frame,
	}, {
		corner(10), stroke(C.white, 1, 0.93),
		make("UIPadding", {
			PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9),
			PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
		}),
	})
end

local function addButton(c, text, cb)
	local b = make("TextButton", {
		LayoutOrder = c.order(), Text = text, Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = C.black, BackgroundColor3 = C.white, AutoButtonColor = true,
		Size = UDim2.new(1, 0, 0, 36), Parent = c.frame,
	}, { corner(10) })
	b.Activated:Connect(cb)
end

local function addTextBox(c, placeholder)
	return make("TextBox", {
		LayoutOrder = c.order(), Text = "", PlaceholderText = placeholder, PlaceholderColor3 = C.muted,
		Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = C.text, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundColor3 = C.card, BackgroundTransparency = 0.12, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 36), Parent = c.frame,
	}, {
		corner(10), stroke(C.white, 1, 0.93),
		make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
end

-- lista de paths do Auto Find (cada linha com botão X); retorna a função de atualizar
local function addPathList(c)
	local list = make("Frame", {
		LayoutOrder = c.order(), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Parent = c.frame,
	}, { make("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local function refresh()
		for _, ch in ipairs(list:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end
		for i, p in ipairs(findPaths) do
			local row = make("Frame", {
				LayoutOrder = i, Size = UDim2.new(1, 0, 0, 32),
				BackgroundColor3 = C.card, BackgroundTransparency = 0.12, BorderSizePixel = 0, Parent = list,
			}, { corner(10), stroke(C.white, 1, 0.93) })
			make("TextLabel", {
				Text = p, Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.text,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -42, 1, 0), Parent = row,
			})
			local x = make("TextButton", {
				Text = "X", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.muted,
				BackgroundTransparency = 1, AutoButtonColor = false,
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
				Size = UDim2.fromOffset(28, 26), Parent = row,
			})
			x.Activated:Connect(function()
				table.remove(findPaths, i)
				refresh()
			end)
		end
	end
	return refresh
end

----------------------------------------------------------------
-- Conteúdo do hub
----------------------------------------------------------------
addTab("main", "Main")
addTab("items", "Items")
addTab("stars", "Misc")
addTab("esp", "ESP")
addTab("config", "Config")

local main = newPage("main")
local items = newPage("items")
local starsPage = newPage("stars")
local espPage = newPage("esp")
local config = newPage("config")

-- Principal
local cCollect = newCard(main, 1, "Auto Collect")
local mainToggle
mainToggle = addToggle(cCollect, "Enable", false, function(v)
	S.enabled = v
	if not v then setStatus("idle") end
end)
local statusInfo = addInfo(cCollect, "Status: idle")
local countInfo = addInfo(cCollect, "Collected: 0")

local cTp = newCard(main, 2, "Teleport")
addSlider(cTp, "Item Delay", 0.05, 1, S.stepDelay, 0.01, "%.2fs", function(v) S.stepDelay = v end)
addSlider(cTp, "Height Offset", 0, 8, S.offsetY, 0.5, "%.1f", function(v) S.offsetY = v end)
addDropdown(cTp, "Order", { "Closest", "Farthest", "Random" }, S.order, function(v) S.order = v end)

-- Itens
local cSpawn = newCard(items, 1, "Item Spawns")
addToggle(cSpawn, "Enable", S.items, function(v) S.items = v end)
addCheckbox(cSpawn, "Skip Disabled Prompts", S.skipDisabled, function(v) S.skipDisabled = v end)

local cAll = newCard(items, 2, "Collect Objects")
addToggle(cAll, "Enable", S.collectAll, function(v) S.collectAll = v end)

local cPot = newCard(items, 2, "Potions, Coins")
addToggle(cPot, "Enable", S.potions, function(v) S.potions = v end)

local cFind = newCard(items, 1, "Auto Find")
addToggle(cFind, "Enable", false, function(v)
	S.find = v
	if not v then setStatus("idle") end
end)
local pathBox = addTextBox(cFind, "Paste path here")
local refreshPaths = function() end
addButton(cFind, "Add Path", function()
	local text = (pathBox.Text:gsub("^%s+", ""))
	text = (text:gsub("%s+$", ""))
	if text == "" then return end
	for _, p in ipairs(findPaths) do
		if p == text then
			pathBox.Text = ""
			return
		end
	end
	table.insert(findPaths, text)
	pathBox.Text = ""
	refreshPaths()
	if not resolvePath(text) then setStatus("path not found yet") end
end)
refreshPaths = addPathList(cFind)
addDropdown(cFind, "Mode", { "Teleport", "Tween", "Remote" }, S.findMode, function(v) S.findMode = v end)
addSlider(cFind, "Tween Speed", 20, 500, S.findTweenSpeed, 10, "%.0f", function(v) S.findTweenSpeed = v end)
addSlider(cFind, "Revisit Delay", 1, 60, S.findDelay, 1, "%.0fs", function(v) S.findDelay = v end)
addButton(cFind, "Clear All", function()
	table.clear(findPaths)
	refreshPaths()
end)

-- Estrelas
local cStar = newCard(starsPage, 1, "Collect Stars")
addToggle(cStar, "Enable", S.stars, function(v) S.stars = v end)

local cBaeus = newCard(starsPage, 2, "Collect Baeus")
addToggle(cBaeus, "Enable", S.baeus, function(v) S.baeus = v end)
addDropdown(cBaeus, "Touch Mode", { "Teleport", "Remote", "Tween" }, S.baeusMode, function(v) S.baeusMode = v end)
addSlider(cBaeus, "Tween Speed", 20, 500, S.tweenSpeed, 10, "%.0f", function(v) S.tweenSpeed = v end)
addSlider(cBaeus, "Revisit Delay", 1, 60, S.baeusDelay, 1, "%.0fs", function(v) S.baeusDelay = v end)

-- ESP (um toggle separado por grupo)
for i, g in ipairs(ESP_GROUPS) do
	local card = newCard(espPage, ((i - 1) % 2) + 1, g.title)
	addToggle(card, "Enable", false, function(v) S.espOn[g.id] = v end)
end

-- Config
local cCfg = newCard(config, 1, "Settings")
addSlider(cCfg, "Item Cooldown", 0.2, 5, S.cooldown, 0.1, "%.1fs", function(v) S.cooldown = v end)

local cAuto = newCard(config, 1, "Auto Interact")
addToggle(cAuto, "Enable", S.autoInteract, function(v) S.autoInteract = v end)
addSlider(cAuto, "Range", 10, 200, S.interactRange, 5, "%.0f", function(v) S.interactRange = v end)
local cUi = newCard(config, 2, "Interface")
addButton(cUi, "Reset Counter", function()
	collected = 0
	setCount(0)
end)
addButton(cUi, "Close UI", function()
	S.enabled = false
	gui:Destroy()
end)

----------------------------------------------------------------
-- Pílula de status (barra superior, à direita da busca, brilho ciano)
----------------------------------------------------------------
local pillGlow = make("Frame", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -90, 0, 3),
	Size = UDim2.fromOffset(152, 46), BackgroundColor3 = C.cyan, BackgroundTransparency = 0.9,
	BorderSizePixel = 0, ZIndex = 4, Parent = topbar,
}, { corner(23) })
local pill = make("TextButton", {
	Text = "", AutoButtonColor = false,
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -96, 0, 9),
	Size = UDim2.fromOffset(140, 34), BackgroundColor3 = C.black, BackgroundTransparency = 0.1,
	BorderSizePixel = 0, ZIndex = 5, Parent = topbar,
}, { corner(17) })
local pillStroke = make("UIStroke", {
	Thickness = 2, Color = C.white, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = pill,
})
local pillGrad = make("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.cyan),
		ColorSequenceKeypoint.new(0.5, C.blue),
		ColorSequenceKeypoint.new(1, C.cyan),
	}),
	Parent = pillStroke,
})
TweenService:Create(pillGrad, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), {
	Rotation = 360,
}):Play()
local pillDot = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 15, 0.5, 0),
	Size = UDim2.fromOffset(8, 8), Rotation = 45, BackgroundColor3 = C.cyan,
	BorderSizePixel = 0, ZIndex = 6, Parent = pill,
})
local pillText = make("TextLabel", {
	Text = "Idle", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	BackgroundTransparency = 1, Position = UDim2.fromOffset(32, 0),
	Size = UDim2.new(1, -42, 1, 0), ZIndex = 6, Parent = pill,
})
pill.Activated:Connect(function() selectTab("main") end)

setStatus = function(t)
	statusInfo.Text = "Status: " .. t
	pillText.Text = (t:sub(1, 1):upper() .. t:sub(2))
end
setCount = function(n) countInfo.Text = "Collected: " .. n end

----------------------------------------------------------------
-- Bolha minimizada (mesmo tile do cabeçalho)
----------------------------------------------------------------
local bubble = make("Frame", {
	Visible = false, Size = UDim2.fromOffset(44, 44),
	Position = UDim2.new(0, 20, 0.5, -22),
	BackgroundColor3 = C.black, BackgroundTransparency = 0.1, BorderSizePixel = 0,
}, { corner(12), stroke(C.white, 1, 0.78) })
leafIcon(bubble, 32)

local bubblePlaced = false
local function minimize()
	-- só define a posição inicial na primeira vez; depois mantém onde foi arrastada
	if not bubblePlaced then
		local p = window.AbsolutePosition
		bubble.Position = UDim2.fromOffset(math.max(p.X, 8), math.max(p.Y, 8))
		bubblePlaced = true
	end
	window.Visible = false
	bubble.Visible = true
end
minBtn.Activated:Connect(minimize)
makeDraggable(bubble, bubble, nil, function()
	bubble.Visible = false
	window.Visible = true
end)

closeBtn.Activated:Connect(function()
	S.enabled = false
	gui:Destroy()
end)

-- Busca
searchBox:GetPropertyChangedSignal("Text"):Connect(applySearch)

-- Arrastar janela pela barra superior
makeDraggable(topbar, window, scale, nil)

----------------------------------------------------------------
-- Layout dinâmico (paisagem / retrato + escala)
----------------------------------------------------------------
applyLayout = function()
	local cam = workspace.CurrentCamera
	if not cam then return end
	local vp = cam.ViewportSize
	local portrait = vp.Y > vp.X

	local w, h = 560, 330
	if portrait then w, h = 340, 480 end

	window.Size = UDim2.fromOffset(w, h)
	scale.Scale = math.clamp(math.min(vp.X / (w + 24), vp.Y / (h + 40)), 0.5, 1.15)
	searchWrap.Size = portrait and UDim2.fromOffset(134, 32) or UDim2.fromOffset(220, 32)
	-- pílula de status: completa na paisagem, só o brilho/ícone no retrato
	pillText.Visible = not portrait
	pill.Size = portrait and UDim2.fromOffset(34, 34) or UDim2.fromOffset(140, 34)
	pillGlow.Size = portrait and UDim2.fromOffset(46, 46) or UDim2.fromOffset(152, 46)
	pillDot.AnchorPoint = portrait and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5)
	pillDot.Position = portrait and UDim2.new(0.5, 0, 0.5, 0) or UDim2.new(0, 15, 0.5, 0)

	local vertical = portrait or viewMode == "List"
	for _, p in pairs(pages) do
		if vertical then
			p.holderLayout.FillDirection = Enum.FillDirection.Vertical
			for _, col in ipairs(p.cols) do col.Size = UDim2.new(1, 0, 0, 0) end
		else
			p.holderLayout.FillDirection = Enum.FillDirection.Horizontal
			for _, col in ipairs(p.cols) do col.Size = UDim2.new(0.5, -5, 0, 0) end
		end
	end
end

applyLayout()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
end

window.Parent = gui
bubble.Parent = gui
gui.Parent = parentGui
setView("Board")
selectTab("main")

----------------------------------------------------------------
-- Auto Interact (todos os ProximityPrompt ao redor de uma vez)
----------------------------------------------------------------
do
	local promptCache, lastScan = {}, 0

	local function scanPrompts()
		promptCache = {}
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") then table.insert(promptCache, d) end
		end
		lastScan = os.clock()
	end

	task.spawn(function()
		while gui.Parent do
			if S.autoInteract then
				local hrp = getHRP()
				if hrp then
					if os.clock() - lastScan > 1.5 then scanPrompts() end
					local origin = hrp.Position
					for _, p in ipairs(promptCache) do
						if not S.autoInteract then break end
						if p.Parent and p.Enabled then
							local pos = posOf(p)
							if pos and (pos - origin).Magnitude <= S.interactRange then
								local last = cooldown[p]
								if not last or (os.clock() - last) >= S.cooldown then
									cooldown[p] = os.clock()
									pcall(firePrompt, p)
									collected += 1
									setCount(collected)
								end
							end
						end
					end
				end
				task.wait(0.15)
			else
				task.wait(0.25)
			end
		end
	end)
end

----------------------------------------------------------------
-- Auto Find (qualquer path colado)
----------------------------------------------------------------
task.spawn(function()
	while gui.Parent do
		if S.find and #findPaths > 0 and getHRP() then
			local on = function() return S.find end
			local snapshot = table.clone(findPaths)

			for _, pathStr in ipairs(snapshot) do
				if not S.find then break end
				local root = resolvePath(pathStr)
				if not root then
					setStatus("path not found")
				else
					local targets = findTargets(root)
					local hrp = getHRP()
					local origin = hrp and hrp.Position or Vector3.zero
					table.sort(targets, function(a, b)
						local pa, pb = posOf(a), posOf(b)
						if not pa then return false end
						if not pb then return true end
						return (pa - origin).Magnitude < (pb - origin).Magnitude
					end)

					for _, inst in ipairs(targets) do
						if not S.find then break end
						if inst.Parent and not (inst:IsA("ProximityPrompt") and not inst.Enabled) then
							local last = cooldown[inst]
							if not last or (os.clock() - last) >= S.findDelay then
								setStatus("finding " .. inst.Name)
								findVisit(inst, S.findMode, on)
								cooldown[inst] = os.clock()
								collected += 1
								setCount(collected)
								task.wait(S.stepDelay)
							end
						end
					end
				end
			end
			task.wait(0.3)
		else
			task.wait(0.25)
		end
	end
end)

----------------------------------------------------------------
-- ESP (através de tudo, brilho forte, distância em studs)
----------------------------------------------------------------
do
	local host = (parentGui == player:FindFirstChild("PlayerGui")) and workspace.CurrentCamera or parentGui
	local espFolder = Instance.new("Folder")
	espFolder.Name = "LumimESP"
	espFolder.Parent = host

	local items = {} -- items[groupId][obj] = item
	local WHITE = Color3.new(1, 1, 1)

	local function resolvePath(path)
		local cur = workspace
		for _, name in ipairs(path) do
			cur = cur and cur:FindFirstChild(name)
		end
		return cur
	end

	local function mainPart(obj)
		if obj:IsA("BasePart") then return obj end
		if obj:IsA("Model") then
			return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		end
	end

	local function makeBox(part, color, transp, z)
		local box = Instance.new("BoxHandleAdornment")
		box.Adornee = part
		box.Size = Vector3.new(1, 1, 1)
		box.Color3 = color
		box.Transparency = transp
		box.AlwaysOnTop = true
		box.ZIndex = z
		box.Parent = espFolder
		return box
	end

	local function makeLabel(part, obj, color)
		local bb = Instance.new("BillboardGui")
		bb.Adornee = part
		bb.AlwaysOnTop = true
		bb.ResetOnSpawn = false
		bb.Size = UDim2.fromOffset(140, 38)
		bb.StudsOffset = Vector3.new(0, 2.5, 0)
		bb.Parent = espFolder

		local function lbl(y, h, size, font, col)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency = 1
			t.Position = UDim2.new(0, 0, 0, y)
			t.Size = UDim2.new(1, 0, 0, h)
			t.Font = font
			t.TextSize = size
			t.TextColor3 = col
			t.TextStrokeColor3 = Color3.new(0, 0, 0)
			t.TextStrokeTransparency = 0
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.Parent = bb
			return t
		end

		local nameLabel = lbl(0, 16, 12, Enum.Font.GothamMedium, WHITE)
		nameLabel.Text = obj.Name
		local distLabel = lbl(16, 22, 17, Enum.Font.GothamBold, color)
		distLabel.Text = "..."
		return bb, distLabel
	end

	local function destroyItem(it)
		for _, k in ipairs({ "inner", "outer", "glow", "hl", "gui" }) do
			if it[k] then it[k]:Destroy() end
		end
	end

	local function clearGroup(id)
		local tbl = items[id]
		if not tbl then return end
		for obj, it in pairs(tbl) do
			destroyItem(it)
			tbl[obj] = nil
		end
	end

	local function collectObjects(group)
		local out = {}
		local root = resolvePath(group.path)
		if not root then return out end

		local function addKids(f)
			for _, child in ipairs(f:GetChildren()) do
				if child:IsA("Folder") then
					addKids(child)
				elseif child:IsA("Model") or child:IsA("BasePart") then
					table.insert(out, child)
				end
			end
		end

		if root:IsA("Folder") then
			addKids(root)
		elseif root:IsA("Model") or root:IsA("BasePart") then
			if group.split and root:IsA("Model") then
				addKids(root)
				if #out == 0 then table.insert(out, root) end
			else
				table.insert(out, root)
			end
		end
		return out
	end

	local function updateGroup(group)
		items[group.id] = items[group.id] or {}
		local tbl = items[group.id]
		local alive = {}

		for _, obj in ipairs(collectObjects(group)) do
			alive[obj] = true
			if not tbl[obj] then
				local part = mainPart(obj)
				if part then
					local gui2, distLabel = makeLabel(part, obj, group.color)
					tbl[obj] = {
						obj = obj, part = part, color = group.color,
						inner = makeBox(part, group.color, 0.25, 3),
						outer = makeBox(part, group.color:Lerp(WHITE, 0.25), 0.65, 2),
						glow = makeBox(part, group.color, 0.88, 1),
						gui = gui2, label = distLabel,
					}
				end
			end
		end

		for obj, it in pairs(tbl) do
			if not alive[obj] or not it.part.Parent then
				destroyItem(it)
				tbl[obj] = nil
			end
		end
	end

	local function getOrigin()
		local hrp = getHRP()
		local cam = workspace.CurrentCamera
		return hrp and hrp.Position or (cam and cam.CFrame.Position) or Vector3.zero
	end

	-- geometria dos brilhos (cresce com a distância para continuar visível de longe)
	local function refreshBoxes(it, dist)
		local obj, part = it.obj, it.part
		local size, rel
		if obj:IsA("BasePart") then
			size, rel, it.center = part.Size, CFrame.new(), part.Position
		else
			local cf, sz = obj:GetBoundingBox()
			size, rel, it.center = sz, part.CFrame:ToObjectSpace(cf), cf.Position
		end
		local pad = math.clamp(dist * 0.03, 0.3, 8)
		it.inner.Size = size + Vector3.new(0.1, 0.1, 0.1)
		it.outer.Size = size + Vector3.new(0.6 + pad, 0.6 + pad, 0.6 + pad)
		it.glow.Size = size + Vector3.new(1.4 + pad * 2, 1.4 + pad * 2, 1.4 + pad * 2)
		it.inner.CFrame, it.outer.CFrame, it.glow.CFrame = rel, rel, rel
	end

	local function updateAll()
		for _, g in ipairs(ESP_GROUPS) do
			if S.espOn[g.id] then
				pcall(updateGroup, g)
			else
				clearGroup(g.id)
			end
		end

		local origin = getOrigin()
		local all = {}
		for _, tbl in pairs(items) do
			for _, it in pairs(tbl) do
				it.dist = (it.part.Position - origin).Magnitude
				table.insert(all, it)
			end
		end
		table.sort(all, function(a, b) return a.dist < b.dist end)

		-- Highlight real (contorno brilhante) nos 30 mais próximos de todos os grupos; limite do Roblox é 31
		for i, it in ipairs(all) do
			pcall(refreshBoxes, it, it.dist)
			if i <= 30 then
				if not it.hl then
					local hl = Instance.new("Highlight")
					hl.Adornee = it.obj
					hl.FillColor = it.color
					hl.FillTransparency = 0.35
					hl.OutlineColor = it.color:Lerp(WHITE, 0.6)
					hl.OutlineTransparency = 0
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.Parent = espFolder
					it.hl = hl
				end
			elseif it.hl then
				it.hl:Destroy()
				it.hl = nil
			end
		end
	end

	-- só os números de distância (leve, roda mais vezes)
	local function updateLabels()
		local origin = getOrigin()
		for _, tbl in pairs(items) do
			for _, it in pairs(tbl) do
				local c = it.center or it.part.Position
				it.label.Text = string.format("%d studs", math.floor((c - origin).Magnitude + 0.5))
			end
		end
	end

	task.spawn(function()
		local tick = 0
		while gui.Parent do
			if tick % 5 == 0 then
				pcall(updateAll)
			end
			pcall(updateLabels)
			tick += 1
			task.wait(0.1)
		end
		for _, g in ipairs(ESP_GROUPS) do clearGroup(g.id) end
		espFolder:Destroy()
	end)
end
