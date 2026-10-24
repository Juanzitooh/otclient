local FEEDBACK_CATEGORIES = {
    { id = 'bug', label = tr('Bug') },
    { id = 'gameplay', label = tr('Gameplay') },
    { id = 'usability', label = tr('Usability') },
    { id = 'other', label = tr('Other') },
}

local FEEDBACK_ICON = '/images/icons/icon_help'
local FEEDBACK_BUTTON_ID = 'elementalBetaFeedbackButton'
local FEEDBACK_DESCRIPTION_MAX_LENGTH = 2000
local FEEDBACK_DESCRIPTION_MAX_BYTES = FEEDBACK_DESCRIPTION_MAX_LENGTH * 4
local FEEDBACK_TIMEOUT_SECONDS = 10

local feedbackWindow
local feedbackCategoryBox
local feedbackDescriptionEdit
local feedbackStatusLabel
local feedbackSendButton
local feedbackButton
local feedbackPending = false

local function getBetaFeedbackEndpoint()
    if type(G) ~= 'table' or type(G.host) ~= 'string' or type(G.sessionKey) ~= 'string' then
        return nil
    end
    if not G.host:match('^https://[^/]+/beta/v1/login$')
        or not G.sessionKey:match('^b1%.[A-Za-z0-9_-]+$') or #G.sessionKey ~= 46 then
        return nil
    end
    return G.host:gsub('/login$', '/feedback')
end

local function getFeedbackReleaseVersion()
    local updater = Services and Services.elementalUpdater
    local releaseVersion = updater and updater.releaseVersion
    if type(releaseVersion) ~= 'string' or releaseVersion == '' then
        return 'unknown'
    end
    return releaseVersion
end

local function getUtf8CharacterCount(value)
    local _, continuationBytes = value:gsub('[\128-\191]', '')
    return #value - continuationBytes
end

local function setFeedbackStatus(message, isError)
    if not feedbackStatusLabel then
        return
    end
    feedbackStatusLabel:setText(message or '')
    feedbackStatusLabel:setColor(isError and '#f07070' or '#c0c0c0')
end

local function setFeedbackPending(pending)
    feedbackPending = pending
    feedbackSendButton:setEnabled(not pending)
end

local function onFeedbackResponse(_, errorMessage)
    setFeedbackPending(false)
    if not errorMessage then
        feedbackDescriptionEdit:setText('')
        setFeedbackStatus(tr('Feedback sent. Thank you.'), false)
        return
    end

    if errorMessage:match('^http_status::401') then
        setFeedbackStatus(tr('Your session expired. Please sign in again.'), true)
    elseif errorMessage:match('^http_status::429') then
        setFeedbackStatus(tr('Feedback limit reached. Please try again later.'), true)
    else
        setFeedbackStatus(tr('Feedback could not be sent. Check your connection and try again.'), true)
    end
end

function init()
    g_ui.importStyle('bugreport')
    feedbackWindow = g_ui.createWidget('BetaFeedbackWindow', rootWidget)
    feedbackWindow:hide()

    feedbackCategoryBox = feedbackWindow:getChildById('feedbackCategoryBox')
    feedbackDescriptionEdit = feedbackWindow:getChildById('feedbackDescriptionEdit')
    feedbackStatusLabel = feedbackWindow:getChildById('feedbackStatusLabel')
    feedbackSendButton = feedbackWindow:getChildById('feedbackSendButton')
    feedbackDescriptionEdit:setMaxLength(FEEDBACK_DESCRIPTION_MAX_BYTES)

    for _, category in ipairs(FEEDBACK_CATEGORIES) do
        feedbackCategoryBox:addOption(category.label, category.id)
    end
    feedbackCategoryBox:setCurrentOptionByData('bug')

    Keybind.new('Dialogs', 'Open Bugreport', 'Ctrl+Z', '')
    Keybind.bind('Dialogs', 'Open Bugreport', {
        {
            type = KEY_DOWN,
            callback = show,
        }
    }, modules.game_interface.getRootPanel())

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
    })
    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
    })
    Keybind.delete('Dialogs', 'Open Bugreport')
    if feedbackButton and not feedbackButton:isDestroyed() then
        feedbackButton:destroy()
    end
    feedbackButton = nil
    feedbackWindow:destroy()
end

function onGameStart()
    local endpoint = getBetaFeedbackEndpoint()
    if not feedbackButton or feedbackButton:isDestroyed() then
        feedbackButton = modules.game_mainpanel.addToggleButton(
            FEEDBACK_BUTTON_ID,
            tr('Beta feedback'),
            FEEDBACK_ICON,
            show,
            false,
            40
        )
    end
    feedbackButton:setVisible(endpoint ~= nil)
    feedbackButton:setOn(false)
end

function onGameEnd()
    hideFeedback()
    if feedbackButton and not feedbackButton:isDestroyed() then
        feedbackButton:setVisible(false)
        feedbackButton:setOn(false)
    end
    setFeedbackPending(false)
end

function show()
    if not g_game.isOnline() or not getBetaFeedbackEndpoint() then
        return
    end

    feedbackWindow:getChildById('feedbackReleaseVersion'):setText(getFeedbackReleaseVersion())
    feedbackCategoryBox:setCurrentOptionByData('bug')
    feedbackDescriptionEdit:setText('')
    setFeedbackStatus('', false)
    feedbackWindow:show()
    feedbackWindow:raise()
    feedbackWindow:focus()
    if feedbackButton and not feedbackButton:isDestroyed() then
        feedbackButton:setOn(true)
    end
end

function hideFeedback()
    if feedbackWindow then
        feedbackWindow:hide()
    end
    if feedbackButton and not feedbackButton:isDestroyed() then
        feedbackButton:setOn(false)
    end
end

function sendFeedback()
    if feedbackPending or not g_game.isOnline() then
        return
    end

    local endpoint = getBetaFeedbackEndpoint()
    local categoryOption = feedbackCategoryBox:getCurrentOption()
    local description = feedbackDescriptionEdit:getText():gsub('^%s+', ''):gsub('%s+$', '')
    if not endpoint or not categoryOption or not categoryOption.data then
        setFeedbackStatus(tr('Your beta session is unavailable. Please sign in again.'), true)
        return
    end
    if description == '' then
        setFeedbackStatus(tr('Write a short description before sending.'), true)
        return
    end
    if getUtf8CharacterCount(description) > FEEDBACK_DESCRIPTION_MAX_LENGTH then
        setFeedbackStatus(tr('Description must be 2,000 characters or fewer.'), true)
        return
    end

    local payload = {
        releaseVersion = getFeedbackReleaseVersion(),
        category = categoryOption.data,
        description = description,
    }
    setFeedbackPending(true)
    setFeedbackStatus(tr('Sending feedback...'), false)
    HTTP.postWithBearer(endpoint, payload, G.sessionKey, onFeedbackResponse, FEEDBACK_TIMEOUT_SECONDS)
end
