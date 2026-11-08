CharacterList = {}

-- private variables
local charactersWindow
local loadBox
local characterList
local errorBox
local waitingWindow
local updateWaitEvent
local resendWaitEvent
local loginEvent

-- functionality
local panelSort
local showHiddenCheckbox
local showOutfitsCheckbox
local premiumBenefitsPanel
local premiumButton
local createCharacterButton
local emptyCharacterPrompt
local accountManagementButton
local characterAssemblyWindow
local accountManagementWindow
local firstPasswordWindow
local characterAssemblyRequestSerial = 0
local characterAssemblyOptionsPending = false
local characterAssemblyCreatePending = false
local accountRequestSerial = 0
local accountRequestPending = false
local firstPasswordRequestSerial = 0
local firstPasswordRequestPending = false
local firstPasswordEmail
local firstPasswordInitialPassword
local firstPasswordKeyboardReflowEvent
local firstPasswordKeyboardLayoutKey
local accountPendingEmail
local suppressCharacterAssemblyCallbacks = false
local characterAssemblyCatalog = {}
local suppressCheckCallbacks = false
local elementalDesktopLayout = false
local worldLoginPending = false
local ELEMENTAL_MODAL_BLUR_SHADER = 'Elemental Modal Blur'
local FIRST_PASSWORD_KEYBOARD_RECHECK_MS = 100
local FIRST_PASSWORD_KEYBOARD_WINDOW_MAX_WIDTH = 520
local FIRST_PASSWORD_KEYBOARD_WINDOW_MAX_HEIGHT = 340
local FIRST_PASSWORD_KEYBOARD_WINDOW_MIN_HEIGHT = 250

local function setElementalBackgroundBlur(blurred)
    if not elementalDesktopLayout or not modules.client_background or
        not modules.client_background.getBackground then
        return
    end

    local background = modules.client_background.getBackground()
    local artwork = background and background:getChildById('backgroundArtwork')
    if artwork then
        artwork:setShader(blurred and ELEMENTAL_MODAL_BLUR_SHADER or '')
    end
end

local function setCheckedWithoutCallback(widget, checked)
    if not widget then return end
    suppressCheckCallbacks = true
    widget:setChecked(checked)
    suppressCheckCallbacks = false
end

local SORT_COLUMN = {
    Character = 1,
    Status = 2,
    Level = 3,
    Vocation = 4,
    World = 5
}

local SORT_BUTTON_IDS = {
    [SORT_COLUMN.Character] = 'characterSort',
    [SORT_COLUMN.Status] = 'statusSort',
    [SORT_COLUMN.Level] = 'levelSort',
    [SORT_COLUMN.Vocation] = 'vocationSort',
    [SORT_COLUMN.World] = 'worldSort'
}

local SHOW_HIDDEN_SETTING = 'characterlist-show-hidden'
local SORT_COLUMN_SETTING = 'characterlist-sort-column'
local SORT_ASCENDING_SETTING = 'characterlist-sort-ascending'
local PINNED_CHARACTERS_SETTING = 'characterlist-pinned-characters'
--[[
    Controls whether the "Premium Benefits Include" panel is visible.

    true  -> panel is displayed
    false -> panel is hidden
]]
local SHOW_PREMIUM_WIDGETS = true

-- autoReconnect Button
local autoReconnectButton
local autoReconnectEvent
local lastLogout = 0
local function removeAutoReconnectEvent() --prevent
    if autoReconnectEvent then
        removeEvent(autoReconnectEvent)
        autoReconnectEvent = nil
    end
end

local function resetUIReferences()
    characterList = nil
    panelSort = nil
    showHiddenCheckbox = nil
    showOutfitsCheckbox = nil
    premiumBenefitsPanel = nil
    premiumButton = nil
    createCharacterButton = nil
    emptyCharacterPrompt = nil
    accountManagementButton = nil
    elementalDesktopLayout = false
    worldLoginPending = false
end

local function toBoolean(value, default)
    if value == nil then return default == true end
    local t = type(value)
    if t == 'boolean' then return value end
    if t == 'number' then return value ~= 0 end
    if t == 'string' then
        local v = string.lower(value)
        if v == 'true' or v == '1' then return true end
        if v == 'false' or v == '0' or v == '' then return false end
    end
    return value and true or false
end

local function shouldShowAppearance()
    return g_game.getFeature(GameEnterGameShowAppearance)
end

local function isPremiumAccount(account)
    if not account then
        return false
    end

    if account.subStatus == SubscriptionStatus.Premium then
        return true
    end

    local premDays = tonumber(account.premDays)
    return premDays ~= nil and premDays > 0
end

local function updatePremiumBenefitsVisibility(account)
    local showBenefits = shouldShowAppearance() and SHOW_PREMIUM_WIDGETS and not isPremiumAccount(account)
    if premiumBenefitsPanel then
        premiumBenefitsPanel:setVisible(showBenefits)
        if showBenefits then
            premiumBenefitsPanel:setHeight(120)
            premiumBenefitsPanel:setMarginBottom(6)
        else
            premiumBenefitsPanel:setHeight(0)
            premiumBenefitsPanel:setMarginBottom(0)
        end
    end
    if premiumButton then
        premiumButton:setVisible(showBenefits)
    end
end

local ELEMENTAL_CONTRACT_VERSION = 1
local ELEMENTAL_RACE_COUNT = 5
local ELEMENTAL_VOCATION_FIRST = 51
local ELEMENTAL_VOCATION_LAST = 62
local ACCOUNT_CHANGE_TIMEOUT_SECONDS = 10
local ELEMENTAL_ASSEMBLY_TEXT = {
    ['Account could not be created. Try again.'] = 'Nao foi possivel criar a conta. Tente novamente.',
    ['This email already has an account.'] = 'Este e-mail ja possui uma conta.',
    ['The email or password is invalid.'] = 'O e-mail ou a senha sao invalidos.',
    ['Addons'] = 'Extras',
    ['Appearance:'] = 'Aparencia:',
    ['Character created, but the list could not refresh. Use Refresh List.'] =
        'Personagem criado, mas a lista nao atualizou. Use Atualizar.',
    ['Character created. Refresh the list to continue.'] = 'Personagem criado. Atualize a lista para continuar.',
    ['Character could not be created. Try again.'] = 'Nao foi possivel criar o personagem. Tente novamente.',
    ['Character details are ready.'] = 'Dados do personagem prontos.',
    ['Character list could not be refreshed. Try again.'] = 'Nao foi possivel atualizar a lista. Tente novamente.',
    ['Character options are unavailable. Try again.'] = 'Opcoes de personagem indisponiveis. Tente novamente.',
    ['Character service is unavailable. Please log in again.'] = 'Servico de personagens indisponivel. Entre novamente.',
    ['Checking whether the character was created...'] = 'Confirmando a criacao do personagem...',
    ['Choose every field. No selection is prefilled.'] = 'Escolha os campos obrigatorios. Nenhum vem preselecionado.',
    ['Choose your race, vocation and appearance.'] = 'Escolha raca, vocacao e aparencia.',
    ['Complete every field before creating the character.'] = 'Preencha todos os campos para criar o personagem.',
    ['Creating character...'] = 'Criando personagem...',
    ['Female'] = 'Feminino',
    ['Login expired. Please log in again.'] = 'Sua sessao expirou. Entre novamente.',
    ['Loading character options...'] = 'Carregando opcoes de personagem...',
    ['Male'] = 'Masculino',
    ['No appearances are available for this sex.'] = 'Nenhuma aparencia disponivel para este sexo.',
    ['No character was confirmed. Check the list and try again.'] = 'Nao foi possivel confirmar. Atualize a lista e tente novamente.',
    ['None (0)'] = 'Nenhum (0)',
    ['One or more selections are no longer available.'] = 'Uma ou mais escolhas nao estao mais disponiveis.',
    ['Refresh List'] = 'Atualizar',
    ['Refreshing character list...'] = 'Atualizando lista de personagens...',
    ['Select'] = 'Selecionar',
    ['Select all four colors and addons.'] = 'Selecione as quatro cores e os extras.',
    ['Select appearance'] = 'Selecione a aparencia',
    ['Select race'] = 'Selecione a raca',
    ['Select sex'] = 'Selecione o sexo',
    ['Select vocation'] = 'Selecione a vocacao',
    ['Select a sex to load available appearances.'] = 'Selecione o sexo para carregar aparencias.',
    ['This name is already taken.'] = 'Este nome ja esta em uso.',
    ['You can refresh the list to confirm the new character.'] = 'Atualize a lista para confirmar o novo personagem.',
    ['The character service did not confirm the result.'] = 'O servico nao confirmou o resultado.',
    ['This account already has a character.'] = 'Esta conta ja possui um personagem.',
    ['Character created. Log in again to see it.'] = 'Personagem criado. Entre novamente para visualiza-lo.',
    ['Character created, but the list could not refresh.'] = 'Personagem criado, mas a lista nao atualizou.',
    ['Character created. Refresh the list.'] = 'Personagem criado. Atualize a lista.',
    ['The account service is unavailable.'] = 'O servico de contas esta indisponivel.',
    ['Character creation is unavailable.'] = 'A criacao de personagem esta indisponivel.',
    ['Select every field before continuing.'] = 'Selecione todos os campos para continuar.',
    ['Retry'] = 'Tentar novamente',
    ['Colors'] = 'Cores',
    ['Head color'] = 'Cor da cabeca',
    ['Body color'] = 'Cor do tronco',
    ['Legs color'] = 'Cor das pernas',
    ['Feet color'] = 'Cor dos detalhes',
    ['The local game service did not accept the request.'] = 'O servico local nao aceitou a solicitacao.',
}

local function localizeAssemblyText(text)
    if not elementalDesktopLayout then
        return text
    end
    return ELEMENTAL_ASSEMBLY_TEXT[text] or text
end

local function isInteger(value)
    return type(value) == 'number' and value % 1 == 0
end

local function isBetaLogin()
    return type(G.host) == 'string' and G.host:match('^https://[^/]+/beta/v1/login$') ~= nil
end

local function getElementalEndpoint(endpoint)
    if isBetaLogin() then
        return G.host:gsub('/login$', '/' .. endpoint)
    end
    if not Services or type(Services.createAccount) ~= 'string' then
        return nil
    end

    local url, replacements = Services.createAccount:gsub('/createaccount$', '/' .. endpoint)
    return replacements == 1 and url or nil
end

local function postCharacterRequest(endpoint, payload, callback, timeout)
    if isBetaLogin() then
        return HTTP.postWithBearer(endpoint, payload, G.sessionKey, callback, timeout)
    end
    return HTTP.post(endpoint, payload, callback)
end

local function decodeElementalResponse(message, err)
    local statusCode = type(err) == 'string' and tonumber(err:match('^http_status::(%d%d%d)'))
    if err and (not statusCode or statusCode < 400 or statusCode > 599) then
        return nil
    end
    if type(message) ~= 'string' then
        return nil
    end

    local jsonText = message:match('{.*}')
    if not jsonText then
        return nil
    end

    local ok, response = pcall(json.decode, jsonText)
    if not ok or type(response) ~= 'table' then
        return nil
    end
    if err and (response.contractVersion ~= ELEMENTAL_CONTRACT_VERSION or type(response.errorCode) ~= 'string' or
        response.success ~= nil) then
        return nil
    end
    return response
end

local function isHttpClientError(err)
    local statusCode = type(err) == 'string' and tonumber(err:match('^http_status::(%d%d%d)'))
    return statusCode and statusCode >= 400 and statusCode < 500
end

local function getAssemblyWidget(id)
    return characterAssemblyWindow and characterAssemblyWindow:recursiveGetChildById(id) or nil
end

local function setCharacterDetailsLabel(id, value, prefix)
    local label = charactersWindow and charactersWindow:recursiveGetChildById(id)
    if not label then
        return
    end

    local text = value ~= nil and tostring(value) or ''
    if text ~= '' and prefix then
        text = prefix .. text
    end
    label:setText(text)
    label:setVisible(text ~= '')

    local heading = charactersWindow:recursiveGetChildById(id .. 'Heading')
    if heading then
        heading:setVisible(text ~= '')
    end
end

local function setWorldLoginStatus(message, isError)
    local status = charactersWindow and charactersWindow:recursiveGetChildById('worldConnectionStatus')
    if not status then
        return
    end

    status:setText(message or '')
    status:setColor(isError and '#f07070' or '#ffbd6b')
    status:setVisible(message ~= nil and message ~= '')
end

local function setWorldLoginPending(pending)
    worldLoginPending = pending
    if not elementalDesktopLayout or not charactersWindow then
        return
    end

    local enterButton = charactersWindow:recursiveGetChildById('buttonOk')
    if enterButton then
        enterButton:setText(pending and 'Cancelar conexão' or 'Escolher Personagem')
        enterButton:setEnabled(true)
    end

    local characterListWidget = charactersWindow:recursiveGetChildById('characters')
    if characterListWidget then
        characterListWidget:setEnabled(not pending)
    end

    for _, id in ipairs({ 'buttonBack', 'buttonAccount', 'characterListUpButton', 'characterListDownButton' }) do
        local control = charactersWindow:recursiveGetChildById(id)
        if control then
            control:setEnabled(not pending)
        end
    end
end

local function updateSelectedCharacter(characterWidget)
    if not elementalDesktopLayout or not charactersWindow then
        return
    end

    local details = charactersWindow:recursiveGetChildById('selectedCharacterDetails')
    local emptyState = charactersWindow:recursiveGetChildById('selectedCharacterEmpty')
    local enterButton = charactersWindow:recursiveGetChildById('buttonOk')
    local cancelButton = charactersWindow:recursiveGetChildById('buttonCancel')

    if characterWidget and characterWidget.isCreateCharacterEntry then
        details:hide()
        emptyState:hide()
        enterButton:hide()
        cancelButton:hide()
        CharacterList.openCharacterAssembly()
        return
    end

    local characterInfo = characterWidget and characterWidget.characterInfo
    if not characterInfo then
        details:hide()
        emptyState:show()
        enterButton:hide()
        cancelButton:hide()
        return
    end

    if characterAssemblyWindow then
        CharacterList.closeCharacterAssembly()
    end

    details:show()
    emptyState:hide()
    enterButton:setText('Escolher Personagem')
    enterButton:show()
    enterButton:enable()
    cancelButton:hide()
    setCharacterDetailsLabel('selectedCharacterName', characterInfo.name)
    setCharacterDetailsLabel('selectedCharacterLevel', characterInfo.level)
    setCharacterDetailsLabel('selectedCharacterVocation', characterInfo.vocation)
    setCharacterDetailsLabel('selectedCharacterRace', characterInfo.raceName)
    setCharacterDetailsLabel('selectedCharacterWorld', characterInfo.worldName)

    local preview = charactersWindow:recursiveGetChildById('selectedCharacterPreview')
    local lookType = tonumber(characterInfo.outfitid)
    if not lookType or lookType <= 0 then
        preview:hide()
        return
    end

    local creature = charactersWindow.previewCharacterCreature
    if not creature then
        creature = Creature.create()
        creature:setDirection(2)
        charactersWindow.previewCharacterCreature = creature
    end
    creature:setOutfit({
        type = lookType,
        head = tonumber(characterInfo.headcolor) or 0,
        body = tonumber(characterInfo.torsocolor) or 0,
        legs = tonumber(characterInfo.legscolor) or 0,
        feet = tonumber(characterInfo.detailcolor) or 0,
        addons = tonumber(characterInfo.addonsflags) or 0
    })
    preview:setCreature(creature)
    preview:show()
end

local function setAssemblyStatus(message, isError)
    if not characterAssemblyWindow then
        return
    end
    local status = getAssemblyWidget('assemblyStatus')
    status:setText(localizeAssemblyText(message or ''))
    status:setColor(isError and '#f07070' or '#c0c0c0')
end

local function setComboPrompt(comboBox, prompt)
    local previousSuppression = suppressCharacterAssemblyCallbacks
    suppressCharacterAssemblyCallbacks = true
    comboBox:clearOptions()
    comboBox:addOption(localizeAssemblyText(prompt), -1)
    comboBox:setCurrentOptionByData(-1)
    suppressCharacterAssemblyCallbacks = previousSuppression
end

local function getComboData(comboBox)
    if not comboBox then
        return nil
    end
    local option = comboBox:getCurrentOption()
    return type(option) == 'table' and option.data or nil
end

local function setComboOptions(comboBox, prompt, options, labelField, dataField, selectedData)
    local previousSuppression = suppressCharacterAssemblyCallbacks
    suppressCharacterAssemblyCallbacks = true
    comboBox:clearOptions()
    comboBox:addOption(localizeAssemblyText(prompt), -1)
    for _, option in ipairs(options) do
        comboBox:addOption(option[labelField], option[dataField])
    end
    comboBox:setCurrentOptionByData(-1)
    if isInteger(selectedData) then
        comboBox:setCurrentOptionByData(selectedData)
    end
    suppressCharacterAssemblyCallbacks = previousSuppression
end

local function findAppearance(lookType, sex)
    for _, appearance in ipairs(characterAssemblyCatalog.appearances or {}) do
        if appearance.lookType == lookType and appearance.sex == sex then
            return appearance
        end
    end
    return nil
end

local function isAppearanceColorSelected(color, colorRange)
    return isInteger(color) and type(colorRange) == 'table' and
        isInteger(colorRange.min) and isInteger(colorRange.max) and
        color >= colorRange.min and color <= colorRange.max
end

local function isAppearanceAddonSelected(appearance, addons)
    if not appearance or not isInteger(addons) or type(appearance.addons) ~= 'table' then
        return false
    end

    for _, availableAddon in ipairs(appearance.addons) do
        if availableAddon == addons then
            return true
        end
    end
    return false
end

local function areAppearanceChoicesSelected(appearance, headColor, bodyColor, legsColor, feetColor, addons)
    if not appearance then
        return false
    end

    local colorRange = appearance.colorRange
    return isAppearanceColorSelected(headColor, colorRange) and
        isAppearanceColorSelected(bodyColor, colorRange) and
        isAppearanceColorSelected(legsColor, colorRange) and
        isAppearanceColorSelected(feetColor, colorRange) and
        isAppearanceAddonSelected(appearance, addons)
end

local function updateAssemblyPreview()
    if not characterAssemblyWindow then
        return
    end

    local preview = getAssemblyWidget('appearancePreview')
    local sex = getComboData(getAssemblyWidget('sexCombo'))
    local lookType = getComboData(getAssemblyWidget('appearanceCombo'))
    local appearance = isInteger(lookType) and findAppearance(lookType, sex) or nil
    local headColor = getComboData(getAssemblyWidget('headColorCombo'))
    local bodyColor = getComboData(getAssemblyWidget('bodyColorCombo'))
    local legsColor = getComboData(getAssemblyWidget('legsColorCombo'))
    local feetColor = getComboData(getAssemblyWidget('feetColorCombo'))
    local addons = getComboData(getAssemblyWidget('addonsCombo'))

    if not areAppearanceChoicesSelected(appearance, headColor, bodyColor, legsColor, feetColor, addons) then
        preview:hide()
        getAssemblyWidget('previewHint'):show()
        return
    end

    local creature = characterAssemblyWindow.previewCreature
    local isNewCreature = not creature
    if not creature then
        creature = Creature.create()
        creature:setDirection(2)
        characterAssemblyWindow.previewCreature = creature
    end
    creature:setOutfit({
        type = appearance.lookType,
        head = headColor,
        body = bodyColor,
        legs = legsColor,
        feet = feetColor,
        addons = addons
    })
    if isNewCreature then
        preview:setCreature(creature)
    end
    preview:show()
    getAssemblyWidget('previewHint'):hide()
end

local function canSubmitCharacter()
    if not characterAssemblyWindow or characterAssemblyOptionsPending or characterAssemblyCreatePending then
        return false
    end

    local name = getAssemblyWidget('characterNameEdit'):getText()
    local raceId = getComboData(getAssemblyWidget('raceCombo'))
    local vocationId = getComboData(getAssemblyWidget('vocationCombo'))
    local sex = getComboData(getAssemblyWidget('sexCombo'))
    local lookType = getComboData(getAssemblyWidget('appearanceCombo'))
    local headColor = getComboData(getAssemblyWidget('headColorCombo'))
    local bodyColor = getComboData(getAssemblyWidget('bodyColorCombo'))
    local legsColor = getComboData(getAssemblyWidget('legsColorCombo'))
    local feetColor = getComboData(getAssemblyWidget('feetColorCombo'))
    local addons = getComboData(getAssemblyWidget('addonsCombo'))
    local appearance = isInteger(lookType) and findAppearance(lookType, sex) or nil

    return type(name) == 'string' and #name >= 3 and #name <= 18 and name:match("^[a-zA-Z' ]+$") ~= nil and
        isInteger(raceId) and raceId >= 0 and raceId < ELEMENTAL_RACE_COUNT and
        isInteger(vocationId) and vocationId >= ELEMENTAL_VOCATION_FIRST and vocationId <= ELEMENTAL_VOCATION_LAST and
        isInteger(sex) and (sex == 0 or sex == 1) and appearance ~= nil and
        areAppearanceChoicesSelected(appearance, headColor, bodyColor, legsColor, feetColor, addons)
end

local function updateAssemblySubmitButton()
    if characterAssemblyWindow then
        local ready = canSubmitCharacter()
        getAssemblyWidget('createCharacterButton'):setEnabled(ready)
        local statusWidget = getAssemblyWidget('assemblyStatus')
        local currentStatus = statusWidget:getText()
        local readyStatus = localizeAssemblyText('Character details are ready.')
        local colorStatus = localizeAssemblyText('Select all four colors and addons.')
        local completeStatus = localizeAssemblyText('Complete every field before creating the character.')

        if ready then
            setAssemblyStatus('Character details are ready.', false)
        elseif currentStatus == readyStatus or currentStatus == colorStatus or currentStatus == completeStatus then
            local sex = getComboData(getAssemblyWidget('sexCombo'))
            local lookType = getComboData(getAssemblyWidget('appearanceCombo'))
            local appearance = isInteger(lookType) and findAppearance(lookType, sex) or nil
            if appearance and not areAppearanceChoicesSelected(appearance,
                getComboData(getAssemblyWidget('headColorCombo')),
                getComboData(getAssemblyWidget('bodyColorCombo')),
                getComboData(getAssemblyWidget('legsColorCombo')),
                getComboData(getAssemblyWidget('feetColorCombo')),
                getComboData(getAssemblyWidget('addonsCombo'))) then
                setAssemblyStatus('Select all four colors and addons.', false)
            else
                setAssemblyStatus('Complete every field before creating the character.', false)
            end
        end
    end
end

local function clearAppearanceChoices()
    if not characterAssemblyWindow then
        return
    end

    local appearanceCombo = getAssemblyWidget('appearanceCombo')
    getAssemblyWidget('appearanceLabel'):setText(localizeAssemblyText('Appearance:'))
    setComboPrompt(appearanceCombo, 'Select appearance')
    appearanceCombo:disable()
    for _, id in ipairs({ 'headColorCombo', 'bodyColorCombo', 'legsColorCombo', 'feetColorCombo', 'addonsCombo' }) do
        local comboBox = getAssemblyWidget(id)
        setComboPrompt(comboBox, 'Select')
        comboBox:disable()
    end
    characterAssemblyCatalog.appearances = nil
    updateAssemblyPreview()
    updateAssemblySubmitButton()
end

local function isAsciiLabel(value)
    return type(value) == 'string' and #value > 0 and value:match('^[ -~]+$') ~= nil
end

local function validateCharacterCatalog(response, sex)
    if response.contractVersion ~= ELEMENTAL_CONTRACT_VERSION or type(response.races) ~= 'table' or
        type(response.vocations) ~= 'table' or type(response.appearances) ~= 'table' then
        return false
    end

    local raceIds = {}
    for _, race in ipairs(response.races) do
        if type(race) ~= 'table' or not isInteger(race.raceId) or race.raceId < 0 or
            race.raceId >= ELEMENTAL_RACE_COUNT or not isAsciiLabel(race.name) or raceIds[race.raceId] then
            return false
        end
        raceIds[race.raceId] = true
    end
    if #response.races ~= ELEMENTAL_RACE_COUNT then
        return false
    end
    for raceId = 0, ELEMENTAL_RACE_COUNT - 1 do
        if not raceIds[raceId] then
            return false
        end
    end

    local vocationIds = {}
    for _, vocation in ipairs(response.vocations) do
        if type(vocation) ~= 'table' or not isInteger(vocation.vocationId) or
            vocation.vocationId < ELEMENTAL_VOCATION_FIRST or vocation.vocationId > ELEMENTAL_VOCATION_LAST or
            not isAsciiLabel(vocation.name) or vocationIds[vocation.vocationId] then
            return false
        end
        vocationIds[vocation.vocationId] = true
    end
    if #response.vocations ~= ELEMENTAL_VOCATION_LAST - ELEMENTAL_VOCATION_FIRST + 1 then
        return false
    end
    for vocationId = ELEMENTAL_VOCATION_FIRST, ELEMENTAL_VOCATION_LAST do
        if not vocationIds[vocationId] then
            return false
        end
    end

    for _, appearance in ipairs(response.appearances) do
        local range = type(appearance) == 'table' and appearance.colorRange or nil
        if type(appearance) ~= 'table' or appearance.sex ~= sex or not isInteger(appearance.lookType) or
            appearance.lookType < 0 or appearance.lookType > 65535 or not isAsciiLabel(appearance.name) or
            type(range) ~= 'table' or not isInteger(range.min) or not isInteger(range.max) or
            range.min < 0 or range.max > 255 or range.min > range.max or type(appearance.addons) ~= 'table' then
            return false
        end
        for _, addon in ipairs(appearance.addons) do
            if not isInteger(addon) or addon < 0 or addon > 255 then
                return false
            end
        end
    end
    return true
end

local function populateAppearanceColors(appearance)
    local range = appearance.colorRange
    local colorCombos = {
        { 'headColorCombo', 'headColor', 'Head color' },
        { 'bodyColorCombo', 'bodyColor', 'Body color' },
        { 'legsColorCombo', 'legsColor', 'Legs color' },
        { 'feetColorCombo', 'feetColor', 'Feet color' }
    }
    suppressCharacterAssemblyCallbacks = true
    for _, colorInfo in ipairs(colorCombos) do
        local comboBox = getAssemblyWidget(colorInfo[1])
        setComboPrompt(comboBox, 'Select')
        for color = range.min, range.max do
            comboBox:addOption(tostring(color), color)
        end
        comboBox:enable()
    end

    local addonsCombo = getAssemblyWidget('addonsCombo')
    setComboPrompt(addonsCombo, 'Select')
    for _, addon in ipairs(appearance.addons) do
        local label = addon == 0 and localizeAssemblyText('None (0)') or
            (elementalDesktopLayout and ('Extra ' .. tostring(addon)) or ('Addon ' .. tostring(addon)))
        addonsCombo:addOption(label, addon)
    end
    addonsCombo:enable()
    suppressCharacterAssemblyCallbacks = false
end

local function getCharacterApiError(response)
    local errorCode = response and response.errorCode
    local messages = {
        invalid_credentials = 'Login expired. Please log in again.',
        invalid_session = 'Login expired. Please log in again.',
        character_catalog_unavailable = 'Character options are unavailable. Try again.',
        character_list_unavailable = 'Character list could not be refreshed. Try again.',
        invalid_character = 'One or more selections are no longer available.',
        character_name_taken = 'This name is already taken.',
        character_creation_failed = 'Character could not be created. Try again.',
        account_creation_failed = 'Account could not be created. Try again.',
        account_already_exists = 'This email already has an account.',
        invalid_account_data = 'The email or password is invalid.'
    }
    local message = messages[errorCode] or 'The local game service did not accept the request.'
    return localizeAssemblyText(message)
end

local function getAccountWidget(id)
    return accountManagementWindow and accountManagementWindow:recursiveGetChildById(id) or nil
end

local function setAccountStatus(message, isError)
    if not accountManagementWindow then
        return
    end
    local status = getAccountWidget('accountStatus')
    status:setText(message or '')
    status:setColor(isError and '#f07070' or '#c0c0c0')
end

local function getFirstPasswordWidget(id)
    return firstPasswordWindow and firstPasswordWindow:recursiveGetChildById(id) or nil
end

local function cancelFirstPasswordKeyboardReflow()
    if firstPasswordKeyboardReflowEvent then
        removeEvent(firstPasswordKeyboardReflowEvent)
        firstPasswordKeyboardReflowEvent = nil
    end
    firstPasswordKeyboardLayoutKey = nil
end

local function setFirstPasswordWidgetVisible(id, visible, height)
    local widget = getFirstPasswordWidget(id)
    if not widget then
        return
    end
    if height ~= nil then
        widget:setHeight(height)
    end
    widget:setVisible(visible)
end

local function applyFirstPasswordKeyboardLayout()
    if not firstPasswordWindow or firstPasswordWindow:isDestroyed() or not g_platform.isMobile() then
        return
    end

    local parent = firstPasswordWindow:getParent()
    local parentWidth = parent and parent:getWidth() or 0
    local parentHeight = parent and parent:getHeight() or 0
    local keyboardBottom = 0
    if firstPasswordWindow:isVisible() and g_platform.getSoftKeyboardHeight then
        local keyboardPixelHeight = g_platform.getSoftKeyboardHeight()
        local displayHeight = g_window.getDisplayHeight()
        if keyboardPixelHeight > 0 and displayHeight > 0 and parentHeight > 0 then
            keyboardBottom = math.floor(parentHeight * math.min(0.75, keyboardPixelHeight / displayHeight))
        end
    end

    local keyboardOpen = keyboardBottom > 0
    local visibleHeight = math.max(0, parentHeight - keyboardBottom)
    local layoutKey = string.format('%s:%d:%d', keyboardOpen and 'keyboard' or 'full', parentWidth, visibleHeight)
    if layoutKey == firstPasswordKeyboardLayoutKey then
        return
    end
    firstPasswordKeyboardLayoutKey = layoutKey

    local panel = getFirstPasswordWidget('firstPasswordPanel')
    local heading = getFirstPasswordWidget('firstPasswordHeading')
    local newPasswordLabel = getFirstPasswordWidget('firstPasswordNewLabel')
    local newPasswordEdit = getFirstPasswordWidget('firstPasswordNewEdit')
    local confirmPasswordLabel = getFirstPasswordWidget('firstPasswordConfirmLabel')
    local confirmPasswordEdit = getFirstPasswordWidget('firstPasswordConfirmEdit')
    local submitButton = getFirstPasswordWidget('firstPasswordSubmitButton')
    local cancelButton = getFirstPasswordWidget('firstPasswordCancelButton')

    if keyboardOpen then
        local windowWidth = math.max(1, math.min(FIRST_PASSWORD_KEYBOARD_WINDOW_MAX_WIDTH, parentWidth - 24))
        local windowHeight = math.max(FIRST_PASSWORD_KEYBOARD_WINDOW_MIN_HEIGHT,
            math.min(FIRST_PASSWORD_KEYBOARD_WINDOW_MAX_HEIGHT, visibleHeight - 16))
        firstPasswordWindow:setSize({width = windowWidth, height = windowHeight})
        firstPasswordWindow:breakAnchors()
        firstPasswordWindow:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        firstPasswordWindow:addAnchor(AnchorTop, 'parent', AnchorTop)
        firstPasswordWindow:setMarginTop(math.max(8, math.floor((visibleHeight - windowHeight) / 2)))

        if panel then
            panel:setMarginTop(8)
            panel:setMarginRight(8)
            panel:setMarginBottom(8)
            panel:setMarginLeft(8)
        end
        local intro = getFirstPasswordWidget('firstPasswordIntro')
        local accountPanel = getFirstPasswordWidget('firstPasswordAccountPanel')
        if intro then
            intro:setMarginTop(0)
        end
        if accountPanel then
            accountPanel:setMarginTop(0)
        end
        setFirstPasswordWidgetVisible('firstPasswordIntro', false, 0)
        setFirstPasswordWidgetVisible('firstPasswordAccountPanel', false, 0)
        setFirstPasswordWidgetVisible('firstPasswordHint', false, 0)
        if heading then
            heading:setHeight(22)
        end
        if newPasswordLabel then
            newPasswordLabel:setMarginTop(5)
        end
        if newPasswordEdit then
            newPasswordEdit:setHeight(40)
            newPasswordEdit:setMarginTop(3)
        end
        if confirmPasswordLabel then
            confirmPasswordLabel:setMarginTop(7)
        end
        if confirmPasswordEdit then
            confirmPasswordEdit:setHeight(40)
            confirmPasswordEdit:setMarginTop(3)
        end
        local status = getFirstPasswordWidget('firstPasswordStatus')
        if status then
            status:setHeight(30)
        end
        if submitButton then
            submitButton:breakAnchors()
            submitButton:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            submitButton:addAnchor(AnchorRight, 'parent', AnchorRight)
            submitButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
            submitButton:setHeight(40)
        end
        if cancelButton then
            cancelButton:hide()
        end
    else
        firstPasswordWindow:setSize({width = 500, height = 420})
        firstPasswordWindow:breakAnchors()
        firstPasswordWindow:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
        firstPasswordWindow:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        firstPasswordWindow:setMarginTop(0)

        if panel then
            panel:setMarginTop(12)
            panel:setMarginRight(12)
            panel:setMarginBottom(12)
            panel:setMarginLeft(12)
        end
        local intro = getFirstPasswordWidget('firstPasswordIntro')
        local accountPanel = getFirstPasswordWidget('firstPasswordAccountPanel')
        if intro then
            intro:setMarginTop(5)
        end
        if accountPanel then
            accountPanel:setMarginTop(8)
        end
        setFirstPasswordWidgetVisible('firstPasswordIntro', true, 42)
        setFirstPasswordWidgetVisible('firstPasswordAccountPanel', true, 38)
        setFirstPasswordWidgetVisible('firstPasswordHint', true, 30)
        if heading then
            heading:setHeight(24)
        end
        if newPasswordLabel then
            newPasswordLabel:setMarginTop(11)
        end
        if newPasswordEdit then
            newPasswordEdit:setHeight(26)
            newPasswordEdit:setMarginTop(3)
        end
        if confirmPasswordLabel then
            confirmPasswordLabel:setMarginTop(9)
        end
        if confirmPasswordEdit then
            confirmPasswordEdit:setHeight(26)
            confirmPasswordEdit:setMarginTop(3)
        end
        local status = getFirstPasswordWidget('firstPasswordStatus')
        if status then
            status:setHeight(32)
        end
        if submitButton then
            submitButton:breakAnchors()
            submitButton:addAnchor(AnchorRight, 'parent', AnchorRight)
            submitButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
            submitButton:setWidth(142)
            submitButton:setHeight(30)
        end
        if cancelButton then
            cancelButton:show()
        end
    end
end

local function scheduleFirstPasswordKeyboardReflow()
    if not g_platform.isMobile() or firstPasswordKeyboardReflowEvent or not firstPasswordWindow then
        return
    end

    firstPasswordKeyboardReflowEvent = scheduleEvent(function()
        firstPasswordKeyboardReflowEvent = nil
        if not firstPasswordWindow or firstPasswordWindow:isDestroyed() then
            return
        end
        applyFirstPasswordKeyboardLayout()
        if firstPasswordWindow:isVisible() then
            scheduleFirstPasswordKeyboardReflow()
        end
    end, FIRST_PASSWORD_KEYBOARD_RECHECK_MS)
end

local function setFirstPasswordStatus(message, isError)
    if not firstPasswordWindow then
        return
    end
    local status = getFirstPasswordWidget('firstPasswordStatus')
    status:setText(message or '')
    status:setColor(isError and '#e56b6b' or '#aeb4c0')
end

local function clearFirstPasswordFields()
    for _, id in ipairs({'firstPasswordNewEdit', 'firstPasswordConfirmEdit'}) do
        local field = getFirstPasswordWidget(id)
        if field then
            field:clearText()
        end
    end
end

local function updateFirstPasswordButtons()
    if not firstPasswordWindow then
        return
    end
    getFirstPasswordWidget('firstPasswordNewEdit'):setEnabled(not firstPasswordRequestPending)
    getFirstPasswordWidget('firstPasswordConfirmEdit'):setEnabled(not firstPasswordRequestPending)
    getFirstPasswordWidget('firstPasswordSubmitButton'):setEnabled(not firstPasswordRequestPending)
    getFirstPasswordWidget('firstPasswordCancelButton'):setEnabled(not firstPasswordRequestPending)
end

local function maskEmail(email)
    if type(email) ~= 'string' then
        return '***'
    end
    local localPart, domain = email:match('^([^@]+)@(.+)$')
    if not localPart or not domain then
        return '***'
    end
    return localPart:sub(1, 1) .. '***@' .. domain
end

local function clearAccountSensitiveFields()
    for _, id in ipairs({
        'passwordCurrentEdit', 'passwordNewEdit', 'passwordConfirmEdit',
        'emailCurrentPasswordEdit', 'emailNewAddressEdit', 'emailCodeEdit'
    }) do
        local field = getAccountWidget(id)
        if field then
            field:clearText()
        end
    end
end

local function decodeBetaCharacters(response)
    if type(response) ~= 'table' or response.contractVersion ~= ELEMENTAL_CONTRACT_VERSION or
        type(response.characters) ~= 'table' then
        return nil
    end

    local characters = {}
    for _, character in ipairs(response.characters) do
        if type(character) ~= 'table' then
            return nil
        end
        local worldIp = character.worldIp
        local worldPort = tonumber(character.worldPort)
        if type(character.name) ~= 'string' or character.name == '' or
            type(character.worldName) ~= 'string' or character.worldName == '' or
            type(worldIp) ~= 'string' or worldIp == '' or not worldPort or worldPort < 1 or worldPort > 65535 then
            return nil
        end

        characters[#characters + 1] = {
            name = character.name,
            level = tonumber(character.level) or 1,
            main = character.ismaincharacter,
            dailyrewardstate = character.dailyrewardstate,
            hidden = character.ishidden,
            vocation = character.vocation,
            vocationId = character.vocationId,
            raceId = character.raceId,
            raceName = character.raceName,
            outfitid = character.outfitid,
            headcolor = character.headcolor,
            torsocolor = character.torsocolor,
            legscolor = character.legscolor,
            detailcolor = character.detailcolor,
            addonsflags = character.addonsflags,
            worldName = character.worldName,
            worldIp = worldIp,
            worldHost = worldIp,
            worldPort = worldPort,
            previewState = character.previewState,
            pvptype = character.pvptype,
        }
    end
    return characters
end

local function applyBetaCharacterList(characters)
    G.characters = characters
    CharacterList.closeCharacterAssembly()
    CharacterList.rebuildCharactersList()
    CharacterList.show()
end

local function refreshBetaCharacterList(callback)
    local endpoint = getElementalEndpoint('characters/list')
    if not isBetaLogin() or type(G.sessionKey) ~= 'string' or not endpoint then
        callback(nil, 'invalid_session')
        return
    end

    postCharacterRequest(endpoint, { contractVersion = ELEMENTAL_CONTRACT_VERSION }, function(message, err)
        local response = decodeElementalResponse(message, err)
        local characters = response and decodeBetaCharacters(response) or nil
        if not characters then
            callback(nil, response and response.errorCode or err or 'character_list_unavailable')
            return
        end
        callback(characters)
    end, ACCOUNT_CHANGE_TIMEOUT_SECONDS)
end

local function getAccountApiError(response)
    local errorCode = response and response.errorCode
    local messages = {
        account_change_rate_limited = 'Too many attempts. Wait before trying again.',
        account_change_unavailable = 'Account service is unavailable. Try again.',
        invalid_email = 'Enter a valid email address.',
        invalid_email_confirmation = 'The confirmation code is invalid or expired.',
        invalid_request = 'Check the information and try again.',
        invalid_session = 'Login expired. Please log in again.',
        reauthentication_failed = 'The current password is incorrect.',
    }
    return messages[errorCode] or 'Account service did not accept the request.'
end

local function clearBetaSessionAndRelogin(email, message)
    local reloginEmail = type(email) == 'string' and email or G.account
    CharacterList.closeAccountManagement()
    G.account = reloginEmail or ''
    G.password = ''
    G.sessionKey = nil
    G.requestId = 0
    if EnterGame and EnterGame.prepareBetaRelogin then
        EnterGame.prepareBetaRelogin(G.account)
    else
        EnterGame.setPassword('')
    end
    CharacterList.hide(true)
    displayInfoBox(tr('Login required'), tr(message or 'Please log in again.'))
end

local function requestAccountChange(endpoint, payload, callback)
    if not isBetaLogin() or type(G.sessionKey) ~= 'string' or
        not G.sessionKey:match('^b1%.[A-Za-z0-9_-]+$') then
        callback(nil, 'invalid_session')
        return
    end
    local url = getElementalEndpoint(endpoint)
    if not url then
        callback(nil, 'account_change_unavailable')
        return
    end
    postCharacterRequest(url, payload, callback, ACCOUNT_CHANGE_TIMEOUT_SECONDS)
end

local function getShowHiddenCharacters()
    return g_settings.getBoolean(SHOW_HIDDEN_SETTING, true)
end

local function setShowHiddenCharacters(value)
    g_settings.set(SHOW_HIDDEN_SETTING, value)
end

local function getShowOutfits()
    return toBoolean(modules.client_options.getOption('showOutfitsOnList'), true)
end

local function setShowOutfits(value)
    value = toBoolean(value, true)
    modules.client_options.setOption('showOutfitsOnList', value)
end

local function getSortColumn()
    local sortColumn = g_settings.getNumber(SORT_COLUMN_SETTING, SORT_COLUMN.Character)
    if sortColumn < SORT_COLUMN.Character or sortColumn > SORT_COLUMN.World then
        sortColumn = SORT_COLUMN.Character
    end
    return sortColumn
end

local function getSortAscending()
    return g_settings.getBoolean(SORT_ASCENDING_SETTING, true)
end

local function getCharacterStatusValue(characterInfo)
    local main = characterInfo.main and 0 or 1
    local hidden = characterInfo.hidden and 0 or 1
    local dailyReward = tonumber(characterInfo.dailyreward) == 0 and 0 or 1
    return main * 100 + hidden * 10 + dailyReward
end

local function getPinnedCharacters()
    local rawPinnedCharacters = g_settings.getNode(PINNED_CHARACTERS_SETTING)
    if type(rawPinnedCharacters) ~= 'table' then
        return {}
    end

    local pinnedCharacters = {}

    -- Legacy compatibility: normalize array/string shapes into a pinKey->true map.
    for key, value in pairs(rawPinnedCharacters) do
        if type(key) == 'number' then
            if type(value) == 'string' and value ~= '' then
                pinnedCharacters[value] = true
            end
        elseif type(key) == 'string' then
            if value == true then
                pinnedCharacters[key] = true
            elseif type(value) == 'number' then
                if value ~= 0 then
                    pinnedCharacters[key] = true
                end
            elseif type(value) == 'string' then
                local normalizedValue = string.lower(value)
                if normalizedValue == 'true' or normalizedValue == '1' then
                    pinnedCharacters[key] = true
                end
            end
        end
    end

    return pinnedCharacters
end

local function setPinnedCharacters(characters)
    g_settings.setNode(PINNED_CHARACTERS_SETTING, characters)
end

local function getCharacterPinKey(characterName, worldName)
    local name = tostring(characterName or '')
    if name == '' then
        return nil
    end

    return string.format('%s|%s', name, tostring(worldName or ''))
end

local function isCharacterPinned(characterName, worldName, pinnedLookup)
    local pinKey = getCharacterPinKey(characterName, worldName)
    if not pinKey then
        return false
    end

    local pinnedCharacters = pinnedLookup or getPinnedCharacters()
    if pinnedCharacters[pinKey] == true then
        return true
    end

    -- Legacy compatibility: old entries were keyed only by character name.
    return pinnedCharacters[tostring(characterName)] == true
end

local function setCharacterPinned(characterName, worldName, isPinned)
    local pinKey = getCharacterPinKey(characterName, worldName)
    if not pinKey then
        return
    end

    local pinnedCharacters = getPinnedCharacters()
    pinnedCharacters[pinKey] = isPinned and true or nil
    pinnedCharacters[tostring(characterName)] = nil
    setPinnedCharacters(pinnedCharacters)
end

local function toLowerText(value)
    return string.lower(tostring(value or ''))
end

local function toNumberValue(value)
    if type(value) == 'number' then
        return value
    end

    local numericValue = tonumber(value)
    if numericValue then
        return numericValue
    end

    if type(value) == 'string' then
        numericValue = tonumber((value:gsub('[^%d%-%.]', '')))
        if numericValue then
            return numericValue
        end
    end

    return 0
end

local PVP_TYPE_LABELS = {
    [0] = 'Open PvP',
    [1] = 'Optional PvP',
    [2] = 'Hardcore PvP',
    [3] = 'Retro Open PvP',
    [4] = 'Retro Hardcore PvP',
}

local function getPvpTypeText(pvpType)
    if pvpType == nil then
        return nil
    end

    local label = PVP_TYPE_LABELS[tonumber(pvpType) or pvpType]
    if label then
        return tr(label)
    end

    if type(pvpType) == 'string' and pvpType ~= '' then
        return pvpType
    end

    return nil
end

local function getCharacterWorldLabel(characterInfo)
    local worldName = tostring(characterInfo.worldName or '')
    if worldName == '' then
        return worldName
    end

    local pvpTypeText = getPvpTypeText(characterInfo.pvptype)
    if not pvpTypeText or pvpTypeText == '' then
        return worldName
    end

    return string.format('%s\n(%s)', worldName, pvpTypeText)
end

local function compareCharacters(a, b, sortColumn, sortAscending, pinnedLookup)
    local prioritizePinned = sortColumn ~= SORT_COLUMN.Level
    if prioritizePinned then
        local aPinned = isCharacterPinned(a.name, a.worldName, pinnedLookup)
        local bPinned = isCharacterPinned(b.name, b.worldName, pinnedLookup)
        if aPinned ~= bPinned then return aPinned end
    end

    local aValue, bValue
    if sortColumn == SORT_COLUMN.Character then
        aValue, bValue = toLowerText(a.name), toLowerText(b.name)
    elseif sortColumn == SORT_COLUMN.Status then
        aValue, bValue = getCharacterStatusValue(a), getCharacterStatusValue(b)
    elseif sortColumn == SORT_COLUMN.Level then
        aValue, bValue = toNumberValue(a.level), toNumberValue(b.level)
    elseif sortColumn == SORT_COLUMN.Vocation then
        aValue, bValue = toLowerText(a.vocation), toLowerText(b.vocation)
    else
        aValue, bValue = toLowerText(a.worldName), toLowerText(b.worldName)
    end

    if aValue == bValue then
        aValue, bValue = toLowerText(a.name), toLowerText(b.name)
        if aValue == bValue then
            aValue, bValue = toLowerText(a.worldName), toLowerText(b.worldName)
        end
    end

    if sortAscending then return aValue < bValue end
    return aValue > bValue
end

local function updateSortButtons()
    if not panelSort or not shouldShowAppearance() then
        return
    end

    local sortColumn = getSortColumn()
    local sortAscending = getSortAscending()
    for column = SORT_COLUMN.Character, SORT_COLUMN.World do
        local button = panelSort:getChildById(SORT_BUTTON_IDS[column])
        if button then
            local isSelected = column == sortColumn
            button:setOn(isSelected)
            button:setChecked(isSelected and sortAscending or false, true)
        end
    end
end

local function buildCharacters(pinnedLookup)
    local characters = {}
    if not G.characters then
        return characters
    end

    local showAppearance = shouldShowAppearance()
    local showHidden = not showAppearance or getShowHiddenCharacters()
    for _, characterInfo in ipairs(G.characters) do
        if showHidden or not characterInfo.hidden then
            table.insert(characters, characterInfo)
        end
    end

    if showAppearance then
        local sortColumn = getSortColumn()
        local sortAscending = getSortAscending()
        table.sort(characters, function(a, b)
            return compareCharacters(a, b, sortColumn, sortAscending, pinnedLookup)
        end)
    end

    return characters
end

-- private functions
local function tryLogin(charInfo, tries)
    tries = tries or 1

    if ClientLauncherUpdate and ClientLauncherUpdate.blockLoginIfRequired and
       ClientLauncherUpdate.blockLoginIfRequired() then
        return
    end

    if tries > 50 then
        return
    end

    if g_game.isOnline() then
        if tries == 1 then
            g_game.safeLogout()
			if loginEvent then
				removeEvent(loginEvent)
				loginEvent = nil
			end
        end
        loginEvent = scheduleEvent(function()
            tryLogin(charInfo, tries + 1)
        end, 100)
        return
    end

    if elementalDesktopLayout then
        setWorldLoginPending(true)
        setWorldLoginStatus('Conectando ao mundo...', false)
    else
        CharacterList.hide()
    end

    if os.getenv("ELEMENTAL_LOCAL_TEST") == "1" then
        g_logger.info(("Elemental local test world target: %s:%s"):format(
            tostring(charInfo.worldHost), tostring(charInfo.worldPort)))
        g_logger.info(("Elemental local test protocol: client=%s protocol=%s challenge=%s rsa=%s checksum=%s session=%s"):format(
            tostring(g_game.getClientVersion()), tostring(g_game.getProtocolVersion()),
            tostring(g_game.getFeature(GameChallengeOnLogin)), tostring(g_game.getFeature(GameLoginPacketEncryption)),
            tostring(g_game.getFeature(GameProtocolChecksum)), tostring(g_game.getFeature(GameSessionKey))))
        g_logger.info(("Elemental local test session transport: %s"):format(
            G.sessionKey and G.sessionKey:sub(1, 3) == 'b1.' and 'secure token' or 'plain account session'))
    end

    g_game.loginWorld(G.account, G.password, charInfo.worldName, charInfo.worldHost, charInfo.worldPort,
                      charInfo.characterName, G.authenticatorToken, G.sessionKey)

    if not elementalDesktopLayout then
        loadBox = displayCancelBox(tr('Please wait'), tr('Connecting to game server...'))
        connect(loadBox, {
            onCancel = function()
                loadBox = nil
                g_game.cancelLogin()
                CharacterList.show()
            end
        })
    end

    -- save last used character
    g_settings.set('last-used-character', charInfo.characterName)
    g_settings.set('last-used-world', charInfo.worldName)
    removeAutoReconnectEvent()
end

local function updateWait(timeStart, timeEnd)
    if elementalDesktopLayout and worldLoginPending then
        local time = g_clock.seconds()
        if time <= timeEnd then
            local timeStr = string.format('%.0f', timeEnd - time)
            setWorldLoginStatus(('Na fila do mundo · %s s'):format(timeStr), false)
            updateWaitEvent = scheduleEvent(function()
                updateWait(timeStart, timeEnd)
            end, 1000)
            return true
        end
    end

    if waitingWindow then
        local time = g_clock.seconds()
        if time <= timeEnd then
            local percent = ((time - timeStart) / (timeEnd - timeStart)) * 100
            local timeStr = string.format('%.0f', timeEnd - time)

            local progressBar = waitingWindow:getChildById('progressBar')
            progressBar:setPercent(percent)

            local label = waitingWindow:getChildById('timeLabel')
            label:setText(tr('Trying to reconnect in %s seconds.', timeStr))

            updateWaitEvent = scheduleEvent(function()
                updateWait(timeStart, timeEnd)
            end, 1000 * progressBar:getPercentPixels() / 100 * (timeEnd - timeStart))
            return true
        end
    end

    if updateWaitEvent then
        updateWaitEvent:cancel()
        updateWaitEvent = nil
    end
end

local function resendWait()
    local desktopWaiting = elementalDesktopLayout and worldLoginPending
    if waitingWindow or desktopWaiting then
        if waitingWindow then
            waitingWindow:destroy()
            waitingWindow = nil
        end

        if updateWaitEvent then
            updateWaitEvent:cancel()
            updateWaitEvent = nil
        end

        if charactersWindow then
            local selected = characterList:getFocusedChild()
            if selected then
                local charInfo = {
                    worldHost = selected.worldHost,
                    worldPort = selected.worldPort,
                    worldName = selected.worldName,
                    characterName = selected.characterName,
                    characterLevel = selected.characterLevel,
                    main = selected.main,
                    dailyreward = selected.dailyreward,
                    hidden = selected.hidden,
                    outfitid = selected.outfitid,
                    headcolor = selected.headcolor,
                    torsocolor = selected.torsocolor,
                    legscolor = selected.legscolor,
                    detailcolor = selected.detailcolor,
                    addonsflags = selected.addonsflags,
                    characterVocation = selected.characterVocation
                }
                tryLogin(charInfo)
            end
        end
    end
end

local function onLoginWait(message, time)
    CharacterList.destroyLoadBox()

    if elementalDesktopLayout and worldLoginPending then
        setWorldLoginStatus('Aguardando a disponibilidade do mundo...', false)
        updateWaitEvent = scheduleEvent(function()
            updateWait(g_clock.seconds(), g_clock.seconds() + time)
        end, 0)
        resendWaitEvent = scheduleEvent(resendWait, time * 1000)
        return
    end

    waitingWindow = g_ui.displayUI('waitinglist')

    local label = waitingWindow:getChildById('infoLabel')
    label:setText(message)

    updateWaitEvent = scheduleEvent(function()
        updateWait(g_clock.seconds(), g_clock.seconds() + time)
    end, 0)
    resendWaitEvent = scheduleEvent(resendWait, time * 1000)
end

function onGameLoginError(message)
    CharacterList.destroyLoadBox()
    if elementalDesktopLayout and worldLoginPending then
        setWorldLoginPending(false)
        setWorldLoginStatus(message or 'Não foi possível entrar no mundo.', true)
        CharacterList.show()
        return
    end
    errorBox = displayErrorBox(tr('Login Error'), message)
    errorBox.onOk = function()
        errorBox = nil
        CharacterList.showAgain()
    end
end

function onGameSessionEnd(reason)
    CharacterList.destroyLoadBox()
    if elementalDesktopLayout and worldLoginPending then
        setWorldLoginPending(false)
        setWorldLoginStatus('A sessão foi encerrada. Tente entrar novamente.', true)
        CharacterList.show()
        return
    end
    CharacterList.showAgain()
end

function onGameConnectionError(message, code)
    CharacterList.destroyLoadBox()
    if elementalDesktopLayout and worldLoginPending then
        local status = 'Não foi possível conectar ao mundo. Tente novamente.'
        if code == 111 or code == 61 then
            status = 'O mundo está offline ou reiniciando. Tente novamente mais tarde.'
        elseif code == 110 then
            status = 'O mundo não respondeu. Tente novamente em instantes.'
        elseif isNetworkAddressResolutionError(code, message) then
            status = 'O endereço do mundo não está disponível.'
        end
        setWorldLoginPending(false)
        setWorldLoginStatus(status, true)
        CharacterList.show()
        return
    end
    local text = translateNetworkError(code, g_game.getProtocolGame() and g_game.getProtocolGame():isConnecting(),
                                       message)
    errorBox = displayErrorBox(tr('Connection Error'), text)
    errorBox.onOk = function()
        errorBox = nil
        CharacterList.showAgain()
    end
end

function onGameUpdateNeeded(signature)
    CharacterList.destroyLoadBox()
    if elementalDesktopLayout and worldLoginPending then
        setWorldLoginPending(false)
        setWorldLoginStatus('O cliente precisa ser atualizado antes de entrar no mundo.', true)
        CharacterList.show()
        return
    end
    errorBox = displayErrorBox(tr('Update needed'), tr('Enter with your account again to update your client.'))
    errorBox.onOk = function()
        errorBox = nil
        CharacterList.showAgain()
    end
end

local function onGameStart()
    CharacterList.destroyLoadBox()
    setWorldLoginPending(false)
    setWorldLoginStatus(nil, false)
    if elementalDesktopLayout then
        CharacterList.hide()
    end
end

function onSortButtonClick(button, columnIndex)
    if not shouldShowAppearance() then
        return
    end

    local sortColumn = getSortColumn()
    local sortAscending = getSortAscending()
    if sortColumn == columnIndex then
        sortAscending = not sortAscending
    else
        sortColumn = columnIndex
        sortAscending = true
    end

    g_settings.set(SORT_COLUMN_SETTING, sortColumn)
    g_settings.set(SORT_ASCENDING_SETTING, sortAscending)
    CharacterList.rebuildCharactersList()
end

function onShowHiddenCharacters(widget, isChecked)
    if suppressCheckCallbacks then return end
    setShowHiddenCharacters(isChecked)
    CharacterList.rebuildCharactersList()
end

function onShowOutfits(widget, isChecked)
    if suppressCheckCallbacks then return end
    setShowOutfits(isChecked)
    CharacterList.updateCharactersAppearances(isChecked)
end

function onPinCharacter(widget, isChecked)
    if suppressCheckCallbacks then return end
    if not shouldShowAppearance() then return end

    local parentWidget = widget and widget:getParent()
    if not parentWidget or not parentWidget.characterName then
        return
    end

    setCharacterPinned(parentWidget.characterName, parentWidget.worldName, toBoolean(isChecked, false))
    CharacterList.rebuildCharactersList()
end

function onPremiumButtonClick(widget)
    if Services and Services.getCoinsUrl and Services.getCoinsUrl ~= '' then
        g_platform.openUrl(Services.getCoinsUrl)
        return
    end
    local info = debug.getinfo(1, "Slfn")
    local filename = info.short_src or "unknown_file"
    local line = info.currentline or 0
    local funcname = info.name or "unknown_function"
    displayInfoBox(
        tr('Information'),
        string.format(
            "[%s:%d - %s] Premium URL not configured. Please contact the server administrator.",
            filename,
            line,
            funcname
        )
    )
end

-- public functions
function CharacterList.closeCharacterAssembly(force)
    if characterAssemblyCreatePending and not force then
        return false
    end
    characterAssemblyRequestSerial = characterAssemblyRequestSerial + 1
    characterAssemblyOptionsPending = false
    characterAssemblyCreatePending = false
    characterAssemblyCatalog = {}
    if characterAssemblyWindow then
        characterAssemblyWindow:destroy()
        characterAssemblyWindow = nil
    end
    if elementalDesktopLayout and charactersWindow then
        local detailsPanel = charactersWindow:recursiveGetChildById('characterDetailsPanel')
        if detailsPanel then
            detailsPanel:show()
        end
    end
    return true
end

function CharacterList.cancelCharacterAssembly()
    if not CharacterList.closeCharacterAssembly() then
        return false
    end

    local selected = characterList and characterList:getFocusedChild()
    if selected and selected.characterInfo then
        updateSelectedCharacter(selected)
        return true
    end

    if characterList then
        for _, entry in ipairs(characterList:getChildren()) do
            if entry.characterInfo then
                characterList:focusChild(entry, KeyboardFocusReason)
                return true
            end
        end
    end

    if charactersWindow then
        local details = charactersWindow:recursiveGetChildById('selectedCharacterDetails')
        local emptyState = charactersWindow:recursiveGetChildById('selectedCharacterEmpty')
        local enterButton = charactersWindow:recursiveGetChildById('buttonOk')
        if details then details:hide() end
        if emptyState then
            local message = G.characters and #G.characters > 0 and
                'Selecione um personagem para ver sua ficha.' or
                'Crie seu primeiro personagem para entrar no mundo Elemental.'
            emptyState:setText(message)
            emptyState:show()
        end
        if enterButton then enterButton:hide() end
    end
    return true
end

function CharacterList.closeAccountManagement(force)
    if accountRequestPending and not force then
        return false
    end
    accountRequestSerial = accountRequestSerial + 1
    accountRequestPending = false
    accountPendingEmail = nil
    clearAccountSensitiveFields()
    if accountManagementWindow then
        accountManagementWindow:destroy()
        accountManagementWindow = nil
    end
    return true
end

function CharacterList.closeFirstPasswordChange(force)
    if firstPasswordRequestPending and not force then
        return false
    end
    cancelFirstPasswordKeyboardReflow()
    firstPasswordRequestSerial = firstPasswordRequestSerial + 1
    firstPasswordRequestPending = false
    clearFirstPasswordFields()
    firstPasswordEmail = nil
    firstPasswordInitialPassword = nil
    if firstPasswordWindow then
        firstPasswordWindow:destroy()
        firstPasswordWindow = nil
    end
    return true
end

function CharacterList.cancelFirstPasswordChange()
    if not CharacterList.closeFirstPasswordChange() then
        return false
    end
    EnterGame.show()
    if EnterGame and EnterGame.prepareBetaRelogin then
        EnterGame.prepareBetaRelogin('')
    end
    EnterGame.setLoginStatus('A senha inicial continua ativa. Digite sua conta e senha para tentar novamente.', true)
    return true
end

function CharacterList.openFirstPasswordChange(email, initialPassword)
    if not isBetaLogin() or type(email) ~= 'string' or email == '' or
        type(initialPassword) ~= 'string' or initialPassword == '' then
        return false
    end
    CharacterList.closeFirstPasswordChange(true)
    g_ui.importStyle('elemental_brand')
    g_ui.importStyle('characterlist')
    firstPasswordEmail = email
    firstPasswordInitialPassword = initialPassword
    firstPasswordWindow = g_ui.createWidget('ElementalBetaFirstPasswordWindow', rootWidget)
    getFirstPasswordWidget('firstPasswordEmailValue'):setText(maskEmail(email))

    getFirstPasswordWidget('firstPasswordSubmitButton').onClick = function()
        EnterGame.playUiClickSound()
        if firstPasswordRequestPending then
            return
        end

        local newPassword = getFirstPasswordWidget('firstPasswordNewEdit'):getText()
        local confirmedPassword = getFirstPasswordWidget('firstPasswordConfirmEdit'):getText()
        if #newPassword < 12 or #newPassword > 1024 or newPassword ~= confirmedPassword then
            setFirstPasswordStatus('Digite uma senha nova com pelo menos 12 caracteres e confirme a mesma senha.', true)
            return
        end
        if newPassword == firstPasswordInitialPassword then
            setFirstPasswordStatus('A senha nova precisa ser diferente da senha inicial.', true)
            return
        end

        local endpoint = getElementalEndpoint('account/first-password')
        if not endpoint then
            setFirstPasswordStatus('O serviço de troca inicial de senha está indisponível.', true)
            return
        end

        firstPasswordRequestSerial = firstPasswordRequestSerial + 1
        local requestSerial = firstPasswordRequestSerial
        local requestEmail = firstPasswordEmail
        local requestInitialPassword = firstPasswordInitialPassword
        firstPasswordRequestPending = true
        clearFirstPasswordFields()
        setFirstPasswordStatus('Atualizando sua senha…', false)
        updateFirstPasswordButtons()

        local function onFirstPasswordChanged(message, err)
            if requestSerial ~= firstPasswordRequestSerial or not firstPasswordWindow then
                return
            end
            firstPasswordRequestPending = false
            local response = type(message) == 'table' and message or decodeElementalResponse(message, err)
            if response and response.contractVersion == ELEMENTAL_CONTRACT_VERSION and
                response.success == true and response.requiresLogin == true then
                CharacterList.closeFirstPasswordChange(true)
                EnterGame.show()
                EnterGame.prepareBetaRelogin('')
                EnterGame.setLoginStatus('Senha atualizada. Digite sua conta e a senha nova para entrar.', false)
                return
            end

            local messages = {
                invalid_credentials = 'A senha inicial não foi aceita. Volte ao login e tente novamente.',
                password_confirmation_mismatch = 'As senhas digitadas não coincidem. Digite-as novamente.',
                password_must_change = 'Escolha uma senha diferente da senha inicial.',
                login_unavailable = 'Muitas tentativas. Aguarde antes de tentar de novo.',
                account_change_unavailable = 'O serviço de contas está indisponível. Tente novamente.',
            }
            setFirstPasswordStatus(messages[response and response.errorCode] or
                'Não foi possível atualizar a senha. Confira a conexão e tente novamente.', true)
            updateFirstPasswordButtons()
        end

        local ok, operation = pcall(function()
            return HTTP.postSecureJSON(endpoint, {
                contractVersion = ELEMENTAL_CONTRACT_VERSION,
                email = requestEmail,
                currentPassword = requestInitialPassword,
                newPassword = newPassword,
                confirmPassword = confirmedPassword,
            }, onFirstPasswordChanged, ACCOUNT_CHANGE_TIMEOUT_SECONDS)
        end)
        if (not ok or type(operation) ~= 'number' or operation < 0) and firstPasswordRequestPending then
            firstPasswordRequestPending = false
            setFirstPasswordStatus('Não foi possível iniciar a troca segura da senha. Tente novamente.', true)
            updateFirstPasswordButtons()
        end
    end

    getFirstPasswordWidget('firstPasswordCancelButton').onClick = function()
        EnterGame.playUiClickSound()
        CharacterList.cancelFirstPasswordChange()
    end
    firstPasswordWindow:show()
    firstPasswordWindow:raise()
    firstPasswordWindow:focus()
    getFirstPasswordWidget('firstPasswordNewEdit'):focus()
    applyFirstPasswordKeyboardLayout()
    scheduleFirstPasswordKeyboardReflow()
    setFirstPasswordStatus('', false)
    updateFirstPasswordButtons()
    return true
end

local function updateAccountButtons()
    if not accountManagementWindow then
        return
    end
    for _, id in ipairs({
        'passwordCurrentEdit', 'passwordNewEdit', 'passwordConfirmEdit',
        'emailCurrentPasswordEdit', 'emailNewAddressEdit', 'emailCodeEdit'
    }) do
        local field = getAccountWidget(id)
        if accountRequestPending then
            field:disable()
        else
            field:enable()
        end
    end
    getAccountWidget('changePasswordButton'):setEnabled(not accountRequestPending)
    getAccountWidget('requestEmailCodeButton'):setEnabled(not accountRequestPending)
    getAccountWidget('confirmEmailButton'):setEnabled(not accountRequestPending and accountPendingEmail ~= nil)
    getAccountWidget('closeAccountButton'):setEnabled(not accountRequestPending)
end

local function handleAccountApiFailure(response, err)
    local errorCode = response and response.errorCode
    if errorCode == 'invalid_session' or err == 'invalid_session' then
        clearBetaSessionAndRelogin(G.account, 'Your session expired. Log in again to continue.')
        return true
    end
    if accountManagementWindow then
        setAccountStatus(getAccountApiError(response), true)
    end
    return false
end

function CharacterList.openAccountManagement()
    if not isBetaLogin() or type(G.sessionKey) ~= 'string' then
        return
    end
    if accountManagementWindow then
        accountManagementWindow:show()
        accountManagementWindow:raise()
        accountManagementWindow:focus()
        return
    end

    accountRequestSerial = accountRequestSerial + 1
    accountRequestPending = false
    accountPendingEmail = nil
    accountManagementWindow = g_ui.createWidget('ElementalBetaAccountWindow', rootWidget)
    getAccountWidget('currentEmailValue'):setText(maskEmail(G.account))

    getAccountWidget('changePasswordButton').onClick = function()
        EnterGame.playUiClickSound()
        if accountRequestPending then
            return
        end
        local currentPassword = getAccountWidget('passwordCurrentEdit'):getText()
        local newPassword = getAccountWidget('passwordNewEdit'):getText()
        local confirmedPassword = getAccountWidget('passwordConfirmEdit'):getText()
        if currentPassword == '' or #newPassword < 12 or #newPassword > 1024 or
            newPassword ~= confirmedPassword then
            setAccountStatus('Enter the current password and matching new passwords (12–1024 characters).', true)
            return
        end

        accountRequestSerial = accountRequestSerial + 1
        local requestSerial = accountRequestSerial
        accountRequestPending = true
        clearAccountSensitiveFields()
        setAccountStatus('Changing password. Please wait...', false)
        updateAccountButtons()
        requestAccountChange('account/password', {
            contractVersion = ELEMENTAL_CONTRACT_VERSION,
            currentPassword = currentPassword,
            newPassword = newPassword,
        }, function(message, err)
            if requestSerial ~= accountRequestSerial or not accountManagementWindow then
                return
            end
            accountRequestPending = false
            local response = decodeElementalResponse(message, err)
            if not response or response.contractVersion ~= ELEMENTAL_CONTRACT_VERSION or
                response.success ~= true or response.requiresLogin ~= true then
                if not handleAccountApiFailure(response, err) then
                    updateAccountButtons()
                end
                return
            end
            clearBetaSessionAndRelogin(G.account, 'Password changed. Log in again with your new password.')
        end)
    end

    getAccountWidget('requestEmailCodeButton').onClick = function()
        EnterGame.playUiClickSound()
        if accountRequestPending then
            return
        end
        local currentPassword = getAccountWidget('emailCurrentPasswordEdit'):getText()
        local newEmail = getAccountWidget('emailNewAddressEdit'):getText():match('^%s*(.-)%s*$'):lower()
        if currentPassword == '' or newEmail == '' then
            setAccountStatus('Enter the current password and the new email address.', true)
            return
        end

        accountRequestSerial = accountRequestSerial + 1
        local requestSerial = accountRequestSerial
        accountRequestPending = true
        clearAccountSensitiveFields()
        setAccountStatus('Requesting email confirmation...', false)
        updateAccountButtons()
        requestAccountChange('account/email-change', {
            contractVersion = ELEMENTAL_CONTRACT_VERSION,
            currentPassword = currentPassword,
            newEmail = newEmail,
        }, function(message, err)
            if requestSerial ~= accountRequestSerial or not accountManagementWindow then
                return
            end
            accountRequestPending = false
            local response = decodeElementalResponse(message, err)
            if not response or response.contractVersion ~= ELEMENTAL_CONTRACT_VERSION or response.success ~= true then
                if not handleAccountApiFailure(response, err) then
                    updateAccountButtons()
                end
                return
            end
            accountPendingEmail = newEmail
            setAccountStatus(
                'If ' .. maskEmail(accountPendingEmail) .. ' can be used, a code was sent. Your current email stays active until confirmation.',
                false
            )
            updateAccountButtons()
        end)
    end

    getAccountWidget('confirmEmailButton').onClick = function()
        EnterGame.playUiClickSound()
        if accountRequestPending or not accountPendingEmail then
            return
        end
        local code = getAccountWidget('emailCodeEdit'):getText():match('^%s*(.-)%s*$')
        if code == '' then
            setAccountStatus('Enter the confirmation code from the new email inbox.', true)
            return
        end

        accountRequestSerial = accountRequestSerial + 1
        local requestSerial = accountRequestSerial
        local confirmedEmail = accountPendingEmail
        accountRequestPending = true
        clearAccountSensitiveFields()
        setAccountStatus('Confirming email address...', false)
        updateAccountButtons()
        requestAccountChange('account/email-change/confirm', {
            contractVersion = ELEMENTAL_CONTRACT_VERSION,
            code = code,
        }, function(message, err)
            if requestSerial ~= accountRequestSerial or not accountManagementWindow then
                return
            end
            accountRequestPending = false
            local response = decodeElementalResponse(message, err)
            if not response or response.contractVersion ~= ELEMENTAL_CONTRACT_VERSION or
                response.success ~= true or response.requiresLogin ~= true then
                if not handleAccountApiFailure(response, err) then
                    updateAccountButtons()
                end
                return
            end
            clearBetaSessionAndRelogin(confirmedEmail, 'Email changed. Log in again with the new address.')
        end)
    end

    getAccountWidget('closeAccountButton').onClick = function()
        EnterGame.playUiClickSound()
        CharacterList.closeAccountManagement()
    end
    accountManagementWindow:show()
    accountManagementWindow:raise()
    accountManagementWindow:focus()
    getAccountWidget('passwordCurrentEdit'):focus()
    setAccountStatus('Secrets are sent only over the protected beta session and cleared from this form.', false)
    updateAccountButtons()
end

function CharacterList.reloadCharacterOptions()
    if not characterAssemblyWindow or characterAssemblyOptionsPending or characterAssemblyCreatePending then
        return
    end

    local sex = getComboData(getAssemblyWidget('sexCombo'))
    if not isInteger(sex) or (sex ~= 0 and sex ~= 1) then
        setAssemblyStatus('Select a sex to load available appearances.', true)
        return
    end

    local endpoint = getElementalEndpoint('character-options')
    local betaLogin = type(G.host) == 'string' and G.host:match('^https://[^/]+/beta/v1/login$')
    if not endpoint or (betaLogin and type(G.sessionKey) ~= 'string') or
        (not betaLogin and (type(G.account) ~= 'string' or G.account == '' or
        type(G.password) ~= 'string' or G.password == '')) then
        setAssemblyStatus('Character service is unavailable. Please log in again.', true)
        return
    end

    characterAssemblyRequestSerial = characterAssemblyRequestSerial + 1
    local requestSerial = characterAssemblyRequestSerial
    characterAssemblyOptionsPending = true
    getAssemblyWidget('sexCombo'):disable()
    clearAppearanceChoices()
    getAssemblyWidget('retryOptionsButton'):hide()
    setAssemblyStatus('Loading character options...', false)
    updateAssemblySubmitButton()

    local request = { contractVersion = ELEMENTAL_CONTRACT_VERSION, sex = sex }
    if not betaLogin then
        request.email = G.account
        request.password = G.password
    end
    postCharacterRequest(endpoint, request, function(message, err)
        if requestSerial ~= characterAssemblyRequestSerial or not characterAssemblyWindow then
            return
        end

        characterAssemblyOptionsPending = false
        getAssemblyWidget('sexCombo'):enable()
        local response = decodeElementalResponse(message, err)
        if not response or not validateCharacterCatalog(response, sex) then
            if response and response.errorCode == 'invalid_session' then
                clearBetaSessionAndRelogin(G.account, 'Your session expired. Log in again to continue.')
                return
            end
            setAssemblyStatus(response and getCharacterApiError(response) or 'Character options are unavailable. Try again.', true)
            getAssemblyWidget('retryOptionsButton'):show()
            updateAssemblySubmitButton()
            return
        end

        local raceCombo = getAssemblyWidget('raceCombo')
        local vocationCombo = getAssemblyWidget('vocationCombo')
        local selectedRace = getComboData(raceCombo)
        local selectedVocation = getComboData(vocationCombo)
        setComboOptions(raceCombo, 'Select race', response.races, 'name', 'raceId', selectedRace)
        setComboOptions(vocationCombo, 'Select vocation', response.vocations, 'name', 'vocationId', selectedVocation)
        raceCombo:enable()
        vocationCombo:enable()
        characterAssemblyCatalog.races = response.races
        characterAssemblyCatalog.vocations = response.vocations
        characterAssemblyCatalog.appearances = response.appearances

        local appearanceCombo = getAssemblyWidget('appearanceCombo')
        setComboOptions(appearanceCombo, 'Select appearance', response.appearances, 'name', 'lookType')
        appearanceCombo:enable()
        if #response.appearances == 0 then
            setAssemblyStatus('No appearances are available for this sex.', true)
        else
            setAssemblyStatus('Choose your race, vocation and appearance.', false)
        end
        updateAssemblySubmitButton()
    end, false)
end

function CharacterList.openCharacterAssembly()
    if characterAssemblyWindow then
        characterAssemblyWindow:show()
        characterAssemblyWindow:raise()
        characterAssemblyWindow:focus()
        return
    end

    if not G.characters or (not isBetaLogin() and #G.characters ~= 0) then
        return
    end

    local assemblyWindowStyle = elementalDesktopLayout and 'ElementalDesktopCharacterAssemblyWindow' or
        'ElementalCharacterAssemblyWindow'
    characterAssemblyWindow = g_ui.createWidget(assemblyWindowStyle,
        elementalDesktopLayout and charactersWindow or rootWidget)
    if elementalDesktopLayout then
        local detailsPanel = charactersWindow:recursiveGetChildById('characterDetailsPanel')
        if detailsPanel then
            detailsPanel:hide()
        end
    end
    characterAssemblyCatalog = {}
    characterAssemblyOptionsPending = false
    characterAssemblyCreatePending = false

    local sexCombo = getAssemblyWidget('sexCombo')
    local raceCombo = getAssemblyWidget('raceCombo')
    local vocationCombo = getAssemblyWidget('vocationCombo')
    local appearanceCombo = getAssemblyWidget('appearanceCombo')
    local nameEdit = getAssemblyWidget('characterNameEdit')

    setComboPrompt(sexCombo, 'Select sex')
    sexCombo:addOption(localizeAssemblyText('Female'), 0)
    sexCombo:addOption(localizeAssemblyText('Male'), 1)
    sexCombo.onOptionChange = function(comboBox, _, sex)
        if suppressCharacterAssemblyCallbacks then return end
        clearAppearanceChoices()
        if isInteger(sex) and (sex == 0 or sex == 1) then
            CharacterList.reloadCharacterOptions()
        else
            setAssemblyStatus('Select a sex to load available appearances.', false)
        end
    end

    setComboPrompt(raceCombo, 'Select race')
    setComboPrompt(vocationCombo, 'Select vocation')
    raceCombo:disable()
    vocationCombo:disable()
    setComboPrompt(appearanceCombo, 'Select appearance')
    appearanceCombo:disable()

    local colorPrompts = {
        'headColorCombo', 'bodyColorCombo', 'legsColorCombo', 'feetColorCombo', 'addonsCombo'
    }
    for _, id in ipairs(colorPrompts) do
        local comboBox = getAssemblyWidget(id)
        setComboPrompt(comboBox, 'Select')
        comboBox:disable()
        comboBox.onOptionChange = function()
            if suppressCharacterAssemblyCallbacks then return end
            updateAssemblyPreview()
            updateAssemblySubmitButton()
        end
    end

    appearanceCombo.onOptionChange = function(comboBox, _, lookType)
        if suppressCharacterAssemblyCallbacks then return end
        local sex = getComboData(sexCombo)
        local appearance = isInteger(lookType) and findAppearance(lookType, sex) or nil
        if not appearance then
            clearAppearanceChoices()
            return
        end
        getAssemblyWidget('appearanceLabel'):setText(localizeAssemblyText('Appearance:') .. ' ' .. appearance.name)
        populateAppearanceColors(appearance)
        updateAssemblyPreview()
        setAssemblyStatus('Select all four colors and addons.', false)
        updateAssemblySubmitButton()
    end

    for _, id in ipairs({ 'raceCombo', 'vocationCombo' }) do
        getAssemblyWidget(id).onOptionChange = function()
            if suppressCharacterAssemblyCallbacks then return end
            updateAssemblySubmitButton()
        end
    end

    nameEdit.onTextChange = function()
        updateAssemblySubmitButton()
    end
    getAssemblyWidget('retryOptionsButton').onClick = function()
        EnterGame.playUiClickSound()
        CharacterList.reloadCharacterOptions()
    end
    getAssemblyWidget('refreshCharactersButton').onClick = function()
        EnterGame.playUiClickSound()
        if characterAssemblyCreatePending then
            return
        end
        characterAssemblyCreatePending = true
        setAssemblyStatus('Refreshing character list...', false)
        getAssemblyWidget('refreshCharactersButton'):disable()
        getAssemblyWidget('cancelAssemblyButton'):disable()
        refreshBetaCharacterList(function(characters, errorCode)
            if not characterAssemblyWindow then
                return
            end
            characterAssemblyCreatePending = false
            if not characters then
                if errorCode == 'invalid_session' then
                    clearBetaSessionAndRelogin(G.account, 'Your session expired. Log in again to continue.')
                    return
                end
                setAssemblyStatus(getCharacterApiError({ errorCode = errorCode }), true)
                getAssemblyWidget('refreshCharactersButton'):enable()
                getAssemblyWidget('cancelAssemblyButton'):enable()
                return
            end
            applyBetaCharacterList(characters)
        end)
    end
    getAssemblyWidget('cancelAssemblyButton').onClick = function()
        EnterGame.playUiClickSound()
        CharacterList.cancelCharacterAssembly()
    end
    getAssemblyWidget('createCharacterButton').onClick = function()
        EnterGame.playUiClickSound()
        if not canSubmitCharacter() then
            setAssemblyStatus('Complete every field before creating the character.', true)
            return
        end

        local endpoint = getElementalEndpoint('characters')
        local betaLogin = type(G.host) == 'string' and G.host:match('^https://[^/]+/beta/v1/login$')
        if not endpoint or (betaLogin and type(G.sessionKey) ~= 'string') or
            (not betaLogin and (type(G.account) ~= 'string' or G.account == '' or
            type(G.password) ~= 'string' or G.password == '')) then
            setAssemblyStatus('Character service is unavailable. Please log in again.', true)
            return
        end

        local sex = getComboData(sexCombo)
        local payload = {
            contractVersion = ELEMENTAL_CONTRACT_VERSION,
            characterName = nameEdit:getText(),
            raceId = getComboData(raceCombo),
            vocationId = getComboData(vocationCombo),
            appearance = {
                sex = sex,
                lookType = getComboData(appearanceCombo),
                headColor = getComboData(getAssemblyWidget('headColorCombo')),
                bodyColor = getComboData(getAssemblyWidget('bodyColorCombo')),
                legsColor = getComboData(getAssemblyWidget('legsColorCombo')),
                feetColor = getComboData(getAssemblyWidget('feetColorCombo')),
                addons = getComboData(getAssemblyWidget('addonsCombo'))
            }
        }
        if not betaLogin then
            payload.email = G.account
            payload.password = G.password
        end

        characterAssemblyCreatePending = true
        characterAssemblyRequestSerial = characterAssemblyRequestSerial + 1
        local requestSerial = characterAssemblyRequestSerial
        getAssemblyWidget('createCharacterButton'):disable()
        getAssemblyWidget('cancelAssemblyButton'):disable()
        setAssemblyStatus('Creating character...', false)
        postCharacterRequest(endpoint, payload, function(message, err)
            if requestSerial ~= characterAssemblyRequestSerial or not characterAssemblyWindow then
                return
            end
            local response = decodeElementalResponse(message, err)
            if betaLogin and err and isHttpClientError(err) then
                characterAssemblyCreatePending = false
                if response and response.errorCode == 'invalid_session' then
                    clearBetaSessionAndRelogin(G.account, 'Your session expired. Log in again to continue.')
                    return
                end
                setAssemblyStatus(getCharacterApiError(response), true)
                getAssemblyWidget('cancelAssemblyButton'):enable()
                updateAssemblySubmitButton()
                return
            end
            if betaLogin and (err or not response) then
                setAssemblyStatus('Checking whether the character was created...', false)
                refreshBetaCharacterList(function(characters, errorCode)
                    if not characterAssemblyWindow then
                        return
                    end
                    characterAssemblyCreatePending = false
                    if errorCode == 'invalid_session' then
                        clearBetaSessionAndRelogin(G.account, 'Your session expired. Log in again to continue.')
                        return
                    end
                    local wasCreated = false
                    for _, character in ipairs(characters or {}) do
                        if character.name == payload.characterName then
                            wasCreated = true
                            break
                        end
                    end
                    if wasCreated then
                        applyBetaCharacterList(characters)
                        return
                    end
                    setAssemblyStatus('No character was confirmed. Check the list and try again.', true)
                    getAssemblyWidget('cancelAssemblyButton'):enable()
                    updateAssemblySubmitButton()
                end)
                return
            end
            characterAssemblyCreatePending = false
            if not response or response.contractVersion ~= ELEMENTAL_CONTRACT_VERSION or
                response.success ~= true or response.characterName ~= payload.characterName then
                if response and response.errorCode == 'invalid_session' then
                    clearBetaSessionAndRelogin(G.account, 'Your session expired. Log in again to continue.')
                    return
                end
                setAssemblyStatus(getCharacterApiError(response), true)
                getAssemblyWidget('cancelAssemblyButton'):enable()
                updateAssemblySubmitButton()
                return
            end

            if betaLogin then
                getAssemblyWidget('createCharacterButton'):disable()
                getAssemblyWidget('refreshCharactersButton'):show()
                setAssemblyStatus('Character created. Refresh the list to continue.', false)
                characterAssemblyCreatePending = true
                refreshBetaCharacterList(function(characters, errorCode)
                    if not characterAssemblyWindow then
                        return
                    end
                    characterAssemblyCreatePending = false
                    if not characters then
                        if errorCode == 'invalid_session' then
                            clearBetaSessionAndRelogin(G.account, 'Your session expired. Log in again to continue.')
                            return
                        end
                        setAssemblyStatus('Character created, but the list could not refresh. Use Refresh List.', true)
                        getAssemblyWidget('refreshCharactersButton'):enable()
                        getAssemblyWidget('cancelAssemblyButton'):enable()
                        return
                    end
                    applyBetaCharacterList(characters)
                end)
            else
                CharacterList.closeCharacterAssembly()
                CharacterList.hide(false)
                if not EnterGame.reloadCharacterList() then
                    displayErrorBox(tr('Character created'), tr('Character was created. Log in again to see it.'))
                    CharacterList.show()
                end
            end
        end, betaLogin and ACCOUNT_CHANGE_TIMEOUT_SECONDS or false)
    end

    characterAssemblyWindow:show()
    characterAssemblyWindow:raise()
    characterAssemblyWindow:focus()
    if not g_platform.isMobile() then
        nameEdit:focus()
    end
    setAssemblyStatus('Choose every field. No selection is prefilled.', false)
    updateAssemblySubmitButton()
end

function CharacterList.init()
    connect(g_game, {
        onLoginError = onGameLoginError
    })
    connect(g_game, {
        onSessionEnd = onGameSessionEnd
    })
    connect(g_game, {
        onUpdateNeeded = onGameUpdateNeeded
    })
    connect(g_game, {
        onConnectionError = onGameConnectionError
    })
    connect(g_game, {
        onGameStart = onGameStart
    })
    connect(g_game, {
        onLoginWait = onLoginWait
    })
    connect(g_game, {
        onGameEnd = CharacterList.showAgain
    })
    connect(g_game, {
        onLogout = onLogout
    })

    if G.characters then
        CharacterList.create(G.characters, G.characterAccount)
    end
end

function CharacterList.terminate()
    setElementalBackgroundBlur(false)
    if worldLoginPending then
        g_game.cancelLogin()
        worldLoginPending = false
    end
    disconnect(g_game, {
        onLoginError = onGameLoginError
    })
    disconnect(g_game, {
        onSessionEnd = onGameSessionEnd
    })
    disconnect(g_game, {
        onUpdateNeeded = onGameUpdateNeeded
    })
    disconnect(g_game, {
        onConnectionError = onGameConnectionError
    })
    disconnect(g_game, {
        onGameStart = onGameStart
    })
    disconnect(g_game, {
        onLoginWait = onLoginWait
    })
    disconnect(g_game, {
        onGameEnd = CharacterList.showAgain
    })
    disconnect(g_game, {
        onLogout = onLogout
    })

    CharacterList.closeAccountManagement(true)
    CharacterList.closeFirstPasswordChange(true)
    CharacterList.closeCharacterAssembly(true)

    if charactersWindow then
        resetUIReferences()
        charactersWindow:destroy()
        charactersWindow = nil
    end

    if loadBox then
        g_game.cancelLogin()
        loadBox:destroy()
        loadBox = nil
    end

    if waitingWindow then
        waitingWindow:destroy()
        waitingWindow = nil
    end

    if updateWaitEvent then
        removeEvent(updateWaitEvent)
        updateWaitEvent = nil
    end

    if resendWaitEvent then
        removeEvent(resendWaitEvent)
        resendWaitEvent = nil
    end

    if loginEvent then
        removeEvent(loginEvent)
        loginEvent = nil
    end

    removeAutoReconnectEvent()
    destroyCreateAccount()

    CharacterList = nil
end

function CharacterList.create(characters, account, otui)
    elementalDesktopLayout = true
    worldLoginPending = false
    if elementalDesktopLayout then
        g_ui.importStyle('elemental_brand')
        g_ui.importStyle('characterlist')
        otui = 'characterlist_elemental_desktop'
    elseif not otui then
        otui = 'characterlist'
    end

    CharacterList.closeAccountManagement(true)
    CharacterList.closeCharacterAssembly(true)
    if charactersWindow then
        charactersWindow:destroy()
    end

    charactersWindow = g_ui.displayUI(otui)
    characterList = charactersWindow:recursiveGetChildById('characters')
    panelSort = charactersWindow:recursiveGetChildById('characterTable')
    autoReconnectButton = charactersWindow:recursiveGetChildById('autoReconnect')
    showHiddenCheckbox = charactersWindow:recursiveGetChildById('checkBoxHidden')
    showOutfitsCheckbox = charactersWindow:recursiveGetChildById('checkBoxOutfit')
    premiumBenefitsPanel = charactersWindow:recursiveGetChildById('premiumBenefitsPanel')
    premiumButton = charactersWindow:recursiveGetChildById('premiumButton')
    createCharacterButton = charactersWindow:recursiveGetChildById('buttonCreateCharacter')
    emptyCharacterPrompt = charactersWindow:recursiveGetChildById('emptyCharacterPrompt')
    accountManagementButton = charactersWindow:recursiveGetChildById('buttonAccount')
    accountManagementButton.onClick = function()
        EnterGame.playUiClickSound()
        CharacterList.openAccountManagement()
    end

    characterList.onChildFocusChange = function(self, focusedChild, oldFocusedChild)
        removeAutoReconnectEvent()
        if oldFocusedChild then oldFocusedChild:updateOnStates() end
        if focusedChild then
            focusedChild:updateOnStates()
            self:ensureChildVisible(focusedChild)
        end
        updateSelectedCharacter(focusedChild)
    end

    -- characters
    G.characters = characters
    G.characterAccount = account

    local accountStatusLabel = charactersWindow:recursiveGetChildById('accountStatusLabel')
    local accountStatusIcon = nil
    if shouldShowAppearance() then
        accountStatusIcon = charactersWindow:recursiveGetChildById('accountStatusIcon')
    end

    if showHiddenCheckbox then
        setCheckedWithoutCallback(showHiddenCheckbox, getShowHiddenCharacters())
    end

    if showOutfitsCheckbox then
        setCheckedWithoutCallback(showOutfitsCheckbox, getShowOutfits())
    end

    -- account
    local status = ''
    if elementalDesktopLayout and account.status == AccountStatus.Frozen then
        status = ' (Conta congelada)'
    elseif elementalDesktopLayout and account.status == AccountStatus.Suspended then
        status = ' (Conta suspensa)'
    elseif account.status == AccountStatus.Frozen then
        status = tr(' (Frozen)')
    elseif account.status == AccountStatus.Suspended then
        status = tr(' (Suspended)')
    end

    if account.subStatus == SubscriptionStatus.Free then
        local label = elementalDesktopLayout and 'Conta gratuita' or tr('Free Account')
        accountStatusLabel:setText(('%s%s'):format(label, status))
        if accountStatusIcon then
            accountStatusIcon:setImageSource('/images/game/entergame/nopremium')
        end
    elseif account.subStatus == SubscriptionStatus.Premium then
        if account.premDays == 0 or account.premDays == 65535 then
            local label = elementalDesktopLayout and 'Conta premium' or tr('Gratis Premium Account')
            accountStatusLabel:setText(('%s%s'):format(label, status))
        else
            local label = elementalDesktopLayout and
                ('Conta premium (%s dias)'):format(account.premDays) or
                tr('Premium Account (%s days left)', account.premDays)
            accountStatusLabel:setText(('%s%s'):format(label, status))
        end
        if accountStatusIcon then
            accountStatusIcon:setImageSource('/images/game/entergame/premium')
        end
    end

    if account.premDays > 0 and account.premDays <= 7 then
        accountStatusLabel:setOn(true)
    else
        accountStatusLabel:setOn(false)
    end

    updatePremiumBenefitsVisibility(account)

    CharacterList.rebuildCharactersList()

    if os.getenv("ELEMENTAL_LOCAL_TEST") == "1" and os.getenv("ELEMENTAL_TEST_AUTOLOGIN") ~= "0" and
        g_settings.getBoolean('autologin', false) then
        scheduleEvent(function()
            if not CharacterList.isVisible() or not characterList or not characterList:getFocusedChild() then
                return
            end

            CharacterList.doLogin()
        end, 300)
    end

    autoReconnectButton.onClick = function(widget)
        local autoReconnect = not g_settings.getBoolean('autoReconnect', false)
        autoReconnectButton:setOn(autoReconnect)
        g_settings.set('autoReconnect', autoReconnect)
        local statusText = autoReconnect and 'Auto reconnect: On' or 'Auto reconnect: off'
        if not shouldShowAppearance() then
            statusText = autoReconnect and 'Auto reconnect:\n On' or 'Auto reconnect:\n off'
        end

        autoReconnectButton:setText(statusText)
    end
end

function CharacterList.rebuildCharactersList()
    if not characterList then
        return
    end

    local showAppearance = shouldShowAppearance()
    local showOutfits = showAppearance and getShowOutfits()
    local oddRowColor = showAppearance and '#484848' or '#565656'
    local evenRowColor = showAppearance and '#414141' or '#4f4f4f'
    local focused = characterList:getFocusedChild()
    local focusName = focused and focused.characterName or g_settings.get('last-used-character')
    local focusWorld = focused and focused.worldName or g_settings.get('last-used-world')
    local preserveFocusedCharacter = focused and focused.characterInfo ~= nil
    local localTestMode = os.getenv("ELEMENTAL_LOCAL_TEST") == "1"
    local pinnedLookup = showAppearance and getPinnedCharacters() or {}

    if showHiddenCheckbox then
        setCheckedWithoutCallback(showHiddenCheckbox, getShowHiddenCharacters())
    end

    if showOutfitsCheckbox then
        setCheckedWithoutCallback(showOutfitsCheckbox, showOutfits)
    end

    local characters = buildCharacters(pinnedLookup)
    local focusLabel
    characterList:destroyChildren()

    local canCreateCharacter = type(G.characters) == 'table' and
        (isBetaLogin() or #G.characters == 0) and getElementalEndpoint('characters') ~= nil
    if createCharacterButton then
        createCharacterButton:setVisible(not elementalDesktopLayout and canCreateCharacter)
        createCharacterButton:setEnabled(not elementalDesktopLayout and canCreateCharacter)
    end
    if accountManagementButton then
        accountManagementButton:setVisible(isBetaLogin())
        accountManagementButton:setEnabled(isBetaLogin())
    end
    if emptyCharacterPrompt then
        local emptyText = elementalDesktopLayout and 'Nenhum personagem' or
            'This account has no characters yet. Create one before entering the world.'
        emptyCharacterPrompt:setText(emptyText)
        emptyCharacterPrompt:setVisible(not elementalDesktopLayout and #characters == 0 and canCreateCharacter)
    end
    local characterCountLabel = charactersWindow:recursiveGetChildById('characterCountLabel')
    if characterCountLabel then
        characterCountLabel:setText(string.format('%d personagem%s', #characters, #characters == 1 and '' or 's'))
    end
    local canShowCreateEntry = elementalDesktopLayout and type(G.characters) == 'table' and
        (#G.characters == 0 or canCreateCharacter)
    local navigationVisible = #characters + (canShowCreateEntry and 1 or 0) > 1
    for _, controlId in ipairs({ 'characterListUpButton', 'characterListDownButton' }) do
        local control = charactersWindow:recursiveGetChildById(controlId)
        if control then
            control:setVisible(navigationVisible)
        end
    end
    local enterCharacterButton = charactersWindow:recursiveGetChildById('buttonOk')
    if enterCharacterButton then
        enterCharacterButton:setVisible(not elementalDesktopLayout and #characters > 0)
        enterCharacterButton:setEnabled(not elementalDesktopLayout and #characters > 0)
    end

    for i, characterInfo in ipairs(characters) do
        local widgetStyle = elementalDesktopLayout and 'ElementalDesktopCharacterWidget' or 'CharacterWidget'
        local widget = g_ui.createWidget(widgetStyle, characterList)
        local rowColor = (i % 2 == 0) and evenRowColor or oddRowColor
        widget.rowColor = rowColor
        widget:setBackgroundColor(rowColor)
        widget.characterInfo = characterInfo
        for key, value in pairs(characterInfo) do
            local subWidget = widget:getChildById(key)
            if subWidget then
                if key == 'outfit' then -- it's an exception
                    subWidget:setOutfit(value)
                elseif key == 'worldName' and showAppearance then
                    subWidget:setText(getCharacterWorldLabel(characterInfo))
                else
                    local text = value
                    if subWidget.baseText and subWidget.baseTranslate then
                        text = tr(subWidget.baseText, text)
                    elseif subWidget.baseText then
                        text = string.format(subWidget.baseText, text)
                    end
                    subWidget:setText(text)
                end
            end
        end

        if showAppearance then
            CharacterList.updateCharactersAppearance(widget, characterInfo, showOutfits)
        end

        -- these are used by login
        widget.characterName = characterInfo.name
        widget.worldName = characterInfo.worldName
        widget.worldHost = characterInfo.worldIp
        widget.worldPort = characterInfo.worldPort

        local pinButton = widget:getChildById('pin')
        if pinButton then
            setCheckedWithoutCallback(pinButton, isCharacterPinned(widget.characterName, widget.worldName, pinnedLookup))
        end

        connect(widget, {
            onClick = function()
                if elementalDesktopLayout then
                    EnterGame.playUiClickSound()
                end
            end,
            onDoubleClick = function()
                CharacterList.doLogin()
                return true
            end
        })

        if elementalDesktopLayout then
            local matchesFocusedCharacter = preserveFocusedCharacter and focusName == widget.characterName and
                focusWorld == widget.worldName
            if matchesFocusedCharacter or (not preserveFocusedCharacter and i == 1) then
                focusLabel = widget
            end
        else
            local matchesLastCharacter = focusName and focusName == widget.characterName
            if localTestMode then
                if matchesLastCharacter then
                    focusLabel = widget
                end
            elseif matchesLastCharacter and focusWorld and focusWorld == widget.worldName then
                focusLabel = widget
            end

            if i == 1 and not focusLabel then
                focusLabel = widget
            end
        end
        widget:updateOnStates()
    end

    local createEntry
    if canShowCreateEntry then
        createEntry = g_ui.createWidget('ElementalDesktopCreateCharacterWidget', characterList)
        createEntry.isCreateCharacterEntry = true
        local name = createEntry:getChildById('name')
        name:setText(#G.characters == 0 and '+  Novo personagem' or '+  Criar novo personagem')
        name:setColor('#ffbd6b')
        createEntry:updateOnStates()
        if #characters == 0 then
            focusLabel = createEntry
        end
    end

    if focusLabel then
        characterList:focusChild(focusLabel, KeyboardFocusReason)
        updateSelectedCharacter(focusLabel)
        addEvent(function()
            characterList:ensureChildVisible(focusLabel)
        end)
    else
        updateSelectedCharacter(nil)
    end
    updateSortButtons()
end

function CharacterList.destroy()
    if worldLoginPending then
        CharacterList.cancelLogin()
    end
    CharacterList.closeAccountManagement(true)
    CharacterList.hide(true)

    if charactersWindow then
        resetUIReferences()
        charactersWindow:destroy()
        charactersWindow = nil
    end
end

function CharacterList.show()
    if loadBox or errorBox or not charactersWindow then
        return
    end
    if elementalDesktopLayout and modules.client_topmenu then
        modules.client_topmenu.hide()
    end
    setElementalBackgroundBlur(true)
    charactersWindow:show()
    charactersWindow:raise()
    charactersWindow:focus()

    if showHiddenCheckbox then
        setCheckedWithoutCallback(showHiddenCheckbox, getShowHiddenCharacters())
    end
    if showOutfitsCheckbox then
        setCheckedWithoutCallback(showOutfitsCheckbox, getShowOutfits())
    end

    updatePremiumBenefitsVisibility(G.characterAccount)
    updateSortButtons()

    local autoReconnect = g_settings.getBoolean('autoReconnect', false)
    autoReconnectButton:setOn(autoReconnect)
    local reconnectStatus = autoReconnect and 'On' or 'Off'
    if not shouldShowAppearance() then
        autoReconnectButton:setText('Auto reconnect:\n ' .. reconnectStatus)
    else
        autoReconnectButton:setText('Auto reconnect: ' .. reconnectStatus)
    end
end

function CharacterList.showWithTransition(duration)
    if not elementalDesktopLayout or not charactersWindow then
        CharacterList.show()
        return
    end

    duration = duration or 270

    local animatedWidgets = {}
    for _, widgetId in ipairs({ 'characterSidebar', 'characterDetailsPanel' }) do
        local widget = charactersWindow:recursiveGetChildById(widgetId)
        if widget then
            g_effects.cancelFade(widget)
            widget:setOpacity(0)
            table.insert(animatedWidgets, widget)
        end
    end

    if characterAssemblyWindow and characterAssemblyWindow:isVisible() then
        g_effects.cancelFade(characterAssemblyWindow)
        characterAssemblyWindow:setOpacity(0)
        table.insert(animatedWidgets, characterAssemblyWindow)
    end

    CharacterList.show()
    for _, widget in ipairs(animatedWidgets) do
        g_effects.fadeIn(widget, duration)
    end
end

function CharacterList.hide(showLogin)
    removeAutoReconnectEvent()
    CharacterList.closeAccountManagement(true)
    CharacterList.closeCharacterAssembly(true)
    setElementalBackgroundBlur(false)
    if charactersWindow then
        charactersWindow:hide()
    end

    if showLogin and EnterGame and not g_game.isOnline() then
        EnterGame.show()
    end
end

function CharacterList.showAgain()
    if characterList and characterList:hasChildren() then
        CharacterList.show()
        scheduleAutoReconnect()
    end
end

function CharacterList.isVisible()
    if charactersWindow and charactersWindow:isVisible() then
        return true
    end
    return false
end

function CharacterList.doLogin()
    removeAutoReconnectEvent()
    if worldLoginPending then
        CharacterList.cancelLogin()
        return
    end

    local selected = characterList:getFocusedChild()
    if selected and selected.isCreateCharacterEntry then
        return
    end
    if selected then
        local charInfo = {
            worldHost = selected.worldHost,
            worldPort = selected.worldPort,
            worldName = selected.worldName,
            characterName = selected.characterName
        }
        if not elementalDesktopLayout then
            setElementalBackgroundBlur(false)
            charactersWindow:hide()
        end
        if loginEvent then
            removeEvent(loginEvent)
            loginEvent = nil
        end
        tryLogin(charInfo)
    else
        displayErrorBox(tr('Error'), tr('You must select a character to login!'))
    end
end

function CharacterList.cancelLogin()
    if not worldLoginPending then
        return false
    end

    if waitingWindow then
        waitingWindow:destroy()
        waitingWindow = nil
    end
    if updateWaitEvent then
        removeEvent(updateWaitEvent)
        updateWaitEvent = nil
    end
    if resendWaitEvent then
        removeEvent(resendWaitEvent)
        resendWaitEvent = nil
    end

    g_game.cancelLogin()
    setWorldLoginPending(false)
    setWorldLoginStatus(nil, false)
    CharacterList.show()
    return true
end

function CharacterList.destroyLoadBox()
    if loadBox then
        loadBox:destroy()
        loadBox = nil
    end
    destroyCreateAccount()
end

function CharacterList.cancelWait()
    if elementalDesktopLayout and worldLoginPending then
        CharacterList.cancelLogin()
        return
    end

    if waitingWindow then
        waitingWindow:destroy()
        waitingWindow = nil
    end

    if updateWaitEvent then
        removeEvent(updateWaitEvent)
        updateWaitEvent = nil
    end

    if resendWaitEvent then
        removeEvent(resendWaitEvent)
        resendWaitEvent = nil
    end

    CharacterList.destroyLoadBox()
    CharacterList.showAgain()
end

function CharacterList.updateCharactersAppearance(widget, characterInfo, showOutfits)
    if not shouldShowAppearance() then
        return
    end

    if showOutfits == nil then
        showOutfits = getShowOutfits()
    end

    local creatureDisplay = widget:getChildById('outfitCreatureBox')
    local nameLabel = widget:getChildById('name')
    local mainCharacter = widget:getChildById('mainCharacter')
    local statusDailyReward = widget:getChildById('statusDailyReward')
    local statusHidden = widget:getChildById('statusHidden')

    if creatureDisplay then
        creatureDisplay:setVisible(not elementalDesktopLayout and showOutfits)
        if showOutfits and not elementalDesktopLayout then
            creatureDisplay:setSize('64 64')
            local creature = widget.cachedOutfitCreature
            if not creature then
                creature = Creature.create()
                widget.cachedOutfitCreature = creature
            end
            local outfit = {
                type = characterInfo.outfitid or 0,
                head = characterInfo.headcolor or 0,
                body = characterInfo.torsocolor or 0,
                legs = characterInfo.legscolor or 0,
                feet = characterInfo.detailcolor or 0,
                addons = characterInfo.addonsflags or 0
            }
            creature:setOutfit(outfit)
            creature:setDirection(2)
            creatureDisplay:setCreature(creature)
            creatureDisplay:setPadding(0)
        end
    end

    if nameLabel then
        nameLabel:setMarginLeft(elementalDesktopLayout and 14 or (showOutfits and 65 or 5))
    end

    widget:setHeight(elementalDesktopLayout and 50 or (showOutfits and 64 or 29))

    if mainCharacter then
        mainCharacter:setImageSource(not elementalDesktopLayout and characterInfo.main and
            '/images/game/entergame/maincharacter' or '')
    end

    if statusDailyReward then
        local dailyRewardCollected = tonumber(characterInfo.dailyreward) == 0
        statusDailyReward:setImageSource(dailyRewardCollected and '/images/game/entergame/dailyreward_collected' or
            '/images/game/entergame/dailyreward_notcollected')
    end

    if statusHidden then
        statusHidden:setImageSource(characterInfo.hidden and '/images/game/entergame/hidden' or '')
    end
end

function CharacterList.updateCharactersAppearances(showOutfits)
    if not shouldShowAppearance() or not characterList then
        return
    end

    if showOutfits == nil then
        showOutfits = getShowOutfits()
    end

    if showOutfitsCheckbox and showOutfits ~= showOutfitsCheckbox:isChecked() then
        setCheckedWithoutCallback(showOutfitsCheckbox, showOutfits)
    end

    if not(characterList) or #(characterList:getChildren()) == 0 then
        return
    end

    for _, widget in ipairs(characterList:getChildren()) do
        if widget.characterInfo then
            CharacterList.updateCharactersAppearance(widget, widget.characterInfo, showOutfits)
        end
    end
end

function onLogout()
    lastLogout = g_clock.millis()
end

function scheduleAutoReconnect()
    if not g_settings.getBoolean('autoReconnect') or lastLogout + 2000 > g_clock.millis() then
        return
    end

    removeAutoReconnectEvent()
    autoReconnectEvent = scheduleEvent(executeAutoReconnect, 2500)
end

function executeAutoReconnect()
    if not g_settings.getBoolean('autoReconnect') then
        return
    end

    if errorBox then
        errorBox:destroy()
        errorBox = nil
    end
    CharacterList.doLogin()
end
