local REQUEST_PATH = os.getenv("ELEMENTAL_UPDATE_REQUEST_PATH")
local NOTICE_PATH = os.getenv("ELEMENTAL_UPDATE_NOTICE_PATH")
local POLL_INTERVAL = 500
local NOTICE_POLL_INTERVAL = 1500

local pending_request
local poll_event
local notice_event
local logout_sent = false
local game_event_connected = false
local last_notice_id
local awaiting_apply = false

ClientLauncherUpdate = {}

local function is_logout_blocked(player)
   if player:hasState(PlayerStates.Pz) then
      return false
   end

   if player:hasState(PlayerStates.PzBlock) then
      return true
   end

   return player:hasState(PlayerStates.Swords)
end

ClientLauncherUpdate.isLogoutBlocked = is_logout_blocked

local function read_update_notice()
   if not NOTICE_PATH or NOTICE_PATH == "" then
      return nil
   end

   local file = io.open(NOTICE_PATH, "r")
   if not file then
      return nil
   end

   local content = file:read("*a")
   file:close()

   local success, notice = pcall(json.decode, content)
   if not success or type(notice) ~= "table" or
      notice.schemaVersion ~= 1 or
      type(notice.noticeId) ~= "string" or
      type(notice.version) ~= "string" or
      type(notice.minimumVersion) ~= "string" or
      type(notice.minimumUpdateRequired) ~= "boolean" or
      type(notice.expiresAt) ~= "number" or
      notice.expiresAt < os.time() then
      return nil
   end

   return notice
end

function ClientLauncherUpdate.isLoginBlockedByMinimumVersion()
   local notice = read_update_notice()
   return notice ~= nil and notice.minimumUpdateRequired
end

function ClientLauncherUpdate.selfTest()
   local function player_with(states)
      return {
         hasState = function(_, state)
            return states[state] == true
         end
      }
   end

   assert(not is_logout_blocked(player_with({
      [PlayerStates.Pz] = true,
      [PlayerStates.PzBlock] = true,
      [PlayerStates.Swords] = true,
   })))
   assert(is_logout_blocked(player_with({ [PlayerStates.PzBlock] = true })))
   assert(is_logout_blocked(player_with({ [PlayerStates.Swords] = true })))
   assert(not is_logout_blocked(player_with({})))
   if NOTICE_PATH then
      assert(ClientLauncherUpdate.isLoginBlockedByMinimumVersion())
   end
   return true
end

function ClientLauncherUpdate.blockLoginIfRequired()
   if g_platform.isMobile() then
      return false
   end

   local notice = read_update_notice()
   if not awaiting_apply and (not notice or not notice.minimumUpdateRequired) then
      return false
   end

   displayErrorBox(
      awaiting_apply and "Atualização preparada" or "Atualização necessária",
      awaiting_apply and
         "Confirme a aplicação no launcher ou cancele a atualização antes de entrar novamente."
         or string.format(
            "A versão %s é necessária para entrar. Volte ao launcher e escolha REINICIAR E APLICAR.",
            notice.minimumVersion
         )
   )
   return true
end

local function show_update_notice()
   notice_event = nil
   local notice = read_update_notice()
   if notice and notice.noticeId ~= last_notice_id then
      last_notice_id = notice.noticeId
      local message
      if notice.minimumUpdateRequired then
         message = string.format(
            "A versão %s é necessária para entrar novamente. A sessão atual continuará ativa. Quando decidir sair, use o launcher para preparar e aplicar a atualização.",
            notice.minimumVersion
         )
      else
         message = string.format(
            "A versão %s está disponível. Você pode continuar jogando e preparar a atualização pelo launcher quando preferir.",
            notice.version
         )
      end
      displayInfoBox("Atualização do Elemental", message)
   end

   notice_event = scheduleEvent(show_update_notice, NOTICE_POLL_INTERVAL)
end

local function write_status(status, reason)
   if not REQUEST_PATH or not pending_request then
      return
   end

   local file = io.open(REQUEST_PATH .. ".status", "w")
   if not file then
      return
   end

   file:write(json.encode({
      requestId = pending_request.requestId,
      status = status,
      reason = reason,
   }))
   file:close()
end

local function read_request()
   if not REQUEST_PATH then
      return nil
   end

   local file = io.open(REQUEST_PATH, "r")
   if not file then
      return nil
   end

   local content = file:read("*a")
   file:close()

   local success, request = pcall(json.decode, content)
   if not success or type(request) ~= "table" or
      type(request.requestId) ~= "string" or
      type(request.expiresAt) ~= "number" or
      request.expiresAt < os.time() then
      return nil
   end

   if request.action ~= "safe_logout_to_charlist" and
      request.action ~= "exit_for_update" and
      request.action ~= "cancel_safe_logout" then
      return nil
   end

   return request
end

local function finish_update()
   if not pending_request then
      return
   end

   write_status("safe_to_restart")
   if poll_event then
      removeEvent(poll_event)
      poll_event = nil
   end
   pending_request = nil
   logout_sent = false
   awaiting_apply = false
   g_app.exit()
end

local function on_game_end()
   if pending_request then
      awaiting_apply = true
      logout_sent = false
      write_status("safe_to_apply")
   end
end

local function process_request()
   poll_event = nil
   local request = read_request()

   if request and request.action == "cancel_safe_logout" and pending_request and
      request.requestId == pending_request.requestId then
      write_status("cancelled")
      pending_request = nil
      logout_sent = false
      awaiting_apply = false
   end

   if request and request.action == "exit_for_update" and pending_request and
      request.requestId == pending_request.requestId and awaiting_apply then
      finish_update()
      return
   end

   if request and request.action == "safe_logout_to_charlist" and
      (not pending_request or request.requestId ~= pending_request.requestId) then
      pending_request = request
      logout_sent = false
      awaiting_apply = false
      write_status("accepted")
   end

   if not pending_request then
      poll_event = scheduleEvent(process_request, POLL_INTERVAL)
      return
   end

   if awaiting_apply then
      poll_event = scheduleEvent(process_request, POLL_INTERVAL)
      return
   end

   if not g_game.isOnline() then
      awaiting_apply = true
      write_status("safe_to_apply")
      poll_event = scheduleEvent(process_request, POLL_INTERVAL)
      return
   end

   local player = g_game.getLocalPlayer()
   if player and is_logout_blocked(player) then
      write_status("waiting_for_combat", "logout_block")
      logout_sent = false
   elseif not logout_sent then
      write_status("logging_out")
      g_game.safeLogout()
      logout_sent = true
   end

   poll_event = scheduleEvent(process_request, POLL_INTERVAL)
end

function init()
   if g_platform.isMobile() then
      return
   end

   if os.getenv("ELEMENTAL_UPDATE_SELF_TEST") == "1" then
      local success, result = pcall(ClientLauncherUpdate.selfTest)
      if success and result == true then
         g_logger.info("[launcher_update] synthetic state self-test passed")
      else
         g_logger.error("[launcher_update] synthetic state self-test failed: " .. tostring(result))
      end
   end

   if REQUEST_PATH and REQUEST_PATH ~= "" then
      connect(g_game, { onGameEnd = on_game_end })
      game_event_connected = true
      process_request()
   end

   if NOTICE_PATH and NOTICE_PATH ~= "" then
      show_update_notice()
   end
end

function terminate()
   if poll_event then
      removeEvent(poll_event)
      poll_event = nil
   end
   if notice_event then
      removeEvent(notice_event)
      notice_event = nil
   end

   if game_event_connected then
      disconnect(g_game, { onGameEnd = on_game_end })
      game_event_connected = false
   end
   pending_request = nil
   awaiting_apply = false
end
