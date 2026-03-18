function init()
    connect(g_app, {
        onExit = exit
    })

    local platformType = g_window.getPlatformType()
    local isX11 = type(platformType) == 'string' and platformType:find('X11', 1, true) == 1
    local density = (isX11 and g_window.getDisplayDensity()) or 1

    if g_platform.isMobile() then
        g_window.setMinimumSize({ width = 640, height = 360 })
    else
        local minSize = { width = 1020, height = 644 }
        if isX11 and density ~= 1 then
            minSize = {
                width = math.floor((minSize.width * density) + 0.5),
                height = math.floor((minSize.height * density) + 0.5)
            }
        end
        g_window.setMinimumSize(minSize)
    end

    -- window size
    local size = { width = 1020, height = 644 }
    size = g_settings.getSize('window-size', size)
    if isX11 and density ~= 1 then
        size = {
            width = math.floor((size.width * density) + 0.5),
            height = math.floor((size.height * density) + 0.5)
        }
    end

    local displaySize = g_window.getDisplaySize()
    if isX11 then
        size.width = math.max(1, math.min(size.width, displaySize.width))
        size.height = math.max(1, math.min(size.height, displaySize.height))
    end
    g_window.resize(size)

    -- window position, default is the screen center
    local defaultPos = {
        x = (displaySize.width - size.width) / 2,
        y = (displaySize.height - size.height) / 2
    }
    local pos = g_settings.getPoint('window-pos', defaultPos)
    if isX11 and density ~= 1 then
        pos = {
            x = math.floor((pos.x * density) + 0.5),
            y = math.floor((pos.y * density) + 0.5)
        }
        local maxX = math.max(displaySize.width - size.width, 0)
        local maxY = math.max(displaySize.height - size.height, 0)
        pos.x = math.max(0, math.min(pos.x, maxX))
        pos.y = math.max(0, math.min(pos.y, maxY))
    else
        pos.x = math.max(pos.x, 0)
        pos.y = math.max(pos.y, 0)
    end
    g_window.move(pos)

    -- window maximized?
    local maximized = g_settings.getBoolean('window-maximized', false)
    if maximized then g_window.maximize() end

    g_window.setTitle(g_app.getName())
    g_window.setIcon('/images/clienticon')

    -- poll resize events
    g_window.poll()

    -- generate machine uuid, this is a security measure for storing passwords
    if not g_crypt.setMachineUUID(g_settings.get('uuid')) then
        g_settings.set('uuid', g_crypt.getMachineUUID())
        g_settings.save()
    end
end

function terminate()
    disconnect(g_app, {
        onExit = exit
    })

    local platformType = g_window.getPlatformType()
    local isX11 = type(platformType) == 'string' and platformType:find('X11', 1, true) == 1
    local density = (isX11 and g_window.getDisplayDensity()) or 1

    -- save window configs
    local windowSize = g_window.getUnmaximizedSize()
    local windowPos = g_window.getUnmaximizedPos()
    if isX11 and density ~= 1 then
        windowSize = {
            width = math.floor((windowSize.width / density) + 0.5),
            height = math.floor((windowSize.height / density) + 0.5)
        }
        windowPos = {
            x = math.floor((windowPos.x / density) + 0.5),
            y = math.floor((windowPos.y / density) + 0.5)
        }
    end
    g_settings.set('window-size', windowSize)
    g_settings.set('window-pos', windowPos)
    g_settings.set('window-maximized', g_window.isMaximized())
    g_settings.save()
end

function exit()
    g_logger.info('Exiting application..')
end
