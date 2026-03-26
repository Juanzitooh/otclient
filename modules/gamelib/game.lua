function g_game.getRsa()
    return G.currentRsa
end

function g_game.findPlayerItem(itemId, subType, tier)
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer then
        for slot = InventorySlotFirst, InventorySlotLast do
            local item = localPlayer:getInventoryItem(slot)
            if item and item:getId() == itemId and (subType == -1 or item:getSubType() == subType) then
                return item
            end
        end
    end

    return g_game.findItemInContainers(itemId, subType, tier or 0)
end

function g_game.chooseRsa(host)
    if G.currentRsa ~= CIPSOFT_RSA and G.currentRsa ~= OTSERV_RSA then
        return
    end
    if host:ends('.tibia.com') or host:ends('.cipsoft.com') then
        g_game.setRsa(CIPSOFT_RSA)

        if g_app.getOs() == 'windows' then
            g_game.setCustomOs(OsTypes.Windows)
        else
            g_game.setCustomOs(OsTypes.Linux)
        end
    else
        if G.currentRsa == CIPSOFT_RSA then
            g_game.setCustomOs(-1)
        end
        g_game.setRsa(OTSERV_RSA)
    end

    -- Hack fix to resolve some 760 login issues
    if g_game.getClientVersion() <= 760 then
        g_game.setCustomOs(2)
    end
end

function g_game.setRsa(rsa, e)
    e = e or '65537'
    g_crypt.rsaSetPublicKey(rsa, e)
    G.currentRsa = rsa
end

function g_game.isOfficialTibia()
    return G.currentRsa == CIPSOFT_RSA
end

function g_game.getSupportedClients()
    return { 740, 741, 750, 755, 760, 770, 772, 780, 781, 782, 790, 792, 800, 810, 811, 820, 821, 822, 830, 831, 840,
        842, 850, 853, 854, 855, 857, 860, 861, 862, 870, 871, 900, 910, 920, 931, 940, 943, 944, 951, 952, 953,
        954, 960, 961, 963, 970, 971, 972, 973, 980, 981, 982, 983, 984, 985, 986, 1000, 1001, 1002, 1010, 1011,
        1012, 1013, 1020, 1021, 1022, 1030, 1031, 1032, 1033, 1034, 1035, 1036, 1037, 1038, 1039, 1040, 1041, 1050,
        1051, 1052, 1053, 1054, 1055, 1056, 1057, 1058, 1059, 1060, 1061, 1062, 1063, 1064, 1070, 1071, 1072, 1073,
        1074, 1075, 1076, 1080, 1081, 1082, 1090, 1091, 1092, 1093, 1094, 1095, 1096, 1097, 1098, 1099, 1100, 1281, 1285,
        1286, 1287, 1291, 1300, 1310, 1311, 1314, 1316, 1320, 1321, 1322, 1332, 1334, 1336, 1337, 1340, 1400, 1405, 1410, 1412,
        1500, 1501, 1503, 1510, 1511}
end

-- The client version and protocol version where
-- unsynchronized for some releases, not sure if this
-- will be the normal standard.

-- Client Version: Publicly given version when
-- downloading Cipsoft client.

-- Protocol Version: Previously was the same as
-- the client version, but was unsychronized in some
-- releases, now it needs to be verified and added here
-- if it does not match the client version.

-- Reason for defining both: The server now requires a
-- Client version and Protocol version from the client.

-- Important: Use getClientVersion for specific protocol
-- features to ensure we are using the proper version.

function g_game.getClientProtocolVersion(client)
    local clients = {
        [980] = 971,
        [981] = 973,
        [982] = 974,
        [983] = 975,
        [984] = 976,
        [985] = 977,
        [986] = 978,
        [1001] = 979,
        [1002] = 980
    }
    return clients[client] or client
end

if not G.currentRsa then
    g_game.setRsa(OTSERV_RSA)
end

function g_game.closeContainerByItemId(itemId, tier)
    if not itemId then
        return false
    end
    local containersToClose = {}
    for _, container in pairs(g_game.getContainers()) do
        local containerItem = container:getContainerItem()
        if containerItem and containerItem:getId() == itemId then
            local containerTier = containerItem.getTier and containerItem:getTier() or nil
            if not tier or containerTier == tier then
                table.insert(containersToClose, container)
            end
        end
    end
    for _, container in ipairs(containersToClose) do
        g_game.close(container)
    end
    return #containersToClose > 0
end

local function normalizePositiveNumber(value)
    value = tonumber(value) or 0
    if value < 0 then
        return 0
    end
    return math.floor(value)
end

local HOUSE_LUA_LOG_TAG = "[cyclopedia-houses-lua]"

local function houseLuaLog(level, message, ...)
    local text = message
    if select("#", ...) > 0 then
        text = string.format(message, ...)
    end

    if level == "warning" then
        g_logger.warning(HOUSE_LUA_LOG_TAG .. " " .. text)
    elseif level == "error" then
        g_logger.error(HOUSE_LUA_LOG_TAG .. " " .. text)
    else
        g_logger.info(HOUSE_LUA_LOG_TAG .. " " .. text)
    end
end

local function houseAuctionTypeName(auctionType)
    if auctionType == CyclopediaHouseAuctionTypes.Show then
        return "Show"
    elseif auctionType == CyclopediaHouseAuctionTypes.Bid then
        return "Bid"
    elseif auctionType == CyclopediaHouseAuctionTypes.MoveOut then
        return "MoveOut"
    elseif auctionType == CyclopediaHouseAuctionTypes.Transfer then
        return "Transfer"
    elseif auctionType == CyclopediaHouseAuctionTypes.CancelMoveOut then
        return "CancelMoveOut"
    elseif auctionType == CyclopediaHouseAuctionTypes.CancelTransfer then
        return "CancelTransfer"
    elseif auctionType == CyclopediaHouseAuctionTypes.AcceptTransfer then
        return "AcceptTransfer"
    elseif auctionType == CyclopediaHouseAuctionTypes.RejectTransfer then
        return "RejectTransfer"
    end

    return string.format("Unknown(%s)", tostring(auctionType))
end

function g_game.requestShowHouses(townName)
    local normalizedTownName = townName or ""
    houseLuaLog("info", "TX action=%s houseId=0 timestamp=0 bidValue=0 town=\"%s\"",
        houseAuctionTypeName(CyclopediaHouseAuctionTypes.Show), normalizedTownName)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.Show, 0, 0, 0, normalizedTownName)
end

function g_game.requestBidHouse(houseId, bidValue)
    local normalizedHouseId = normalizePositiveNumber(houseId)
    local normalizedBid = normalizePositiveNumber(bidValue)
    if normalizedHouseId == 0 or normalizedBid == 0 then
        houseLuaLog("warning", "Bid request with low payload houseId=%s bidValue=%s (normalized to %d/%d)",
            tostring(houseId), tostring(bidValue), normalizedHouseId, normalizedBid)
    end
    houseLuaLog("info", "TX action=%s houseId=%d timestamp=0 bidValue=%d",
        houseAuctionTypeName(CyclopediaHouseAuctionTypes.Bid), normalizedHouseId, normalizedBid)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.Bid, normalizedHouseId, 0, normalizedBid, "")
end

function g_game.requestMoveOutHouse(houseId, timestamp)
    local normalizedHouseId = normalizePositiveNumber(houseId)
    local normalizedTimestamp = normalizePositiveNumber(timestamp)
    if normalizedHouseId == 0 or normalizedTimestamp == 0 then
        houseLuaLog("warning", "MoveOut request with low payload houseId=%s timestamp=%s (normalized to %d/%d)",
            tostring(houseId), tostring(timestamp), normalizedHouseId, normalizedTimestamp)
    end
    houseLuaLog("info", "TX action=%s houseId=%d timestamp=%d bidValue=0",
        houseAuctionTypeName(CyclopediaHouseAuctionTypes.MoveOut), normalizedHouseId, normalizedTimestamp)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.MoveOut, normalizedHouseId, normalizedTimestamp, 0, "")
end

function g_game.requestTransferHouse(houseId, timestamp, newOwner, bidValue)
    local normalizedHouseId = normalizePositiveNumber(houseId)
    local normalizedTimestamp = normalizePositiveNumber(timestamp)
    local normalizedBid = normalizePositiveNumber(bidValue)
    local normalizedOwner = newOwner or ""
    if normalizedHouseId == 0 or normalizedTimestamp == 0 or normalizedOwner == "" then
        houseLuaLog("warning",
            "Transfer request with low payload houseId=%s timestamp=%s owner=\"%s\" bidValue=%s (normalized to %d/%d/%s/%d)",
            tostring(houseId), tostring(timestamp), tostring(newOwner), tostring(bidValue), normalizedHouseId, normalizedTimestamp,
            normalizedOwner == "" and "<empty>" or normalizedOwner, normalizedBid)
    end
    houseLuaLog("info", "TX action=%s houseId=%d timestamp=%d bidValue=%d owner=\"%s\"",
        houseAuctionTypeName(CyclopediaHouseAuctionTypes.Transfer), normalizedHouseId, normalizedTimestamp, normalizedBid,
        normalizedOwner)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.Transfer, normalizedHouseId, normalizedTimestamp,
        normalizedBid, normalizedOwner)
end

function g_game.requestCancelMoveOutHouse(houseId)
    local normalizedHouseId = normalizePositiveNumber(houseId)
    if normalizedHouseId == 0 then
        houseLuaLog("warning", "CancelMoveOut request with invalid houseId=%s", tostring(houseId))
    end
    houseLuaLog("info", "TX action=%s houseId=%d", houseAuctionTypeName(CyclopediaHouseAuctionTypes.CancelMoveOut),
        normalizedHouseId)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.CancelMoveOut, normalizedHouseId, 0, 0, "")
end

function g_game.requestCancelHouseTransfer(houseId)
    local normalizedHouseId = normalizePositiveNumber(houseId)
    if normalizedHouseId == 0 then
        houseLuaLog("warning", "CancelTransfer request with invalid houseId=%s", tostring(houseId))
    end
    houseLuaLog("info", "TX action=%s houseId=%d", houseAuctionTypeName(CyclopediaHouseAuctionTypes.CancelTransfer),
        normalizedHouseId)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.CancelTransfer, normalizedHouseId, 0, 0, "")
end

function g_game.requestAcceptHouseTransfer(houseId)
    local normalizedHouseId = normalizePositiveNumber(houseId)
    if normalizedHouseId == 0 then
        houseLuaLog("warning", "AcceptTransfer request with invalid houseId=%s", tostring(houseId))
    end
    houseLuaLog("info", "TX action=%s houseId=%d", houseAuctionTypeName(CyclopediaHouseAuctionTypes.AcceptTransfer),
        normalizedHouseId)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.AcceptTransfer, normalizedHouseId, 0, 0, "")
end

function g_game.requestRejectHouseTransfer(houseId)
    local normalizedHouseId = normalizePositiveNumber(houseId)
    if normalizedHouseId == 0 then
        houseLuaLog("warning", "RejectTransfer request with invalid houseId=%s", tostring(houseId))
    end
    houseLuaLog("info", "TX action=%s houseId=%d", houseAuctionTypeName(CyclopediaHouseAuctionTypes.RejectTransfer),
        normalizedHouseId)
    g_game.sendCyclopediaHouseAuction(CyclopediaHouseAuctionTypes.RejectTransfer, normalizedHouseId, 0, 0, "")
end
