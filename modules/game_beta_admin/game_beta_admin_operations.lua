local CAPABILITY_COMPENSATE = "beta.compensate"
local CAPABILITY_ELEVATION_REQUEST = "beta.elevation.request"
local CAPABILITY_ITEMS = "beta.test.items"
local CAPABILITY_MONSTERS = "beta.test.monsters"

local ELEVATION_CAPABILITIES = {
    { id = CAPABILITY_ITEMS, label = "Teste de itens" },
    { id = CAPABILITY_MONSTERS, label = "Teste de monstros" },
}

local ELEVATION_STATUS_LABELS = {
    pending = "Aguardando aprovacao",
    active = "Ativa",
    revoked = "Revogada",
    expired = "Expirada",
    denied = "Recusada",
}

BetaAdminOperations = {
    controller = nil,
    ui = nil,
    snapshot = nil,
    canCompensate = false,
    canRequestElevation = false,
    canApproveElevation = false,
    localTestMode = false,
    elevationRequests = {},
}

local function trim(value)
    return (tostring(value or "")):match("^%s*(.-)%s*$")
end

local function getText(ui, id)
    local widget = ui and ui:recursiveGetChildById(id)
    return widget and trim(widget:getText()) or ""
end

local function validReason(reason)
	return #reason >= 12 and #reason <= 256 and not reason:find('[%z\1-\31\\"]')
end

local function validTicket(ticket)
    return #ticket >= 3 and #ticket <= 64 and ticket:match("^[%w._/-]+$") ~= nil
end

local function getSelectedData(widget)
    local option = widget and widget:getCurrentOption()
    return option and option.data or nil
end

function BetaAdminOperations:init(controller, ui)
    self.controller = controller
    self.ui = ui
    self.snapshot = nil
    self.elevationRequests = {}
    self.canCompensate = false
    self.canRequestElevation = false
    self.canApproveElevation = false
    self.localTestMode = false

    self.ui:recursiveGetChildById("compensationTarget").onTextChange = function()
        self:updatePreview()
    end
    self.ui:recursiveGetChildById("compensationAmount").onTextChange = function()
        self:updatePreview()
    end
    self.ui:recursiveGetChildById("compensationReason").onTextChange = function()
        self:updatePreview()
    end
    self.ui:recursiveGetChildById("compensationTicket").onTextChange = function()
        self:updatePreview()
    end
    self.ui:recursiveGetChildById("elevationCapability"):clearOptions()
    for _, option in ipairs(ELEVATION_CAPABILITIES) do
        self.ui:recursiveGetChildById("elevationCapability"):addOption(option.label, option.id)
    end
    self.ui:recursiveGetChildById("elevationCapability"):setCurrentOptionByData(CAPABILITY_ITEMS)
    self.ui:recursiveGetChildById("elevationDuration"):clearOptions()
    self.ui:hide()
    self:updatePreview()
end

function BetaAdminOperations:selfTest()
    local errors = {}
    local requiredWidgets = {
        "compensationTarget", "compensationAmount", "compensationReason", "compensationTicket",
        "compensationPreview", "compensationConfirmButton", "compensationStatus",
        "elevationCapability", "elevationDuration", "elevationReason", "elevationTicket",
        "elevationRequestButton", "elevationRefreshButton", "elevationListStatus", "elevationRequests",
    }
    for _, id in ipairs(requiredWidgets) do
        if not self.ui or not self.ui:recursiveGetChildById(id) then
            errors[#errors + 1] = "controle ausente: " .. id
        end
    end
    if #ELEVATION_CAPABILITIES ~= 2
        or ELEVATION_CAPABILITIES[1].id ~= CAPABILITY_ITEMS
        or ELEVATION_CAPABILITIES[2].id ~= CAPABILITY_MONSTERS then
        errors[#errors + 1] = "escopos de elevacao fora da allowlist"
    end
    if not validReason("Revisar perda de quest") or not validTicket("BUG-538")
		or validReason("curto") or validReason('Validar "item" perdido') or validTicket("BUG 538") then
        errors[#errors + 1] = "validacao de motivo/ticket divergente"
    end
    local originalUi = self.ui
    local elevationListMessage
    self.ui = {
        isDestroyed = function() return false end,
        recursiveGetChildById = function(_, id)
            if id == "elevationListStatus" then
                return { setText = function(_, message) elevationListMessage = message end }
            end
        end,
    }
    self:onOperationResult({ action = "list_elevations", success = false, code = "audit_unavailable" })
    self.ui = originalUi
    if elevationListMessage ~= "A trilha de auditoria esta indisponivel; nenhuma alteracao foi autorizada." then
        errors[#errors + 1] = "falha ao listar elevacoes nao foi exibida na pagina de operacoes"
    end
    return #errors == 0, table.concat(errors, "; ")
end

function BetaAdminOperations:setSnapshot(snapshot)
    self.snapshot = snapshot
    self.canCompensate = snapshot ~= nil and snapshot.canCompensate == true
    self.canRequestElevation = snapshot ~= nil and snapshot.canRequestElevation == true
    self.canApproveElevation = snapshot ~= nil and snapshot.canApproveElevation == true

    if not self.ui or self.ui:isDestroyed() then
        return
    end

    local compensationPanel = self.ui:recursiveGetChildById("compensationPanel")
    local elevationPanel = self.ui:recursiveGetChildById("elevationPanel")
    compensationPanel:setVisible(self.canCompensate)
    elevationPanel:setVisible(self.canRequestElevation or self.canApproveElevation)

    local maxGold = tonumber(snapshot and snapshot.compensationMaxGold) or 0
    local dailyMax = tonumber(snapshot and snapshot.compensationDailyMaxGold) or 0
    local maxMinutes = tonumber(snapshot and snapshot.elevationMaxMinutes) or 0
    self.ui:recursiveGetChildById("compensationScope"):setText(
        string.format("Somente credito positivo no banco de jogador online. Limite: %d gp por operacao e %d gp por CM/dia UTC; motivo e ticket obrigatorios.", maxGold, dailyMax))
    self.ui:recursiveGetChildById("elevationScope"):setText(
        string.format("Apenas teste de itens/monstros; aprovacao independente de God; Group e AccountType nao mudam. Maximo configurado: %d min.", maxMinutes))

    local duration = self.ui:recursiveGetChildById("elevationDuration")
    duration:clearOptions()
    local added = {}
    for _, minutes in ipairs({ 5, 15, 30, maxMinutes }) do
        if minutes > 0 and minutes <= maxMinutes and not added[minutes] then
            duration:addOption(tostring(minutes) .. " min", minutes)
            added[minutes] = true
        end
    end
    if maxMinutes > 0 and not added[maxMinutes] then
        duration:addOption(tostring(maxMinutes) .. " min", maxMinutes)
    end
    if maxMinutes > 0 then
        duration:setCurrentOptionByData(math.min(15, maxMinutes))
    end

	local requestControls = {
		"elevationCapabilityLabel", "elevationCapability", "elevationDurationLabel", "elevationDuration",
		"elevationRequestButton",
	}
    for _, id in ipairs(requestControls) do
        self.ui:recursiveGetChildById(id):setVisible(self.canRequestElevation)
    end
	local decisionControls = { "elevationReasonLabel", "elevationReason", "elevationTicketLabel", "elevationTicket" }
	for _, id in ipairs(decisionControls) do
		self.ui:recursiveGetChildById(id):setVisible(self.canRequestElevation or self.canApproveElevation)
	end
    self.ui:recursiveGetChildById("elevationRefreshButton"):setEnabled(self.canRequestElevation or self.canApproveElevation)
    self:updatePreview()
    self:renderElevationRequests()
end

function BetaAdminOperations:prepareLocalTestScreen(screen)
    self.localTestMode = screen == "beta-operations-cm" or screen == "beta-operations-requester"
        or screen == "beta-operations-god"
    if not self.localTestMode then
        return
    end
    local snapshot = {
        canCompensate = screen == "beta-operations-cm",
        canRequestElevation = screen == "beta-operations-requester",
        canApproveElevation = screen == "beta-operations-god",
        compensationMaxGold = 10000,
        compensationDailyMaxGold = 50000,
        elevationMaxMinutes = 30,
    }
    self:setSnapshot(snapshot)
    self.elevationRequests = {
        {
            id = 6401,
            requesterName = "T538 Developer QA",
            capability = CAPABILITY_ITEMS,
            reason = "Validar restauracao de item de quest.",
            ticketReference = "BUG-538",
            status = screen == "beta-operations-god" and "pending" or "active",
            durationMinutes = 15,
            expiresAt = screen == "beta-operations-god" and "" or "2026-10-27 21:45:00",
        },
    }
    self:renderElevationRequests()
end

function BetaAdminOperations:setCompensationTarget(name)
    if not self.canCompensate or not self.ui or self.ui:isDestroyed() then
        return
    end
    self.ui:recursiveGetChildById("compensationTarget"):setText(tostring(name or ""))
    self:updatePreview()
end

function BetaAdminOperations:isAuthorized()
    return self.controller ~= nil and (self.canCompensate or self.canRequestElevation or self.canApproveElevation)
end

function BetaAdminOperations:onGameEnd()
    self.snapshot = nil
    self.canCompensate = false
    self.canRequestElevation = false
    self.canApproveElevation = false
    self.localTestMode = false
    self.elevationRequests = {}
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    self.ui:recursiveGetChildById("compensationTarget"):setText("")
    self.ui:recursiveGetChildById("compensationAmount"):setText("1")
    self.ui:recursiveGetChildById("compensationReason"):setText("")
    self.ui:recursiveGetChildById("compensationTicket"):setText("")
    self.ui:recursiveGetChildById("elevationReason"):setText("")
    self.ui:recursiveGetChildById("elevationTicket"):setText("")
    self.ui:recursiveGetChildById("elevationRequests"):destroyChildren()
    self.ui:recursiveGetChildById("compensationStatus"):setText("")
    self.ui:recursiveGetChildById("elevationListStatus"):setText("Sessao encerrada.")
    self:updatePreview()
    self.ui:hide()
end

function BetaAdminOperations:terminate()
    if self.ui and not self.ui:isDestroyed() then
        self.ui:destroy()
    end
    self.controller = nil
    self.ui = nil
    self.elevationRequests = {}
end

function BetaAdminOperations:updatePreview()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    local target = getText(self.ui, "compensationTarget")
    local amountText = getText(self.ui, "compensationAmount")
    local amount = tonumber(amountText)
    local reason = getText(self.ui, "compensationReason")
    local ticket = getText(self.ui, "compensationTicket")
    local maxGold = tonumber(self.snapshot and self.snapshot.compensationMaxGold) or 0
    local dailyMax = tonumber(self.snapshot and self.snapshot.compensationDailyMaxGold) or 0
    local validAmount = amount and amount > 0 and amount % 1 == 0 and amount <= maxGold
    local valid = self.canCompensate and target ~= "" and #target <= 48 and validAmount
        and validReason(reason) and validTicket(ticket) and maxGold > 0 and dailyMax > 0
    if valid then
        self.ui:recursiveGetChildById("compensationPreview"):setText(
            string.format("Credito bancario: %d gp para %s. Limite da operacao: %d gp; teto diario do CM: %d gp. Motivo: %s. Referencia: %s.", amount, target, maxGold, dailyMax, reason, ticket))
    else
        self.ui:recursiveGetChildById("compensationPreview"):setText(
            "Informe personagem online, valor dentro do limite, motivo com 12 a 256 caracteres e referencia de bug/ticket.")
    end
    self.ui:recursiveGetChildById("compensationConfirmButton"):setEnabled(valid == true)

    local selectedDuration = tonumber(getSelectedData(self.ui:recursiveGetChildById("elevationDuration")))
    local maxMinutes = tonumber(self.snapshot and self.snapshot.elevationMaxMinutes) or 0
    local elevationReason = getText(self.ui, "elevationReason")
    local elevationTicket = getText(self.ui, "elevationTicket")
    local elevationValid = self.canRequestElevation and selectedDuration and selectedDuration > 0
        and selectedDuration <= maxMinutes and validReason(elevationReason) and validTicket(elevationTicket)
    self.ui:recursiveGetChildById("elevationRequestButton"):setEnabled(elevationValid == true)
end

function BetaAdminOperations:submitCompensation()
    if not self.canCompensate or not self.ui or self.ui:isDestroyed() then
        return
    end
    self:updatePreview()
    if not self.ui:recursiveGetChildById("compensationConfirmButton"):isEnabled() then
        return
    end
    local target = getText(self.ui, "compensationTarget")
    local amount = tonumber(getText(self.ui, "compensationAmount"))
    local reason = getText(self.ui, "compensationReason")
    local ticket = getText(self.ui, "compensationTicket")
    local preview = self.ui:recursiveGetChildById("compensationPreview"):getText()
    self.controller:displayConfirmation("Confirmar compensacao do CM", preview,
        "Voltar", "Creditar", function()
            if self.localTestMode then
                self.ui:recursiveGetChildById("compensationStatus"):setText("QA local: nenhuma operacao foi enviada.")
                return
            end
            self.controller:sendRequest("compensate_bank", {
                targetName = target,
                amount = amount,
                reason = reason,
                ticketReference = ticket,
            })
            self.ui:recursiveGetChildById("compensationStatus"):setText("Pedido enviado ao Canary para autorizacao e auditoria.")
        end)
end

function BetaAdminOperations:requestElevation()
    self:updatePreview()
    if not self.canRequestElevation or not self.ui:recursiveGetChildById("elevationRequestButton"):isEnabled() then
        return
    end
    local capability = getSelectedData(self.ui:recursiveGetChildById("elevationCapability"))
    local durationMinutes = tonumber(getSelectedData(self.ui:recursiveGetChildById("elevationDuration")))
    local reason = getText(self.ui, "elevationReason")
    local ticketReference = getText(self.ui, "elevationTicket")
    local label = capability == CAPABILITY_ITEMS and "Teste de itens" or "Teste de monstros"
    local preview = string.format("Solicitar %s para sua propria conta por %d minutos. Motivo: %s. Referencia: %s. AccountType e Group nao serao alterados; um God de outra conta precisa aprovar.",
        label, durationMinutes, reason, ticketReference)
    self.controller:displayConfirmation("Confirmar elevacao temporaria", preview,
        "Voltar", "Solicitar", function()
            if self.localTestMode then
                self.ui:recursiveGetChildById("elevationListStatus"):setText("QA local: nenhuma solicitacao foi enviada.")
                return
            end
            self.controller:sendRequest("request_elevation", {
                capability = capability,
                durationMinutes = durationMinutes,
                reason = reason,
                ticketReference = ticketReference,
            })
            self.ui:recursiveGetChildById("elevationListStatus"):setText("Solicitacao enviada; aguarda aprovacao independente.")
        end)
end

function BetaAdminOperations:refreshElevations()
    if not self:isAuthorized() or (not self.canRequestElevation and not self.canApproveElevation) then
        return
    end
    if self.localTestMode then
        self.ui:recursiveGetChildById("elevationListStatus"):setText("Fixture local sintetica; nenhuma consulta ao servidor.")
        self:renderElevationRequests()
        return
    end
    self.controller:sendRequest("list_elevations")
    self.ui:recursiveGetChildById("elevationListStatus"):setText("Consultando pedidos e prazos no Canary...")
end

function BetaAdminOperations:onElevationResponse(response)
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    if type(response.items) ~= "table" then
        self.ui:recursiveGetChildById("elevationListStatus"):setText("Resposta da lista de elevacoes invalida.")
        return
    end
    self.elevationRequests = response.items
    self.canApproveElevation = response.canApprove == true
    self.ui:recursiveGetChildById("elevationListStatus"):setText(string.format("%d pedido(s) nos ultimos 30 dias.", #response.items))
    self:renderElevationRequests()
end

function BetaAdminOperations:renderElevationRequests()
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    local list = self.ui:recursiveGetChildById("elevationRequests")
    list:destroyChildren()
    for _, request in ipairs(self.elevationRequests or {}) do
        local row = g_ui.createWidget("BetaAdminElevationRow", list)
        local status = ELEVATION_STATUS_LABELS[request.status] or request.status or "desconhecida"
        local capability = request.capability == CAPABILITY_ITEMS and "Teste de itens" or "Teste de monstros"
        local expires = request.expiresAt and request.expiresAt ~= "" and ("; expira " .. request.expiresAt) or ""
        row:getChildById("elevationSummary"):setText(string.format("#%d | %s | %s | %d min | %s | %s | %s%s",
            request.id, request.requesterName or "Conta sintetica", capability,
            tonumber(request.durationMinutes) or 0, status, request.ticketReference or "", request.reason or "", expires))
        local approve = row:getChildById("approveButton")
        local deny = row:getChildById("denyButton")
        local revoke = row:getChildById("revokeButton")
        local pending = request.status == "pending"
        local active = request.status == "active"
        approve:setVisible(self.canApproveElevation and pending)
        deny:setVisible(self.canApproveElevation and pending)
        revoke:setVisible(active and (self.canApproveElevation or self.canRequestElevation))
        approve.onClick = function()
            self:confirmElevationAction("approve_elevation", request)
        end
        deny.onClick = function()
            self:confirmElevationAction("deny_elevation", request)
        end
        revoke.onClick = function()
            self:confirmElevationAction("revoke_elevation", request)
        end
    end
end

function BetaAdminOperations:confirmElevationAction(action, request)
    if self.localTestMode then
        self.ui:recursiveGetChildById("elevationListStatus"):setText("QA local: nenhuma acao de aprovacao foi enviada.")
        return
    end
    local reason = getText(self.ui, "elevationReason")
    local ticketReference = getText(self.ui, "elevationTicket")
    if action ~= "approve_elevation" and (not validReason(reason) or not validTicket(ticketReference)) then
        self.ui:recursiveGetChildById("elevationListStatus"):setText("Para recusar ou revogar, informe motivo e referencia no formulario.")
        return
    end
    local labels = { approve_elevation = "aprovar", deny_elevation = "recusar", revoke_elevation = "revogar" }
    local explanation = string.format("%s a elevacao #%d de %s (%s).", labels[action], request.id,
        request.requesterName or "conta sintetica", request.capability)
    if action ~= "approve_elevation" then
        explanation = explanation .. " Motivo: " .. reason .. ". Referencia: " .. ticketReference .. "."
    else
        explanation = explanation .. " A capacidade e a validade solicitadas serao aplicadas exatamente como registradas."
    end
    self.controller:displayConfirmation("Confirmar decisao de elevacao", explanation,
        "Voltar", labels[action], function()
            local fields = { elevationId = request.id }
            if action ~= "approve_elevation" then
                fields.reason = reason
                fields.ticketReference = ticketReference
            end
            self.controller:sendRequest(action, fields)
            self.ui:recursiveGetChildById("elevationListStatus"):setText("Decisao enviada ao Canary para gravacao na trilha.")
        end)
end

function BetaAdminOperations:onOperationResult(response)
    local statuses = {
        compensation_applied = "Credito bancario aplicado e auditado.",
        compensation_disabled = "Compensacao desativada pela configuracao atual.",
        compensation_limit_exceeded = "O valor ultrapassa o limite por operacao.",
        daily_compensation_limit_exceeded = "O teto diario de compensacao deste CM seria ultrapassado.",
        balance_out_of_supported_range = "O saldo esta fora do intervalo seguro para a operacao.",
        balance_out_of_supported_range_or_stale = "O saldo mudou durante a operacao ou excede o intervalo seguro.",
        target_balance_unavailable = "Nao foi possivel confirmar o saldo persistido do personagem.",
        balance_update_failed = "O saldo nao foi atualizado; a operacao foi cancelada.",
        compensation_failed = "A compensacao nao foi aplicada.",
        self_compensation_denied = "A conta do CM nao pode receber a propria compensacao.",
        target_not_player_account = "A compensacao pode ser aplicada apenas a uma conta de jogador.",
        temporary_elevation_required = "Esse acesso so pode ser concedido por elevacao temporaria aprovada.",
        audit_unavailable = "A trilha de auditoria esta indisponivel; nenhuma alteracao foi autorizada.",
        reason_or_ticket_required = "Informe motivo e referencia validos antes de continuar.",
        elevation_requested = "Pedido de elevacao registrado; aguarda aprovacao de outra conta God.",
        elevation_approved = "Elevacao aprovada e com expiracao registrada.",
        elevation_denied = "Pedido recusado e auditado.",
        elevation_revoked = "Elevacao revogada e auditada.",
        elevation_not_pending = "O pedido nao esta mais pendente.",
        elevation_not_active = "A elevacao nao esta ativa ou ja expirou.",
        elevation_duration_exceeded = "A duracao ultrapassa o maximo configurado.",
        elevation_scope_not_allowed = "Esse escopo nao pode ser elevado temporariamente.",
        elevation_already_open = "Ja existe pedido pendente ou elevacao ativa para esse escopo.",
        elevation_no_longer_eligible = "O pedido expirou ou a capability ja esta ativa.",
        target_not_eligible = "A conta solicitante deixou de ser elegivel para elevacao.",
        independent_approval_required = "A aprovacao precisa vir de outra conta God.",
    }
    local message = statuses[response.code] or (response.success and "Operacao concluida." or "Operacao recusada pelo servidor.")
    if not self.ui or self.ui:isDestroyed() then
        return
    end
    if response.action == "compensate_bank" then
        self.ui:recursiveGetChildById("compensationStatus"):setText(message)
    elseif response.action == "request_elevation" or response.action == "approve_elevation"
        or response.action == "deny_elevation" or response.action == "revoke_elevation"
        or response.action == "list_elevations" then
        self.ui:recursiveGetChildById("elevationListStatus"):setText(message)
    else
        return
    end
    if response.success and (response.action == "request_elevation" or response.action == "approve_elevation"
        or response.action == "deny_elevation" or response.action == "revoke_elevation") then
        self:refreshElevations()
    end
end
