local accountWindow
local modalBackdrop
local accountRequestSerial = 0
local accountRequestPending = false

local function getAccountWidget(id)
    return accountWindow and accountWindow:recursiveGetChildById(id) or nil
end

local function decodeAccountResponse(message)
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
    return response
end

local function setAccountStatus(message, isError)
    if not accountWindow then
        return
    end
    local status = getAccountWidget('accountStatus')
    status:setText(message or '')
    status:setColor(isError and '#f07070' or '#c0c0c0')
end

function onCreateAccountInputChanged()
    setAccountStatus('', false)
end

local function getAccountError(response, requestError)
    local messages = {
        account_already_exists = 'Este e-mail ja possui uma conta.',
        invalid_account_data = 'O e-mail ou a senha sao invalidos.',
        account_creation_failed = 'Nao foi possivel criar a conta. Tente novamente.'
    }
    local errorCode = response and response.errorCode
    if not errorCode and type(requestError) == 'string' then
        local statusCode = requestError:match('http_status::(%d%d%d)')
        local statusErrors = {
            ['400'] = 'invalid_account_data',
            ['409'] = 'account_already_exists',
            ['500'] = 'account_creation_failed'
        }
        errorCode = statusErrors[statusCode]
    end
    return messages[errorCode] or 'Servico de contas indisponivel. Tente novamente mais tarde.'
end

function toggleCreateAccount(showLogin)
    if showLogin then
        destroyCreateAccount()
        EnterGame.show()
        return
    end

    createWidgetAccount()
end

local function createModalBackdrop()
    if modalBackdrop then
        return
    end

    modalBackdrop = g_ui.createWidget('ElementalModalBlurBackdrop', rootWidget)
    modalBackdrop:show()
    modalBackdrop:raise()

    local background = modalBackdrop:getChildById('blurredBackground')
    if background then
        background:setShader('Elemental Modal Blur')
    end
end

function createWidgetAccount()
    if accountWindow then
        if modalBackdrop then
            modalBackdrop:raise()
        end
        accountWindow:show()
        accountWindow:raise()
        accountWindow:focus()
        return
    end

    if not Services or type(Services.createAccount) ~= 'string' then
        ensableBtnCreateNewAccount()
        local message = 'O servico local de contas esta indisponivel.'
        if not g_platform.isMobile() and EnterGame.setLoginStatus then
            EnterGame.setLoginStatus(message, true)
        else
            displayErrorBox(tr('Account Error'), message)
        end
        return
    end

    createModalBackdrop()
    local accountLayout = g_platform.isMobile() and
        'createAccount_elemental_mobile' or 'createAccount_elemental_desktop'
    accountWindow = g_ui.displayUI(accountLayout)
    if g_platform.isMobile() then
        local width = math.max(320, math.min(520, rootWidget:getWidth() - 40))
        accountWindow:setSize({width = width, height = 520})
        local buttonWidth = math.max(130, math.min(190, math.floor((width - 64) / 2)))
        getAccountWidget('buttonBackToLogin'):setWidth(buttonWidth)
        getAccountWidget('buttonStartPlaying'):setWidth(buttonWidth)
    end
    accountWindow:show()
    accountWindow:raise()
    accountWindow:focus()
    getAccountWidget('accountEmail'):focus()
    accountRequestPending = false
    ensableBtnCreateNewAccount()
end

function onClickStartPlaying()
    if not accountWindow or accountRequestPending then
        return
    end

    local emailEdit = getAccountWidget('accountEmail')
    local passwordEdit = getAccountWidget('accountPassword')
    local repeatPasswordEdit = getAccountWidget('repeatPassword')
    local email = emailEdit:getText():match('^%s*(.-)%s*$')
    local password = passwordEdit:getText()
    local repeatedPassword = repeatPasswordEdit:getText()

    if #email < 6 or #password < 6 or password ~= repeatedPassword then
        setAccountStatus('Informe um e-mail valido e senhas iguais com pelo menos 6 caracteres.', true)
        return
    end

    accountRequestSerial = accountRequestSerial + 1
    local requestSerial = accountRequestSerial
    accountRequestPending = true
    getAccountWidget('buttonStartPlaying'):disable()
    setAccountStatus('Criando conta...', false)

    HTTP.post(Services.createAccount, json.encode({
        type = 'createaccount',
        contractVersion = 1,
        email = email,
        password = password
    }), function(message, err)
        if requestSerial ~= accountRequestSerial or not accountWindow then
            return
        end

        accountRequestPending = false
        local response = decodeAccountResponse(message)
        if err or not response or response.contractVersion ~= 1 or response.Success ~= true then
            setAccountStatus(getAccountError(response, err), true)
            getAccountWidget('buttonStartPlaying'):enable()
            return
        end

        destroyCreateAccount()
        EnterGame.setAccountName(g_crypt.encrypt(email))
        EnterGame.setPassword(g_crypt.encrypt(password))
        EnterGame.doLogin()
    end, false)
end

function destroyCreateAccount()
    accountRequestSerial = accountRequestSerial + 1
    accountRequestPending = false
    if accountWindow then
        accountWindow:destroy()
        accountWindow = nil
    end
    if modalBackdrop then
        modalBackdrop:destroy()
        modalBackdrop = nil
    end
end
