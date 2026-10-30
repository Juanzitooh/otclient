local OPCODE = ExtendedIds.BetaAdmin
local CONTRACT_VERSION = 1
local MAX_REQUEST_ID = 2147483647
local ELEMENTAL_WINDOW_ID = "beta-admin"
local ROLE_NAMES = {
    [1] = "Player",
    [2] = "Tutor",
    [3] = "Senior Tutor",
    [4] = "Game Master",
    [5] = "Community Manager",
    [6] = "God",
}
local CAPABILITY_ITEMS = "beta.test.items"
local CAPABILITY_MONSTERS = "beta.test.monsters"
local CAPABILITY_FEEDBACK = "beta.feedback.triage"
local CAPABILITY_MANAGE_TUTORS = "beta.manage.tutors"
local CAPABILITY_MANAGE_STAFF = "beta.manage.staff"
local CAPABILITY_COMPENSATE = "beta.compensate"
local CAPABILITY_ELEVATION_REQUEST = "beta.elevation.request"
local MAX_QUERY_LENGTH = 64
local CAPABILITY_LABELS = {
    ["beta.feedback.triage"] = "Triagem de feedback",
    [CAPABILITY_MANAGE_STAFF] = "Gerir equipe abaixo de CM",
    [CAPABILITY_MANAGE_TUTORS] = "Gerir Tutores",
    [CAPABILITY_COMPENSATE] = "Compensacao bancaria limitada",
    [CAPABILITY_ELEVATION_REQUEST] = "Solicitar elevacao tecnica temporaria",
    ["beta.test.items"] = "Teste de itens",
    ["beta.test.monsters"] = "Teste de monstros",
}
local MANAGEMENT_SCOPE_LABELS = {
    god = "God: gerencia personagens abaixo de God; grants beta exclusivos de God.",
    tutors = "Senior Tutor: contas Normal/Tutor; grupos Player/Tutor.",
    staff = "Community Manager: equipe abaixo de CM; grupos Player/Tutor/Senior Tutor.",
}
local MANAGEMENT_OPTION_LIMITS = {
    god = { accountType = 5, group = 3 },
    tutors = { accountType = 2, group = 2 },
    staff = { accountType = 4, group = 3 },
}
local USER_MANAGEMENT_WIDGET_IDS = {
    "accountTypeScope",
    "accountTypeSelection",
    "applyAccountTypeButton",
    "groupScope",
    "groupSelection",
    "applyGroupButton",
    "capabilitiesTitle",
    "capabilityStoreStatus",
    "userCapabilitiesScrollBar",
    "userCapabilities",
}
local TARGET_ACTION_MENU_CATEGORY = "betaAdmin"
local TARGET_ACTION_MENU_HOOKS = {
    { words = "/kick", label = "Painel beta: Expulsar", buttonId = "userQuickKickButton", buttonLabel = "Expulsar" },
    { words = "/ban", label = "Painel beta: Banir", buttonId = "userQuickBanButton", buttonLabel = "Banir" },
    { words = "/t", label = "Painel beta: Enviar ao templo", buttonId = "userQuickTempleButton", buttonLabel = "Templo" },
}

local function hasValidManagementOptions(snapshot)
    local limits = MANAGEMENT_OPTION_LIMITS[snapshot.managementScope]
    if not limits then
        return snapshot.canManageUsers ~= true
    end
    if snapshot.canManageUsers ~= true or type(snapshot.accountTypeOptions) ~= "table"
        or type(snapshot.groupOptions) ~= "table" or type(snapshot.capabilityOptions) ~= "table" then
        return false
    end
    if snapshot.managementScope ~= "god" and #snapshot.capabilityOptions > 0 then
        return false
    end
    for _, option in ipairs(snapshot.accountTypeOptions) do
        if type(option) ~= "table" or type(option.id) ~= "number" or option.id > limits.accountType then
            return false
        end
    end
    for _, option in ipairs(snapshot.groupOptions) do
        if type(option) ~= "table" or type(option.id) ~= "number" or option.id > limits.group then
            return false
        end
    end
    return true
end

local function trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

local function lower(value)
    return string.lower(trim(value))
end

local function getFirstWord(words)
    local first = tostring(words or ""):match("^%s*([^,]+)")
    return lower(first)
end

local function splitWords(words)
    local result = {}
    for word in (tostring(words or "") .. ","):gmatch("(.-),") do
        word = lower(word)
        if word ~= "" then
            result[#result + 1] = word
        end
    end
    return result
end

local function hasCapability(capabilities, capability)
    return capabilities and capabilities[capability] == true
end

local function hasQuickTargetAction(user, words)
    return user ~= nil and type(user.quickActions) == "table" and user.quickActions[words] == true
end

local function findExecutableTargetAction(actions, snapshot, words)
    if type(snapshot) ~= "table" or type(snapshot.accountType) ~= "number" then
        return nil
    end

    for _, action in ipairs(actions or {}) do
        if type(action) == "table" and type(action.words) == "string"
            and getFirstWord(action.words) == words and type(action.groupType) == "number"
            and action.groupType <= snapshot.accountType and type(action.schema) == "table"
            and not action.schema.blockedReason then
            return action
        end
    end
    return nil
end

local function resolveLivePlayerTarget(creature, isOnline, getCreatureById)
    if isOnline ~= true or not creature or type(creature.isPlayer) ~= "function"
        or not creature:isPlayer() or creature:isLocalPlayer() or creature:isRemoved()
        or type(getCreatureById) ~= "function" then
        return nil
    end

    local targetId = creature:getId()
    local targetName = creature:getName()
    if type(targetId) ~= "number" or type(targetName) ~= "string" or targetName == "" then
        return nil
    end

    local liveTarget = getCreatureById(targetId)
    if not liveTarget or not liveTarget:isPlayer() or liveTarget:isLocalPlayer()
        or liveTarget:isRemoved() or liveTarget:getName() ~= targetName then
        return nil
    end

    return { id = targetId, name = targetName }
end

local function parseInteger(value, minimum, maximum)
    if type(value) ~= "string" or not value:match("^-?%d+$") then
        return nil
    end
    local parsed = tonumber(value)
    if not parsed or parsed < minimum or parsed > maximum or parsed % 1 ~= 0 then
        return nil
    end
    return parsed
end

local function setWidgetText(widget, value)
    if widget then
        widget:setText(tostring(value or ""))
    end
end

local function createMonsterOutfit(monster)
    return {
        type = tonumber(monster.lookType) or 0,
        auxType = tonumber(monster.lookTypeEx) or 0,
        head = tonumber(monster.lookHead) or 0,
        body = tonumber(monster.lookBody) or 0,
        legs = tonumber(monster.lookLegs) or 0,
        feet = tonumber(monster.lookFeet) or 0,
        addons = tonumber(monster.lookAddons) or 0,
    }
end

local function getMonsterLookTypeLabel(monster)
    local lookType = tonumber(monster and monster.lookType)
    if not lookType or lookType <= 0 then
        return "LookType ID indisponivel"
    end
    return string.format("LookType ID %d", lookType)
end

local function getFieldHelp(field)
    if field.help then
        return field.help
    end
    if field.kind == "number" then
        return string.format("Inteiro entre %d e %d.", field.minimum, field.maximum)
    end
    if field.kind == "amount" then
        return "Inteiro positivo ou all."
    end
    if field.kind == "choice" then
        local labels = {}
        for _, option in ipairs(field.options or {}) do
            labels[#labels + 1] = option[2]
        end
        return "Opcoes: " .. table.concat(labels, ", ") .. "."
    end
    return string.format("Texto com ate %d caracteres.", field.maxLength or 48)
end

local function containsValue(values, value)
    for _, candidate in ipairs(values or {}) do
        if candidate == value then
            return true
        end
    end
    return false
end

local function findRoleOption(options, id)
    for _, option in ipairs(options or {}) do
        if tonumber(option.id) == tonumber(id) then
            return option
        end
    end
    return nil
end

GameBetaAdmin = Controller:new()
GameBetaAdmin:setUI("game_beta_admin")
GameBetaAdmin.schemas = BetaAdminTalkActionSchemas
GameBetaAdmin.snapshot = nil
GameBetaAdmin.actions = {}
GameBetaAdmin.filteredActions = {}
GameBetaAdmin.capabilities = {}
GameBetaAdmin.pendingRequests = {}
GameBetaAdmin.fieldWidgets = {}
GameBetaAdmin.selectedAction = nil
GameBetaAdmin.selectedSchema = nil
GameBetaAdmin.selectedItem = nil
GameBetaAdmin.selectedMonster = nil
GameBetaAdmin.selectedUser = nil
GameBetaAdmin.selectedItemRecipient = nil
GameBetaAdmin.userResults = {}
GameBetaAdmin.assignableCapabilities = {}
GameBetaAdmin.userQuery = ""
GameBetaAdmin.userHasMore = false
GameBetaAdmin.userReselectName = nil
GameBetaAdmin.searchEvent = nil
GameBetaAdmin.latestItemSearchRequestId = nil
GameBetaAdmin.latestMonsterSearchRequestId = nil
GameBetaAdmin.latestUserSearchRequestId = nil
GameBetaAdmin.latestItemRecipientRequestId = nil
GameBetaAdmin.itemRecipientSearchEvent = nil
GameBetaAdmin.settingItemRecipient = false
GameBetaAdmin.settingUserSearch = false
GameBetaAdmin.nextRequestId = 0
GameBetaAdmin.activePage = "commands"
GameBetaAdmin.status = "Desconectado."
GameBetaAdmin.catalogStatus = {
    items = "Digite um nome ou ID para pesquisar.",
    monsters = "Digite um nome ou ID para pesquisar.",
}
GameBetaAdmin.targetActionContext = nil
GameBetaAdmin.targetActionHooksRegistered = false

function GameBetaAdmin:onInit()
    self:registerExtendedOpcode(OPCODE, function(_, _, buffer)
        self:onExtendedOpcode(buffer)
    end)

    local levelFilter = self.ui:recursiveGetChildById("levelFilter")
    levelFilter:addOption("Todos os niveis", 0)
    for accountType = 1, 6 do
        levelFilter:addOption(ROLE_NAMES[accountType], accountType)
    end
    levelFilter:setCurrentOptionByData(0)

    local mode = self.ui:recursiveGetChildById("monsterMode")
    mode:addOption("Criatura comum", "spawn")
    mode:addOption("Summon do operador", "summon")
    mode:setCurrentOptionByData("spawn")
    self.ui:recursiveGetChildById("accountTypeSelection").onOptionChange = function()
        self:updateUserActionButtons()
    end
    self.ui:recursiveGetChildById("groupSelection").onOptionChange = function()
        self:updateUserActionButtons()
    end
    local feedbackHost = self.ui:recursiveGetChildById("feedbackHost")
    local feedbackPage = g_ui.loadUI("/modules/game_beta_admin/game_beta_admin_feedback.otui", feedbackHost)
    BetaAdminFeedback:init(self, feedbackPage)
    local operationsHost = self.ui:recursiveGetChildById("operationsHost")
    local operationsPage = g_ui.loadUI("/modules/game_beta_admin/game_beta_admin_operations.otui", operationsHost)
    BetaAdminOperations:init(self, operationsPage)
    modules.game_interface.registerElementalWindow(ELEMENTAL_WINDOW_ID,
        tr("Administracao do beta"), self.ui, {
            directWindow = true,
            minimumWidth = 920,
            minimumHeight = 600
        })
    self:updateVisibility()
    self:registerTargetActionHooks()
    self:prepareLocalTestScreen()
end

function GameBetaAdmin:prepareLocalTestScreen()
    local screen = os.getenv("ELEMENTAL_LOCAL_TEST_SCREEN")
    if screen ~= "beta-admin" and screen ~= "beta-items" and screen ~= "beta-monsters"
        and screen ~= "beta-catalog-status"
        and screen ~= "beta-users" and screen ~= "beta-users-tutors" and screen ~= "beta-users-staff"
        and screen ~= "beta-users-moderator"
        and screen ~= "beta-feedback" and screen ~= "beta-operations-cm"
        and screen ~= "beta-operations-requester" and screen ~= "beta-operations-god" then
        return
    end

    self.localTestMode = true
    local isOperationsCM = screen == "beta-operations-cm"
    local isOperationsRequester = screen == "beta-operations-requester"
    local isOperationsGod = screen == "beta-operations-god"
    local isReadOnlyModerator = screen == "beta-users-moderator"
    local managementScope = screen == "beta-users-tutors" and "tutors"
        or screen == "beta-users-staff" and "staff" or "god"
    if isOperationsCM or isOperationsRequester or isReadOnlyModerator then
        managementScope = nil
    end
    local accountType = managementScope == "tutors" and 3 or managementScope == "staff" and 5 or 6
    if isReadOnlyModerator then
        accountType = 4
    elseif isOperationsCM then
        accountType = 5
    elseif isOperationsRequester then
        accountType = 1
    end
    local managerCapability = managementScope == "tutors" and CAPABILITY_MANAGE_TUTORS
        or managementScope == "staff" and CAPABILITY_MANAGE_STAFF or nil
    self.snapshot = {
        accountType = accountType,
        groupType = managementScope == "tutors" and 3 or managementScope == "staff" and 1
            or isReadOnlyModerator and 4 or (isOperationsCM or isOperationsRequester) and 1 or 6,
        canManageUsers = managementScope ~= nil,
        canSearchOnlinePlayers = managementScope ~= nil or isReadOnlyModerator,
        managementScope = managementScope or "none",
        capabilityStoreAvailable = true,
        canCompensate = isOperationsCM,
        canRequestElevation = isOperationsRequester,
        canApproveElevation = isOperationsGod,
        compensationMaxGold = 10000,
        compensationDailyMaxGold = 50000,
        elevationMaxMinutes = 30,
        capabilities = managerCapability and { managerCapability } or { CAPABILITY_ITEMS, CAPABILITY_MONSTERS },
        capabilityOptions = managerCapability and {} or {
            "beta.feedback.triage",
            CAPABILITY_MANAGE_STAFF,
            CAPABILITY_MANAGE_TUTORS,
            CAPABILITY_ITEMS,
            CAPABILITY_MONSTERS,
            CAPABILITY_COMPENSATE,
            CAPABILITY_ELEVATION_REQUEST,
        },
        accountTypeOptions = managementScope == "tutors" and {
            { id = 1, name = "normal" },
            { id = 2, name = "tutor" },
        } or managementScope == "staff" and {
            { id = 1, name = "normal" },
            { id = 2, name = "tutor" },
            { id = 3, name = "senior tutor" },
            { id = 4, name = "gamemaster" },
        } or {
            { id = 1, name = "normal" },
            { id = 2, name = "tutor" },
            { id = 3, name = "senior tutor" },
            { id = 4, name = "gamemaster" },
            { id = 5, name = "community manager" },
        },
        groupOptions = managementScope == "tutors" and {
            { id = 1, name = "player" },
            { id = 2, name = "tutor" },
        } or {
            { id = 1, name = "player" },
            { id = 2, name = "tutor" },
            { id = 3, name = "senior tutor" },
        },
        talkActions = {
            { words = "!balance", description = "Consulta o saldo bancario proprio.", groupType = 1 },
            { words = "!position", description = "Exibe a posicao atual do colaborador.", groupType = 3 },
            { words = "/kick", description = "Expulsa um jogador online elegivel.", groupType = 3 },
            { words = "/ban", description = "Aplica banimento ao personagem.", groupType = 4 },
            { words = "/t", description = "Envia um jogador online ao templo.", groupType = 4 },
            { words = "/i", description = "Cria um item no inventario do operador.", groupType = 6 },
            { words = "/m", description = "Cria monstros proximos ao operador.", groupType = 6 },
            { words = "/setkv", description = "Altera um valor KV.", groupType = 6 },
            { words = "!livestream", description = "Gerencia controles de transmissao.", groupType = 1 },
        },
    }
    local deferredTalkAction = os.getenv("ELEMENTAL_LOCAL_TEST_TALK_ACTION")
    local localTestTalkActions = {
        ["/active"] = {
            words = "/active",
            description = "Teleporte aleatorio adiado no beta fechado.",
            groupType = 4,
        },
        ["/createtestshop"] = {
            words = "/createtestshop",
            description = "Ferramenta de desenvolvimento fora do beta fechado.",
            groupType = 6,
        },
        ["/testtaintconditions"] = {
            words = "/testtaintconditions",
            description = "Ferramenta de desenvolvimento fora do beta fechado.",
            groupType = 6,
        },
        ["/ambientsound"] = {
            words = "/ambientsound",
            description = "Efeito de audio adiado para aperfeicoamento posterior.",
            groupType = 4,
        },
        ["/musicsound"] = {
            words = "/musicsound",
            description = "Efeito de audio adiado para aperfeicoamento posterior.",
            groupType = 4,
        },
        ["/setlight"] = {
            words = "/setlight",
            description = "Efeito visual sem resultado confirmado no cliente beta.",
            groupType = 4,
        },
        ["/gotohouse"] = {
            words = "/gotohouse",
            description = "Teletransportar o operador para a casa do jogador selecionado ou para a propria casa.",
            groupType = 6,
        },
        ["/setflag"] = {
            words = "/setflag",
            description = "Permissao de grupo compartilhado adiada para revisao.",
            groupType = 6,
        },
        ["/removeflag"] = {
            words = "/removeflag",
            description = "Permissao de grupo compartilhado adiada para revisao.",
            groupType = 6,
        },
    }
    if localTestTalkActions[deferredTalkAction] then
        table.insert(self.snapshot.talkActions, localTestTalkActions[deferredTalkAction])
    end
    self.capabilities = {
        [managerCapability or CAPABILITY_ITEMS] = true,
    }
    if not managerCapability then
        self.capabilities[CAPABILITY_MONSTERS] = true
    end
    if isReadOnlyModerator then
        self.snapshot.capabilities = {}
        self.capabilities = {}
    end
    if isOperationsCM then
        self.snapshot.capabilities = { CAPABILITY_COMPENSATE }
        self.capabilities = { [CAPABILITY_COMPENSATE] = true }
    elseif isOperationsRequester then
        self.snapshot.capabilities = { CAPABILITY_ELEVATION_REQUEST }
        self.capabilities = { [CAPABILITY_ELEVATION_REQUEST] = true }
    elseif isOperationsGod then
        self.snapshot.canApproveElevation = true
    end
    if screen == "beta-feedback" then
        self.snapshot.capabilities[#self.snapshot.capabilities + 1] = CAPABILITY_FEEDBACK
        self.capabilities[CAPABILITY_FEEDBACK] = true
    end
    self.assignableCapabilities = {}
    for _, capability in ipairs(self.snapshot.capabilityOptions) do
        if CAPABILITY_LABELS[capability] then
            self.assignableCapabilities[#self.assignableCapabilities + 1] = capability
        end
    end
    BetaAdminOperations:setSnapshot(self.snapshot)
    BetaAdminOperations:prepareLocalTestScreen(screen)
    self.actions = {}
    for _, action in ipairs(self.snapshot.talkActions) do
        action.schema = self:findSchema(action.words)
        self.actions[#self.actions + 1] = action
    end
    local selfTestPassed, selfTestMessage = self:selfTest()
    g_logger.info(string.format("Beta admin local self-test %s%s", selfTestPassed and "passed" or "failed",
        selfTestPassed and "" or ": " .. selfTestMessage))

    if screen == "beta-items" or screen == "beta-catalog-status" then
        self.activePage = "items"
    elseif screen == "beta-monsters" then
        self.activePage = "monsters"
    elseif screen == "beta-users" or screen == "beta-users-tutors" or screen == "beta-users-staff"
        or screen == "beta-users-moderator" then
        self.activePage = "users"
    elseif screen == "beta-feedback" then
        self.activePage = "feedback"
    elseif isOperationsCM or isOperationsRequester or isOperationsGod then
        self.activePage = "operations"
    end
    self.status = selfTestPassed and "QA local isolado: schemas validos; nenhuma solicitacao sera enviada."
        or ("Falha no self-test: " .. selfTestMessage)
    self:updateUI()
    if screen == "beta-feedback" then
        BetaAdminFeedback:prepareLocalTestScreen()
    end
    if screen == "beta-admin" then
        local selectedTalkAction = os.getenv("ELEMENTAL_LOCAL_TEST_TALK_ACTION") or "/ban"
        for _, action in ipairs(self.actions) do
            if getFirstWord(action.words) == selectedTalkAction then
                self:selectAction(action)
                break
            end
        end
    end
    self.ui:show()
    self.ui:raise()
    self.ui:focus()

    if screen == "beta-items" then
        local items = {
            { id = 3264, name = "sword", stackable = false },
            { id = 3271, name = "Spike Sword", stackable = false },
        }
        self:renderSearchResults("items", items, false)
        self.selectedItem = items[1]
        setWidgetText(self.ui:recursiveGetChildById("selectedItemLabel"), "sword (ID 3264)")
        self.ui:recursiveGetChildById("itemRecipient"):setText("Beta Tester")
        self.ui:recursiveGetChildById("itemCount"):setText("3")
        self:updateItemPreview()
    elseif screen == "beta-monsters" then
        local monsters = {
            { name = "Demon", lookType = 35 },
        }
        self:renderSearchResults("monsters", monsters, false)
        self.selectedMonster = monsters[1]
        setWidgetText(self.ui:recursiveGetChildById("selectedMonsterLabel"),
            string.format("%s (%s)", monsters[1].name, getMonsterLookTypeLabel(monsters[1])))
        self.ui:recursiveGetChildById("monsterCount"):setText("2")
        self:updateMonsterPreview()
    elseif screen == "beta-catalog-status" then
        local items = {
            { id = 3264, name = "sword", stackable = false },
            { id = 3271, name = "Spike Sword", stackable = false },
        }
        local monsters = {
            { name = "Demon", lookType = 35 },
        }
        self:renderSearchResults("items", items, false)
        self:renderSearchResults("monsters", monsters, false)
        self:showPage("items")
        local itemStatus = self.status
        self:showPage("monsters")
        local monsterStatus = self.status
        self:showPage("items")
        if itemStatus == "2 resultado(s)." and monsterStatus == "1 resultado(s)." and self.status == itemStatus then
            g_logger.info("Beta admin catalog status switch self-test passed")
        else
            g_logger.error(string.format("Beta admin catalog status switch self-test failed: items=%s monsters=%s final=%s",
                itemStatus, monsterStatus, self.status))
        end
    elseif screen == "beta-users" then
        self.ui:recursiveGetChildById("userSearch"):setText("beta")
        self:showPage("users")
        if self.userQuery == "" and #self.userResults == 2 then
            g_logger.info("Beta admin empty-query online list self-test passed")
        else
            g_logger.error(string.format("Beta admin empty-query online list self-test failed: query=%s count=%d",
                self.userQuery, #self.userResults))
        end
        self:selectUser(self.userResults[1])
        self.ui:recursiveGetChildById("accountTypeSelection"):setCurrentOptionByData(2)
        self.ui:recursiveGetChildById("groupSelection"):setCurrentOptionByData(2)
        self:updateUserActionButtons()
    elseif screen == "beta-users-tutors" then
        self.userQuery = "tutor"
        self.ui:recursiveGetChildById("userSearch"):setText("tutor")
        self:renderUserResults({
            { name = "Beta Tutor", accountType = 2, groupType = 2, manageable = true, capabilitiesAvailable = false, capabilities = {} },
            { name = "Beta Player", accountType = 1, groupType = 1, manageable = true, capabilitiesAvailable = false, capabilities = {} },
        }, false, false)
        self:selectUser(self.userResults[1])
        self.ui:recursiveGetChildById("accountTypeSelection"):setCurrentOptionByData(1)
        self.ui:recursiveGetChildById("groupSelection"):setCurrentOptionByData(1)
        self:updateUserActionButtons()
    elseif screen == "beta-users-staff" then
        self.userQuery = "staff"
        self.ui:recursiveGetChildById("userSearch"):setText("staff")
        self:renderUserResults({
            { name = "Beta Moderator", accountType = 4, groupType = 1, manageable = true, capabilitiesAvailable = false, capabilities = {} },
            { name = "Beta Senior Tutor", accountType = 3, groupType = 3, manageable = true, capabilitiesAvailable = false, capabilities = {} },
        }, false, false)
        self:selectUser(self.userResults[1])
        self.ui:recursiveGetChildById("accountTypeSelection"):setCurrentOptionByData(3)
        self.ui:recursiveGetChildById("groupSelection"):setCurrentOptionByData(3)
        self:updateUserActionButtons()
    elseif screen == "beta-users-moderator" then
        self.userQuery = "T543"
        self.ui:recursiveGetChildById("userSearch"):setText(self.userQuery)
        self:renderUserResults({
            {
                name = "T543 Synthetic Player",
                accountType = 1,
                groupType = 1,
                manageable = false,
                capabilitiesAvailable = false,
                capabilities = {},
                quickActions = { ["/kick"] = true, ["/ban"] = true, ["/t"] = true },
            },
        }, false, false)
        self:selectUser(self.userResults[1])
    end
    local function captureLocalTestScreen(remainingHideAttempts)
        local loginModule = modules.client_entergame
        local loginController = loginModule and loginModule.EnterGame or EnterGame
        if loginController and loginController.hide then
            loginController.hide()
        end
        local loginWindow = g_ui.getRootWidget():recursiveGetChildById("enterGame")
        if loginWindow and not loginWindow:isDestroyed() then
            loginWindow:hide()
            loginWindow:setOpacity(0)
        end
        if not self.ui or self.ui:isDestroyed() then
            return
        end
        if remainingHideAttempts > 0 then
            self:scheduleEvent(function()
                captureLocalTestScreen(remainingHideAttempts - 1)
            end, 250)
            return
        end
        self.ui:show()
        self.ui:raise()
        self.ui:focus()
        g_logger.info(string.format("Beta admin local test login overlay hidden: %s",
            not loginWindow or loginWindow:isDestroyed() or not loginWindow:isVisible()))
        self:scheduleEvent(function()
            if self.ui and not self.ui:isDestroyed() then
                g_app.doScreenshot(screen .. "-current.png")
            end
        end, 1000)
    end
    self:scheduleEvent(function()
        captureLocalTestScreen(8)
    end, 3500)
end

function GameBetaAdmin:onGameStart()
    self:clearTargetActionContext(true)
    self:cancelItemRecipientSearch()
    BetaAdminFeedback:onGameEnd()
    BetaAdminOperations:onGameEnd()
    self.nextRequestId = 0
    self.pendingRequests = {}
    self.snapshot = nil
    self.actions = {}
    self.capabilities = {}
    self.selectedAction = nil
    self.selectedItem = nil
    self.selectedMonster = nil
    self.selectedUser = nil
    self.selectedItemRecipient = nil
    self.userResults = {}
    self.assignableCapabilities = {}
    self.userQuery = ""
    self.userHasMore = false
    self.latestUserSearchRequestId = nil
    self.latestItemRecipientRequestId = nil
    self.status = "Solicitando permissoes ao servidor..."
    self:updateUI()
    self:updateAdminButton()
    self:requestSnapshot()
end

function GameBetaAdmin:onGameEnd()
    self:clearTargetActionContext(true)
    self:cancelSearch()
    self:cancelItemRecipientSearch()
    BetaAdminFeedback:onGameEnd()
    BetaAdminOperations:onGameEnd()
    self.pendingRequests = {}
    self.snapshot = nil
    self.actions = {}
    self.filteredActions = {}
    self.capabilities = {}
    self.selectedAction = nil
    self.selectedSchema = nil
    self.selectedItem = nil
    self.selectedMonster = nil
    self.selectedUser = nil
    self.selectedItemRecipient = nil
    self.userResults = {}
    self.assignableCapabilities = {}
    self.userQuery = ""
    self.userHasMore = false
    self.userReselectName = nil
    self.fieldWidgets = {}
    self.latestItemSearchRequestId = nil
    self.latestMonsterSearchRequestId = nil
    self.latestUserSearchRequestId = nil
    self.latestItemRecipientRequestId = nil
    self.activePage = "commands"
    self.status = "Desconectado."
    self.isResettingSession = true
    if self.ui then
        self.ui:recursiveGetChildById("actionSearch"):setText("")
        self.ui:recursiveGetChildById("itemSearch"):setText("")
        self.ui:recursiveGetChildById("monsterSearch"):setText("")
        self.ui:recursiveGetChildById("userSearch"):setText("")
        self.ui:recursiveGetChildById("itemRecipient"):setText("")
        self.ui:recursiveGetChildById("itemCount"):setText("1")
        self.ui:recursiveGetChildById("monsterCount"):setText("1")
        self.ui:recursiveGetChildById("itemResults"):destroyChildren()
        self.ui:recursiveGetChildById("monsterResults"):destroyChildren()
        self.ui:recursiveGetChildById("userResults"):destroyChildren()
        self.ui:recursiveGetChildById("itemRecipientResults"):destroyChildren()
        self.ui:recursiveGetChildById("userCapabilities"):destroyChildren()
        self.ui:recursiveGetChildById("fieldsList"):destroyChildren()
        setWidgetText(self.ui:recursiveGetChildById("selectedItemLabel"), "Selecione um item da busca.")
        setWidgetText(self.ui:recursiveGetChildById("selectedMonsterLabel"), "Selecione um monstro da busca.")
        setWidgetText(self.ui:recursiveGetChildById("itemPreview"), "")
        setWidgetText(self.ui:recursiveGetChildById("monsterPreview"), "")
        self.ui:recursiveGetChildById("giveItemButton"):setEnabled(false)
        self.ui:recursiveGetChildById("itemRecipientResults"):hide()
        self.ui:recursiveGetChildById("itemRecipientResultsScrollBar"):hide()
        self.ui:recursiveGetChildById("spawnMonsterButton"):setEnabled(false)
        self.ui:recursiveGetChildById("userLoadMoreButton"):setEnabled(false)
        self.ui:recursiveGetChildById("applyAccountTypeButton"):setEnabled(false)
        self.ui:recursiveGetChildById("applyGroupButton"):setEnabled(false)
        self.ui:recursiveGetChildById("accountTypeSelection"):clearOptions()
        self.ui:recursiveGetChildById("groupSelection"):clearOptions()
        setWidgetText(self.ui:recursiveGetChildById("selectedUserName"), "Selecione um jogador online.")
        setWidgetText(self.ui:recursiveGetChildById("currentUserAccess"), "")
        setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"), "")
    end
    self.isResettingSession = false
    self:hide()
    self:updateUI()
    self:updateAdminButton()
end

function GameBetaAdmin:onTerminate()
    self:unregisterTargetActionHooks()
    self:clearTargetActionContext(true)
    self:cancelSearch()
    self:cancelItemRecipientSearch()
    BetaAdminFeedback:terminate()
    BetaAdminOperations:terminate()
    if modules.game_interface and modules.game_interface.unregisterElementalWindow and self.ui then
        modules.game_interface.unregisterElementalWindow(ELEMENTAL_WINDOW_ID, self.ui)
    end
    if self.button and not self.button:isDestroyed() then
        self.button:destroy()
    end
    self.button = nil
    if self.elementalButton and not self.elementalButton:isDestroyed() then
        self.elementalButton:destroy()
    end
    self.elementalButton = nil
end

function GameBetaAdmin:clearUserManagementState()
    self.selectedUser = nil
    self.userResults = {}
    self.assignableCapabilities = {}
    self.userQuery = ""
    self.userHasMore = false
    self.userReselectName = nil
    self.latestUserSearchRequestId = nil
    if not self.ui then
        return
    end

    self.isResettingSession = true
    self.ui:recursiveGetChildById("userSearch"):setText("")
    self.ui:recursiveGetChildById("userResults"):destroyChildren()
    self.ui:recursiveGetChildById("userCapabilities"):destroyChildren()
    self.ui:recursiveGetChildById("userLoadMoreButton"):setEnabled(false)
    self:updateQuickTargetActionButtons(nil)
    self.ui:recursiveGetChildById("applyAccountTypeButton"):setEnabled(false)
    self.ui:recursiveGetChildById("applyGroupButton"):setEnabled(false)
    self.ui:recursiveGetChildById("accountTypeSelection"):clearOptions()
    self.ui:recursiveGetChildById("groupSelection"):clearOptions()
    setWidgetText(self.ui:recursiveGetChildById("selectedUserName"), "Selecione um jogador online.")
    setWidgetText(self.ui:recursiveGetChildById("currentUserAccess"), "")
    setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"), "")
    self.isResettingSession = false
end

function GameBetaAdmin:updateAdminButton()
    if not self:hasAdminAccess() then
        if self.button and not self.button:isDestroyed() then
            self.button:destroy()
        end
        self.button = nil
        if self.elementalButton and not self.elementalButton:isDestroyed() then
            self.elementalButton:destroy()
        end
        self.elementalButton = nil
        return
    end

    if not self.button or self.button:isDestroyed() then
        self.button = modules.game_mainpanel.addToggleButton(
            "elementalBetaAdminButton",
            tr("Administracao do beta"),
            "/images/options/button_control",
            function()
                self:toggle()
            end,
            false,
            27
        )
    end

    if not self.elementalButton or self.elementalButton:isDestroyed() then
        local layer = modules.game_interface.getElementalWindowLayer()
        if not layer or layer:isDestroyed() then
            return
        end
        self.elementalButton = g_ui.createWidget("Button", layer)
        self.elementalButton:setId("elementalBetaAdminAccess")
        self.elementalButton:setText(tr("Admin"))
        self.elementalButton:setTooltip(tr("Administracao do beta"))
        self.elementalButton:setSize("96 30")
        self.elementalButton:breakAnchors()
        self.elementalButton:addAnchor(AnchorBottom, "parent", AnchorBottom)
        self.elementalButton:addAnchor(AnchorRight, "parent", AnchorRight)
        self.elementalButton:setMarginBottom(16)
        self.elementalButton:setMarginRight(16)
        self.elementalButton:setBackgroundColor("#171A20DD")
        self.elementalButton:setBorderWidth(1)
        self.elementalButton:setBorderColor("#FFB829")
        self.elementalButton:setPhantom(false)
        self.elementalButton.onClick = function()
            self:toggle()
        end
        self.elementalButton:show()
        self.elementalButton:raise()
    end
end

function GameBetaAdmin:cancelSearch()
    if self.searchEvent then
        removeEvent(self.searchEvent)
        self.searchEvent = nil
    end
end

function GameBetaAdmin:cancelItemRecipientSearch()
    if self.itemRecipientSearchEvent then
        removeEvent(self.itemRecipientSearchEvent)
        self.itemRecipientSearchEvent = nil
    end
end

function GameBetaAdmin:nextRequest()
    self.nextRequestId = self.nextRequestId + 1
    if self.nextRequestId > MAX_REQUEST_ID then
        self.nextRequestId = 1
    end
    return self.nextRequestId
end

function GameBetaAdmin:sendRequest(action, fields, context)
    if self.localTestMode then
        self:setStatus("QA local isolado: nenhuma solicitacao foi enviada.")
        return nil
    end
    if not g_game.isOnline() then
        self:setStatus("Conecte-se ao servidor para usar o painel.")
        return nil
    end
    local protocol = g_game.getProtocolGame()
    if not protocol then
        self:setStatus("O protocolo do jogo nao esta disponivel.")
        return nil
    end

    local requestId = self:nextRequest()
    local request = {
        contractVersion = CONTRACT_VERSION,
        requestId = requestId,
        action = action,
    }
    for key, value in pairs(fields or {}) do
        request[key] = value
    end
    self.pendingRequests[requestId] = { action = action, context = context }
    protocol:sendExtendedOpcode(OPCODE, json.encode(request))
    return requestId
end

function GameBetaAdmin:requestSnapshot()
    if not g_game.isOnline() then
        self:setStatus("Conecte-se ao servidor para atualizar as permissoes.")
        return
    end
    self.status = "Atualizando catalogo e permissoes..."
    self:updateUI()
    self:sendRequest("snapshot")
    if self.activePage == "users" then
        self.userReselectName = self.selectedUser and self.selectedUser.name or nil
        self:requestOnlinePlayers(self.userQuery, 0, false)
    end
end

function GameBetaAdmin:onExtendedOpcode(buffer)
    local ok, response = pcall(json.decode, buffer)
    if not ok or type(response) ~= "table" or response.contractVersion ~= CONTRACT_VERSION then
        self:setStatus("Resposta invalida do servidor. Atualize o painel.")
        return
    end

    local pending = self.pendingRequests[response.requestId]
    if not pending or (pending.action ~= response.action and response.type ~= "snapshot") then
        return
    end
    self.pendingRequests[response.requestId] = nil

    if response.type == "snapshot" then
        self:onSnapshot(response)
    elseif response.type == "itemSearch" then
        self:onItemSearchResponse(response)
    elseif response.type == "monsterSearch" then
        self:onMonsterSearchResponse(response)
    elseif response.type == "onlinePlayers" then
        self:onOnlinePlayersResponse(response, pending.context)
    elseif response.type == "elevationRequests" then
        BetaAdminOperations:onElevationResponse(response)
    elseif response.type == "result" then
        if pending.context == "item-recipient" and response.success ~= true then
            self.latestItemRecipientRequestId = nil
            self:setStatus("Canary nao conseguiu buscar destinatarios online para este cargo.")
        else
            self:onOperationResult(response)
        end
    else
        self:setStatus("O servidor retornou uma resposta nao reconhecida.")
    end
end

function GameBetaAdmin:onSnapshot(snapshot)
    if self.targetActionContext then
        self:clearTargetActionContext(true)
    end
    self:cancelItemRecipientSearch()
    self.latestItemRecipientRequestId = nil
    self.selectedItemRecipient = nil
    if self.ui then
        self.isResettingSession = true
        self.ui:recursiveGetChildById("itemRecipient"):setText("")
        self.ui:recursiveGetChildById("itemRecipientResults"):destroyChildren()
        self.ui:recursiveGetChildById("itemRecipientResults"):hide()
        self.ui:recursiveGetChildById("itemRecipientResultsScrollBar"):hide()
        self.isResettingSession = false
    end
    if type(snapshot.accountType) ~= "number" or type(snapshot.groupType) ~= "number"
        or type(snapshot.talkActions) ~= "table" or type(snapshot.capabilities) ~= "table" then
        self.snapshot = nil
        self.actions = {}
        self.capabilities = {}
        self:clearUserManagementState()
        self.status = "O snapshot de permissoes esta incompleto."
        self:updateUI()
        return
    end
    if type(snapshot.canSearchOnlinePlayers) ~= "boolean" then
        snapshot.canSearchOnlinePlayers = snapshot.canManageUsers == true
    end
    if snapshot.managementScope == nil and snapshot.canManageUsers == true and snapshot.accountType == 6 then
        snapshot.managementScope = "god"
    end
    if snapshot.canManageUsers == true and (type(snapshot.accountTypeOptions) ~= "table"
        or type(snapshot.groupOptions) ~= "table" or type(snapshot.capabilityOptions) ~= "table"
        or not MANAGEMENT_SCOPE_LABELS[snapshot.managementScope]) then
        self.snapshot = nil
        self.actions = {}
        self.capabilities = {}
        self:clearUserManagementState()
        self.status = "O snapshot de gestao de usuarios esta incompleto. Atualize Canary."
        self:updateUI()
        self:updateAdminButton()
        return
    end
    if not hasValidManagementOptions(snapshot) then
        self.snapshot = nil
        self.actions = {}
        self.capabilities = {}
        self:clearUserManagementState()
        self.status = "O Canary retornou opcoes de gestao fora do escopo do cargo. Atualize Canary."
        self:updateUI()
        self:updateAdminButton()
        return
    end

    self.snapshot = snapshot
    self.capabilities = {}
    for _, capability in ipairs(snapshot.capabilities) do
        if type(capability) == "string" then
            self.capabilities[capability] = true
        end
    end
    BetaAdminFeedback:setAuthorized(hasCapability(self.capabilities, CAPABILITY_FEEDBACK))
    BetaAdminOperations:setSnapshot(snapshot)
    self.assignableCapabilities = {}
    for _, capability in ipairs(snapshot.capabilityOptions or {}) do
        if CAPABILITY_LABELS[capability] then
            self.assignableCapabilities[#self.assignableCapabilities + 1] = capability
        end
    end
    if snapshot.canManageUsers ~= true then
        self:clearUserManagementState()
    end
    self.actions = {}
    for _, action in ipairs(snapshot.talkActions) do
        if type(action) == "table" and type(action.words) == "string" and type(action.groupType) == "number"
            and action.groupType <= snapshot.accountType then
            action.schema = self:findSchema(action.words)
            self.actions[#self.actions + 1] = action
        end
    end
    self.selectedAction = nil
    self.selectedSchema = nil
    self.selectedItem = nil
    self.selectedMonster = nil
    self.status = string.format("Permissoes atualizadas. %d TalkActions liberadas.", #self.actions)
    local selfTestPassed, selfTestMessage = self:selfTest()
    if not selfTestPassed then
        self.status = "Falha na verificacao local de schemas: " .. selfTestMessage
    end
    self:updateUI()
    self:updateAdminButton()
end

function GameBetaAdmin:findSchema(words)
    for _, word in ipairs(splitWords(words)) do
        if self.schemas[word] then
            return self.schemas[word], word
        end
    end
    return nil, getFirstWord(words)
end

function GameBetaAdmin:hasAdminAccess()
    if not self.snapshot then
        return false
    end
    return self.snapshot.accountType > 1 or next(self.capabilities) ~= nil
        or self.snapshot.canCompensate == true or self.snapshot.canRequestElevation == true
        or self.snapshot.canApproveElevation == true
end

function GameBetaAdmin:hasTalkActionAccess()
    return self.snapshot ~= nil and self.snapshot.accountType > 1 and #self.actions > 0
end

function GameBetaAdmin:selfTest()
    local errors = {}
    for word, schema in pairs(self.schemas or {}) do
        if type(schema) ~= "table" or type(schema.fields) ~= "table" then
            errors[#errors + 1] = word .. ": schema ausente"
        else
            for _, field in ipairs(schema.fields) do
                if type(field.id) ~= "string" or type(field.label) ~= "string"
                    or (field.kind ~= "text" and field.kind ~= "amount" and field.kind ~= "number" and field.kind ~= "choice") then
                    errors[#errors + 1] = word .. ": campo invalido"
                    break
                end
                if field.kind == "number" and (type(field.minimum) ~= "number" or type(field.maximum) ~= "number"
                    or field.minimum > field.maximum) then
                    errors[#errors + 1] = word .. ": faixa numerica invalida"
                    break
                end
                if field.kind == "choice" and (type(field.options) ~= "table" or #field.options == 0) then
                    errors[#errors + 1] = word .. ": opcoes ausentes"
                    break
                end
            end
        end
    end
    for _, action in ipairs(self.actions or {}) do
        if not action.schema then
            errors[#errors + 1] = getFirstWord(action.words) .. ": sem schema (envio bloqueado)"
        end
    end

    for _, scope in ipairs({ "tutors", "staff", "god" }) do
        local limits = MANAGEMENT_OPTION_LIMITS[scope]
        local validSnapshot = {
            managementScope = scope,
            canManageUsers = true,
            accountTypeOptions = { { id = limits.accountType } },
            groupOptions = { { id = limits.group } },
            capabilityOptions = {},
        }
        if not hasValidManagementOptions(validSnapshot) then
            errors[#errors + 1] = scope .. ": opcoes de gestao validas foram recusadas"
        end
        validSnapshot.accountTypeOptions = { { id = limits.accountType + 1 } }
        if hasValidManagementOptions(validSnapshot) then
            errors[#errors + 1] = scope .. ": AccountType acima do escopo foi aceito"
        end
    end
    if not CAPABILITY_LABELS[CAPABILITY_MANAGE_TUTORS] or not CAPABILITY_LABELS[CAPABILITY_MANAGE_STAFF] then
        errors[#errors + 1] = "capability de gestao sem rotulo"
    end

    local savedAction, savedSchema, savedWidgets = self.selectedAction, self.selectedSchema, self.fieldWidgets
    local numberSchema = self.schemas["/looktype"]
    local numberField = numberSchema and numberSchema.fields[1]
    if numberField then
        self.selectedAction = { words = "/looktype" }
        self.selectedSchema = numberSchema
        self.fieldWidgets = {
            lookType = {
                field = numberField,
                widget = { getText = function() return "1468" end },
            },
        }
        if self:buildTalkActionCommand() ~= "/looktype 1468" then
            errors[#errors + 1] = "faixa numerica valida nao foi aceita"
        end
        self.fieldWidgets.lookType.widget.getText = function() return "1469" end
        if self:buildTalkActionCommand() ~= nil then
            errors[#errors + 1] = "valor numerico acima do limite foi aceito"
        end
    else
        errors[#errors + 1] = "formulario looktype ausente"
    end
    for _, word in ipairs({ "/kick", "/ban" }) do
        local schema = self.schemas[word]
        local target = schema and schema.fields[1]
        local reason = schema and schema.fields[#schema.fields]
        if not target or target.id ~= "target" or not reason or reason.id ~= "reason" or reason.required ~= true then
            errors[#errors + 1] = word .. ": formulario deve exigir motivo"
        else
            self.selectedAction = { words = word }
            self.selectedSchema = schema
            self.fieldWidgets = {
                target = { field = target, widget = { getText = function() return "Synthetic Target" end } },
                reason = { field = reason, widget = { getText = function() return "" end } },
            }
            if word == "/ban" then
                local days = schema.fields[2]
                self.fieldWidgets.days = { field = days, widget = { getText = function() return "1" end } }
            end
            if self:buildTalkActionCommand() ~= nil then
                errors[#errors + 1] = word .. ": motivo vazio gerou comando"
            end
            self.fieldWidgets.reason.widget.getText = function() return "Synthetic QA reason" end
            local expected = word == "/kick"
                and "/kick Synthetic Target, Synthetic QA reason"
                or "/ban Synthetic Target, 1, Synthetic QA reason"
            if self:buildTalkActionCommand() ~= expected then
                errors[#errors + 1] = word .. ": previa com motivo valido incorreta"
            end
        end
    end
    for _, hook in ipairs(TARGET_ACTION_MENU_HOOKS) do
        local schema = self.schemas[hook.words]
        local targetField = schema and schema.fields and schema.fields[1]
        local button = self.ui and self.ui:recursiveGetChildById(hook.buttonId)
        if type(hook.label) ~= "string" or hook.label == "" or type(hook.buttonLabel) ~= "string"
            or hook.buttonLabel == "" or not button or not targetField
            or targetField.id ~= "target" or schema.blockedReason or type(schema.confirm) ~= "string" then
            errors[#errors + 1] = hook.words .. ": atalho exige botao, alvo e confirmacao"
        end
    end

    local targetActionFixtures = {
        { words = "/kick", groupType = 3, schema = { fields = {}, confirm = "" } },
        { words = "/ban", groupType = 4, schema = { fields = {}, confirm = "" } },
        { words = "/t", groupType = 4, schema = { fields = {}, confirm = "" } },
    }
    local targetActionLevels = { ["/kick"] = 3, ["/ban"] = 4, ["/t"] = 4 }
    for accountType = 1, 6 do
        for words, minimumAccountType in pairs(targetActionLevels) do
            local expectedAction = accountType >= minimumAccountType
            local action = findExecutableTargetAction(targetActionFixtures, { accountType = accountType }, words)
            if (action ~= nil) ~= expectedAction then
                errors[#errors + 1] = string.format("%s: limite de AccountType incorreto para %d", words, accountType)
            end
        end
    end
    local blockedTargetAction = {
        { words = "/kick", groupType = 3, schema = { fields = {}, blockedReason = "bloqueada" } },
    }
    if findExecutableTargetAction(blockedTargetAction, { accountType = 6 }, "/kick") ~= nil then
        errors[#errors + 1] = "atalho com schema bloqueado foi aceito"
    end
    if findExecutableTargetAction({}, { accountType = 6 }, "/kick") ~= nil then
        errors[#errors + 1] = "atalho fora do snapshot foi aceito"
    end
    if not hasQuickTargetAction({ quickActions = { ["/kick"] = true } }, "/kick")
        or hasQuickTargetAction({ quickActions = { ["/kick"] = false } }, "/kick") then
        errors[#errors + 1] = "permissao de alvo do Canary foi ignorada"
    end

    local function makeTarget(id, name, isPlayer, isLocalPlayer, isRemoved)
        return {
            isPlayer = function() return isPlayer end,
            isLocalPlayer = function() return isLocalPlayer end,
            isRemoved = function() return isRemoved end,
            getId = function() return id end,
            getName = function() return name end,
        }
    end
    local mapTarget = makeTarget(42, "Synthetic Target", true, false, false)
    local liveTargets = { [42] = mapTarget }
    local function getSyntheticCreatureById(targetId)
        return liveTargets[targetId]
    end
    local resolvedTarget = resolveLivePlayerTarget(mapTarget, true, getSyntheticCreatureById)
    if not resolvedTarget or resolvedTarget.id ~= 42 or resolvedTarget.name ~= "Synthetic Target" then
        errors[#errors + 1] = "jogador online elegivel nao foi resolvido"
    end
    if resolveLivePlayerTarget(makeTarget(43, "Self", true, true, false), true, getSyntheticCreatureById) ~= nil then
        errors[#errors + 1] = "atalho para o jogador proprio foi aceito"
    end
    if resolveLivePlayerTarget(makeTarget(44, "Synthetic Monster", false, false, false), true, getSyntheticCreatureById) ~= nil then
        errors[#errors + 1] = "atalho para criatura nao jogador foi aceito"
    end
    if resolveLivePlayerTarget(mapTarget, false, getSyntheticCreatureById) ~= nil then
        errors[#errors + 1] = "atalho fora de sessao online foi aceito"
    end
    liveTargets[42] = makeTarget(42, "Renamed Target", true, false, false)
    if resolveLivePlayerTarget(mapTarget, true, getSyntheticCreatureById) ~= nil then
        errors[#errors + 1] = "identidade alterada do alvo foi aceita"
    end

    self.selectedAction = { words = "/not-in-snapshot" }
    self.selectedSchema = nil
    self.fieldWidgets = {}
    if self:buildTalkActionCommand() ~= nil then
        errors[#errors + 1] = "acao sem schema poderia ser enviada"
    end
    local blockedWords = {
        "!livestream", "!pos", "/active", "/addminorcharms", "/ambientsound", "/attr",
        "/b", "/changeflowmap", "/clean", "/clearhirelingstas", "/closeserver",
        "/countmonsters", "/createtestshop", "/ghost", "/inbox", "/ipban",
        "/mc", "/musicsound", "/n", "/openserver", "/pos", "/probeopcode",
        "/protocolprobe", "/r", "/reload", "/removeflag", "/removetaint", "/setflag",
        "/setkv", "/setlight", "/settaint", "/simraid", "/testlog", "/testtaintconditions",
        "/zones",
    }
    for _, word in ipairs(blockedWords) do
        local schema = self.schemas[word]
        self.selectedAction = { words = word }
        self.selectedSchema = schema
        self.fieldWidgets = {}
        if not schema or type(schema.blockedReason) ~= "string" or schema.blockedReason == "" then
            errors[#errors + 1] = word .. ": motivo de bloqueio ausente"
        elseif self:buildTalkActionCommand() ~= nil then
            errors[#errors + 1] = word .. ": acao bloqueada poderia ser enviada"
        end
    end
    local goToHouseSchema = self.schemas["/gotohouse"]
    if type(goToHouseSchema) ~= "table" or goToHouseSchema.blockedReason
        or goToHouseSchema.separator ~= " " or type(goToHouseSchema.fields) ~= "table"
        or #goToHouseSchema.fields ~= 1 or goToHouseSchema.fields[1].id ~= "target"
        or goToHouseSchema.fields[1].required
        or goToHouseSchema.confirm ~= "Teletransportar voce para a saida da sua casa ou da casa do personagem selecionado." then
        errors[#errors + 1] = "/gotohouse: schema de alvo opcional invalido"
    else
        self.selectedAction = { words = "/gotohouse" }
        self.selectedSchema = goToHouseSchema
        local targetField = goToHouseSchema.fields[1]
        for _, testCase in ipairs({
            { value = "", expected = "/gotohouse" },
            { value = "T542 Player Target", expected = "/gotohouse T542 Player Target" },
        }) do
            self.fieldWidgets = {
                target = {
                    field = targetField,
                    widget = { getText = function() return testCase.value end },
                },
            }
            if self:buildTalkActionCommand() ~= testCase.expected then
                errors[#errors + 1] = "/gotohouse: previa incorreta para alvo selecionado"
                break
            end
        end
    end
    local vipSchema = self.schemas["/vip"]
    local actionText = vipSchema and vipSchema.actionText
    if type(actionText) ~= "table" or type(actionText.values) ~= "table"
        or type(vipSchema.fields) ~= "table" or type(vipSchema.fields[1]) ~= "table"
        or vipSchema.fields[1].id ~= actionText.field then
        errors[#errors + 1] = "formulario VIP sem mensagens por operacao"
    else
        self.selectedSchema = vipSchema
        for _, option in ipairs(vipSchema.fields[1].options or {}) do
            local operation = tostring(option[1])
            local messages = actionText.values[operation]
            if type(messages) ~= "table" then
                errors[#errors + 1] = "/vip: mensagem ausente para " .. operation
            else
                self.fieldWidgets = {
                    operation = {
                        field = { kind = "choice" },
                        widget = { getCurrentOption = function() return { data = operation } end },
                    },
                }
                for _, messageType in ipairs({ "impact", "confirm" }) do
                    if type(messages[messageType]) ~= "string"
                        or self:getTalkActionMessage(messageType) ~= messages[messageType] then
                        errors[#errors + 1] = "/vip: mensagem incorreta para " .. operation
                        break
                    end
                end
            end
        end
    end
    self.selectedAction = savedAction
    self.selectedSchema = savedSchema
    self.fieldWidgets = savedWidgets
    local operationsPassed, operationsMessage = BetaAdminOperations:selfTest()
    if not operationsPassed then
        errors[#errors + 1] = "operacoes CM/elevacao: " .. operationsMessage
    end
    return #errors == 0, table.concat(errors, "; ")
end

function GameBetaAdmin:updateVisibility()
    if not self.ui then
        return
    end
    local hasItems = hasCapability(self.capabilities, CAPABILITY_ITEMS)
    local hasMonsters = hasCapability(self.capabilities, CAPABILITY_MONSTERS)
    local hasCommands = self:hasTalkActionAccess()
    local canManageUsers = self.snapshot ~= nil and self.snapshot.canManageUsers == true
    local hasUsers = self.snapshot ~= nil and self.snapshot.canSearchOnlinePlayers == true
    local hasFeedback = hasCapability(self.capabilities, CAPABILITY_FEEDBACK)
    local hasOperations = self.snapshot ~= nil and (self.snapshot.canCompensate == true
        or self.snapshot.canRequestElevation == true or self.snapshot.canApproveElevation == true)
    local userScopeText = self.snapshot and MANAGEMENT_SCOPE_LABELS[self.snapshot.managementScope] or ""
    if hasUsers and not canManageUsers then
        userScopeText = "Busca somente jogadores online elegiveis para moderacao."
    end
    setWidgetText(self.ui:recursiveGetChildById("userScopeInfo"), userScopeText)
    setWidgetText(self.ui:recursiveGetChildById("usersTab"), tr(canManageUsers and "Usuarios" or "Jogadores"))
    for _, widgetId in ipairs(USER_MANAGEMENT_WIDGET_IDS) do
        self.ui:recursiveGetChildById(widgetId):setVisible(canManageUsers)
    end
    local readOnlySearchInfo = self.ui:recursiveGetChildById("readOnlySearchInfo")
    setWidgetText(readOnlySearchInfo,
        "Acoes limitadas ao seu cargo. Alteracao de conta e grupo indisponivel.")
    readOnlySearchInfo:setVisible(hasUsers and not canManageUsers)
    BetaAdminFeedback:setAuthorized(hasFeedback)
    self.ui:recursiveGetChildById("commandsTab"):setVisible(hasCommands)
    self.ui:recursiveGetChildById("itemsTab"):setVisible(hasItems)
    self.ui:recursiveGetChildById("monstersTab"):setVisible(hasMonsters)
    self.ui:recursiveGetChildById("usersTab"):setVisible(hasUsers)
    self.ui:recursiveGetChildById("feedbackTab"):setVisible(hasFeedback)
    self.ui:recursiveGetChildById("operationsTab"):setVisible(hasOperations)
    if self.activePage == "items" and not hasItems then
        self.activePage = "commands"
    elseif self.activePage == "monsters" and not hasMonsters then
        self.activePage = "commands"
    elseif self.activePage == "users" and not hasUsers then
        self.activePage = "commands"
    elseif self.activePage == "feedback" and not hasFeedback then
        self.activePage = "commands"
    elseif self.activePage == "operations" and not hasOperations then
        self.activePage = "commands"
    end
    if self.activePage == "commands" and not hasCommands then
        self.activePage = hasItems and "items" or hasMonsters and "monsters" or hasUsers and "users"
            or hasFeedback and "feedback" or hasOperations and "operations" or "commands"
    end
    self.ui:recursiveGetChildById("commandsPage"):setVisible(self.activePage == "commands" and hasCommands)
    self.ui:recursiveGetChildById("itemsPage"):setVisible(self.activePage == "items" and hasItems)
    self.ui:recursiveGetChildById("monstersPage"):setVisible(self.activePage == "monsters" and hasMonsters)
    self.ui:recursiveGetChildById("usersPage"):setVisible(self.activePage == "users" and hasUsers)
    self.ui:recursiveGetChildById("feedbackHost"):setVisible(self.activePage == "feedback" and hasFeedback)
    self.ui:recursiveGetChildById("operationsHost"):setVisible(self.activePage == "operations" and hasOperations)
    if BetaAdminFeedback.ui and not BetaAdminFeedback.ui:isDestroyed() then
        BetaAdminFeedback.ui:setVisible(self.activePage == "feedback" and hasFeedback)
    end
    if BetaAdminOperations.ui and not BetaAdminOperations.ui:isDestroyed() then
        BetaAdminOperations.ui:setVisible(self.activePage == "operations" and hasOperations)
    end
end

function GameBetaAdmin:showPage(page)
    if page == "items" and not hasCapability(self.capabilities, CAPABILITY_ITEMS) then
        return
    end
    if page == "monsters" and not hasCapability(self.capabilities, CAPABILITY_MONSTERS) then
        return
    end
    if page == "commands" and not self:hasTalkActionAccess() then
        return
    end
    if page == "users" and (not self.snapshot or self.snapshot.canSearchOnlinePlayers ~= true) then
        return
    end
    if page == "feedback" and not hasCapability(self.capabilities, CAPABILITY_FEEDBACK) then
        return
    end
    if page == "operations" and (not self.snapshot or not (self.snapshot.canCompensate == true
        or self.snapshot.canRequestElevation == true or self.snapshot.canApproveElevation == true)) then
        return
    end
    self.activePage = page
    self:updateVisibility()
    if page == "items" or page == "monsters" then
        self:setStatus(self.catalogStatus[page])
    elseif page == "users" then
        local userSearch = self.ui:recursiveGetChildById("userSearch")
        if userSearch:getText() ~= "" then
            self.settingUserSearch = true
            userSearch:setText("")
            self.settingUserSearch = false
        end
        self:onUserSearchChange("")
    end
    if page == "feedback" then
        BetaAdminFeedback:loadFeedback(false)
    elseif page == "operations" then
        BetaAdminOperations:refreshElevations()
    end
end

function GameBetaAdmin:toggle()
    if not self.ui or not self:hasAdminAccess() then
        return
    end
    if modules.game_interface.isElementalProfileInWorld() then
        modules.game_interface.toggleElementalWindow(ELEMENTAL_WINDOW_ID)
        return
    end
    if self.ui:isVisible() then
        self:hide()
    else
        self.ui:show()
        self.ui:raise()
        self.ui:focus()
        if self.button then
            self.button:setOn(true)
        end
    end
end

function GameBetaAdmin:hide()
    if self.confirmationBox then
        if not self.confirmationBox:isDestroyed() then
            self.confirmationBox:setVisible(false)
            self.confirmationBox:destroy()
        end
        self.confirmationBox = nil
    end
    if self.ui then
        self.ui:hide()
    end
    if self.button and not self.button:isDestroyed() then
        self.button:setOn(false)
    end
end

function GameBetaAdmin:setStatus(message)
    self.status = message
    if self.ui then
        setWidgetText(self.ui:recursiveGetChildById("statusLabel"), message)
    end
end

function GameBetaAdmin:setCatalogStatus(page, message)
    self.catalogStatus[page] = message
    if self.activePage == page then
        self:setStatus(message)
    end
end

function GameBetaAdmin:onActionSearch(query)
    self.actionQuery = lower(query)
    self:renderActionList()
end

function GameBetaAdmin:onLevelFilterChange()
    self:renderActionList()
end

function GameBetaAdmin:renderActionList()
    if not self.ui then
        return
    end
    local list = self.ui:recursiveGetChildById("actionsList")
    list:destroyChildren()
    self.filteredActions = {}
    local search = self.actionQuery or lower(self.ui:recursiveGetChildById("actionSearch"):getText())
    local option = self.ui:recursiveGetChildById("levelFilter"):getCurrentOption()
    local requiredLevel = option and tonumber(option.data) or 0

    for _, action in ipairs(self.actions) do
        local words = lower(action.words)
        local description = lower(action.description)
        local matchesSearch = search == "" or words:find(search, 1, true) or description:find(search, 1, true)
        local matchesLevel = requiredLevel == 0 or action.groupType == requiredLevel
        if matchesSearch and matchesLevel then
            self.filteredActions[#self.filteredActions + 1] = action
            local row = g_ui.createWidget("BetaAdminActionRow", list)
            row:getChildById("actionWords"):setText(action.words)
            row:getChildById("actionLevel"):setText(ROLE_NAMES[action.groupType] or ("Nivel " .. tostring(action.groupType)))
            row:setOn(self.selectedAction == action)
            row.onClick = function()
                self:selectAction(action)
            end
        end
    end
    setWidgetText(self.ui:recursiveGetChildById("actionCount"), string.format("%d / %d", #self.filteredActions, #self.actions))
    if self.selectedAction and not containsValue(self.filteredActions, self.selectedAction) then
        self.selectedAction = nil
        self.selectedSchema = nil
        self:clearTargetActionContext(false)
    end
    if self.selectedAction then
        self:renderActionDetails()
    elseif #self.filteredActions == 0 then
        self:clearActionDetails("Nenhum comando encontrado para este filtro.")
    else
        self:clearActionDetails("Selecione uma TalkAction para ver seu formulario.")
    end
end

function GameBetaAdmin:selectAction(action, targetActionContext)
    self.targetActionContext = targetActionContext
    self.selectedAction = action
    self.selectedSchema = action.schema
    self.fieldWidgets = {}
    self:renderActionList()
    self:renderActionDetails()
end

function GameBetaAdmin:updateQuickTargetActionButtons(user)
    if not self.ui then
        return
    end

    local canOpenActions = user ~= nil and self.snapshot ~= nil
        and self.snapshot.canSearchOnlinePlayers == true
    local hasActions = false
    for _, quickAction in ipairs(TARGET_ACTION_MENU_HOOKS) do
        local button = self.ui:recursiveGetChildById(quickAction.buttonId)
        local action = canOpenActions and hasQuickTargetAction(user, quickAction.words)
            and self:getExecutableTargetAction(quickAction.words) or nil
        local targetField = action and action.schema.fields and action.schema.fields[1]
        local isAvailable = action ~= nil and targetField ~= nil and targetField.id == "target"
            and type(action.schema.confirm) == "string"
        hasActions = hasActions or isAvailable
        button:setVisible(isAvailable)
        button:setEnabled(isAvailable)
        button:setText(tr(quickAction.buttonLabel))
        local actionWords = quickAction.words
        button.onClick = function()
            self:openSelectedUserAction(actionWords)
        end
    end
    self.ui:recursiveGetChildById("userQuickActions"):setVisible(hasActions)
end

function GameBetaAdmin:openSelectedUserAction(words)
    local user = self.selectedUser
    local action = self:getExecutableTargetAction(words)
    if not hasQuickTargetAction(user, words) or not action then
        self:setStatus("Este alvo ou TalkAction nao esta autorizado pelo Canary.")
        self:updateQuickTargetActionButtons(user)
        return false
    end

    self:showPage("commands")
    if not self.ui:isVisible() then
        self:toggle()
    end
    if not self.ui:isVisible() or self.activePage ~= "commands" then
        return false
    end

    self:selectAction(action, {
        source = "online-search",
        name = user.name,
        words = words,
        user = user,
        snapshot = self.snapshot,
    })
    self:setStatus("Alvo da busca online selecionado. Confira a previa e a confirmacao.")
    return true
end

function GameBetaAdmin:getExecutableTargetAction(words)
    if not self.snapshot or not g_game.isOnline() then
        return nil
    end
    return findExecutableTargetAction(self.actions, self.snapshot, words)
end

function GameBetaAdmin:getLivePlayerTarget(creature)
    local getCreatureById = g_map and g_map.getCreatureById
    return resolveLivePlayerTarget(creature, g_game.isOnline(), getCreatureById)
end

function GameBetaAdmin:canOpenTargetAction(words, creature)
    return self.localTestMode ~= true and self:getExecutableTargetAction(words) ~= nil
        and self:getLivePlayerTarget(creature) ~= nil
end

function GameBetaAdmin:openTargetAction(words, creature)
    local action = self:getExecutableTargetAction(words)
    local target = self:getLivePlayerTarget(creature)
    if not action or not target then
        return false
    end

    self:showPage("commands")
    if not self.ui:isVisible() then
        self:toggle()
    end
    if not self.ui:isVisible() then
        return false
    end

    self:selectAction(action, {
        id = target.id,
        name = target.name,
        words = words,
        snapshot = self.snapshot,
    })
    self:setStatus("Alvo online selecionado. Confira o formulario antes de executar.")
    return true
end

function GameBetaAdmin:registerTargetActionHooks()
    local gameInterface = modules.game_interface
    if not gameInterface or type(gameInterface.addMenuHook) ~= "function" then
        return
    end

    if self.targetActionHooksRegistered then
        self:unregisterTargetActionHooks()
    end
    for _, hook in ipairs(TARGET_ACTION_MENU_HOOKS) do
        local words = hook.words
        local label = tr(hook.label)
        gameInterface.addMenuHook(TARGET_ACTION_MENU_CATEGORY, label,
            function(_, _, _, creature)
                self:openTargetAction(words, creature)
            end,
            function(_, _, _, creature)
                return self:canOpenTargetAction(words, creature)
            end)
    end
    self.targetActionHooksRegistered = true
end

function GameBetaAdmin:unregisterTargetActionHooks()
    if not self.targetActionHooksRegistered then
        return
    end
    local gameInterface = modules.game_interface
    if not gameInterface or type(gameInterface.removeMenuHook) ~= "function" then
        self.targetActionHooksRegistered = false
        return
    end

    for _, hook in ipairs(TARGET_ACTION_MENU_HOOKS) do
        gameInterface.removeMenuHook(TARGET_ACTION_MENU_CATEGORY, tr(hook.label))
    end
    self.targetActionHooksRegistered = false
end

function GameBetaAdmin:isTargetActionContextCurrent(context)
    if not context or self.targetActionContext ~= context or not g_game.isOnline()
        or not self.snapshot or self.snapshot ~= context.snapshot or not self.selectedAction
        or getFirstWord(self.selectedAction.words) ~= context.words then
        return false
    end
    if self:getExecutableTargetAction(context.words) == nil then
        return false
    end
    if context.source == "online-search" then
        if self.selectedUser ~= context.user or not hasQuickTargetAction(context.user, context.words) then
            return false
        end
        for _, user in ipairs(self.userResults or {}) do
            if user == context.user then
                return true
            end
        end
        return false
    end

    local targetField = self.fieldWidgets and self.fieldWidgets.target
    if not targetField or self:getFieldValue(targetField) ~= context.name then
        return false
    end

    local liveTarget = g_map and g_map.getCreatureById(context.id)
    local resolvedTarget = self:getLivePlayerTarget(liveTarget)
    return resolvedTarget ~= nil and resolvedTarget.id == context.id and resolvedTarget.name == context.name
end

function GameBetaAdmin:getStaleTargetActionMessage(context)
    if context and context.source == "online-search" then
        return "Acao cancelada: alvo removido da busca ou permissao alterada. Refaca a busca."
    end
    return "Acao cancelada: alvo fora do campo de visao ou permissao alterada. Reabra pelo menu do alvo."
end

function GameBetaAdmin:clearTargetActionContext(closeConfirmation)
    self.targetActionContext = nil
    if closeConfirmation ~= true then
        return
    end

    local confirmationBox = self.confirmationBox
    if confirmationBox and not confirmationBox:isDestroyed() then
        confirmationBox:setVisible(false)
        confirmationBox:destroy()
    end
    self.confirmationBox = nil
end

function GameBetaAdmin:clearActionDetails(message)
    self:clearTargetActionContext(false)
    local panel = self.ui:recursiveGetChildById("actionDetails")
    setWidgetText(panel:getChildById("selectedWords"), "")
    setWidgetText(panel:getChildById("selectedLevel"), "")
    setWidgetText(panel:getChildById("selectedDescription"), "")
    setWidgetText(panel:getChildById("schemaMessage"), message)
    setWidgetText(panel:getChildById("previewLabel"), "Previa: -")
    panel:getChildById("fieldsList"):destroyChildren()
    panel:getChildById("executeButton"):setEnabled(false)
end

function GameBetaAdmin:renderActionDetails()
    if not self.ui then
        return
    end
    local panel = self.ui:recursiveGetChildById("actionDetails")
    local action = self.selectedAction
    if not action then
        return self:clearActionDetails("Selecione uma TalkAction para ver seu formulario.")
    end

    setWidgetText(panel:getChildById("selectedWords"), action.words)
    setWidgetText(panel:getChildById("selectedLevel"), "Nivel minimo: " .. (ROLE_NAMES[action.groupType] or tostring(action.groupType)))
    setWidgetText(panel:getChildById("selectedDescription"), action.description or "Sem descricao no servidor.")

    local fieldsList = panel:getChildById("fieldsList")
    fieldsList:destroyChildren()
    self.fieldWidgets = {}
    local schema = self.selectedSchema
    if not schema then
        setWidgetText(panel:getChildById("schemaMessage"), "Bloqueado: esta acao nao tem schema revisado no cliente; nenhum comando sera enviado.")
        setWidgetText(panel:getChildById("previewLabel"), "Previa: indisponivel")
        panel:getChildById("executeButton"):setEnabled(false)
        return
    end
    if schema.blockedReason then
        setWidgetText(panel:getChildById("schemaMessage"), "Bloqueado: " .. schema.blockedReason)
        setWidgetText(panel:getChildById("previewLabel"), "Previa: indisponivel")
        panel:getChildById("executeButton"):setEnabled(false)
        return
    end
    setWidgetText(panel:getChildById("schemaMessage"), schema.impact or "Confira os campos e a previa antes de executar.")

    for _, field in ipairs(schema.fields or {}) do
        local widgetName = field.kind == "choice" and "BetaAdminSelectFieldRow" or "BetaAdminTextFieldRow"
        local row = g_ui.createWidget(widgetName, fieldsList)
        setWidgetText(row:getChildById("fieldLabel"), field.label .. (field.required and " *" or ""))
        setWidgetText(row:getChildById("fieldHelp"), getFieldHelp(field))
        local input = row:getChildById("fieldInput")
        if field.kind == "choice" then
            for _, option in ipairs(field.options or {}) do
                input:addOption(option[2], option[1])
            end
            if field.options and #field.options > 0 then
                input:setCurrentOptionByData(field.options[1][1])
            end
        end
        if field.id == "target" and self.targetActionContext then
            input:setText(self.targetActionContext.name)
            input:setEnabled(false)
        end
        self.fieldWidgets[field.id] = { widget = input, field = field }
        if field.kind == "choice" then
            input.onOptionChange = function()
                self:updateTalkActionPreview()
            end
        else
            input.onTextChange = function()
                self:updateTalkActionPreview()
            end
        end
    end
    self:updateTalkActionPreview()
end

function GameBetaAdmin:getFieldValue(fieldData)
    if fieldData.field.kind == "choice" then
        local option = fieldData.widget:getCurrentOption()
        return option and tostring(option.data or "") or ""
    end
    return trim(fieldData.widget:getText())
end

function GameBetaAdmin:getTalkActionMessage(messageType)
    local schema = self.selectedSchema
    if not schema then
        return nil
    end

    local actionText = schema.actionText
    local fieldData = actionText and self.fieldWidgets and self.fieldWidgets[actionText.field]
    if fieldData then
        local valueMessages = actionText.values and actionText.values[self:getFieldValue(fieldData)]
        if type(valueMessages) == "table" and type(valueMessages[messageType]) == "string" then
            return valueMessages[messageType]
        end
    end
    return schema[messageType]
end

function GameBetaAdmin:isFieldRequired(field)
    if field.required then
        return true
    end
    if not field.requiredWhen then
        return false
    end
    local controller = self.fieldWidgets[field.requiredWhen.field]
    if not controller then
        return false
    end
    local value = self:getFieldValue(controller)
    return field.requiredWhen.values[value] == true
end

function GameBetaAdmin:buildTalkActionCommand()
    local action = self.selectedAction
    local schema = self.selectedSchema
    if not action or not schema or schema.blockedReason then
        return nil, "Esta acao nao tem um formulario executavel."
    end
    local fields = schema.fields or {}
    local values = {}
    local lastNonEmpty = 0
    for index, field in ipairs(fields) do
        local data = self.fieldWidgets[field.id]
        local value = data and self:getFieldValue(data) or ""
        if self:isFieldRequired(field) and value == "" then
            return nil, "Preencha: " .. field.label .. "."
        end
        if value ~= "" then
            if field.kind == "number" then
                local parsed = parseInteger(value, field.minimum, field.maximum)
                if not parsed then
                    return nil, string.format("%s deve ser um inteiro entre %d e %d.", field.label, field.minimum, field.maximum)
                end
                value = tostring(parsed)
            elseif field.kind == "amount" then
                if lower(value) ~= "all" and not parseInteger(value, 1, 2147483647) then
                    return nil, field.label .. " deve ser all ou um inteiro positivo."
                end
                value = lower(value) == "all" and "all" or tostring(tonumber(value))
            elseif field.kind == "choice" then
                local valid = false
                for _, option in ipairs(field.options or {}) do
                    if value == tostring(option[1]) then
                        valid = true
                        break
                    end
                end
                if not valid then
                    return nil, "Selecione uma opcao valida em " .. field.label .. "."
                end
            elseif field.kind == "text" then
                if #value > field.maxLength or value:find("[\r\n]") then
                    return nil, field.label .. " excede o limite permitido."
                end
                if schema.separator == ", " and value:find(",", 1, true) then
                    return nil, field.label .. " nao pode conter virgula neste formulario."
                end
            end
            lastNonEmpty = index
        end
        values[index] = value
    end

    if lastNonEmpty == 0 then
        return getFirstWord(action.words)
    end
    local args = {}
    for index = 1, lastNonEmpty do
        args[#args + 1] = values[index] or ""
    end
    return getFirstWord(action.words) .. " " .. table.concat(args, schema.separator or " ")
end

function GameBetaAdmin:updateTalkActionPreview()
    if not self.ui then
        return
    end
    local command, errorMessage = self:buildTalkActionCommand()
    local actionDetails = self.ui:recursiveGetChildById("actionDetails")
    local button = actionDetails:getChildById("executeButton")
    local preview = actionDetails:getChildById("previewLabel")
    local guidance = self:getTalkActionMessage("impact") or "Confira os campos e a previa antes de executar."
    setWidgetText(actionDetails:getChildById("schemaMessage"), guidance)
    if command then
        setWidgetText(preview, "Previa: " .. command)
        button:setEnabled(true)
    else
        setWidgetText(preview, "Previa: " .. (errorMessage or "preencha o formulario"))
        button:setEnabled(false)
    end
end

function GameBetaAdmin:displayConfirmation(title, message, cancelText, confirmText, onConfirm)
    if type(onConfirm) ~= "function" then
        return
    end

    if self.confirmationBox and not self.confirmationBox:isDestroyed() then
        self.confirmationBox:raise()
        return self.confirmationBox
    end

    local messageBox
    local function closeMessageBox()
        if not messageBox or messageBox:isDestroyed() then
            return
        end
        messageBox:setVisible(false)
        messageBox:destroy()
    end

    messageBox = displayGeneralBox(title, message, {{
        text = cancelText,
        callback = closeMessageBox
    }, {
        text = confirmText,
        callback = function()
            closeMessageBox()
            onConfirm()
        end
    }})
    messageBox:setId("betaAdminTalkActionConfirmation")
    self.confirmationBox = messageBox
    return messageBox
end

function GameBetaAdmin:executeTalkAction()
    if self.localTestMode then
        self:setStatus("QA local isolado: nenhum comando foi enviado.")
        return
    end
    if not self.snapshot or not self.selectedAction or self.selectedAction.groupType > self.snapshot.accountType then
        self:requestSnapshot()
        return
    end
    local targetActionContext = self.targetActionContext
    if targetActionContext and not self:isTargetActionContextCurrent(targetActionContext) then
        self:clearActionDetails(self:getStaleTargetActionMessage(targetActionContext))
        self:setStatus(self:getStaleTargetActionMessage(targetActionContext))
        return
    end
    local command, errorMessage = self:buildTalkActionCommand()
    if not command then
        self:setStatus(errorMessage or "Formulario invalido.")
        return
    end
    local function execute()
        if targetActionContext and not self:isTargetActionContextCurrent(targetActionContext) then
            self:clearActionDetails(self:getStaleTargetActionMessage(targetActionContext))
            self:setStatus(self:getStaleTargetActionMessage(targetActionContext))
            return
        end
        if not g_game.isOnline() or not self.snapshot or self.selectedAction.groupType > self.snapshot.accountType then
            self:setStatus("A sessao ou a permissao mudou. Atualize o painel.")
            self:requestSnapshot()
            return
        end
        g_game.talk(command)
        self:setStatus("TalkAction enviada pelo dispatcher padrao do Canary.")
    end
    local confirmation = self:getTalkActionMessage("confirm")
    if confirmation then
        self:displayConfirmation("Confirmar TalkAction", confirmation .. "\n\n" .. command,
            "Cancelar", "Executar", execute)
    else
        execute()
    end
end

function GameBetaAdmin:onItemSearchChange(query)
    self:debounceSearch("search_items", query)
end

function GameBetaAdmin:onMonsterSearchChange(query)
    self:debounceSearch("search_monsters", query)
end

function GameBetaAdmin:debounceSearch(action, query)
    self:cancelSearch()
    query = trim(query)
    if action == "search_items" then
        self.latestItemSearchRequestId = nil
        self.selectedItem = nil
        self.ui:recursiveGetChildById("itemResults"):destroyChildren()
        setWidgetText(self.ui:recursiveGetChildById("selectedItemLabel"), "Selecione um item da busca.")
        self:updateItemPreview()
    else
        self.latestMonsterSearchRequestId = nil
        self.selectedMonster = nil
        self.ui:recursiveGetChildById("monsterResults"):destroyChildren()
        setWidgetText(self.ui:recursiveGetChildById("selectedMonsterLabel"), "Selecione um monstro da busca.")
        self:updateMonsterPreview()
    end
    if #query == 0 then
        self:setCatalogStatus(action == "search_items" and "items" or "monsters",
            "Digite um nome ou ID para pesquisar.")
        return
    end
    if #query > MAX_QUERY_LENGTH then
        self:setCatalogStatus(action == "search_items" and "items" or "monsters",
            "A busca precisa ter de 1 a 64 caracteres.")
        return
    end
    if self.localTestMode then
        local fixtureItems = {
            { id = 3264, name = "sword", stackable = false },
            { id = 3271, name = "Spike Sword", stackable = false },
        }
        local fixtureMonsters = {
            { name = "Demon", lookType = 35 },
        }
        self:renderSearchResults(action == "search_items" and "items" or "monsters",
            action == "search_items" and fixtureItems or fixtureMonsters, false)
        return
    end
    self:setCatalogStatus(action == "search_items" and "items" or "monsters",
        "Pesquisando no catalogo do servidor...")
    self.searchEvent = scheduleEvent(function()
        self.searchEvent = nil
        local requestId = self:sendRequest(action, { query = query, offset = 0 })
        if action == "search_items" then
            self.latestItemSearchRequestId = requestId
        else
            self.latestMonsterSearchRequestId = requestId
        end
    end, 300)
end

function GameBetaAdmin:onItemSearchResponse(response)
    if response.requestId ~= self.latestItemSearchRequestId then
        return
    end
    if response.success ~= true or type(response.items) ~= "table" then
        self:setCatalogStatus("items", "Nao foi possivel pesquisar itens no servidor.")
        return
    end
    self:renderSearchResults("items", response.items, response.hasMore == true)
end

function GameBetaAdmin:onMonsterSearchResponse(response)
    if response.requestId ~= self.latestMonsterSearchRequestId then
        return
    end
    if response.success ~= true or type(response.items) ~= "table" then
        self:setCatalogStatus("monsters", "Nao foi possivel pesquisar monstros no servidor.")
        return
    end
    self:renderSearchResults("monsters", response.items, response.hasMore == true)
end

function GameBetaAdmin:resetUserOptionBoxes(user)
    if not self.ui then
        return
    end
    local accountTypeBox = self.ui:recursiveGetChildById("accountTypeSelection")
    local groupBox = self.ui:recursiveGetChildById("groupSelection")
    accountTypeBox:clearOptions()
    accountTypeBox:addOption("Selecione o nivel da conta", -1)
    groupBox:clearOptions()
    groupBox:addOption("Selecione o grupo", -1)

    if self.snapshot and self.snapshot.canManageUsers then
        for _, option in ipairs(self.snapshot.accountTypeOptions or {}) do
            if type(option.id) == "number" and type(option.name) == "string"
                and option.id < self.snapshot.accountType then
                accountTypeBox:addOption(option.name, option.id)
            end
        end
        for _, option in ipairs(self.snapshot.groupOptions or {}) do
            if type(option.id) == "number" and type(option.name) == "string" then
                groupBox:addOption(option.name, option.id)
            end
        end
    end
    accountTypeBox:setCurrentOptionByData(user and user.accountType or -1)
    groupBox:setCurrentOptionByData(user and user.groupType or -1)
end

function GameBetaAdmin:getGroupLabel(groupId)
    local option = findRoleOption(self.snapshot and self.snapshot.groupOptions, groupId)
    return option and option.name or ("Grupo " .. tostring(groupId))
end

function GameBetaAdmin:updateUserActionButtons()
    if not self.ui then
        return
    end
    local user = self.selectedUser
    local canChange = user ~= nil and user.manageable == true and self.snapshot ~= nil
        and self.snapshot.canManageUsers == true
    local accountOption = self.ui:recursiveGetChildById("accountTypeSelection"):getCurrentOption()
    local groupOption = self.ui:recursiveGetChildById("groupSelection"):getCurrentOption()
    local accountType = accountOption and tonumber(accountOption.data) or nil
    local groupId = groupOption and tonumber(groupOption.data) or nil
    self.ui:recursiveGetChildById("applyAccountTypeButton"):setEnabled(canChange
        and accountType ~= nil and accountType > 0 and accountType ~= user.accountType)
    self.ui:recursiveGetChildById("applyGroupButton"):setEnabled(canChange
        and groupId ~= nil and groupId > 0 and groupId ~= user.groupType)
end

function GameBetaAdmin:renderUserDetails(user)
    if not self.ui then
        return
    end
    local nameLabel = self.ui:recursiveGetChildById("selectedUserName")
    local accessLabel = self.ui:recursiveGetChildById("currentUserAccess")
    local capabilityList = self.ui:recursiveGetChildById("userCapabilities")
    capabilityList:destroyChildren()
    self:resetUserOptionBoxes(user)
	self:updateQuickTargetActionButtons(user)

    if not user then
        setWidgetText(nameLabel, "Selecione um jogador online.")
        setWidgetText(accessLabel, "")
        setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"), "")
        self:updateUserActionButtons()
        return
    end

    local accountTypeName = ROLE_NAMES[user.accountType] or tostring(user.accountType)
    setWidgetText(nameLabel, user.name)
    setWidgetText(accessLabel, string.format("AccountType da conta: %s  |  Group/flags do personagem: %s",
        accountTypeName, self:getGroupLabel(user.groupType)))

    local storeAvailable = self.snapshot and self.snapshot.capabilityStoreAvailable == true
    if not self.snapshot or not self.snapshot.canManageUsers then
        setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"), "Gestao nao autorizada pelo Canary.")
        self:updateUserActionButtons()
        return
    end
    if user.manageable ~= true then
        setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"),
            "Este jogador nao esta abaixo do seu nivel; alteracoes estao bloqueadas.")
        self:updateUserActionButtons()
        return
    end
    if not storeAvailable then
        setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"),
            "Store de grants indisponivel; alteracoes de permissao estao bloqueadas.")
        self:updateUserActionButtons()
        return
    end
    if user.capabilitiesAvailable ~= true then
        setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"),
            "Grants nao disponiveis para este alvo.")
        self:updateUserActionButtons()
        return
    end
    setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"), "Grants beta persistentes disponiveis.")
    if #self.assignableCapabilities == 0 then
        setWidgetText(self.ui:recursiveGetChildById("capabilityStoreStatus"),
            "Canary nao forneceu capabilities liberadas para gestao.")
        self:updateUserActionButtons()
        return
    end

    for _, capability in ipairs(self.assignableCapabilities) do
        local row = g_ui.createWidget("BetaAdminCapabilityRow", capabilityList)
        local granted = containsValue(user.capabilities, capability)
        setWidgetText(row:getChildById("capabilityName"), CAPABILITY_LABELS[capability])
        setWidgetText(row:getChildById("capabilityStatus"), granted and "Concedida para esta conta." or "Nao concedida.")
        local button = row:getChildById("changeCapabilityButton")
        setWidgetText(button, granted and "Revogar" or "Conceder")
        button:setEnabled(user.manageable == true)
        button.onClick = function()
            self:confirmCapabilityChange(capability, not granted)
        end
    end
    self:updateUserActionButtons()
end

function GameBetaAdmin:selectUser(user)
    if not user then
        return
    end
	if self.targetActionContext and self.targetActionContext.source == "online-search"
		and self.targetActionContext.user ~= user then
		self:clearTargetActionContext(true)
	end
    self.selectedUser = user
    if self.snapshot and self.snapshot.canCompensate == true then
        BetaAdminOperations:setCompensationTarget(user.name)
    end
    local list = self.ui:recursiveGetChildById("userResults")
    for _, row in ipairs(list:getChildren()) do
        row:setOn(row.userEntry == user)
    end
    self:renderUserDetails(user)
end

function GameBetaAdmin:renderUserResults(users, hasMore, append)
    local list = self.ui:recursiveGetChildById("userResults")
    if not append then
        if self.targetActionContext and self.targetActionContext.source == "online-search" then
            self:clearTargetActionContext(true)
        end
        list:destroyChildren()
        self.userResults = {}
        self.selectedUser = nil
    end
    for _, user in ipairs(users) do
        self.userResults[#self.userResults + 1] = user
        local row = g_ui.createWidget("BetaAdminUserRow", list)
        row.userEntry = user
        row:getChildById("userName"):setText(user.name)
        local accountTypeName = ROLE_NAMES[user.accountType] or tostring(user.accountType)
        row:getChildById("userAccess"):setText(string.format("%s  |  Grupo %s",
            accountTypeName, tostring(user.groupType)))
        row:setOn(self.selectedUser == user)
        row.onClick = function()
            self:selectUser(user)
        end
    end
    self.userHasMore = hasMore == true
    self.ui:recursiveGetChildById("userLoadMoreButton"):setEnabled(self.userHasMore)

    if self.userReselectName then
        local selectedName = self.userReselectName:lower()
        for _, user in ipairs(self.userResults) do
            if user.name:lower() == selectedName then
                self:selectUser(user)
                self.userReselectName = nil
                break
            end
        end
    end
    if not self.selectedUser then
        self:renderUserDetails(nil)
    end
    if self.userQuery == "" then
        self:setStatus(string.format("%d jogador(es) online visiveis para seu cargo%s.", #self.userResults,
            self.userHasMore and "; ha mais resultados" or ""))
    else
        self:setStatus(string.format("%d jogador(es) online na busca%s.", #self.userResults,
            self.userHasMore and "; ha mais resultados" or ""))
    end
end

function GameBetaAdmin:requestOnlinePlayers(query, offset, append)
    if not g_game.isOnline() or not self.snapshot or self.snapshot.canSearchOnlinePlayers ~= true then
        self:setStatus("A busca exige permissao de consulta de jogadores online no Canary.")
        return
    end
    local requestId = self:sendRequest("online_players", { query = query, offset = offset })
    if not requestId then
        return
    end
    self.latestUserSearchRequestId = requestId
    self.userSearchAppend = append == true
    self:setStatus("Pesquisando jogadores online...")
end

function GameBetaAdmin:onUserSearchChange(query)
    if self.isResettingSession or self.settingUserSearch then
        return
    end
    self:cancelSearch()
    if self.targetActionContext and self.targetActionContext.source == "online-search" then
        self:clearTargetActionContext(true)
    end
    query = trim(query)
    self.userQuery = query
    self.latestUserSearchRequestId = nil
    self.userReselectName = nil
    self.selectedUser = nil
    self.userResults = {}
    self.userHasMore = false
    self.ui:recursiveGetChildById("userResults"):destroyChildren()
    self.ui:recursiveGetChildById("userLoadMoreButton"):setEnabled(false)
    self:renderUserDetails(nil)

    if #query > MAX_QUERY_LENGTH then
        self:setStatus("A busca precisa ter no maximo 64 caracteres.")
        return
    end
    if not self.snapshot or self.snapshot.canSearchOnlinePlayers ~= true then
        self:setStatus("Seu cargo nao tem permissao para buscar jogadores online.")
        return
    end
    if self.localTestMode then
        local fixtures = {
            { name = "Beta Tester", accountType = 1, groupType = 1, manageable = true, capabilities = { CAPABILITY_ITEMS } },
            { name = "Beta Builder", accountType = 2, groupType = 2, manageable = true, capabilities = {} },
        }
        local results = {}
        for _, user in ipairs(fixtures) do
            if user.name:lower():find(query:lower(), 1, true) then
                results[#results + 1] = user
            end
        end
        self:renderUserResults(results, false, false)
        return
    end
    self:setStatus(query == "" and "Carregando jogadores online visiveis para seu cargo..."
        or "Pesquisando jogadores online...")
    self.searchEvent = scheduleEvent(function()
        self.searchEvent = nil
        self:requestOnlinePlayers(query, 0, false)
    end, 300)
end

function GameBetaAdmin:loadMoreUsers()
    if not self.userHasMore then
        return
    end
    if self.localTestMode then
        self.userHasMore = false
        self.ui:recursiveGetChildById("userLoadMoreButton"):setEnabled(false)
        return
    end
    self:requestOnlinePlayers(self.userQuery, #self.userResults, true)
end

function GameBetaAdmin:onOnlinePlayersResponse(response, context)
    if context == "item-recipient" then
        self:onItemRecipientSearchResponse(response)
        return
    end
    if response.requestId ~= self.latestUserSearchRequestId then
        return
    end

    local users, errorMessage = self:decodeOnlinePlayers(response)
    if not users then
        self:setStatus(errorMessage)
        return
    end
    self:renderUserResults(users, response.hasMore == true, self.userSearchAppend)
end

function GameBetaAdmin:decodeOnlinePlayers(response)
    if response.success ~= true or type(response.items) ~= "table" then
        return nil, "Canary nao conseguiu listar os jogadores online."
    end

    local users = {}
    for _, user in ipairs(response.items) do
        if type(user) == "table" and type(user.name) == "string"
            and type(user.accountType) == "number" and type(user.groupType) == "number"
            and type(user.manageable) == "boolean" and type(user.capabilitiesAvailable) == "boolean"
            and type(user.capabilities) == "table" then
            if type(user.quickActions) ~= "table" then
                user.quickActions = {}
                if user.manageable then
                    for _, quickAction in ipairs(TARGET_ACTION_MENU_HOOKS) do
                        user.quickActions[quickAction.words] = self:getExecutableTargetAction(quickAction.words) ~= nil
                    end
                end
            end
            for _, quickAction in ipairs(TARGET_ACTION_MENU_HOOKS) do
                if type(user.quickActions[quickAction.words]) ~= "boolean" then
                    return nil, "Resposta de acoes online incompativel; atualize Canary e OTClient juntos."
                end
            end
            users[#users + 1] = user
        else
            return nil, "Resposta de gestao incompativel; atualize Canary e OTClient juntos."
        end
    end
    return users
end

function GameBetaAdmin:onItemRecipientChange(query)
    if self.isResettingSession or self.settingItemRecipient then
        self:updateItemPreview()
        return
    end
    self:cancelItemRecipientSearch()
    self.latestItemRecipientRequestId = nil
    self.selectedItemRecipient = nil
    local results = self.ui:recursiveGetChildById("itemRecipientResults")
    results:destroyChildren()
    results:hide()
    self.ui:recursiveGetChildById("itemRecipientResultsScrollBar"):hide()

    query = trim(query)
    self:updateItemPreview()
    if #query == 0 then
        self:setStatus("Digite parte do nome de um jogador online.")
        return
    end
    if #query > MAX_QUERY_LENGTH then
        self:setStatus("A busca de destinatario precisa ter no maximo 64 caracteres.")
        return
    end
    if not self.snapshot or self.snapshot.canSearchOnlinePlayers ~= true then
        self:setStatus("Seu cargo nao pode consultar jogadores online para escolher destinatarios.")
        return
    end
    if self.localTestMode then
        local fixtures = {
            { name = "Beta Tester", accountType = 1, groupType = 1 },
            { name = "Beta Builder", accountType = 2, groupType = 2 },
        }
        local matches = {}
        local normalizedQuery = query:lower()
        for _, user in ipairs(fixtures) do
            if user.name:lower():find(normalizedQuery, 1, true) then
                matches[#matches + 1] = user
            end
        end
        self:renderItemRecipientResults(matches, false)
        return
    end

    self:setStatus("Pesquisando jogadores online para o destinatario...")
    self.itemRecipientSearchEvent = scheduleEvent(function()
        self.itemRecipientSearchEvent = nil
        local requestId = self:sendRequest("online_players", { query = query, offset = 0 }, "item-recipient")
        self.latestItemRecipientRequestId = requestId
    end, 300)
end

function GameBetaAdmin:onItemRecipientSearchResponse(response)
    if response.requestId ~= self.latestItemRecipientRequestId then
        return
    end
    self.latestItemRecipientRequestId = nil
    local users, errorMessage = self:decodeOnlinePlayers(response)
    if not users then
        self:setStatus(errorMessage)
        return
    end
    self:renderItemRecipientResults(users, response.hasMore == true)
end

function GameBetaAdmin:renderItemRecipientResults(users, hasMore)
    local list = self.ui:recursiveGetChildById("itemRecipientResults")
    list:destroyChildren()
    if #users == 0 then
        list:hide()
        self.ui:recursiveGetChildById("itemRecipientResultsScrollBar"):hide()
        self:setStatus("Nenhum jogador online elegivel corresponde a essa busca.")
        return
    end

    for _, user in ipairs(users) do
        local row = g_ui.createWidget("BetaAdminUserRow", list)
        row:getChildById("userName"):setText(user.name)
        local roleName = ROLE_NAMES[user.accountType] or tostring(user.accountType)
        row:getChildById("userAccess"):setText(string.format("%s  |  Grupo %s", roleName,
            tostring(user.groupType)))
        row.onClick = function()
            self:selectItemRecipient(user)
        end
    end
    list:show()
    self.ui:recursiveGetChildById("itemRecipientResultsScrollBar"):show()
    local suffix = hasMore and "; refine a busca para outros resultados" or ""
    self:setStatus(string.format("%d jogador(es) online encontrado(s)%s.", #users, suffix))
end

function GameBetaAdmin:selectItemRecipient(user)
    if not user or type(user.name) ~= "string" or user.name == "" then
        return
    end
    self.selectedItemRecipient = user
    self.settingItemRecipient = true
    self.ui:recursiveGetChildById("itemRecipient"):setText(user.name)
    self.settingItemRecipient = false
    self.ui:recursiveGetChildById("itemRecipientResults"):destroyChildren()
    self.ui:recursiveGetChildById("itemRecipientResults"):hide()
    self.ui:recursiveGetChildById("itemRecipientResultsScrollBar"):hide()
    self:setStatus(string.format("Destinatario online selecionado: %s.", user.name))
    self:updateItemPreview()
end

function GameBetaAdmin:confirmAccountTypeChange()
    local user = self.selectedUser
    local option = self.ui:recursiveGetChildById("accountTypeSelection"):getCurrentOption()
    local accountType = option and tonumber(option.data) or nil
    if not user or user.manageable ~= true or not accountType
        or not findRoleOption(self.snapshot and self.snapshot.accountTypeOptions, accountType)
        or accountType == user.accountType then
        return
    end
    local targetName = user.name
    local currentName = ROLE_NAMES[user.accountType] or tostring(user.accountType)
    local newName = ROLE_NAMES[accountType] or tostring(accountType)
    self:displayConfirmation("Confirmar alteracao da conta",
        string.format("Conta de %s: %s -> %s. A mudanca vale para todos os personagens desta conta.",
            targetName, currentName, newName), "Cancelar", "Alterar conta", function()
            self:sendRequest("set_account_type", { targetName = targetName, accountType = accountType })
            self:setStatus("Alteracao de AccountType enviada ao Canary para validacao e auditoria.")
        end)
end

function GameBetaAdmin:confirmGroupChange()
    local user = self.selectedUser
    local option = self.ui:recursiveGetChildById("groupSelection"):getCurrentOption()
    local groupId = option and tonumber(option.data) or nil
    local group = findRoleOption(self.snapshot and self.snapshot.groupOptions, groupId)
    if not user or user.manageable ~= true or not group or groupId == user.groupType then
        return
    end
    local targetName = user.name
    local currentName = self:getGroupLabel(user.groupType)
    self:displayConfirmation("Confirmar alteracao do personagem",
        string.format("Personagem %s: grupo %s -> %s. A mudanca nao altera a conta.",
            targetName, currentName, group.name), "Cancelar", "Alterar grupo", function()
            self:sendRequest("set_group", { targetName = targetName, groupId = groupId })
            self:setStatus("Alteracao de Group enviada ao Canary para validacao e auditoria.")
        end)
end

function GameBetaAdmin:confirmCapabilityChange(capability, grant)
    local user = self.selectedUser
    if not user or user.manageable ~= true or not self.snapshot
        or self.snapshot.capabilityStoreAvailable ~= true or not containsValue(self.assignableCapabilities, capability) then
        return
    end
    local hasCapability = containsValue(user.capabilities, capability)
    if hasCapability == grant then
        return
    end
    local targetName = user.name
    local operation = grant and "grant_capability" or "revoke_capability"
    local verb = grant and "conceder" or "revogar"
    self:displayConfirmation("Confirmar permissao beta",
        string.format("%s %s para a conta de %s? A mudanca sera persistente e auditada.",
            verb, CAPABILITY_LABELS[capability], targetName), "Cancelar", grant and "Conceder" or "Revogar", function()
            self:sendRequest(operation, { targetName = targetName, capability = capability })
            self:setStatus("Alteracao de capability enviada ao Canary para validacao e auditoria.")
        end)
end

function GameBetaAdmin:renderSearchResults(kind, items, hasMore)
    local listId = kind == "items" and "itemResults" or "monsterResults"
    local list = self.ui:recursiveGetChildById(listId)
    list:destroyChildren()
    if kind == "items" then
        self.selectedItem = nil
        setWidgetText(self.ui:recursiveGetChildById("selectedItemLabel"), "Selecione um item da busca.")
    else
        self.selectedMonster = nil
        setWidgetText(self.ui:recursiveGetChildById("selectedMonsterLabel"), "Selecione um monstro da busca.")
    end
    for _, item in ipairs(items) do
        if kind == "items" and type(item.id) == "number" and type(item.name) == "string" then
            local row = g_ui.createWidget("BetaAdminItemRow", list)
            row:getChildById("itemSprite"):setItemId(item.id)
            row:getChildById("itemSprite"):show()
            row:getChildById("monsterSprite"):hide()
            row:getChildById("itemName"):setText(item.name)
            row:getChildById("itemId"):setText(string.format("ID %d%s", item.id, item.stackable and "  empilhavel" or ""))
            row.onClick = function()
                self.selectedItem = item
                setWidgetText(self.ui:recursiveGetChildById("selectedItemLabel"), string.format("%s (ID %d)", item.name, item.id))
                self:updateItemPreview()
            end
        elseif kind == "monsters" and type(item.name) == "string" then
            local row = g_ui.createWidget("BetaAdminItemRow", list)
            row:getChildById("itemSprite"):hide()
            local monsterSprite = row:getChildById("monsterSprite")
            monsterSprite:setOutfit(createMonsterOutfit(item))
            monsterSprite:setCreatureSize(36)
            monsterSprite:show()
            row:getChildById("itemName"):setText(item.name)
            row:getChildById("itemId"):setText(getMonsterLookTypeLabel(item))
            row.onClick = function()
                self.selectedMonster = item
                setWidgetText(self.ui:recursiveGetChildById("selectedMonsterLabel"),
                    string.format("%s (%s)", item.name, getMonsterLookTypeLabel(item)))
                self:updateMonsterPreview()
            end
        end
    end
    self:setCatalogStatus(kind, string.format("%d resultado(s)%s.", #items,
        hasMore and "; refine a busca para ver outros" or ""))
    if kind == "items" then
        self:updateItemPreview()
    else
        self:updateMonsterPreview()
    end
end

function GameBetaAdmin:updateItemPreview()
    if not self.ui then
        return
    end
    local count = parseInteger(trim(self.ui:recursiveGetChildById("itemCount"):getText()), 1, 100)
    local target = trim(self.ui:recursiveGetChildById("itemRecipient"):getText())
    local selectedTarget = self.selectedItemRecipient
        and self.selectedItemRecipient.name == target
        and self.snapshot and self.snapshot.canSearchOnlinePlayers == true
    local sprite = self.ui:recursiveGetChildById("itemPreviewSprite")
    if self.selectedItem then
        sprite:setItemId(self.selectedItem.id)
        sprite:show()
    else
        sprite:setItemId(0)
        sprite:hide()
    end
    local enabled = self.selectedItem ~= nil and count ~= nil and selectedTarget == true and #target <= 48
        and hasCapability(self.capabilities, CAPABILITY_ITEMS)
    local name = self.selectedItem and self.selectedItem.name or "item nao selecionado"
    local recipient = selectedTarget and target or "selecione um jogador online"
    setWidgetText(self.ui:recursiveGetChildById("itemPreview"), string.format("Previa: %s x %s para %s.",
        name, tostring(count or "?"), recipient))
    self.ui:recursiveGetChildById("giveItemButton"):setEnabled(enabled)
end

function GameBetaAdmin:confirmGiveItem()
    self:updateItemPreview()
    if not self.ui:recursiveGetChildById("giveItemButton"):isEnabled()
        or not self.selectedItem or not self.selectedItemRecipient then
        return
    end
    local target = self.selectedItemRecipient.name
    local count = parseInteger(trim(self.ui:recursiveGetChildById("itemCount"):getText()), 1, 100)
    local itemId = self.selectedItem.id
    local itemName = self.selectedItem.name
    local description = string.format("Entregar %d x %s (ID %d) para %s, jogador online selecionado?",
        count, itemName, itemId, target)
    self:displayConfirmation("Confirmar entrega de item", description, "Cancelar", "Entregar", function()
        self:sendRequest("give_item", { targetName = target, itemId = itemId, count = count })
        self:setStatus("Solicitacao de item enviada; o Canary verificara cargo, alvo e limites.")
    end)
end

function GameBetaAdmin:updateMonsterPreview()
    if not self.ui then
        return
    end
    local count = parseInteger(trim(self.ui:recursiveGetChildById("monsterCount"):getText()), 1, 3)
    local option = self.ui:recursiveGetChildById("monsterMode"):getCurrentOption()
    local mode = option and option.data or nil
    local sprite = self.ui:recursiveGetChildById("monsterPreviewSprite")
    if self.selectedMonster then
        sprite:setOutfit(createMonsterOutfit(self.selectedMonster))
        sprite:setCreatureSize(56)
        sprite:show()
    else
        sprite:setOutfit({ type = 0, auxType = 0 })
        sprite:hide()
    end
    local enabled = self.selectedMonster ~= nil and count ~= nil and (mode == "spawn" or mode == "summon")
        and hasCapability(self.capabilities, CAPABILITY_MONSTERS)
    local name = self.selectedMonster and self.selectedMonster.name or "monstro nao selecionado"
    setWidgetText(self.ui:recursiveGetChildById("monsterPreview"), string.format("Previa: criar %s x %s como %s.", tostring(count or "?"), name, mode == "summon" and "summon" or "criatura comum"))
    self.ui:recursiveGetChildById("spawnMonsterButton"):setEnabled(enabled)
end

function GameBetaAdmin:confirmSpawnMonster()
    self:updateMonsterPreview()
    if not self.ui:recursiveGetChildById("spawnMonsterButton"):isEnabled() or not self.selectedMonster then
        return
    end
    local count = parseInteger(trim(self.ui:recursiveGetChildById("monsterCount"):getText()), 1, 3)
    local option = self.ui:recursiveGetChildById("monsterMode"):getCurrentOption()
    local mode = option and option.data or ""
    local monsterName = self.selectedMonster.name
    self:displayConfirmation("Confirmar criacao de monstro",
        self.ui:recursiveGetChildById("monsterPreview"):getText(), "Cancelar", "Criar", function()
            self:sendRequest("spawn_monster", { monsterName = monsterName, count = count, mode = mode })
            self:setStatus("Solicitacao de monstro enviada; o Canary verificara cargo, modo e limite.")
        end)
end

function GameBetaAdmin:onOperationResult(response)
    local messages = {
        capability_store_unavailable = "O armazenamento de permissoes nao esta disponivel.",
        not_authorized = "O Canary recusou a operacao: seu acesso nao esta autorizado.",
        target_offline = "O alvo precisa estar online e ser elegivel.",
        invalid_item_request = "O item ou a quantidade nao podem ser entregues.",
        invalid_monster_request = "O monstro, modo ou quantidade nao sao permitidos.",
        monster_not_allowed = "Esse monstro nao pode ser criado pelo painel.",
        monster_spawn_failed = "O espaco atual nao permitiu criar o monstro; nenhuma operacao foi mantida.",
        invalid_query = "A busca precisa ter de 1 a 64 caracteres.",
        catalog_unavailable = "O catalogo do servidor nao esta disponivel.",
        invalid_offset = "A pagina da busca expirou; faca uma nova busca.",
        invalid_mode = "O modo solicitado nao e permitido.",
        audit_unavailable = "A auditoria nao esta disponivel; a operacao foi recusada.",
        account_type_updated = "AccountType da conta alterado com sucesso e auditado.",
        group_updated = "Group deste personagem alterado com sucesso e auditado.",
        capability_granted = "Permissao beta concedida a conta e auditada.",
        capability_revoked = "Permissao beta revogada da conta e auditada.",
        self_change_denied = "O Canary bloqueou a alteracao da propria conta.",
        target_not_lower = "O alvo precisa estar abaixo do seu AccountType.",
        target_out_of_scope = "O alvo esta fora do escopo de gestao do seu cargo.",
        account_type_not_allowed = "Esse AccountType nao pode ser atribuido a esse alvo.",
        group_not_allowed = "Esse Group nao pode ser atribuido pelo painel.",
        capability_role_mismatch = "Essa capability so pode ser concedida ao cargo correspondente.",
        unchanged = "O alvo ja possui esse valor.",
        account_update_failed = "A conta nao foi alterada; a operacao foi revertida.",
        group_update_failed = "O personagem nao foi alterado; a operacao foi revertida.",
        capability_update_failed = "A permissao nao foi alterada; a operacao foi revertida.",
        item_delivered = "Item entregue com sucesso.",
        item_sent_to_inbox = "Inventario cheio; item enviado para a caixa de entrada do jogador.",
        monsters_created = "Monstro criado com sucesso.",
        compensation_applied = "Credito bancario aplicado e auditado.",
        compensation_disabled = "Compensacao desativada na configuracao atual.",
        compensation_limit_exceeded = "O valor ultrapassa o limite por operacao.",
        daily_compensation_limit_exceeded = "O teto diario do CM seria ultrapassado.",
        balance_out_of_supported_range = "O saldo esta fora do intervalo seguro.",
        balance_out_of_supported_range_or_stale = "O saldo mudou durante a operacao ou excede o intervalo seguro.",
        target_balance_unavailable = "Nao foi possivel confirmar o saldo persistido do personagem.",
        balance_update_failed = "O saldo nao foi atualizado; a operacao foi cancelada.",
        self_compensation_denied = "A conta do CM nao pode receber a propria compensacao.",
        target_not_player_account = "A compensacao pode ser aplicada apenas a uma conta de jogador.",
        temporary_elevation_required = "Esse acesso so pode ser concedido por elevacao temporaria aprovada.",
        compensation_failed = "A compensacao nao foi aplicada.",
        reason_or_ticket_required = "Informe motivo e referencia de bug/ticket validos.",
        elevation_requested = "Pedido de elevacao registrado; aguarda aprovacao independente.",
        elevation_approved = "Elevacao aprovada com expiracao automatica.",
        elevation_denied = "Pedido recusado e auditado.",
        elevation_revoked = "Elevacao revogada e auditada.",
        elevation_not_pending = "O pedido nao esta mais pendente.",
        elevation_not_active = "A elevacao nao esta ativa ou expirou.",
        elevation_duration_exceeded = "A duracao ultrapassa o maximo configurado.",
        elevation_scope_not_allowed = "Esse escopo nao pode ser elevado temporariamente.",
        elevation_already_open = "Ja existe pedido pendente ou elevacao ativa nesse escopo.",
        elevation_no_longer_eligible = "O pedido perdeu elegibilidade ou a capability ja esta ativa.",
        target_not_eligible = "A conta solicitante deixou de ser elegivel.",
        independent_approval_required = "A aprovacao precisa vir de outra conta God.",
    }
    local message = messages[response.code] or (response.success and "Operacao concluida." or "Operacao recusada pelo servidor.")
    self:setStatus(message)
    BetaAdminOperations:onOperationResult(response)
    if response.success then
        local permissionsChanged = response.action == "set_account_type" or response.action == "set_group"
            or response.action == "grant_capability" or response.action == "revoke_capability"
        if permissionsChanged then
            self.userReselectName = self.selectedUser and self.selectedUser.name or nil
            self:requestSnapshot()
        end
    end
end

function GameBetaAdmin:updateUI()
    if not self.ui then
        return
    end
    local role = self.snapshot and (ROLE_NAMES[self.snapshot.accountType] or tostring(self.snapshot.accountType)) or "aguardando servidor"
    local groupId = self.snapshot and tostring(self.snapshot.groupType) or "-"
    local storeStatus = self.snapshot and (self.snapshot.capabilityStoreAvailable and "disponivel" or "indisponivel") or "-"
    setWidgetText(self.ui:recursiveGetChildById("accessLabel"), string.format("Conta: %s  |  Grupo do personagem: %s  |  Permissoes beta: %s", role, groupId, storeStatus))
    setWidgetText(self.ui:recursiveGetChildById("statusLabel"), self.status)
    self:updateVisibility()
    self:renderActionList()
    self:updateItemPreview()
    self:updateMonsterPreview()
    self:updateAdminButton()
end
