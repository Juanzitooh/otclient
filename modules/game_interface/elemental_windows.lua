ElementalWindowHost = {}

local windowLayer = nil
local entries = {}
local active = false
local reflowEvent = nil
local viewportMonitorEvent = nil
local lastViewportWidth = nil
local lastViewportHeight = nil
local geometryOwner = nil
local originalGeometryChange = nil
local geometryChangeHandler = nil
local SETTINGS_KEY = 'ElementalDesktopWindows'

local function getRootPanel()
    return modules.game_interface.getRootPanel()
end

local function getLayerSize()
    local width = windowLayer:getWidth()
    local height = windowLayer:getHeight()
    local rootPanel = getRootPanel()
    if width <= 0 then
        width = rootPanel:getWidth()
    end
    if height <= 0 then
        height = rootPanel:getHeight()
    end
    return width, height
end

local function getSettings()
    return g_settings.getNode(SETTINGS_KEY) or {}
end

local function getMobileBottomInset()
    if not g_platform.isMobile() then
        return 0
    end

    local inset = 0
    for _, module in ipairs({ modules.game_joystick, modules.game_shortcuts }) do
        if module and module.getPanel then
            local panel = module.getPanel()
            if panel and not panel:isDestroyed() and panel:isVisible() then
                inset = math.max(inset, panel:getHeight())
            end
        end
    end
    return inset + 12
end

local function getDefaultRect(id)
    local parentWidth, parentHeight = getLayerSize()
    local rect = { x = 24, y = 72, width = 300, height = 320 }

    if id == 'inventory' then
        rect = { x = 24, y = 72, width = 250, height = 280 }
    elseif id == 'battle' then
        rect = { x = parentWidth - 242, y = 72, width = 218, height = 360 }
    elseif id == 'friends' then
        rect = { x = parentWidth - 312, y = parentHeight - 326, width = 288, height = 300 }
    elseif id == 'chat' then
        if g_platform.isMobile() then
            local width = math.min(500, math.max(parentWidth - 24, 160))
            local bottomInset = getMobileBottomInset()
            local availableHeight = math.max(140, parentHeight - bottomInset - 12)
            local height = math.min(300, math.max(170, math.floor(parentHeight * 0.36)), availableHeight)
            rect = {
                x = math.floor((parentWidth - width) / 2),
                y = parentHeight - bottomInset - height,
                width = width,
                height = height
            }
        else
            rect = { x = 8, y = parentHeight - 163, width = 550, height = 155 }
        end
    end

    rect.width = math.min(rect.width, math.max(parentWidth - 16, 160))
    rect.height = math.min(rect.height, math.max(parentHeight - 16, 120))
    rect.x = math.max(8, math.min(rect.x, parentWidth - rect.width - 8))
    rect.y = math.max(8, math.min(rect.y, parentHeight - rect.height - 8))
    return rect
end

local function getWindow(entry)
    return (entry.isMiniWindow or entry.isDirectWindow) and entry.widget or entry.shell
end

local function saveGeometry(entry)
    local widget = getWindow(entry)
    if not widget or widget:isDestroyed() then
        return
    end

    local settings = getSettings()
    settings[entry.id] = {
        x = widget:getX(),
        y = widget:getY(),
        width = widget:getWidth(),
        height = widget:getHeight()
    }
    g_settings.setNode(SETTINGS_KEY, settings)
    g_settings.save()
end

local function scheduleSave(entry)
    if not active or entry.applyingGeometry then
        return
    end
    if entry.saveEvent then
        removeEvent(entry.saveEvent)
    end
    entry.saveEvent = scheduleEvent(function()
        entry.saveEvent = nil
        saveGeometry(entry)
    end, 200)
end

local function scheduleWrappedContentSync(entry)
    if not entry.fitContent or not entry.managed or not entry.shell or entry.shell:isDestroyed() then
        return
    end
    if entry.contentInitialized and not entry.fitContentOnResize then
        return
    end
    if entry.contentSyncEvent then
        removeEvent(entry.contentSyncEvent)
    end
    entry.contentSyncEvent = scheduleEvent(function()
        entry.contentSyncEvent = nil
        if not entry.managed or not entry.shell or entry.shell:isDestroyed() or entry.widget:isDestroyed() then
            return
        end
        entry.widget:setRect({
            x = 0,
            y = 0,
            width = math.max(entry.shell:getWidth() - 16, 0),
            height = math.max(entry.shell:getHeight() - 40, 0)
        })
        entry.widget:bindRectToParent()
        entry.widget:show()
        entry.widget:raise()
        entry.contentInitialized = true
        if entry.onContentSync then
            entry.onContentSync(entry.widget)
        end
    end, 50)
end

local function connectGeometry(entry, widget)
    entry.originalGeometryChange = widget.onGeometryChange
    widget.onGeometryChange = function(...)
        if entry.originalGeometryChange then
            entry.originalGeometryChange(...)
        end
        scheduleWrappedContentSync(entry)
        scheduleSave(entry)
    end
end

local function applyGeometry(entry)
    local widget = getWindow(entry)
    if not widget or widget:isDestroyed() then
        return
    end

    local parentWidth, parentHeight = getLayerSize()
    local settings = getSettings()
    local rect
    if g_platform.isMobile() and entry.id == 'chat' then
        rect = getDefaultRect(entry.id)
    else
        rect = settings[entry.id] or getDefaultRect(entry.id)
    end
    local width = math.min(tonumber(rect.width) or 300, math.max(parentWidth - 16, 160))
    local height = math.min(tonumber(rect.height) or 300, math.max(parentHeight - 16, 120))
    local x = tonumber(rect.x) or 8
    local y = tonumber(rect.y) or 8
    x = math.max(8, math.min(x, parentWidth - width - 8))
    y = math.max(8, math.min(y, parentHeight - height - 8))

    if entry.geometryUnlockEvent then
        removeEvent(entry.geometryUnlockEvent)
        entry.geometryUnlockEvent = nil
    end
    entry.applyingGeometry = true
    widget:setRect({ x = x, y = y, width = width, height = height })
    widget:bindRectToParent()
    if entry.isMiniWindow then
        local resizeBorder = widget:getChildById('bottomResizeBorder')
        if resizeBorder then
            resizeBorder:setMaximum(math.max(parentHeight - 16, resizeBorder:getMinimum()))
        end
    elseif entry.isDirectWindow then
        local rightResizeBorder = widget:getChildById('elementalWindowRightResize')
        local bottomResizeBorder = widget:getChildById('elementalWindowBottomResize')
        if not entry.resizable then
            if rightResizeBorder then
                rightResizeBorder:disable()
                rightResizeBorder:hide()
            end
            if bottomResizeBorder then
                bottomResizeBorder:disable()
                bottomResizeBorder:hide()
            end
        end
        if rightResizeBorder and entry.resizable then
            rightResizeBorder:enable()
            rightResizeBorder:show()
            rightResizeBorder:setMaximum(math.max(parentWidth - 16, rightResizeBorder:getMinimum()))
            if entry.minimumWidth then
                rightResizeBorder:setMinimum(entry.minimumWidth)
            end
        end
        if bottomResizeBorder and entry.resizable then
            bottomResizeBorder:enable()
            bottomResizeBorder:show()
            bottomResizeBorder:setMaximum(math.max(parentHeight - 16, bottomResizeBorder:getMinimum()))
            if entry.minimumHeight then
                bottomResizeBorder:setMinimum(entry.minimumHeight)
            end
        end
    else
        local rightResizeBorder = widget:getChildById('elementalWindowRightResize')
        local bottomResizeBorder = widget:getChildById('elementalWindowBottomResize')
        if not entry.resizable then
            if rightResizeBorder then
                rightResizeBorder:disable()
                rightResizeBorder:hide()
            end
            if bottomResizeBorder then
                bottomResizeBorder:disable()
                bottomResizeBorder:hide()
            end
        end
        if rightResizeBorder then
            if entry.resizable then
                rightResizeBorder:enable()
                rightResizeBorder:show()
            end
            rightResizeBorder:setMaximum(math.max(parentWidth - 16, rightResizeBorder:getMinimum()))
            if entry.minimumWidth then
                rightResizeBorder:setMinimum(entry.minimumWidth)
            end
        end
        if bottomResizeBorder then
            if entry.resizable then
                bottomResizeBorder:enable()
                bottomResizeBorder:show()
            end
            bottomResizeBorder:setMaximum(math.max(parentHeight - 16, bottomResizeBorder:getMinimum()))
            if entry.minimumHeight then
                bottomResizeBorder:setMinimum(entry.minimumHeight)
            end
        end
        scheduleWrappedContentSync(entry)
    end
    entry.geometryUnlockEvent = scheduleEvent(function()
        entry.geometryUnlockEvent = nil
        entry.applyingGeometry = false
    end, 100)
end

local function scheduleReflow(delay)
    if reflowEvent then
        removeEvent(reflowEvent)
    end
    reflowEvent = scheduleEvent(function()
        reflowEvent = nil
        if not active then
            return
        end
        for _, entry in pairs(entries) do
            if entry.managed then
                applyGeometry(entry)
            end
        end
    end, delay or 75)
end

local function monitorViewport()
    viewportMonitorEvent = nil
    if not active then
        return
    end

    local width, height = getLayerSize()
    if width ~= lastViewportWidth or height ~= lastViewportHeight then
        lastViewportWidth = width
        lastViewportHeight = height
        scheduleReflow(75)
    end
    viewportMonitorEvent = scheduleEvent(monitorViewport, 250)
end

local function closeWindow(entry)
    if not entry then
        return false
    end

    if entry.isMiniWindow then
        entry.widget:close(true)
    elseif entry.isDirectWindow then
        entry.widget:hide()
    elseif entry.shell and not entry.shell:isDestroyed() then
        entry.shell:hide()
    end
    getRootPanel():focus()
    return true
end

local function openWindow(entry)
    if not entry or not active then
        return false
    end

    if entry.isMiniWindow then
        entry.widget:open(true)
        entry.widget:raise()
    elseif entry.isDirectWindow then
        entry.widget:show()
        entry.widget:raise()
    else
        entry.widget:show()
        entry.shell:show()
        entry.shell:raise()
    end
    scheduleReflow(50)
    getRootPanel():focus()
    return true
end

local function manage(entry)
    if not modules.game_interface.isElementalProfileInWorld() or not windowLayer or entry.managed then
        return false
    end
    if not entry.widget or entry.widget:isDestroyed() then
        return false
    end

    if entry.isMiniWindow then
        entry.widget.save = false
        entry.widget:setParent(windowLayer, true)
        entry.widget:close(true)
        local closeButton = entry.widget:getChildById('closeButton')
        if closeButton then
            entry.originalCloseClick = closeButton.onClick
            closeButton.onClick = function()
                closeWindow(entry)
            end
        end
        connectGeometry(entry, entry.widget)
    elseif entry.isDirectWindow then
        entry.originalParent = entry.widget:getParent()
        entry.originalRect = entry.widget:getRect()
        entry.originalDraggable = entry.widget:isDraggable()
        entry.originalVisible = entry.widget:isVisible()
        entry.widget:setParent(windowLayer, true)
        entry.widget:breakAnchors()
        entry.widget:setDraggable(true)
        entry.widget:hide()
        connectGeometry(entry, entry.widget)
    else
        entry.shell = g_ui.createWidget('ElementalFloatingWindow', windowLayer)
        entry.shell:getChildById('elementalWindowTitle'):setText(entry.title)
        entry.shell:getChildById('elementalWindowCloseButton').onClick = function()
            closeWindow(entry)
        end
        entry.originalParent = entry.widget:getParent()
        entry.originalRect = entry.widget:getRect()
        entry.widget:setDraggable(false)
        entry.widget:setParent(entry.shell:getChildById('elementalWindowContent'))
        entry.widget:bindRectToParent()
        entry.widget:show()
        entry.shell:hide()
        connectGeometry(entry, entry.shell)
    end

    entry.managed = true
    applyGeometry(entry)
    return true
end

local function release(entry, restoreCharacterSettings)
    if entry.geometryUnlockEvent then
        removeEvent(entry.geometryUnlockEvent)
        entry.geometryUnlockEvent = nil
    end
    entry.applyingGeometry = false
    if entry.saveEvent then
        removeEvent(entry.saveEvent)
        entry.saveEvent = nil
    end
    if entry.contentSyncEvent then
        removeEvent(entry.contentSyncEvent)
        entry.contentSyncEvent = nil
    end
    if not entry.managed then
        return
    end

    if entry.isMiniWindow then
        entry.widget:close(true)
        entry.widget.onGeometryChange = entry.originalGeometryChange
        entry.widget.save = entry.originalSave
        local closeButton = entry.widget:getChildById('closeButton')
        if closeButton then
            closeButton.onClick = entry.originalCloseClick
        end
        entry.widget:setParent(nil, true)
        if restoreCharacterSettings and g_game.isOnline() then
            entry.widget:setupOnStart()
        end
    elseif entry.isDirectWindow then
        entry.widget.onGeometryChange = entry.originalGeometryChange
        entry.widget:setParent(entry.originalParent, true)
        entry.widget:breakAnchors()
        entry.widget:fill('parent')
        entry.widget:setDraggable(entry.originalDraggable)
        entry.widget:setVisible(entry.originalVisible)
    else
        entry.widget:setParent(entry.originalParent, true)
        if entry.originalRect then
            entry.widget:setRect(entry.originalRect)
        end
        entry.widget:setDraggable(entry.originalDraggable)
        if entry.shell and not entry.shell:isDestroyed() then
            entry.shell:destroy()
        end
        entry.shell = nil
    end

    entry.managed = false
    entry.contentInitialized = false
end

function ElementalWindowHost.init(parentLayer)
    local parentPanel = parentLayer:getParent()
    if windowLayer == parentLayer and geometryOwner == parentPanel and geometryChangeHandler then
        return
    end
    if geometryOwner and geometryChangeHandler and geometryOwner.onGeometryChange == geometryChangeHandler then
        geometryOwner.onGeometryChange = originalGeometryChange
    end
    windowLayer = parentLayer
    geometryOwner = parentPanel
    originalGeometryChange = geometryOwner.onGeometryChange
    geometryChangeHandler = function(...)
        if originalGeometryChange then
            originalGeometryChange(...)
        end
        if active then
            scheduleReflow()
        end
    end
    geometryOwner.onGeometryChange = geometryChangeHandler
end

function ElementalWindowHost.register(id, title, widget, options)
    if not id or not widget then
        return false
    end

    local entry = entries[id]
    if not entry then
        options = options or {}
        entry = {
            id = id,
            title = title,
            widget = widget,
            isMiniWindow = widget.UIMiniWindowContainer == true and not options.wrap,
            isDirectWindow = options.directWindow == true,
            originalParent = widget:getParent(),
            originalRect = widget:getRect(),
            originalSave = widget.save,
            originalDraggable = widget:isDraggable(),
            fitContent = options.fitContent == true,
            fitContentOnResize = options.fitContentOnResize ~= false,
            resizable = options.resizable ~= false,
            minimumWidth = options.minimumWidth,
            minimumHeight = options.minimumHeight,
            onContentSync = options.onContentSync
        }
        entries[id] = entry
    else
        entry.title = title or entry.title
        entry.widget = widget
    end

    if active then
        manage(entry)
    end
    return true
end

function ElementalWindowHost.unregister(id, widget)
    local entry = entries[id]
    if not entry or widget and entry.widget ~= widget then
        return false
    end
    release(entry, false)
    entries[id] = nil
    return true
end

function ElementalWindowHost.activate()
    if active then
        return
    end
    active = true
    windowLayer:show()
    lastViewportWidth, lastViewportHeight = getLayerSize()
    for _, entry in pairs(entries) do
        manage(entry)
    end
    scheduleReflow(50)
    viewportMonitorEvent = scheduleEvent(monitorViewport, 250)
end

function ElementalWindowHost.deactivate(restoreCharacterSettings)
    if not active then
        return
    end
    active = false
    if reflowEvent then
        removeEvent(reflowEvent)
        reflowEvent = nil
    end
    if viewportMonitorEvent then
        removeEvent(viewportMonitorEvent)
        viewportMonitorEvent = nil
    end
    for _, entry in pairs(entries) do
        release(entry, restoreCharacterSettings)
    end
    windowLayer:hide()
end

function ElementalWindowHost.toggle(id)
    if not active then
        return false
    end
    local entry = entries[id]
    if not entry or not entry.managed then
        return false
    end

    local widget = getWindow(entry)
    if widget:isVisible() then
        return closeWindow(entry)
    end
    return openWindow(entry)
end

function ElementalWindowHost.show(id)
    if not active then
        return false
    end
    local entry = entries[id]
    if not entry or not entry.managed then
        return false
    end

    local widget = getWindow(entry)
    if widget:isVisible() then
        return true
    end
    return openWindow(entry)
end

function ElementalWindowHost.saveAll()
    if not active then
        return
    end
    for _, entry in pairs(entries) do
        if entry.managed then
            saveGeometry(entry)
        end
    end
end
