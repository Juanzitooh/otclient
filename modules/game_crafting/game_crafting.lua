local MAX_REQUEST_ID = 4294967295
local CATALOG_PAGE_SIZE = 10
local CATEGORIES = {
    { id = "alquimia", label = "Alquimia" },
    { id = "artesanato", label = "Artesanato" },
    { id = "culinaria", label = "Culinaria" },
    { id = "forja", label = "Forja" },
    { id = "joalheria", label = "Joalheria" },
}
local SKILL_LABELS = {
    [15] = "Coleta",
    [16] = "Mineracao",
    [17] = "Culinaria",
    [18] = "Forja",
    [19] = "Artesanato",
    [20] = "Alquimia",
    [21] = "Joalheria",
}
local CHARGED_OUTPUTS = { [3453] = true, [3456] = true, [3308] = true, [31327] = true, [17512] = true, [21351] = true }

local category_labels = {}
for _, category in ipairs(CATEGORIES) do
    category_labels[category.id] = category.label
end

local error_messages = {
    duplicate_request = "Este pedido ja foi processado.",
    request_id_out_of_sequence = "A sequencia do pedido foi rejeitada. Atualize o catalogo.",
    unknown_recipe = "Receita desconhecida.",
    station_unavailable = "A estacao necessaria nao esta proxima.",
    skill_too_low = "Nivel da skill insuficiente.",
    progression_unavailable = "A progressao desta skill nao esta disponivel.",
    missing_ingredients = "Voce nao tem os ingredientes necessarios.",
    insufficient_gold = "Voce nao tem Gold suficiente.",
    insufficient_soul = "Voce nao tem Soul suficiente.",
    inventory_full = "Nao ha espaco suficiente no inventario.",
    transaction_failed = "A operacao nao foi concluida; os itens foram restaurados.",
    rollback_failed = "Falha ao restaurar a operacao. Procure um administrador.",
}

local function split_fields(payload)
    local fields = {}
    for field in (payload .. "|"):gmatch("(.-)|") do
        fields[#fields + 1] = field
    end
    return fields
end

local function parse_integer(value, minimum, maximum)
    if type(value) ~= "string" or not value:match("^%d+$") then
        return nil
    end

    local number = tonumber(value)
    if not number or number < minimum or number > maximum or number % 1 ~= 0 or tostring(number) ~= value then
        return nil
    end
    return number
end

local function parse_percent(value)
    if type(value) ~= "string" or not value:match("^%d+%.?%d*$") then
        return nil
    end

    local number = tonumber(value)
    if not number or number < 0 or number > 100 or number ~= number or number == math.huge then
        return nil
    end
    return number
end

local function format_percent(value)
    if value % 1 == 0 then
        return tostring(math.floor(value))
    end
    return (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function get_item_name(item_id)
    local item_type = g_things.getThingType(item_id, ThingCategoryItem)
    if item_type then
        local name = item_type:getName()
        if name and name ~= "" then
            return name
        end
    end
    return "Item " .. tostring(item_id)
end

local function format_output(item_id, count)
    local name = get_item_name(item_id)
    if CHARGED_OUTPUTS[item_id] then
        return string.format("%s (1 item, %d cargas)", name, count)
    end
    return string.format("%s x%d", name, count)
end

local function parse_recipe(fields, index)
    local recipe = {
        recipeId = parse_integer(fields[index], 1, 65535),
        outputId = parse_integer(fields[index + 1], 1, 65535),
        outputCount = parse_integer(fields[index + 2], 1, 65535),
        skillId = parse_integer(fields[index + 3], 1, 65535),
        minimumLevel = parse_integer(fields[index + 4], 1, 65535),
        goldCost = parse_integer(fields[index + 5], 0, 4294967295),
        soulCost = parse_integer(fields[index + 6], 0, 65535),
        stationId = parse_integer(fields[index + 7], 1, 65535),
        materialCount = parse_integer(fields[index + 8], 1, #fields),
        ingredients = {},
    }

    if not recipe.recipeId or not recipe.outputId or not recipe.outputCount or not recipe.skillId
        or not recipe.minimumLevel or recipe.goldCost == nil or recipe.soulCost == nil
        or not recipe.stationId or not recipe.materialCount then
        return nil, index
    end

    index = index + 9
    if recipe.materialCount * 2 > #fields - index + 1 then
        return nil, index
    end

    for material_index = 1, recipe.materialCount do
        local ingredient = {
            itemId = parse_integer(fields[index], 1, 65535),
            count = parse_integer(fields[index + 1], 1, 65535),
        }
        if not ingredient.itemId or not ingredient.count then
            return nil, index
        end
        recipe.ingredients[material_index] = ingredient
        index = index + 2
    end

    return recipe, index
end

GameCrafting = Controller:new()
GameCrafting:setUI("game_crafting")
GameCrafting.category = "culinaria"
GameCrafting.page = 1
GameCrafting.totalRecords = 0
GameCrafting.catalogRecords = {}
GameCrafting.filteredRecords = {}
GameCrafting.records = {}
GameCrafting.searchQuery = ""
GameCrafting.skillStates = {}
GameCrafting.selectedRecipe = nil
GameCrafting.pendingRecipe = nil
GameCrafting.nextRequestId = nil
GameCrafting.pendingRequestId = nil
GameCrafting.pendingCatalogRequest = nil
GameCrafting.waitingForResult = false
GameCrafting.requestingCatalog = false
GameCrafting.needsCatalogSync = true
GameCrafting.status = "Aguardando conexao com o servidor."
GameCrafting.button = nil

function GameCrafting:onInit()
    local categoryBox = self.ui:getChildById("categoryBox")
    self.initializingCategories = true
    for _, category in ipairs(CATEGORIES) do
        categoryBox:addOption(category.label, category.id)
    end
    categoryBox:setCurrentOptionByData(self.category)
    self.initializingCategories = false
    self:updateUI()
end

function GameCrafting:onGameStart()
    if not self.button or self.button:isDestroyed() then
        self.button = modules.game_mainpanel.addToggleButton(
            "elementalCraftingButton",
            tr("Oficios"),
            "/images/options/button_skills",
            function()
                self:toggle()
            end,
            false,
            30
        )
    end

    self.nextRequestId = nil
    self.page = 1
    self.totalRecords = 0
    self.catalogRecords = {}
    self.filteredRecords = {}
    self.records = {}
    self.selectedRecipe = nil
    self.pendingRecipe = nil
    self.pendingRequestId = nil
    self.pendingCatalogRequest = nil
    self.skillStates = {}
    self.waitingForResult = false
    self.requestingCatalog = false
    self.needsCatalogSync = true
    self.status = "Sincronizando com o servidor..."
    self:updateUI()
    self:requestCatalog()

    if os.getenv("ELEMENTAL_LOCAL_TEST_SCREEN") == "crafting" then
        self:scheduleEvent(function()
            if g_game.isOnline() and self.ui and not self.ui:isDestroyed() then
                self.ui:show()
                self.ui:raise()
                self.ui:focus()
                if self.button then
                    self.button:setOn(true)
                end
                self:scheduleEvent(function()
                    if g_game.isOnline() and self.ui and not self.ui:isDestroyed() then
                        g_app.doScreenshot("crafting-current.png")
                    end
                end, 2500)
            end
        end, 1500)
    end
end

function GameCrafting:onGameEnd()
    self.records = {}
    self.catalogRecords = {}
    self.filteredRecords = {}
    self.totalRecords = 0
    self.selectedRecipe = nil
    self.pendingRecipe = nil
    self.skillStates = {}
    self.nextRequestId = nil
    self.pendingRequestId = nil
    self.pendingCatalogRequest = nil
    self.waitingForResult = false
    self.requestingCatalog = false
    self.needsCatalogSync = true
    self.status = "Desconectado do servidor."
    self:hide()
    self:updateUI()
end

function GameCrafting:onTerminate()
    if self.button and not self.button:isDestroyed() then
        self.button:destroy()
    end
    self.button = nil
end

function GameCrafting:onExtendedOpcode(opcode, buffer)
    if opcode ~= ExtendedIds.Elemental or type(buffer) ~= "string" then
        return
    end

    local fields = split_fields(buffer)
    if fields[1] ~= "v1" then
        return
    end

    if fields[2] == "catalog" then
        self:onCatalog(fields)
    elseif fields[2] == "result" then
        self:onResult(fields)
    elseif fields[2] == "error" and #fields == 3 then
        if self.requestingCatalog or self.waitingForResult then
            self:onServerError(fields[3])
        end
    end
end

function GameCrafting:onCatalog(fields)
    local pending = self.pendingCatalogRequest
    if not self.requestingCatalog or not pending or #fields < 7 then
        return
    end

    local page = parse_integer(fields[4], 1, 65535)
    local total = parse_integer(fields[5], 0, 65535)
    local record_count = parse_integer(fields[6], 0, CATALOG_PAGE_SIZE)
    local next_request_id = parse_integer(fields[7], 1, MAX_REQUEST_ID)
    if fields[3] ~= pending.category or page ~= pending.page
        or fields[3] ~= self.category or not total or not record_count or not next_request_id then
        self:onProtocolError("Catalogo recebido fora da solicitacao atual.")
        return
    end

    local page_count = math.max(1, math.ceil(total / CATALOG_PAGE_SIZE))
    local expected_records = math.max(0, math.min(CATALOG_PAGE_SIZE, total - (page - 1) * CATALOG_PAGE_SIZE))
    if page > page_count or record_count ~= expected_records or (total == 0 and page ~= 1) then
        self:onProtocolError("Paginacao do catalogo invalida.")
        return
    end

    if page > 1 and (total ~= self.totalRecords or fields[7] ~= self.nextRequestId) then
        self:onProtocolError("Catalogo alterado durante a consulta.")
        return
    end

    local records = {}
    local seen_recipe_ids = {}
    for _, recipe in ipairs(self.catalogRecords) do
        seen_recipe_ids[recipe.recipeId] = true
    end
    local index = 8
    for record_index = 1, record_count do
        local recipe, next_index = parse_recipe(fields, index)
        if not recipe or seen_recipe_ids[recipe.recipeId] then
            self:onProtocolError("Receita recebida com campos invalidos.")
            return
        end
        seen_recipe_ids[recipe.recipeId] = true
        records[record_index] = recipe
        index = next_index
    end

    if index ~= #fields + 1 then
        self:onProtocolError("Catalogo recebido com campos excedentes.")
        return
    end

    self.totalRecords = total
    for _, recipe in ipairs(records) do
        self.catalogRecords[#self.catalogRecords + 1] = recipe
    end
    self.nextRequestId = fields[7]
    self.pendingCatalogRequest = nil

    if #self.catalogRecords < total then
        self.status = string.format("Carregando receitas: %d de %d...", #self.catalogRecords, total)
        self:updateUI()
        self:requestServerPage(page + 1)
        return
    end

    self.pendingRequestId = nil
    self.waitingForResult = false
    self.requestingCatalog = false
    self.needsCatalogSync = false
    self.status = total == 0 and "Nenhuma receita liberada nesta categoria." or "Receitas recebidas do servidor."
    self:filterRecords()
end

function GameCrafting:onResult(fields)
    local request_id = parse_integer(fields[3], 1, MAX_REQUEST_ID)
    if not self.waitingForResult or not self.pendingRecipe or not request_id
        or not self.pendingRequestId or fields[3] ~= self.pendingRequestId then
        return
    end

    local recipe = self.pendingRecipe

    if fields[4] == "ok" then
        if #fields ~= 9 then
            self:onProtocolError("Resultado de crafting invalido.")
            return
        end
        local output_id = parse_integer(fields[5], 1, 65535)
        local output_count = parse_integer(fields[6], 1, 65535)
        local skill_level = parse_integer(fields[7], 0, 65535)
        local skill_percent = parse_percent(fields[8])
        local next_request_id = parse_integer(fields[9], 1, MAX_REQUEST_ID)
        if not output_id or not output_count or not skill_level or skill_percent == nil or not next_request_id then
            self:onProtocolError("Resultado de crafting invalido.")
            return
        end

        recipe.outputId = output_id
        recipe.outputCount = output_count
        recipe.skillLevel = skill_level
        recipe.skillPercent = skill_percent
        self.skillStates[recipe.skillId] = { level = skill_level, percent = skill_percent }
        self.nextRequestId = fields[9]
        if CHARGED_OUTPUTS[output_id] then
            self.status = string.format("Craft concluido: 1 item com %d cargas entregue.", output_count)
        else
            self.status = string.format("Craft concluido: %d item(ns) entregues.", output_count)
        end
    elseif fields[4] == "error" then
        if #fields ~= 8 then
            self:onProtocolError("Erro de crafting invalido.")
            return
        end
        local skill_level = parse_integer(fields[6], 0, 65535)
        local skill_percent = parse_percent(fields[7])
        local next_request_id = parse_integer(fields[8], 1, MAX_REQUEST_ID)
        if not skill_level or skill_percent == nil or not next_request_id then
            self:onProtocolError("Erro de crafting invalido.")
            return
        end

        recipe.skillLevel = skill_level
        recipe.skillPercent = skill_percent
        self.skillStates[recipe.skillId] = { level = skill_level, percent = skill_percent }
        self.nextRequestId = fields[8]
        self.status = error_messages[fields[5]] or ("Erro do servidor: " .. fields[5])
    else
        self:onProtocolError("Resultado de crafting invalido.")
        return
    end

    self.pendingRequestId = nil
    self.pendingRecipe = nil
    self.waitingForResult = false
    self.needsCatalogSync = false
    self:updateUI()
end

function GameCrafting:onServerError(error_code)
    self.page = 1
    self.totalRecords = 0
    self.catalogRecords = {}
    self.filteredRecords = {}
    self.records = {}
    self.selectedRecipe = nil
    self.pendingRecipe = nil
    self.pendingCatalogRequest = nil
    self.pendingRequestId = nil
    self.requestingCatalog = false
    self.waitingForResult = false
    self.nextRequestId = nil
    self.needsCatalogSync = true
    self.status = error_messages[error_code] or ("Erro do servidor: " .. error_code)
    self:updateUI()
end

function GameCrafting:onProtocolError(message)
    self.page = 1
    self.records = {}
    self.catalogRecords = {}
    self.filteredRecords = {}
    self.totalRecords = 0
    self.selectedRecipe = nil
    self.pendingRecipe = nil
    self.nextRequestId = nil
    self.pendingRequestId = nil
    self.pendingCatalogRequest = nil
    self.waitingForResult = false
    self.requestingCatalog = false
    self.needsCatalogSync = true
    self.status = message .. " Atualize o catalogo para continuar."
    self:updateUI()
end

function GameCrafting:onCategoryChange(category)
    if self.initializingCategories then
        return
    end
    if not category_labels[category] or category == self.category then
        return
    end

    self.category = category
    self.page = 1
    self.records = {}
    self.catalogRecords = {}
    self.filteredRecords = {}
    self.totalRecords = 0
    self.selectedRecipe = nil
    self.pendingRecipe = nil
    self.needsCatalogSync = true
    self.status = "Consultando categoria..."
    self:updateUI()
    self:requestCatalog()
end

function GameCrafting:requestServerPage(page)
    self.pendingCatalogRequest = { category = self.category, page = page }
    self:sendExtendedOpcode(ExtendedIds.Elemental, "v1|catalog|" .. self.category .. "|" .. tostring(page))
end

function GameCrafting:requestCatalog()
    if not g_game.isOnline() then
        self.status = "Entre no jogo para consultar o catalogo."
        self:updateUI()
        return
    end
    if self.waitingForResult or self.requestingCatalog then
        return
    end

    local protocol = g_game.getProtocolGame()
    if not protocol then
        self:onProtocolError("Conexao do jogo indisponivel.")
        return
    end

    self.page = 1
    self.records = {}
    self.catalogRecords = {}
    self.filteredRecords = {}
    self.totalRecords = 0
    self.selectedRecipe = nil
    self.pendingRecipe = nil
    self.nextRequestId = nil
    self.pendingRequestId = nil
    self.pendingCatalogRequest = nil
    self.waitingForResult = false
    self.requestingCatalog = true
    self.needsCatalogSync = true
    self.status = "Consultando o catalogo do servidor..."
    self:updateUI()
    self:requestServerPage(1)
end

function GameCrafting:refreshCatalog()
    self:requestCatalog()
end

function GameCrafting:previousPage()
    if self.page > 1 and not self.requestingCatalog and not self.waitingForResult then
        self.page = self.page - 1
        self:showPage()
    end
end

function GameCrafting:nextPage()
    if self.page < math.max(1, math.ceil(#self.filteredRecords / CATALOG_PAGE_SIZE))
        and not self.requestingCatalog and not self.waitingForResult then
        self.page = self.page + 1
        self:showPage()
    end
end

function GameCrafting:onSearchChange(query)
    if self.waitingForResult then
        return
    end
    self.searchQuery = query:lower():match("^%s*(.-)%s*$")
    self.page = 1
    if not self.requestingCatalog then
        self:filterRecords()
    end
end

function GameCrafting:filterRecords()
    self.filteredRecords = {}
    for _, recipe in ipairs(self.catalogRecords) do
        local name = get_item_name(recipe.outputId):lower()
        local skill = (SKILL_LABELS[recipe.skillId] or ""):lower()
        if self.searchQuery == "" or name:find(self.searchQuery, 1, true)
            or skill:find(self.searchQuery, 1, true)
            or tostring(recipe.recipeId):find(self.searchQuery, 1, true) then
            self.filteredRecords[#self.filteredRecords + 1] = recipe
        end
    end
    self:showPage()
end

function GameCrafting:showPage()
    local page_count = math.max(1, math.ceil(#self.filteredRecords / CATALOG_PAGE_SIZE))
    self.page = math.min(self.page, page_count)
    self.records = {}
    local first = (self.page - 1) * CATALOG_PAGE_SIZE + 1
    for index = first, math.min(first + CATALOG_PAGE_SIZE - 1, #self.filteredRecords) do
        self.records[#self.records + 1] = self.filteredRecords[index]
    end
    self.selectedRecipe = self.records[1]
    self:updateUI()
end

function GameCrafting:selectRecipe(recipe_id)
    if self.waitingForResult or self.requestingCatalog then
        return
    end
    for _, recipe in ipairs(self.records) do
        if recipe.recipeId == recipe_id then
            self.selectedRecipe = recipe
            self.status = "Receita selecionada."
            self:updateUI()
            return
        end
    end
end

function GameCrafting:craft()
    if not g_game.isOnline() or not self.selectedRecipe or not self.nextRequestId
        or self.needsCatalogSync or self.requestingCatalog then
        self.status = "Atualize o catalogo antes de solicitar o craft."
        self:updateUI()
        return
    end
    if self.waitingForResult then
        return
    end

    local protocol = g_game.getProtocolGame()
    if not protocol then
        self:onProtocolError("Conexao do jogo indisponivel.")
        return
    end

    self.pendingRequestId = self.nextRequestId
    self.pendingRecipe = self.selectedRecipe
    self.waitingForResult = true
    self.status = "Aguardando resposta do servidor..."
    self:updateUI()
    self:sendExtendedOpcode(
        ExtendedIds.Elemental,
        "v1|craft|" .. self.pendingRequestId .. "|" .. tostring(self.selectedRecipe.recipeId)
    )
end

function GameCrafting:onEconomicSkillUpdate(skill_id, level, percent)
    self.skillStates[skill_id] = { level = level, percent = percent }
    for _, recipe in ipairs(self.catalogRecords) do
        if recipe.skillId == skill_id then
            recipe.skillLevel = level
            recipe.skillPercent = percent
        end
    end
    self:updateUI()
end

function GameCrafting:toggle()
    if not self.ui then
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

function GameCrafting:hide()
    if self.ui then
        self.ui:hide()
    end
    if self.button then
        self.button:setOn(false)
    end
end

function GameCrafting:renderRecords()
    local list = self.ui:getChildById("recipeList")
    list:destroyChildren()

    for _, recipe in ipairs(self.records) do
        local row = g_ui.createWidget("CraftingRecipeRow", list)
        row.recipeId = recipe.recipeId
        row:getChildById("outputItem"):setItemId(recipe.outputId)
        row:getChildById("outputItem"):setItemCount(CHARGED_OUTPUTS[recipe.outputId] and 1 or recipe.outputCount)
        row:getChildById("recipeName"):setText(format_output(recipe.outputId, recipe.outputCount))
        row:getChildById("recipeSummary"):setText(string.format(
            "ID %d  |  %s nivel %d",
            recipe.recipeId,
            SKILL_LABELS[recipe.skillId] or ("Skill " .. tostring(recipe.skillId)),
            recipe.minimumLevel
        ))
        row:setOn(self.selectedRecipe == recipe)
        row.onClick = function()
            self:selectRecipe(recipe.recipeId)
        end
    end
end

function GameCrafting:renderMaterials(recipe)
    local list = self.ui:recursiveGetChildById("materialsList")
    list:destroyChildren()

    if not recipe then
        return
    end

    for _, ingredient in ipairs(recipe.ingredients) do
        local row = g_ui.createWidget("CraftingMaterialRow", list)
        row:getChildById("materialItem"):setItemId(ingredient.itemId)
        row:getChildById("materialItem"):setItemCount(ingredient.count)
        row:getChildById("materialName"):setText(string.format(
            "%s x%d", get_item_name(ingredient.itemId), ingredient.count
        ))
    end
end

function GameCrafting:updateUI()
    if not self.ui or self.ui:isDestroyed() then
        return
    end

    local category_box = self.ui:getChildById("categoryBox")
    local category_label = self.ui:recursiveGetChildById("categoryLabel")
    local page_label = self.ui:recursiveGetChildById("pageLabel")
    local total_label = self.ui:getChildById("totalLabel")
    local skill_label = self.ui:recursiveGetChildById("skillLabel")
    local result_item = self.ui:recursiveGetChildById("resultItem")
    local result_name = self.ui:recursiveGetChildById("resultName")
    local costs_label = self.ui:recursiveGetChildById("costsLabel")
    local status_label = self.ui:getChildById("statusLabel")
    local previous_button = self.ui:recursiveGetChildById("previousButton")
    local next_button = self.ui:recursiveGetChildById("nextButton")
    local refresh_button = self.ui:getChildById("catalogButton")
    local search_input = self.ui:getChildById("searchInput")
    local craft_button = self.ui:getChildById("craftButton")
    local page_count = math.max(1, math.ceil(#self.filteredRecords / CATALOG_PAGE_SIZE))

    if category_box:getCurrentOption() and category_box:getCurrentOption().data ~= self.category then
        category_box:setCurrentOptionByData(self.category)
    end
    category_label:setText("Producao - " .. (category_labels[self.category] or "Crafting"))
    page_label:setText(string.format("Pagina %d / %d", self.page, page_count))
    total_label:setText(string.format("%d / %d receita(s)", #self.filteredRecords, self.totalRecords))
    previous_button:setEnabled(self.page > 1 and not self.requestingCatalog and not self.waitingForResult)
    next_button:setEnabled(self.page < page_count and not self.requestingCatalog and not self.waitingForResult)
    category_box:setEnabled(not self.requestingCatalog and not self.waitingForResult)
    refresh_button:setEnabled(g_game.isOnline() and not self.waitingForResult and not self.requestingCatalog)
    search_input:setEnabled(not self.waitingForResult)

    if self.selectedRecipe then
        local recipe = self.selectedRecipe
        result_item:setItemId(recipe.outputId)
        result_item:setItemCount(CHARGED_OUTPUTS[recipe.outputId] and 1 or recipe.outputCount)
        result_name:setText(format_output(recipe.outputId, recipe.outputCount))
        local skill_state = self.skillStates[recipe.skillId]
        if not skill_state and modules.game_skills and modules.game_skills.getEconomicSkillState then
            skill_state = modules.game_skills.getEconomicSkillState(recipe.skillId)
        end
        if skill_state then
            skill_label:setText(string.format(
                "%s: nivel %d (%s%%) - requisito %d",
                SKILL_LABELS[recipe.skillId] or ("Skill " .. tostring(recipe.skillId)),
                skill_state.level,
                format_percent(skill_state.percent),
                recipe.minimumLevel
            ))
        else
            skill_label:setText(string.format(
                "%s: sincronizando nivel - requisito %d",
                SKILL_LABELS[recipe.skillId] or ("Skill " .. tostring(recipe.skillId)),
                recipe.minimumLevel
            ))
        end

        costs_label:setText(string.format(
            "Estacao ID %d  |  Gold %d  |  Soul %d",
            recipe.stationId, recipe.goldCost, recipe.soulCost
        ))
    else
        result_item:setItemId(0)
        result_name:setText(self.totalRecords == 0 and "Nenhuma receita nesta categoria."
            or #self.filteredRecords == 0 and "Nenhuma receita corresponde a pesquisa."
            or "Selecione uma receita da lista.")
        skill_label:setText("Selecione uma receita para ver os requisitos.")
        costs_label:setText("")
    end

    status_label:setText(self.status)
    craft_button:setEnabled(self.selectedRecipe ~= nil and self.nextRequestId ~= nil
        and not self.waitingForResult and not self.requestingCatalog and not self.needsCatalogSync)
    self:renderRecords()
    self:renderMaterials(self.selectedRecipe)

    if self.button then
        self.button:setOn(self.ui:isVisible())
    end
end
