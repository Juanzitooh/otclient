-- this file is loaded after all modules are loaded and initialized
-- selected by init.lua when ELEMENTAL_OTUI_DESIGN=1

g_logger.info("Elemental custom rc loaded.")

local function get_environment(name)
    local value = os.getenv(name)
    if not value or value == "" then
        return nil
    end
    return value
end

local function log(message)
    g_logger.info("[elemental-smoke] " .. message)
end

local function log_error(message)
    g_logger.error("[elemental-smoke] " .. message)
end

local function run_smoke_login()
    local enabled = get_environment("ELEMENTAL_OTCLIENT_SMOKE") == "1"
    if not enabled then
        return
    end

    local login_url = get_environment("ELEMENTAL_LOGIN_URL")
    local login_email = get_environment("ELEMENTAL_LOGIN_EMAIL")
    local login_password = get_environment("ELEMENTAL_LOGIN_PASSWORD")
    local character_name = get_environment("ELEMENTAL_CHARACTER_NAME")
    local world_name = get_environment("ELEMENTAL_WORLD_NAME")
    local login_port = tonumber(get_environment("ELEMENTAL_LOGIN_PORT"))
    local client_version = tonumber(get_environment("ELEMENTAL_CLIENT_VERSION")) or 1525

    if not login_url or not login_email or not login_password or not character_name or not world_name or not login_port then
        log_error("missing required local login settings")
        return
    end

    local url_host = login_url:match("^https?://%[([^%]]+)%]") or login_url:match("^https?://([^/:]+)")
    url_host = url_host and url_host:lower()
    if url_host ~= "127.0.0.1" and url_host ~= "localhost" and url_host ~= "::1" then
        log_error("login URL must use loopback")
        return
    end

    local enter_game_module = modules.client_entergame
    local enter_game = enter_game_module and enter_game_module.EnterGame
    local character_list = enter_game_module and enter_game_module.CharacterList
    if not enter_game or not character_list then
        log_error("client_entergame APIs are unavailable")
        return
    end

    Servers_init = {
        [login_url] = {
            port = login_port,
            protocol = client_version,
            httpLogin = true,
            useAuthenticator = false,
        },
    }

    enter_game.setUniqueServer(login_url, login_port, client_version, 380, 300)
    enter_game.setHttpLogin(true)
    enter_game.setAccountName(g_crypt.encrypt(login_email))
    enter_game.setPassword(g_crypt.encrypt(login_password))

    local enter_game_window = g_ui.getRootWidget():getChildById("enterGame")
    if enter_game_window then
        for _, id in ipairs({"rememberEmailBox", "autoLoginBox", "stayLoggedBox"}) do
            local checkbox = enter_game_window:getChildById(id)
            if checkbox then
                checkbox:setChecked(false)
            end
        end
    end

    local original_show = character_list.show
    local original_login_success = enter_game.loginSuccess
    local original_login_failed = enter_game.loginFailed
    local selection_started = false
    local world_online = false
    local finished = false
    local attempts = 0
    local game_events

    local function restore_hooks()
        if finished then
            return
        end
        finished = true
        disconnect(g_game, game_events)
        character_list.show = original_show
        enter_game.loginSuccess = original_login_success
        enter_game.loginFailed = original_login_failed
    end

    local function on_game_start()
        if world_online then
            return
        end
        world_online = true

        local player = g_game.getLocalPlayer()
        log("WORLD_ONLINE player=" .. (player and player:getName() or "unknown"))

        local action_name = get_environment("ELEMENTAL_POST_LOGIN_ACTION")
        if action_name == "dev_otui.selfTest" then
            local dev_otui = modules.dev_otui
            if not dev_otui or type(dev_otui.selfTest) ~= "function" then
                log_error("POST_LOGIN_ACTION_UNAVAILABLE dev_otui.selfTest")
            else
                local ok, result = pcall(dev_otui.selfTest)
                if ok and result == true then
                    log("POST_LOGIN_ACTION_OK dev_otui.selfTest")
                else
                    log_error("POST_LOGIN_ACTION_FAILED dev_otui.selfTest")
                end
            end
        elseif action_name then
            log_error("POST_LOGIN_ACTION_UNKNOWN " .. action_name)
        else
            log("POST_LOGIN_HOOK_READY")
        end

        local screenshot_path = get_environment("ELEMENTAL_POST_LOGIN_SCREENSHOT")
        if screenshot_path then
            scheduleEvent(function()
                g_app.doScreenshot(screenshot_path)
                log("POST_LOGIN_SCREENSHOT_REQUESTED")
            end, 1000)
        end
        restore_hooks()
    end

    local function on_game_login_error()
        log_error("GAME_LOGIN_FAILED")
        restore_hooks()
    end

    local function on_connection_error(_, error_code)
        log_error("GAME_CONNECTION_FAILED code=" .. tostring(error_code))
        restore_hooks()
    end

    game_events = {
        onGameStart = on_game_start,
        onLoginError = on_game_login_error,
        onConnectionError = on_connection_error,
    }

    local function select_character()
        if selection_started then
            return
        end
        selection_started = true

        local window = g_ui.getRootWidget():getChildById("charactersWindow")
        local list = window and window:getChildById("characters")
        if not list then
            log_error("CHARACTER_LIST_UNAVAILABLE")
            return
        end

        for _, widget in ipairs(list:getChildren()) do
            local matches_character = (widget.characterName or ""):lower() == character_name:lower()
            local matches_world = (widget.worldName or ""):lower() == world_name:lower()
            if matches_character and matches_world then
                list:focusChild(widget, KeyboardFocusReason)
                list:ensureChildVisible(widget)
                log("CHARACTER_SELECTED name=" .. widget.characterName .. " world=" .. widget.worldName)
                character_list.doLogin()
                log("CHARACTER_LOGIN_REQUESTED")
                return
            end
        end

        log_error("CHARACTER_NOT_FOUND")
    end

    character_list.show = function(...)
        local result = original_show(...)
        if character_list.isVisible() then
            addEvent(select_character)
        end
        return result
    end

    enter_game.loginSuccess = function(...)
        log("HTTP_LOGIN_SUCCESS")
        return original_login_success(...)
    end

    enter_game.loginFailed = function(...)
        log_error("HTTP_LOGIN_FAILED")
        restore_hooks()
        return original_login_failed(...)
    end

    connect(g_game, game_events)
    log("LOGIN_STARTED")
    enter_game.doLogin()

    local function wait_for_world()
        if finished then
            return
        end
        if g_game.isOnline() then
            on_game_start()
            return
        end

        attempts = attempts + 1
        if attempts >= 90 then
            log_error("WORLD_ENTRY_TIMEOUT logging=" .. tostring(g_game.isLogging()))
            restore_hooks()
            return
        end

        scheduleEvent(wait_for_world, 1000)
    end

    scheduleEvent(wait_for_world, 1000)
end

run_smoke_login()
print 'Startup done :]'
