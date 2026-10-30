local API_CONTRACT_VERSION = 1
local FEEDBACK_CAPABILITY = "beta.feedback.triage"
local PAGE_SIZE = 25
local REQUEST_KINDS = { "list", "detail", "update" }

local CATEGORY_LABELS = {
    bug = "Bug",
    gameplay = "Gameplay",
    usability = "Usabilidade",
    other = "Outro",
}

local STATUS_LABELS = {
    new = "Novo",
    investigating = "Em investigacao",
    resolved = "Resolvido",
}
local LOCAL_FIXTURE_DESCRIPTION = "Fixture sintetica: a porta da arena nao fecha depois do teste de grupo."
    .. "\n\nPassos: entrar na arena, finalizar o duelo e sair pelo portao norte."
local LOCAL_FIXTURE_UPDATED_AT = "2026-10-22T04:30:00Z"

BetaAdminFeedback = {
    controller = nil,
    ui = nil,
    authorized = false,
    localTestMode = false,
    feedback = {},
    selectedId = nil,
    cursor = nil,
    hasMore = false,
    filters = "",
    requestSerials = {},
    operations = {},
}

local function setText(widget, value)
    if widget then
        widget:setText(tostring(value or ""))
    end
end

local function getOptionData(widget)
    local option = widget and widget:getCurrentOption()
    return option and option.data or nil
end

local function encodeQueryValue(value)
    return tostring(value):gsub("([^%w%-_%.~])", function(character)
        return string.format("%%%02X", character:byte())
    end)
end

local function isUtcTimestamp(value)
    if value == "" then
        return true
    end
    if type(value) ~= "string" or not value:match("^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$") then
        return false
    end
    local year, month, day, hour, minute, second = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
    return tonumber(year) >= 2000 and tonumber(month) >= 1 and tonumber(month) <= 12
        and tonumber(day) >= 1 and tonumber(day) <= 31 and tonumber(hour) <= 23
        and tonumber(minute) <= 59 and tonumber(second) <= 59
end

local function feedbackApiRoot()
    if type(G) ~= "table" or type(G.host) ~= "string"
        or not G.host:match("^https://[^/]+/beta/v1/login$") then
        return nil, "endpoint"
    end
    if type(G.sessionKey) ~= "string" or #G.sessionKey ~= 46
        or not G.sessionKey:match("^b1%.[A-Za-z0-9_-]+$") then
        return nil, "session"
    end
    return G.host:gsub("/login$", "/feedback/admin"), G.sessionKey
end

function BetaAdminFeedback:init(controller, ui)
    self.controller = controller
    self.ui = ui
    self.feedback = {}
    self.selectedId = nil
    self.cursor = nil
    self.hasMore = false
    self.filters = ""
    self.authorized = false
    self.localTestMode = false
    self.requestSerials = {}
    self.operations = {}

    local category = self.ui:recursiveGetChildById("feedbackCategoryFilter")
    category:addOption("Todas as categorias", "all")
    for _, value in ipairs({ "bug", "gameplay", "usability", "other" }) do
        category:addOption(CATEGORY_LABELS[value], value)
    end
    category:setCurrentOptionByData("all")

    local status = self.ui:recursiveGetChildById("feedbackStatusFilter")
    status:addOption("Todos os estados", "all")
    for _, value in ipairs({ "new", "investigating", "resolved" }) do
        status:addOption(STATUS_LABELS[value], value)
    end
    status:setCurrentOptionByData("all")

    local statusSelection = self.ui:recursiveGetChildById("feedbackStatusSelection")
    for _, value in ipairs({ "new", "investigating", "resolved" }) do
        statusSelection:addOption(STATUS_LABELS[value], value)
    end
    statusSelection:setCurrentOptionByData("new")
    statusSelection.onOptionChange = function()
        self:updateStatusButton()
    end

    self:clearUi("A triagem privada aguarda autorizacao do servidor.")
    self.ui:hide()
end

function BetaAdminFeedback:isAuthorized()
    return self.authorized and self.controller ~= nil
        and self.controller.capabilities[FEEDBACK_CAPABILITY] == true
end

function BetaAdminFeedback:cancelRequests()
    for _, kind in ipairs(REQUEST_KINDS) do
        self.requestSerials[kind] = (self.requestSerials[kind] or 0) + 1
    end
    for operationId in pairs(self.operations) do
        if HTTP and HTTP.cancel then
            HTTP.cancel(operationId)
        end
    end
    self.operations = {}
end

function BetaAdminFeedback:cancelKind(kind)
    self.requestSerials[kind] = (self.requestSerials[kind] or 0) + 1
    for operationId, operationKind in pairs(self.operations) do
        if operationKind == kind then
            if HTTP and HTTP.cancel then
                HTTP.cancel(operationId)
            end
            self.operations[operationId] = nil
        end
    end
end

function BetaAdminFeedback:clearUi(message)
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    self.ui:recursiveGetChildById("feedbackResults"):destroyChildren()
    self.ui:recursiveGetChildById("feedbackDescription"):setText("")
    self.ui:recursiveGetChildById("feedbackStatusSelection"):setCurrentOptionByData("new")
    self.ui:recursiveGetChildById("feedbackStatusSelection"):setEnabled(false)
    self.ui:recursiveGetChildById("feedbackUpdateStatusButton"):setEnabled(false)
    self.ui:recursiveGetChildById("feedbackLoadMoreButton"):setEnabled(false)
    setText(self.ui:recursiveGetChildById("feedbackTitle"), "Selecione um relato.")
    setText(self.ui:recursiveGetChildById("feedbackMetadata"), "")
    setText(self.ui:recursiveGetChildById("feedbackListStatus"), message or "")
    setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), "")
end

function BetaAdminFeedback:setAuthorized(authorized)
    authorized = authorized == true
    if self.authorized == authorized then
        return
    end
    self.authorized = authorized
    if not authorized then
        self:cancelRequests()
        self.feedback = {}
        self.selectedId = nil
        self.cursor = nil
        self.hasMore = false
        self:clearUi("Seu perfil nao tem a permissao beta.feedback.triage.")
        return
    end
    if self.localTestMode then
        self:loadLocalFixture()
    end
end

function BetaAdminFeedback:onGameEnd()
    self:cancelRequests()
    self.authorized = false
    self.feedback = {}
    self.selectedId = nil
    self.cursor = nil
    self.hasMore = false
    self.filters = ""
    self.localTestMode = false
    if self.ui and not self.ui:isDestroyed() then
        self.ui:recursiveGetChildById("feedbackSinceFilter"):setText("")
        self.ui:recursiveGetChildById("feedbackUntilFilter"):setText("")
        self:clearUi("Sessao encerrada.")
        self.ui:hide()
    end
end

function BetaAdminFeedback:terminate()
    self:cancelRequests()
    if self.ui and not self.ui:isDestroyed() then
        self.ui:destroy()
    end
    self.controller = nil
    self.ui = nil
end

function BetaAdminFeedback:prepareLocalTestScreen()
    self.localTestMode = true
    self.authorized = true
    self:loadLocalFixture()
end

function BetaAdminFeedback:loadLocalFixture()
    self.feedback = {
        {
            id = 8402,
            category = "bug",
            releaseVersion = "0.5.0-beta.test",
            createdAtUtc = "2026-10-22T04:15:00Z",
            expiresAtUtc = "2027-01-20T04:15:00Z",
            status = "new",
            description = LOCAL_FIXTURE_DESCRIPTION,
        },
        {
            id = 8401,
            category = "gameplay",
            releaseVersion = "0.5.0-beta.test",
            createdAtUtc = "2026-10-21T19:40:00Z",
            expiresAtUtc = "2027-01-19T19:40:00Z",
            status = "investigating",
            description = LOCAL_FIXTURE_DESCRIPTION,
        },
        {
            id = 8400,
            category = "usability",
            releaseVersion = "0.5.0-beta.test",
            createdAtUtc = "2026-10-20T13:10:00Z",
            expiresAtUtc = "2027-01-18T13:10:00Z",
            status = "resolved",
            description = LOCAL_FIXTURE_DESCRIPTION,
        },
    }
    self.cursor = nil
    self.hasMore = false
    self:renderList(false)
    self:selectFeedback(8402)
    setText(self.ui:recursiveGetChildById("feedbackListStatus"), "3 relatos sinteticos; nenhum pedido foi enviado.")
end

function BetaAdminFeedback:readFilters()
    local category = getOptionData(self.ui:recursiveGetChildById("feedbackCategoryFilter")) or "all"
    local status = getOptionData(self.ui:recursiveGetChildById("feedbackStatusFilter")) or "all"
    local since = self.ui:recursiveGetChildById("feedbackSinceFilter"):getText():match("^%s*(.-)%s*$")
    local untilUtc = self.ui:recursiveGetChildById("feedbackUntilFilter"):getText():match("^%s*(.-)%s*$")
    if not isUtcTimestamp(since) or not isUtcTimestamp(untilUtc) then
        return nil, "Use datas UTC no formato AAAA-MM-DDTHH:MM:SSZ."
    end
    if since ~= "" and untilUtc ~= "" and since > untilUtc then
        return nil, "A data inicial precisa ser anterior a data final."
    end

    local parameters = { "pageSize=" .. PAGE_SIZE }
    if category ~= "all" then
        parameters[#parameters + 1] = "category=" .. encodeQueryValue(category)
    end
    if status ~= "all" then
        parameters[#parameters + 1] = "status=" .. encodeQueryValue(status)
    end
    if since ~= "" then
        parameters[#parameters + 1] = "sinceUtc=" .. encodeQueryValue(since)
    end
    if untilUtc ~= "" then
        parameters[#parameters + 1] = "untilUtc=" .. encodeQueryValue(untilUtc)
    end
    return table.concat(parameters, "&")
end

function BetaAdminFeedback:request(kind, url, data, callback)
    local apiRoot, tokenOrError = feedbackApiRoot()
    if not apiRoot then
        callback(nil, tokenOrError == "session" and "invalid_session" or "beta_endpoint_unavailable")
        return
    end
    if not self:isAuthorized() then
        callback(nil, "forbidden")
        return
    end

    self.requestSerials[kind] = (self.requestSerials[kind] or 0) + 1
    local serial = self.requestSerials[kind]
    local operationId
    local responseHandled = false
    local function onResponse(response, err)
        if responseHandled then
            return
        end
        responseHandled = true
        if operationId then
            self.operations[operationId] = nil
            if HTTP and HTTP.operations then
                HTTP.operations[operationId] = nil
            end
        end
        if not self.ui or self.ui:isDestroyed() or self.requestSerials[kind] ~= serial then
            return
        end
        callback(response, err)
    end

    local ok, requestId = pcall(function()
        if kind == "update" then
            return HTTP.postWithBearer(url, data, tokenOrError, onResponse)
        end
        return HTTP.getJSONWithBearer(url, tokenOrError, onResponse)
    end)
    operationId = requestId
    if not ok or type(operationId) ~= "number" or operationId < 0 then
        if type(HTTP) == "table" and type(operationId) == "number" and HTTP.operations then
            HTTP.operations[operationId] = nil
        end
        onResponse(nil, "secure_request_unavailable")
        return
    end
    self.operations[operationId] = kind
end

function BetaAdminFeedback:handleRequestError(err)
    local statusCode = type(err) == "string" and tonumber(err:match("^http_status::(%d%d%d)")) or nil
    if statusCode == 401 then
        self:cancelRequests()
        self.feedback = {}
        self.selectedId = nil
        self:clearUi("A sessao beta expirou. Entre novamente para reabrir a triagem.")
    elseif statusCode == 403 or err == "forbidden" then
        self:setAuthorized(false)
        if self.controller then
            self.controller:requestSnapshot()
        end
    elseif statusCode == 503 then
        setText(self.ui:recursiveGetChildById("feedbackListStatus"), "A triagem esta temporariamente indisponivel. Tente novamente.")
        setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), "Servico indisponivel.")
    elseif statusCode == 400 then
        setText(self.ui:recursiveGetChildById("feedbackListStatus"), "Filtro invalido. Revise categoria, estado e datas UTC.")
    elseif statusCode == 404 then
        setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), "Este relato expirou ou foi removido.")
    else
        setText(self.ui:recursiveGetChildById("feedbackListStatus"), "Nao foi possivel conectar a triagem. Verifique a conexao e tente novamente.")
    end
end

function BetaAdminFeedback:loadFeedback(append, preserveSelection)
    if self.localTestMode then
        self:loadLocalFixture()
        return
    end
    if not self:isAuthorized() then
        setText(self.ui:recursiveGetChildById("feedbackListStatus"), "A triagem requer a capability beta.feedback.triage.")
        return
    end

    local filters, filterError = self:readFilters()
    if not filters then
        setText(self.ui:recursiveGetChildById("feedbackListStatus"), filterError)
        return
    end
    if append then
        if not self.cursor then
            return
        end
    else
        self:cancelKind("list")
        self:cancelKind("detail")
        self.feedback = {}
        self.selectedId = preserveSelection
        self.cursor = nil
        self.hasMore = false
        self:renderList(false)
        self:renderDetail(nil)
        self.filters = filters
    end
    local query = append and self.filters or filters
    if append then
        query = query .. "&beforeId=" .. self.cursor
    end
    setText(self.ui:recursiveGetChildById("feedbackListStatus"), append and "Carregando mais relatos..." or "Carregando relatos...")
    local url = feedbackApiRoot()
    if not url then
        self:handleRequestError("beta_endpoint_unavailable")
        return
    end
    self:request("list", url .. "?" .. query, nil, function(response, err)
        if err or type(response) ~= "table" then
            self:handleRequestError(err or "invalid_response")
            return
        end
        if response.contractVersion ~= API_CONTRACT_VERSION or type(response.feedback) ~= "table" then
            self:handleRequestError("invalid_response")
            return
        end
        local entries = {}
        for _, item in ipairs(response.feedback) do
            if type(item) ~= "table" or type(item.id) ~= "number" or type(item.category) ~= "string"
                or type(item.releaseVersion) ~= "string" or type(item.createdAtUtc) ~= "string"
                or type(item.status) ~= "string" or not STATUS_LABELS[item.status]
                or not CATEGORY_LABELS[item.category] then
                self:handleRequestError("invalid_response")
                return
            end
            entries[#entries + 1] = item
        end
        if not append then
            self.feedback = {}
        end
        for _, item in ipairs(entries) do
            self.feedback[#self.feedback + 1] = item
        end
        self.cursor = type(response.nextBeforeId) == "number" and response.nextBeforeId or nil
        self.hasMore = self.cursor ~= nil
        self:renderList(append == true)
        if self.selectedId then
            self:selectFeedback(self.selectedId)
        end
        setText(self.ui:recursiveGetChildById("feedbackListStatus"), #self.feedback == 0
            and "Nenhum relato ativo corresponde aos filtros."
            or string.format("%d relato(s) carregado(s)%s.", #self.feedback, self.hasMore and "; ha mais resultados" or ""))
    end)
end

function BetaAdminFeedback:loadMore()
    if self.hasMore then
        self:loadFeedback(true)
    end
end

function BetaAdminFeedback:renderList(append)
    local list = self.ui:recursiveGetChildById("feedbackResults")
    if not append then
        list:destroyChildren()
    end
    for _, item in ipairs(self.feedback) do
        if not append or not item.rowWidget then
            local row = g_ui.createWidget("BetaAdminFeedbackRow", list)
            row.feedbackId = item.id
            setText(row:getChildById("feedbackCategory"), CATEGORY_LABELS[item.category] or item.category)
            setText(row:getChildById("feedbackSummary"), string.format("#%d  |  %s  |  %s", item.id,
                STATUS_LABELS[item.status] or item.status, item.createdAtUtc))
            row:setOn(item.id == self.selectedId)
            row.onClick = function()
                self:selectFeedback(item.id)
            end
            item.rowWidget = row
        end
    end
    self.ui:recursiveGetChildById("feedbackLoadMoreButton"):setEnabled(self.hasMore)
end

function BetaAdminFeedback:selectFeedback(feedbackId)
    if not self:isAuthorized() or type(feedbackId) ~= "number" then
        return
    end
    self.selectedId = feedbackId
    for _, item in ipairs(self.feedback) do
        if item.rowWidget then
            item.rowWidget:setOn(item.id == feedbackId)
        end
        if item.id == feedbackId then
            self:renderDetail(item)
            break
        end
    end
    if self.localTestMode then
        return
    end
    self:cancelKind("detail")
    setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), "Carregando relato...")
    local url = feedbackApiRoot()
    if not url then
        self:handleRequestError("beta_endpoint_unavailable")
        return
    end
    self:request("detail", url .. "/" .. feedbackId, nil, function(response, err)
        if err or type(response) ~= "table" then
            self:handleRequestError(err or "invalid_response")
            return
        end
        local item = response.feedback
        if response.contractVersion ~= API_CONTRACT_VERSION or type(item) ~= "table"
            or item.id ~= feedbackId or type(item.description) ~= "string"
            or not STATUS_LABELS[item.status] or not CATEGORY_LABELS[item.category] then
            self:handleRequestError("invalid_response")
            return
        end
        self:renderDetail(item)
    end)
end

function BetaAdminFeedback:renderDetail(item)
    local description = self.ui:recursiveGetChildById("feedbackDescription")
    local statusSelection = self.ui:recursiveGetChildById("feedbackStatusSelection")
    if not item then
        setText(self.ui:recursiveGetChildById("feedbackTitle"), "Selecione um relato.")
        setText(self.ui:recursiveGetChildById("feedbackMetadata"), "")
        setText(description, "")
        setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), "")
        statusSelection:setEnabled(false)
        self:updateStatusButton()
        return
    end
    setText(self.ui:recursiveGetChildById("feedbackTitle"), string.format("Relato #%d", item.id))
    setText(self.ui:recursiveGetChildById("feedbackMetadata"), string.format("%s  |  %s  |  %s  |  %s",
        CATEGORY_LABELS[item.category] or item.category, item.releaseVersion,
        STATUS_LABELS[item.status] or item.status, item.createdAtUtc))
    setText(description, item.description or "Conteudo detalhado nao carregado.")
    setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), item.updatedAtUtc
        and ("Atualizado em " .. item.updatedAtUtc) or "Sem alteracoes de status.")
    statusSelection:setCurrentOptionByData(item.status)
    statusSelection:setEnabled(self:isAuthorized())
    self:updateStatusButton()
end

function BetaAdminFeedback:updateStatusButton()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    local selectedStatus = getOptionData(self.ui:recursiveGetChildById("feedbackStatusSelection"))
    local currentStatus
    for _, item in ipairs(self.feedback) do
        if item.id == self.selectedId then
            currentStatus = item.status
            break
        end
    end
    self.ui:recursiveGetChildById("feedbackUpdateStatusButton"):setEnabled(
        self:isAuthorized() and self.selectedId ~= nil and selectedStatus ~= nil and selectedStatus ~= currentStatus)
end

function BetaAdminFeedback:confirmStatusUpdate()
    if not self:isAuthorized() or type(self.selectedId) ~= "number" then
        return
    end
    local newStatus = getOptionData(self.ui:recursiveGetChildById("feedbackStatusSelection"))
    if not STATUS_LABELS[newStatus] then
        return
    end
    local oldStatus
    for _, item in ipairs(self.feedback) do
        if item.id == self.selectedId then
            oldStatus = item.status
            break
        end
    end
    if not oldStatus or oldStatus == newStatus then
        return
    end
    local feedbackId = self.selectedId
    self.controller:displayConfirmation("Confirmar triagem", string.format("Relato #%d: %s -> %s.", feedbackId,
        STATUS_LABELS[oldStatus], STATUS_LABELS[newStatus]), "Cancelar", "Salvar estado", function()
            self:updateStatus(feedbackId, newStatus)
        end)
end

function BetaAdminFeedback:updateStatus(feedbackId, newStatus)
    if self.localTestMode then
        for _, item in ipairs(self.feedback) do
            if item.id == feedbackId then
                item.status = newStatus
                item.updatedAtUtc = LOCAL_FIXTURE_UPDATED_AT
                self:renderList(false)
                self:selectFeedback(feedbackId)
                setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), "Estado alterado apenas na fixture local.")
                return
            end
        end
        return
    end

    local url = feedbackApiRoot()
    if not url then
        self:handleRequestError("beta_endpoint_unavailable")
        return
    end
    setText(self.ui:recursiveGetChildById("feedbackDetailStatus"), "Salvando estado...")
    self:request("update", url .. "/" .. feedbackId, {
        contractVersion = API_CONTRACT_VERSION,
        status = newStatus,
    }, function(response, err)
        if not err and type(response) == "string" then
            local ok, decoded = pcall(json.decode, response)
            response = ok and decoded or nil
        end
        if err or type(response) ~= "table" then
            self:handleRequestError(err or "invalid_response")
            return
        end
        if response.contractVersion ~= API_CONTRACT_VERSION or response.feedbackId ~= feedbackId
            or response.status ~= newStatus then
            self:handleRequestError("invalid_response")
            return
        end
        for _, item in ipairs(self.feedback) do
            if item.id == feedbackId then
                item.status = newStatus
                break
            end
        end
        self:renderList(false)
        self:loadFeedback(false, feedbackId)
    end)
end

function BetaAdminFeedback:resetFilters()
    self.ui:recursiveGetChildById("feedbackCategoryFilter"):setCurrentOptionByData("all")
    self.ui:recursiveGetChildById("feedbackStatusFilter"):setCurrentOptionByData("all")
    self.ui:recursiveGetChildById("feedbackSinceFilter"):setText("")
    self.ui:recursiveGetChildById("feedbackUntilFilter"):setText("")
    self:loadFeedback(false)
end
