MobileLauncher = {}

local SLIDES = {
    {
        image = '/images/brand/elemental-world.png',
        eyebrow = 'ELEMENTAL • SUA PRÓXIMA JORNADA',
        title = 'Um mundo de possibilidades.'
    },
    {
        image = '/images/brand/elemental-client-login.png',
        eyebrow = 'ENTRE NO MUNDO ELEMENTAL',
        title = 'Sua jornada começa aqui.'
    },
    {
        image = '/images/brand/elemental-world.png',
        eyebrow = 'VIVA ESSA AVENTURA',
        title = 'Descubra seu elemento.'
    }
}

local ASSET_CLIENT_VERSION = 1281
local LOGO_REVEAL_WIDTH = 340
local LOGO_REVEAL_STEP = 5
local LOGO_REVEAL_INTERVAL = 25
local CAROUSEL_INTERVAL = 8000

local window
local artwork
local eyebrow
local title
local statusLabel
local detailLabel
local progressBar
local actionButton
local logoMask
local dots = {}
local slideIndex = 1
local logoRevealEvent
local carouselEvent
local slideTransitionEvent
local onContinue
local clientVersion
local assetsReady = false
local apkCheckComplete = false
local apkUpdateAvailable = false
local assetCheckFailed = false

local function isActive()
    return window and not window:isDestroyed()
end

local function setProgress(percent)
    if not isActive() or not progressBar then
        return
    end
    progressBar:setPercent(math.max(0, math.min(100, tonumber(percent) or 0)))
end

local function setStatus(status, detail, percent)
    if not isActive() then
        return
    end
    if statusLabel then
        statusLabel:setText(status or '')
    end
    if detailLabel then
        detailLabel:setText(detail or '')
    end
    if percent ~= nil then
        setProgress(percent)
    end
end

local function setAction(text, enabled)
    if not isActive() or not actionButton then
        return
    end
    actionButton:setText(text)
    if enabled then
        actionButton:enable()
    else
        actionButton:disable()
    end
end

local function updateAction()
    if not isActive() then
        return
    end

    if assetCheckFailed then
        setAction('TENTAR NOVAMENTE', true)
        return
    end
    if not assetsReady or not apkCheckComplete then
        setAction('PREPARANDO', false)
        return
    end
    if apkUpdateAvailable then
        setAction('ATUALIZAR APK', true)
        return
    end
    setAction('INICIAR', true)
end

local function setChannelAndVersion()
    if not isActive() then
        return
    end

    local channel = Services and Services.elementalUpdater and Services.elementalUpdater.channel or 'test'
    local channelLabels = {
        test = 'TESTE FECHADO',
        beta = 'BETA',
        release = 'RELEASE'
    }
    local channelWidget = window:recursiveGetChildById('mobileLauncherChannel')
    local versionWidget = window:recursiveGetChildById('mobileLauncherVersion')
    if channelWidget then
        channelWidget:setText(channelLabels[channel] or string.upper(channel))
    end
    if versionWidget and g_android then
        versionWidget:setText('ANDROID • v' .. tostring(g_android.getVersionCode()))
    end
end

local function updateDots()
    for index, dot in ipairs(dots) do
        if dot and not dot:isDestroyed() then
            dot:setBackgroundColor(index == slideIndex and '#ffbd6b' or '#f7f1e466')
        end
    end
end

local function stopSlideTransition()
    if slideTransitionEvent then
        removeEvent(slideTransitionEvent)
        slideTransitionEvent = nil
    end
    if artwork and not artwork:isDestroyed() and artwork.fadeEvent and g_effects then
        g_effects.cancelFade(artwork)
    end
end

function MobileLauncher.setSlide(index)
    if not isActive() or not SLIDES[index] or index == slideIndex then
        return
    end

    stopSlideTransition()
    slideIndex = index
    updateDots()
    g_effects.fadeOut(artwork, 220)
    slideTransitionEvent = scheduleEvent(function()
        slideTransitionEvent = nil
        if not isActive() then
            return
        end
        artwork:setImageSource(SLIDES[slideIndex].image)
        eyebrow:setText(SLIDES[slideIndex].eyebrow)
        title:setText(SLIDES[slideIndex].title)
        g_effects.fadeIn(artwork, 420)
    end, 230)
end

local function scheduleCarousel()
    if carouselEvent then
        removeEvent(carouselEvent)
    end
    carouselEvent = scheduleEvent(function()
        carouselEvent = nil
        if not isActive() then
            return
        end
        MobileLauncher.setSlide((slideIndex % #SLIDES) + 1)
        scheduleCarousel()
    end, CAROUSEL_INTERVAL)
end

local function revealLogo()
    if not isActive() then
        return
    end
    local width = 0
    logoMask:setWidth(width)

    local function step()
        logoRevealEvent = nil
        if not isActive() then
            return
        end
        width = math.min(width + LOGO_REVEAL_STEP, LOGO_REVEAL_WIDTH)
        logoMask:setWidth(width)
        if width < LOGO_REVEAL_WIDTH then
            logoRevealEvent = scheduleEvent(step, LOGO_REVEAL_INTERVAL)
        end
    end

    step()
end

local function reloadClientAssets(version, assetsChanged)
    local gameThings = modules.game_things
    local needsReload = assetsChanged or not gameThings or
        not gameThings.isLoaded or not gameThings.isLoaded()
    if not needsReload then
        EnterGame.markClientAssetsReady(version)
        return true
    end
    if not gameThings or not gameThings.reloadClientVersion or
       not gameThings.reloadClientVersion(version) then
        return false
    end

    EnterGame.markClientAssetsReady(version)
    return true
end

local function checkAndroidApk()
    if not isActive() then
        return
    end

    local updater = modules.client_launcher_android_update
    if not updater or not updater.checkForUpdate or not updater.setStatusListener then
        apkCheckComplete = true
        setStatus('Conteúdo pronto para jogar', 'Não foi possível consultar atualizações do APK.', 100)
        updateAction()
        return
    end

    setStatus('Conteúdo pronto para jogar', 'Verificando se o aplicativo também precisa atualizar.', 100)
    updater.setStatusListener(function(message, percent, state)
        if not isActive() then
            return
        end
        if state == 'downloading' then
            setStatus('Baixando atualização do aplicativo',
                tostring(percent or 0) .. '% baixado', percent)
            setAction('BAIXANDO ' .. tostring(percent or 0) .. '%', false)
        elseif state == 'install_permission' then
            setStatus('Permissão necessária para instalar', message)
            setAction('PERMITIR INSTALAÇÃO', true)
        elseif state == 'installer_opened' then
            setStatus('Confirme a atualização no Android', message)
            setAction('CONTINUAR INSTALAÇÃO', true)
        elseif state == 'error' then
            setStatus('Não foi possível concluir a atualização', message)
            updateAction()
        elseif state == 'notice' then
            setStatus(message, 'Siga as instruções exibidas pelo Android.')
            if apkUpdateAvailable then
                setAction('TENTAR APK NOVAMENTE', true)
            end
        end
    end)
    updater.checkForUpdate(function(success, manifest, message)
        if not isActive() then
            return
        end
        apkCheckComplete = true
        apkUpdateAvailable = success and type(manifest) == 'table'
        if apkUpdateAvailable then
            setStatus('Nova versão do aplicativo disponível',
                string.format('A versão %s pode ser instalada agora.', tostring(manifest.versionCode)), 100)
        elseif success then
            setStatus('Tudo pronto para jogar', 'Sprites, áudio e aplicativo estão atualizados.', 100)
        else
            setStatus('Conteúdo pronto para jogar', message or 'Não foi possível verificar o APK; você pode iniciar a versão instalada.', 100)
        end
        updateAction()
    end)
end

local function onAssetsReady(success, message, assetsChanged)
    if not isActive() then
        return
    end

    if not success then
        assetCheckFailed = true
        setStatus('Não foi possível preparar os assets', message or 'Verifique a conexão e tente novamente.')
        updateAction()
        return
    end
    if not reloadClientAssets(clientVersion, assetsChanged) then
        assetCheckFailed = true
        setStatus('Os assets foram baixados, mas não puderam ser carregados',
            'Feche e abra o aplicativo novamente antes de jogar.')
        updateAction()
        return
    end

    assetsReady = true
    assetCheckFailed = false
    setStatus('Conteúdo do jogo pronto', 'Verificando a versão do aplicativo Android.', 100)
    checkAndroidApk()
end

local function beginAssetCheck()
    if not isActive() then
        return
    end

    assetCheckFailed = false
    assetsReady = false
    apkCheckComplete = false
    apkUpdateAvailable = false
    setProgress(0)
    updateAction()

    clientVersion = EnterGame.getSelectedClientVersion()
    if not clientVersion or clientVersion < ASSET_CLIENT_VERSION or
       not modules.client_assets or not modules.client_assets.ensureClientVersion or
       not modules.client_assets.isClientVersionInstalled or
       (modules.client_assets.isEnabled and not modules.client_assets.isEnabled()) then
        assetsReady = true
        EnterGame.markClientAssetsReady(clientVersion)
        setStatus('Conteúdo do jogo pronto', 'Verificando a versão do aplicativo Android.', 100)
        checkAndroidApk()
        return
    end

    local shouldSync = not modules.client_assets.isClientVersionInstalled(clientVersion) or
        (modules.client_assets.shouldCheckClientVersionUpdates and
         modules.client_assets.shouldCheckClientVersionUpdates())
    if not shouldSync then
        assetsReady = true
        EnterGame.markClientAssetsReady(clientVersion)
        setStatus('Conteúdo do jogo pronto', 'Verificando a versão do aplicativo Android.', 100)
        checkAndroidApk()
        return
    end

    setStatus('Atualizando sprites e áudio', 'Aguarde enquanto o conteúdo é preparado para jogar.')
    modules.client_assets.ensureClientVersion(clientVersion, onAssetsReady,
        function(status, percent)
            if not isActive() then
                return
            end
            local progressDetail = 'Conferindo e organizando os arquivos do jogo.'
            local statusText = string.lower(tostring(status or ''))
            if statusText:find('download', 1, true) then
                progressDetail = 'Baixando sprites e áudio.'
            elseif statusText:find('install', 1, true) or statusText:find('finish', 1, true) then
                progressDetail = 'Instalando sprites e áudio.'
            end
            if percent ~= nil then
                progressDetail = string.format('%s • %d%%', progressDetail,
                    math.floor(tonumber(percent) or 0))
            end
            setStatus('Atualizando sprites e áudio', progressDetail, percent)
        end)
end

function MobileLauncher.onAction()
    if not isActive() then
        return
    end

    if assetCheckFailed then
        beginAssetCheck()
        return
    end
    if not assetsReady or not apkCheckComplete then
        return
    end
    if apkUpdateAvailable then
        setAction('PREPARANDO APK', false)
        local updater = modules.client_launcher_android_update
        if updater and updater.downloadAndInstall then
            updater.downloadAndInstall()
        else
            setStatus('Atualização indisponível', 'Reabra o aplicativo e tente novamente.')
            setAction('INICIAR', true)
        end
        return
    end

    local callback = onContinue
    onContinue = nil
    MobileLauncher.hide()
    if callback then
        callback()
    else
        EnterGame.show()
    end
end

function MobileLauncher.show(continueCallback)
    if not g_platform.isMobile() or not g_android then
        return false
    end
    if isActive() then
        return true
    end

    window = g_ui.displayUI('mobile_launcher')
    if not window then
        return false
    end
    onContinue = continueCallback
    EnterGame.hide()

    artwork = window:recursiveGetChildById('mobileLauncherArtwork')
    eyebrow = window:recursiveGetChildById('mobileLauncherEyebrow')
    title = window:recursiveGetChildById('mobileLauncherTitle')
    statusLabel = window:recursiveGetChildById('mobileLauncherStatus')
    detailLabel = window:recursiveGetChildById('mobileLauncherDetail')
    progressBar = window:recursiveGetChildById('mobileLauncherProgress')
    actionButton = window:recursiveGetChildById('mobileLauncherAction')
    logoMask = window:recursiveGetChildById('mobileLauncherLogoMask')
    dots = {
        window:recursiveGetChildById('mobileLauncherDotOne'),
        window:recursiveGetChildById('mobileLauncherDotTwo'),
        window:recursiveGetChildById('mobileLauncherDotThree')
    }
    slideIndex = 1
    setChannelAndVersion()
    updateDots()
    g_effects.fadeIn(window, 300)
    revealLogo()
    scheduleCarousel()
    beginAssetCheck()
    return true
end

function MobileLauncher.hide()
    if carouselEvent then
        removeEvent(carouselEvent)
        carouselEvent = nil
    end
    if slideTransitionEvent then
        removeEvent(slideTransitionEvent)
        slideTransitionEvent = nil
    end
    if logoRevealEvent then
        removeEvent(logoRevealEvent)
        logoRevealEvent = nil
    end
    if artwork and not artwork:isDestroyed() and artwork.fadeEvent then
        g_effects.cancelFade(artwork)
    end
    if window and not window:isDestroyed() and window.fadeEvent then
        g_effects.cancelFade(window)
    end
    if window and not window:isDestroyed() then
        window:destroy()
    end
    local updater = modules.client_launcher_android_update
    if updater and updater.setStatusListener then
        updater.setStatusListener(nil)
    end
    window = nil
    artwork = nil
    eyebrow = nil
    title = nil
    statusLabel = nil
    detailLabel = nil
    progressBar = nil
    actionButton = nil
    logoMask = nil
    dots = {}
end

function MobileLauncher.terminate()
    MobileLauncher.hide()
    onContinue = nil
end
