ClientDistributionAuth = {}

local TOKEN_SETTING = 'elemental-test-feed-token'
local DEVICE_SETTING = 'elemental-test-feed-device'
local TOKEN_PATTERN = '^b1%.[A-Za-z0-9_-]+$'
local ENROLLMENT_TIMEOUT_SECONDS = 30

local pendingCallbacks = {}
local enrollmentOperation
local passwordWindow
local passwordBackdrop
local enrolling = false
local enrollmentRequestPending = false
local environmentTokenRejected = false
local enrollmentSerial = 0

local function getConfig()
  local config = Services and Services.elementalUpdater
  if type(config) ~= 'table' or config.channel ~= 'test' then
    return nil
  end
  return config
end

local function isValidToken(token)
  return type(token) == 'string' and #token == 46 and token:match(TOKEN_PATTERN) ~= nil
end

local function isLoopbackUrl(url)
  return type(url) == 'string' and (
    url:lower():match('^http://localhost[:/]') or
    url:match('^http://127%.0%.0%.1[:/]') or
    url:match('^http://%[::1%][:/]')
  ) ~= nil
end

local function getOrigin(url)
  return type(url) == 'string' and url:match('^(https://[^/]+)') or nil
end

local function getAuthUrl()
  local config = getConfig()
  if not config or type(config.authUrl) ~= 'string' then
    return nil
  end
  local url = config.authUrl
  if not getOrigin(url) or url:find('@', 1, true) or url:find('#', 1, true) or
     url:find('?', 1, true) or url:find('%s') then
    return nil
  end
  return url
end

local function getSavedToken()
  local encrypted = g_settings.get(TOKEN_SETTING)
  if type(encrypted) ~= 'string' or encrypted == '' then
    return nil
  end

  local ok, token = pcall(g_crypt.decrypt, encrypted)
  if ok and isValidToken(token) then
    return token
  end

  g_settings.remove(TOKEN_SETTING)
  g_settings.remove(DEVICE_SETTING)
  g_settings.save()
  return nil
end

local function saveToken(token, deviceId)
  g_settings.set(TOKEN_SETTING, g_crypt.encrypt(token))
  g_settings.set(DEVICE_SETTING, deviceId)
  g_settings.save()
end

local function completePending(token, err)
  enrolling = false
  enrollmentRequestPending = false
  enrollmentOperation = nil
  local callbacks = pendingCallbacks
  pendingCallbacks = {}
  for _, callback in ipairs(callbacks) do
    callback(token, err)
  end
end

local function getPasswordWidget(id)
  return passwordWindow and passwordWindow:recursiveGetChildById(id) or nil
end

local function setPasswordStatus(message, isError)
  local status = getPasswordWidget('testFeedAccessStatus')
  if not status then
    return
  end
  status:setText(message or '')
  status:setColor(isError and '#e56b6b' or '#aeb4c0')
end

local function setPasswordSubmitEnabled(enabled)
  local button = getPasswordWidget('testFeedAccessSubmit')
  if not button then
    return
  end
  if enabled then
    button:enable()
  else
    button:disable()
  end
end

local function destroyPasswordPrompt()
  local passwordEdit = getPasswordWidget('testFeedAccessPassword')
  if passwordEdit then
    passwordEdit:clearText()
  end
  if passwordWindow and not passwordWindow:isDestroyed() then
    passwordWindow:destroy()
  end
  passwordWindow = nil
  if passwordBackdrop and not passwordBackdrop:isDestroyed() then
    passwordBackdrop:destroy()
  end
  passwordBackdrop = nil
end

local function createPasswordBackdrop()
  if passwordBackdrop then
    return
  end

  passwordBackdrop = g_ui.createWidget('ElementalModalBlurBackdrop', rootWidget)
  passwordBackdrop:show()
  passwordBackdrop:raise()
  local background = passwordBackdrop:getChildById('blurredBackground')
  if background then
    pcall(function()
      background:setShader('Elemental Modal Blur')
    end)
  end
end

local function platformName()
  local config = getConfig()
  local platform = config and config.feedPlatform
  if type(platform) ~= 'string' or platform == '' then
    platform = os.getenv('ELEMENTAL_FEED_PLATFORM')
  end
  if type(platform) ~= 'string' or platform == '' then
    platform = g_android and 'android-arm64' or 'otclient-other'
  end
  return platform
end

local function enroll(password)
  local authUrl = getAuthUrl()
  if not authUrl then
    enrollmentRequestPending = false
    setPasswordStatus(tr('O feed de teste não está configurado.'), true)
    setPasswordSubmitEnabled(true)
    return
  end

  enrollmentSerial = enrollmentSerial + 1
  local requestSerial = enrollmentSerial
  local previousTimeout = HTTP.timeout
  HTTP.timeout = ENROLLMENT_TIMEOUT_SECONDS
  local ok, operation = pcall(function()
    return HTTP.postSecureJSON(authUrl, {
      contractVersion = 1,
      password = password,
      platform = platformName()
    }, function(response, err)
      if requestSerial ~= enrollmentSerial then
        return
      end
      enrollmentOperation = nil
      if err or type(response) ~= 'table' or response.channel ~= 'test' or
         type(response.deviceId) ~= 'string' or not isValidToken(response.token) then
        enrollmentRequestPending = false
        setPasswordStatus(
          tr('A senha foi rejeitada ou o feed está indisponível. Tente novamente.'), true)
        setPasswordSubmitEnabled(true)
        if not err then
          g_logger.warning('Elemental test feed enrollment returned an invalid response.')
        end
        return
      end

      enrollmentRequestPending = false
      saveToken(response.token, response.deviceId)
      destroyPasswordPrompt()
      completePending(response.token)
    end)
  end)
  HTTP.timeout = previousTimeout

  if not ok or type(operation) ~= 'number' or operation < 0 then
    enrollmentRequestPending = false
    setPasswordStatus(tr('Não foi possível contatar o feed. Verifique a conexão e tente novamente.'), true)
    setPasswordSubmitEnabled(true)
    g_logger.warning('Elemental test feed enrollment could not start: ' .. tostring(operation))
    return
  end
  enrollmentOperation = operation
end

local function promptForPassword()
  local authUrl = getAuthUrl()
  if not authUrl then
    return completePending(nil, 'test_feed_auth_endpoint_unconfigured')
  end

  local inputBox
  local ok, errorMessage = pcall(function()
    g_ui.importStyle('/modules/client_entergame/elemental_brand.otui')
    createPasswordBackdrop()
    inputBox = g_ui.displayUI('test_feed_access')
    passwordWindow = inputBox
    local width = math.max(280, math.min(500, rootWidget:getWidth() - 32))
    local height = math.max(300, math.min(370, rootWidget:getHeight() - 24))
    inputBox:setSize({width = width, height = height})
    local buttonWidth = math.max(112, math.min(190, math.floor((width - 52) / 2)))
    inputBox:getChildById('testFeedAccessCancel'):setWidth(buttonWidth)
    inputBox:getChildById('testFeedAccessSubmit'):setWidth(buttonWidth)
    return inputBox
  end)

  if not ok then
    destroyPasswordPrompt()
    return completePending(nil, tostring(errorMessage))
  end
  inputBox:show()
  inputBox:raise()
  inputBox:focus()
  local passwordEdit = getPasswordWidget('testFeedAccessPassword')
  if passwordEdit then
    passwordEdit:setMaxLength(1024)
    passwordEdit:focus()
  end
end

function ClientDistributionAuth.submitPassword()
  if not passwordWindow or enrollmentRequestPending then
    return
  end

  local passwordEdit = getPasswordWidget('testFeedAccessPassword')
  local password = passwordEdit and passwordEdit:getText() or ''
  if passwordEdit then
    passwordEdit:clearText()
  end
  if password == '' then
    setPasswordStatus(tr('Informe a senha de acesso para continuar.'), true)
    if passwordEdit then
      passwordEdit:focus()
    end
    return
  end

  enrollmentRequestPending = true
  setPasswordSubmitEnabled(false)
  setPasswordStatus(tr('Autorizando este dispositivo…'), false)
  enroll(password)
end

function ClientDistributionAuth.cancelPassword()
  if not passwordWindow then
    return
  end
  enrollmentSerial = enrollmentSerial + 1
  enrollmentRequestPending = false
  if enrollmentOperation then
    HTTP.cancel(enrollmentOperation)
    enrollmentOperation = nil
  end
  destroyPasswordPrompt()
  completePending(nil, 'enrollment_cancelled')
end

function ClientDistributionAuth.requiresToken(channel, url)
  return channel == 'test' and not isLoopbackUrl(url)
end

function ClientDistributionAuth.ensureToken(callback)
  if type(callback) ~= 'function' then
    return
  end

  local environmentToken = not environmentTokenRejected and os.getenv('ELEMENTAL_TEST_FEED_TOKEN') or nil
  if isValidToken(environmentToken) then
    callback(environmentToken)
    return
  end

  local savedToken = getSavedToken()
  if savedToken then
    callback(savedToken)
    return
  end

  table.insert(pendingCallbacks, callback)
  if enrolling then
    return
  end
  enrolling = true
  promptForPassword()
end

function ClientDistributionAuth.isTrustedUrl(url)
  if type(url) ~= 'string' or url:find('@', 1, true) or url:find('#', 1, true) or
     url:find('?', 1, true) or url:find('%', 1, true) then
    return false
  end
  local authUrl = getAuthUrl()
  local authOrigin = authUrl and getOrigin(authUrl)
  local path = url:match('^https://[^/]+(/.*)$')
  if authOrigin == nil or getOrigin(url) ~= authOrigin or
     path == nil or path:match('^/updates/test/') == nil then
    return false
  end
  for segment in path:gmatch('[^/]+') do
    if segment == '.' or segment == '..' then
      return false
    end
  end
  return true
end

function ClientDistributionAuth.forgetToken()
  environmentTokenRejected = true
  g_settings.remove(TOKEN_SETTING)
  g_settings.remove(DEVICE_SETTING)
  g_settings.save()
end

function ClientDistributionAuth.isUnauthorized(err)
  return type(err) == 'string' and (
    err:find('http_status::401', 1, true) ~= nil or
    err:find('http_status::403', 1, true) ~= nil
  )
end

function ClientDistributionAuth.init()
end

function ClientDistributionAuth.terminate()
  enrollmentSerial = enrollmentSerial + 1
  if enrollmentOperation then
    HTTP.cancel(enrollmentOperation)
    enrollmentOperation = nil
  end
  destroyPasswordPrompt()
  pendingCallbacks = {}
  enrolling = false
  enrollmentRequestPending = false
end
