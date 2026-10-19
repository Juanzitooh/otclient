local APK_RELATIVE_PATH = "updates/elemental-update.apk"
local APK_DOWNLOAD_NAME = "elemental-update.apk"
local CHECK_INTERVAL = 500
local HTTP_TIMEOUT = 120

local update_button
local check_operation
local download_operation
local check_event
local status_event
local update_config
local pending_apk_path
local pending_version_code
local logout_requested = false
local last_progress_percent = -1

local function log_error(message)
   g_logger.error("[elemental-update] " .. tostring(message))
end

local function set_button_status(message, label)
   if update_button and not update_button:isDestroyed() then
      update_button:setTooltip(message or "Atualizar Elemental")
      update_button:setText(label or "Atualizar")
   end
end

local function notify_user(message)
   if g_game.isOnline() and modules.game_textmessage then
      modules.game_textmessage.displayStatusMessage(message)
   else
      displayInfoBox("Atualização do Elemental", message)
   end
end

local function is_allowed_url(url)
   if type(url) ~= "string" then
      return false
   end

   if url:match("^https://") then
      return true
   end

   return url:match("^http://localhost[:/]" ) or
      url:match("^http://127%.0%.0%.1[:/]" ) or
      url:match("^http://%[::1%][:/]" )
end

local function with_http_timeout(callback)
   local previous_timeout = HTTP.timeout
   HTTP.timeout = math.max(1, math.floor(tonumber(update_config.timeout) or HTTP_TIMEOUT))
   local ok, result = pcall(callback)
   HTTP.timeout = previous_timeout
   if not ok then
      error(result)
   end
   return result
end

local function http_get_json(url, callback)
   local function start(token)
      return with_http_timeout(function()
         local request_callback = function(data, err)
            if token and ClientDistributionAuth.isUnauthorized(err) then
               ClientDistributionAuth.forgetToken()
            end
            callback(data, err)
         end
         if token then
            return HTTP.getJSONWithBearer(url, token, request_callback)
         end
         return HTTP.getJSON(url, request_callback)
      end)
   end

   if not ClientDistributionAuth.requiresToken(update_config.channel, url) then
      return start(nil)
   end
   if not ClientDistributionAuth.isTrustedUrl(url) then
      callback(nil, "test_feed_untrusted_origin")
      return nil
   end
   local operation_id
   ClientDistributionAuth.ensureToken(function(token, err)
      if err then
         return callback(nil, err)
      end
      local operation = start(token)
      if operation and operation >= 0 then
         operation_id = operation
         check_operation = operation
      end
   end)
   return operation_id or -1
end

local function http_download(url, path, callback, progress_callback)
   local function start(token)
      return with_http_timeout(function()
         local request_callback = function(download_path, checksum, err)
            if token and ClientDistributionAuth.isUnauthorized(err) then
               ClientDistributionAuth.forgetToken()
            end
            callback(download_path, checksum, err)
         end
         if token then
            return HTTP.downloadWithBearer(url, path, token, request_callback, progress_callback)
         end
         return HTTP.download(url, path, request_callback, progress_callback)
      end)
   end

   if not ClientDistributionAuth.requiresToken(update_config.channel, url) then
      return start(nil)
   end
   if not ClientDistributionAuth.isTrustedUrl(url) then
      callback(nil, nil, "test_feed_untrusted_origin")
      return nil
   end
   local operation_id
   ClientDistributionAuth.ensureToken(function(token, err)
      if err then
         return callback(nil, nil, err)
      end
      local operation = start(token)
      if operation and operation >= 0 then
         operation_id = operation
         download_operation = operation
      end
   end)
   return operation_id or -1
end

local function resolve_asset_url(manifest_url, asset_url)
   if type(asset_url) ~= "string" or asset_url == "" then
      return nil
   end
   if asset_url:match("^https://") or asset_url:match("^http://") then
      return asset_url
   end

   local origin = manifest_url:match("^(https?://[^/]+)")
   if not origin then
      return nil
   end
   if asset_url:sub(1, 1) == "/" then
      return origin .. asset_url
   end
   local directory = manifest_url:match("^(.*[/])")
   return (directory or (manifest_url .. "/")) .. asset_url
end

local function is_sha256(value)
   return type(value) == "string" and value:match("^[%da-fA-F]+$") and #value == 64
end

local function get_update_config()
   if type(Services) ~= "table" or type(Services.elementalUpdater) ~= "table" then
      return nil
   end
   local config = Services.elementalUpdater
   if config.enabled == false or type(config.androidManifestUrl) ~= "string" then
      return nil
   end
   if config.channel ~= "test" and config.channel ~= "beta" and config.channel ~= "release" then
      return nil
   end
   if not is_allowed_url(config.androidManifestUrl) then
      return nil
   end
   return config
end

local function stop_status_event()
   if status_event then
      removeEvent(status_event)
      status_event = nil
   end
end

local function is_logout_blocked(player)
   return player:hasState(PlayerStates.Swords) or
      player:hasState(PlayerStates.PzBlock)
end

local function open_android_installer()
   stop_status_event()
   local apk_path = pending_apk_path
   if not apk_path then
      return
   end

   logout_requested = false
   local result = g_android.installApk(apk_path)
   if result == 0 then
      pending_apk_path = nil
      pending_version_code = nil
      notify_user("Não foi possível abrir o instalador Android para este APK.")
      return
   end

   if result == 1 then
      set_button_status("Permita instalar apps para o Elemental e toque novamente", "Permitir instalação")
      notify_user("Ative a permissão de instalar apps para o Elemental. Depois volte ao jogo e toque em Permitir instalação.")
      return
   end

   set_button_status("Confirme a atualização no instalador Android", "Confirmar instalação")
   notify_user("APK validado. Siga as confirmações do Android para instalar a atualização.")
end

local function wait_for_safe_logout()
   status_event = nil
   if not pending_apk_path then
      return
   end

   if not g_game.isOnline() then
      open_android_installer()
      return
   end

   local player = g_game.getLocalPlayer()
   if not player then
      set_button_status("Atualização pronta; aguardando o personagem", "Aguardando")
      status_event = scheduleEvent(wait_for_safe_logout, CHECK_INTERVAL)
      return
   end

   if is_logout_blocked(player) then
      set_button_status("Atualização pronta; aguardando o fim do bloqueio de combate", "Aguardando")
      status_event = scheduleEvent(wait_for_safe_logout, CHECK_INTERVAL)
      return
   end

   if not logout_requested then
      logout_requested = true
      set_button_status("Combate encerrado; solicitando logout seguro", "Saindo...")
      if modules.game_textmessage then
         modules.game_textmessage.displayStatusMessage("Atualização pronta. Encerrando a sessão com segurança.")
      end
      g_game.safeLogout()
   end

   status_event = scheduleEvent(wait_for_safe_logout, CHECK_INTERVAL)
end

local function handle_download(path, _, err, manifest)
   download_operation = nil
   if err then
      log_error("APK download failed: " .. tostring(err))
      set_button_status("Falha ao baixar a atualização")
      notify_user("Não foi possível baixar a atualização Android.")
      return
   end

   local downloaded_path = tostring(path or "")
      :gsub("^/downloads/", "")
      :gsub("^downloads/", "")
   if downloaded_path == "" or not g_resources.writeDownloadedFileToWorkDir(
      downloaded_path,
      APK_RELATIVE_PATH,
      false
   ) then
      set_button_status("Falha ao preparar o APK")
      notify_user("O APK foi baixado, mas não pôde ser preparado para instalação.")
      return
   end

   local work_dir = g_resources.getWorkDir()
   local apk_path = work_dir .. APK_RELATIVE_PATH
   local actual_size = g_android.getFileSize(apk_path)
   local actual_sha256 = g_android.sha256File(apk_path):lower()
   if actual_size ~= manifest.apk.size or actual_sha256 ~= manifest.apk.sha256:lower() then
      log_error("Downloaded APK failed size or SHA-256 verification")
      set_button_status("APK inválido; atualização cancelada")
      notify_user("A validação do APK falhou. Nenhuma atualização foi instalada.")
      return
   end

   pending_apk_path = apk_path
   pending_version_code = manifest.versionCode
   set_button_status("Atualização validada; aguardando logout seguro")
   if g_game.isOnline() then
      notify_user("Atualização baixada. O jogo aguardará o fim do bloqueio de combate para sair com segurança.")
   end
   wait_for_safe_logout()
end

local function start_download(manifest)
   local apk_url = resolve_asset_url(update_config.androidManifestUrl, manifest.apk.url)
   if not apk_url or not is_allowed_url(apk_url) then
      notify_user("O endereço do APK não usa uma origem segura.")
      return
   end

   local current_version = g_android.getVersionCode()
   if manifest.applicationId ~= g_android.getPackageName() then
      notify_user("Este APK pertence a outro pacote e não pode atualizar esta instalação.")
      return
   end
   if manifest.versionCode <= current_version then
      if manifest.versionCode == current_version then
         notify_user("O Elemental já está atualizado neste canal.")
      else
         notify_user("O canal oferece uma versão anterior. A instalação foi bloqueada para evitar downgrade.")
      end
      return
   end

   if type(manifest.apk.size) ~= "number" or manifest.apk.size < 1 or
      not is_sha256(manifest.apk.sha256) then
      notify_user("O manifesto do APK está incompleto ou inválido.")
      return
   end

   last_progress_percent = -1
   set_button_status("Baixando atualização Android: 0%")
   local ok, operation = pcall(function()
      return http_download(apk_url, APK_DOWNLOAD_NAME, function(path, checksum, err)
            handle_download(path, checksum, err, manifest)
         end, function(progress)
            local percent = math.max(0, math.min(100, math.floor(tonumber(progress) or 0)))
            if percent ~= last_progress_percent then
               last_progress_percent = percent
               set_button_status("Baixando atualização Android: " .. percent .. "%", "Baixando " .. percent .. "%")
            end
         end)
   end)
   if not ok then
      download_operation = nil
      set_button_status("Falha ao iniciar o download")
      notify_user("Não foi possível iniciar o download do APK Android.")
      log_error(operation)
      return
   end
   download_operation = operation
end

local function check_for_update()
   if check_operation or download_operation then
      return
   end

   if pending_apk_path then
      if pending_version_code and g_android.getVersionCode() >= pending_version_code then
         pending_apk_path = nil
         pending_version_code = nil
         set_button_status("Elemental atualizado", "Atualizado")
         notify_user("O Elemental foi atualizado.")
      else
         open_android_installer()
      end
      return
   end

   update_config = get_update_config()
   if not update_config then
      notify_user("O feed Android deste canal ainda não está configurado.")
      return
   end

   set_button_status("Verificando atualização Android")
   local ok, operation = pcall(function()
      return http_get_json(update_config.androidManifestUrl, function(manifest, err)
            check_operation = nil
            if err or type(manifest) ~= "table" then
               log_error("Android manifest check failed: " .. tostring(err))
               set_button_status("Não foi possível verificar atualizações")
               notify_user("Não foi possível verificar a atualização Android.")
               return
            end

            if manifest.schemaVersion ~= 1 or manifest.channel ~= update_config.channel or
               type(manifest.versionCode) ~= "number" or manifest.versionCode % 1 ~= 0 or
               type(manifest.applicationId) ~= "string" or
               type(manifest.apk) ~= "table" then
               notify_user("O manifesto Android não corresponde ao canal selecionado.")
               return
            end

            start_download(manifest)
         end)
   end)
   if not ok then
      check_operation = nil
      set_button_status("Não foi possível verificar atualizações")
      notify_user("Não foi possível verificar a atualização Android.")
      log_error(operation)
      return
   end
   check_operation = operation
end

local function on_game_end()
   if pending_apk_path then
      open_android_installer()
   end
end

function init()
   if not g_platform.isMobile() or not g_android then
      return
   end

   update_config = get_update_config()
   if not update_config then
      return
   end

   update_button = modules.client_topmenu.addRightButton(
      "elementalAndroidUpdateButton",
      "Atualizar Elemental",
      nil,
      check_for_update,
      true
   )
   connect(g_game, { onGameEnd = on_game_end })
   set_button_status("Baixar e instalar a atualização Android")
end

function terminate()
   if check_event then
      removeEvent(check_event)
      check_event = nil
   end
   stop_status_event()
   if check_operation then
      HTTP.cancel(check_operation)
      check_operation = nil
   end
   if download_operation then
      HTTP.cancel(download_operation)
      download_operation = nil
   end
   if update_button and not update_button:isDestroyed() then
      update_button:destroy()
      update_button = nil
   end
   if g_android then
      disconnect(g_game, { onGameEnd = on_game_end })
   end
   pending_apk_path = nil
   pending_version_code = nil
end
