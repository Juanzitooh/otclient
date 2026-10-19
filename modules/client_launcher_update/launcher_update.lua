local REQUEST_PATH = os.getenv("ELEMENTAL_UPDATE_REQUEST_PATH")
local POLL_INTERVAL = 500

local pending_request
local poll_event
local logout_sent = false
local game_event_connected = false

local function is_logout_blocked(player)
   return player:hasState(PlayerStates.Swords) or
      player:hasState(PlayerStates.PzBlock)
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

   if request.action ~= "safe_logout_and_exit" and
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
   g_app.exit()
end

local function on_game_end()
   if pending_request then
      finish_update()
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
   end

   if request and request.action == "safe_logout_and_exit" and
      (not pending_request or request.requestId ~= pending_request.requestId) then
      pending_request = request
      logout_sent = false
      write_status("accepted")
   end

   if not pending_request then
      poll_event = scheduleEvent(process_request, POLL_INTERVAL)
      return
   end

   if not g_game.isOnline() then
      finish_update()
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
   if not REQUEST_PATH or REQUEST_PATH == "" then
      return
   end

   connect(g_game, { onGameEnd = on_game_end })
   game_event_connected = true
   process_request()
end

function terminate()
   if poll_event then
      removeEvent(poll_event)
      poll_event = nil
   end

   if game_event_connected then
      disconnect(g_game, { onGameEnd = on_game_end })
      game_event_connected = false
   end
   pending_request = nil
end
