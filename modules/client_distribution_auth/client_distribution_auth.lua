ClientDistributionAuth = {}

local TOKEN_SETTING = 'elemental-test-feed-token'
local DEVICE_SETTING = 'elemental-test-feed-device'
local TOKEN_PATTERN = '^b1%.[A-Za-z0-9_-]+$'
local ENROLLMENT_TIMEOUT_SECONDS = 30

local pendingCallbacks = {}
local enrollmentOperation
local passwordWindow
local enrolling = false
local environmentTokenRejected = false

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
  enrollmentOperation = nil
  local callbacks = pendingCallbacks
  pendingCallbacks = {}
  for _, callback in ipairs(callbacks) do
    callback(token, err)
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
    return completePending(nil, 'test_feed_auth_endpoint_unconfigured')
  end

  local previousTimeout = HTTP.timeout
  HTTP.timeout = ENROLLMENT_TIMEOUT_SECONDS
  local ok, operation = pcall(function()
    return HTTP.postSecureJSON(authUrl, {
      contractVersion = 1,
      password = password,
      platform = platformName()
    }, function(response, err)
      if err or type(response) ~= 'table' or response.channel ~= 'test' or
         type(response.deviceId) ~= 'string' or not isValidToken(response.token) then
        displayErrorBox(tr('Test access'), tr('The shared password was rejected or the test feed is unavailable.'))
        return completePending(nil, err or 'invalid_enrollment_response')
      end

      saveToken(response.token, response.deviceId)
      completePending(response.token)
    end)
  end)
  HTTP.timeout = previousTimeout

  if not ok or type(operation) ~= 'number' or operation < 0 then
    return completePending(nil, tostring(operation or 'enrollment_request_unavailable'))
  end
  enrollmentOperation = operation
end

local function promptForPassword()
  local authUrl = getAuthUrl()
  if not authUrl then
    return completePending(nil, 'test_feed_auth_endpoint_unconfigured')
  end

  local ok, window = pcall(function()
    local inputBox = UIInputBox.create(
      tr('Elemental test access'),
      function(password)
        passwordWindow = nil
        if type(password) ~= 'string' or password == '' then
          return completePending(nil, 'empty_password')
        end
        enroll(password)
      end,
      function()
        passwordWindow = nil
        completePending(nil, 'enrollment_cancelled')
      end
    )
    inputBox:addLabel(tr('Enter the shared password provided by the project team.'))
    local passwordEdit = inputBox:addLineEdit(tr('Password'), nil, 1024)
    passwordEdit:setTextHidden(true)
    inputBox:display(tr('Continue'), tr('Cancel'))
    passwordEdit:focus()
    return inputBox
  end)

  if not ok then
    return completePending(nil, tostring(window))
  end
  passwordWindow = window
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
  if enrollmentOperation then
    HTTP.cancel(enrollmentOperation)
    enrollmentOperation = nil
  end
  if passwordWindow and not passwordWindow:isDestroyed() then
    passwordWindow:destroy()
    passwordWindow = nil
  end
  pendingCallbacks = {}
  enrolling = false
end
