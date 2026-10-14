local window
local topMenuButton
local canvas
local mountedRoots = {}
local activeVersion
local activeAssetPath
local activeWorkRoot
local selectedAppearanceCategory = 0
local selectedAppearanceId
local selectedSpriteId
local appearanceEntries = {}
local filteredAppearanceEntries = {}
local categoryAppearanceCounts = {}
local appearanceRows = {}
local appearanceOriginal
local appearanceChanges = { bools = {}, values = {}, strings = {}, animation = { groups = {} } }
local appearanceValueWidgets = {}
local appearanceStringWidgets = {}
local animationWidgets = {}
local buildingAppearanceProperties = false
local currentPage = 'editor'
local currentPropertiesTab = 'flags'
local previewFrameGroups = {}
local previewFrameGroupIndex = 1
local previewPatternX = 0
local previewPatternY = 0
local previewPatternZ = 0
local previewLayer = 0
local previewPhase = 0
local previewMounted = false
local previewMoving = false
local previewIdleGroupIndex
local previewMovingGroupIndex
local previewHasMovementToggle = false
local selectedSpriteContext
local gameStartCallback
local gameEndCallback
local pendingSpriteEdit
local preparedSpritePath = ''
local settingSpritePath = false
local spritePickerRanges = {}
local spritePickerIds
local spritePickerCount = 0
local spritePickerCells = { replace = {}, create = {} }
local spritePickerSourceId
local spritePickerQuery = ''
local selectedReplacementSpriteId
local selectedCreateSpriteId
local spriteSearchEvent
local currentImportSection = 'replace'
local currentReplaceMode = 'sprite'
local currentNewAppearanceSourceMode = 'sprite'
local filePickerWindow
local filePickerDirectory
local filePickerSelection
local filePickerTarget

local SPRITE_PICKER_WIDGET_IDS = {
   replace = {
      search = 'spriteSearchEdit',
      count = 'spritePickerCountLabel',
      list = 'spritePickerList',
      content = 'spritePickerContent',
      selection = 'selectedReplacementSpriteLabel',
   },
   create = {
      search = 'newAppearanceSpriteSearchEdit',
      count = 'newAppearanceSpritePickerCountLabel',
      list = 'newAppearanceSpritePickerList',
      content = 'newAppearanceSpritePickerContent',
      selection = 'newAppearanceSelectedSpriteLabel',
   },
}

local EXTERNAL_EDITOR_SETTING = 'offline-assets-editor-external-editor'

local MAX_SPRITE_ID = 2147483647
local APPEARANCE_ROW_HEIGHT = 52
local PREVIEW_CONTROLS_BOTTOM_MARGIN = 14
local PREVIEW_CANVAS_BOTTOM_MARGIN = 4
local PREVIEW_HINT_BOTTOM_MARGIN = 8
local MAX_PREVIEW_TIMELINE_FRAMES = 20
local PREVIEW_TIMELINE_HEIGHT = 74
local PREVIEW_TIMELINE_ONLY_HEIGHT = 36
local PREVIEW_FRAME_SELECTION_WIDTH = 164
local PREVIEW_DURATION_GROUP_GAP = 6
local PREVIEW_DIRECTION_BUTTON_WIDTH = 48
local PREVIEW_DIRECTION_BUTTON_HEIGHT = 21
local PREVIEW_DIRECTION_PAD_GAP = 8
local MAX_APPEARANCE_THUMBNAIL_FRAMES = 8

local PREVIEW_DIRECTIONS = {
   { index = 0, id = 'previewNorth', name = 'North' },
   { index = 1, id = 'previewEast', name = 'East' },
   { index = 2, id = 'previewSouth', name = 'South' },
   { index = 3, id = 'previewWest', name = 'West' },
   { index = 4, id = 'previewNorthEast', name = 'North-east' },
   { index = 5, id = 'previewSouthEast', name = 'South-east' },
   { index = 6, id = 'previewSouthWest', name = 'South-west' },
   { index = 7, id = 'previewNorthWest', name = 'North-west' },
}

local categories = {
   { name = 'Objects', singular = 'Object', data = 0 },
   { name = 'Outfits', singular = 'Outfit', data = 1 },
   { name = 'Effects', singular = 'Effect', data = 2 },
   { name = 'Missiles', singular = 'Missile', data = 3 },
}

local EQUIPMENT_SLOT_OPTIONS = {
   { label = 'Not equippable', data = 0 },
   { label = 'Head', data = 1 },
   { label = 'Necklace', data = 2 },
   { label = 'Backpack', data = 3 },
   { label = 'Armor', data = 4 },
   { label = 'Right hand', data = 5 },
   { label = 'Left hand', data = 6 },
   { label = 'Legs', data = 7 },
   { label = 'Feet', data = 8 },
   { label = 'Ring', data = 9 },
   { label = 'Ammo', data = 10 },
}

local selectAppearance
local selectSprite
local renderAppearanceRows
local configurePreviewControls
local updateAnimationEditor
local updatePreviewPatternControls
local refreshAppearancePreview
local collectAnimationWidgetChanges
local updateDirectionPadLayout
local refreshSpritePicker
local renderSpritePickerRows
local applySpritePickerFilter
local importPngAsNewSprite
local selectSpritePickerSprite
local linkSpriteToSelectedFrame
local replaceSelectedFrameWithSprite
local updateSpriteReplacementTarget

local function getSpritePickerWidget(name)
   if not window then
      return nil
   end
   local ids = SPRITE_PICKER_WIDGET_IDS[currentImportSection]
   return ids and window:recursiveGetChildById(ids[name]) or nil
end

local function getSelectedSpritePickerId()
   if currentImportSection == 'create' then
      return selectedCreateSpriteId
   end
   return selectedReplacementSpriteId
end

local function setSelectedSpritePickerId(spriteId)
   if currentImportSection == 'create' then
      selectedCreateSpriteId = spriteId
   else
      selectedReplacementSpriteId = spriteId
   end
end

local function setStatus(message)
   if window then
      window:recursiveGetChildById('statusLabel'):setText(message)
   end
end

local function setAppearanceStatus(message)
   if window then
      window:recursiveGetChildById('appearanceStatus'):setText(message)
   end
end

local function getUserFacingError(error)
   local message = tostring(error)
   local stackTraceStart = message:find('\nstack traceback:', 1, true)
   if stackTraceStart then
      message = message:sub(1, stackTraceStart - 1)
   end
   message = message:gsub('^C%+%+ call failed: ', '')
   return message
end

local function getVersions()
   local versions = {}
   for _, entry in ipairs(g_resources.listDirectoryFiles('/data/things/')) do
      local version = tonumber(entry)
      if version and version >= 1500 and version < 1600 and version % 1 == 0 and
            g_resources.fileExists(string.format('/data/things/%d/catalog-content.json', version)) then
         table.insert(versions, version)
      end
   end
   table.sort(versions, function(a, b) return a > b end)
   return versions
end

local function formatClientVersion(version)
   return string.format('%d.%02d', math.floor(version / 100), version % 100)
end

local function getCategoryAppearanceCount(category)
   if categoryAppearanceCounts[category.data] ~= nil then
      return categoryAppearanceCounts[category.data]
   end

   local count = 0
   for _, thing in pairs(g_things.getThingTypes(category.data)) do
      if thing and thing:getId() > 0 then
         count = count + 1
      end
   end
   categoryAppearanceCounts[category.data] = count
   return count
end

local function updateCategoryOptions()
   if not window then
      return
   end
   local comboBox = window:recursiveGetChildById('appearanceCategory')
   local onOptionChange = comboBox.onOptionChange
   comboBox.onOptionChange = nil
   comboBox:clearOptions()
   for _, category in ipairs(categories) do
      local label = tr(category.name)
      if activeVersion then
         label = string.format('%s (%d)', label, getCategoryAppearanceCount(category))
      end
      comboBox:addOption(label, category.data)
   end
   comboBox.onOptionChange = onOptionChange
   comboBox:setCurrentOptionByData(selectedAppearanceCategory, true)
end

local function getThumbnailAnimationSprites(thing)
   local sprites = thing:getThumbnailAnimationSprites()
   if #sprites <= MAX_APPEARANCE_THUMBNAIL_FRAMES then
      return sprites
   end

   local sampled = {}
   for index = 0, MAX_APPEARANCE_THUMBNAIL_FRAMES - 1 do
      local sourceIndex = math.floor(index * (#sprites - 1) / (MAX_APPEARANCE_THUMBNAIL_FRAMES - 1)) + 1
      table.insert(sampled, sprites[sourceIndex])
   end
   return sampled
end

local function hasAppearanceChanges()
   if next(appearanceChanges.bools) ~= nil or
         next(appearanceChanges.values) ~= nil or
         next(appearanceChanges.strings) ~= nil or
         next(appearanceChanges.animation.groups) ~= nil then
      return true
   end

   if not appearanceOriginal then
      return false
   end

   for key, edit in pairs(appearanceStringWidgets) do
      if edit:getText() ~= (appearanceOriginal[key] or '') then
         return true
      end
   end

   for key, edit in pairs(appearanceValueWidgets) do
      local value = tonumber(edit:getText())
      if value == nil or value ~= appearanceOriginal.values[key] then
         return true
      end
   end

   local groupIndex = animationWidgets.groupIndex
   local group = groupIndex ~= nil and appearanceOriginal.frameGroups[groupIndex + 1] or nil
   if group and group.animation and group.animation.enabled then
      for field, edit in pairs(animationWidgets.fields or {}) do
         local value = tonumber(edit:getText())
         if value == nil or value ~= group.animation[field] then
            return true
         end
      end

      for phaseIndex, fields in pairs(animationWidgets.phases or {}) do
         local phase = group.animation.phases[phaseIndex + 1]
         if phase then
            for field, edit in pairs(fields) do
               local value = tonumber(edit:getText())
               if value == nil or value ~= phase[field] then
                  return true
               end
            end
         end
      end
   end

   return false
end

local function clearAppearanceChanges()
   appearanceChanges = { bools = {}, values = {}, strings = {}, animation = { groups = {} } }
end

local function sortedKeys(values)
   local keys = {}
   for key in pairs(values) do
      table.insert(keys, key)
   end
   table.sort(keys)
   return keys
end

local function propertyLabel(key)
   local label = key:gsub('%.', ' / '):gsub('_', ' ')
   return label:sub(1, 1):upper() .. label:sub(2)
end

local function selectedOption(comboBox)
   local option = comboBox and comboBox:getCurrentOption()
   return option and option.data
end

local function updateAppearanceSaveButton()
   if window then
      local hasChanges = hasAppearanceChanges()
      local saveButton = window:recursiveGetChildById('saveAppearanceButton')
      saveButton:setVisible(hasChanges)
      saveButton:setHeight(hasChanges and 26 or 0)
      saveButton:setEnabled(hasChanges)
      if appearanceOriginal then
         setAppearanceStatus(hasChanges and tr('Unsaved edits. Save to the working copy.') or
            tr('Saved in the working copy.'))
      end
   end
end

local function setSpritePath(path)
   if not window then
      return
   end
   settingSpritePath = true
   window:recursiveGetChildById('previewSpritePathEdit'):setText(path or '')
   settingSpritePath = false
end

local function normalizeDirectoryPath(path)
   path = (path or ''):trim():gsub('\\', '/')
   if path == '' then
      path = g_platform.getCurrentDir()
   end
   if path:match('^%a:/$') or path == '/' then
      return path
   end
   return path:gsub('/+$', '')
end

local function getParentDirectory(path)
   path = normalizeDirectoryPath(path)
   if path == '/' or path:match('^%a:/$') then
      return nil
   end

   local parent = path:gsub('/+$', ''):match('^(.*)/[^/]+$')
   if not parent or parent == '' then
      return '/'
   end
   if parent:match('^%a:$') then
      return parent .. '/'
   end
   return parent
end

local function getPathName(path)
   return path:gsub('/+$', ''):match('([^/]+)$') or path
end

local function getDefaultPngDirectory()
   local baseDirectory
   local ok, realDirectory = pcall(g_resources.getRealDir, '/data/things/README.md')
   if ok and realDirectory and realDirectory ~= '' then
      baseDirectory = realDirectory
   else
      baseDirectory = g_platform.getCurrentDir()
   end
   baseDirectory = baseDirectory:gsub('\\', '/'):gsub('/+$', '')
   return normalizeDirectoryPath(baseDirectory .. '/data/things/pngs')
end

local function renderPngFilePicker()
   if not filePickerWindow then
      return
   end

   local previousSelection = filePickerSelection
   filePickerDirectory = normalizeDirectoryPath(filePickerDirectory)
   filePickerSelection = nil
   local list = filePickerWindow:recursiveGetChildById('filePickerEntries')
   list:destroyChildren()
   filePickerWindow:recursiveGetChildById('filePickerPathEdit'):setText(filePickerDirectory)
   filePickerWindow:recursiveGetChildById('filePickerSelectedLabel'):setText(tr('Choose a PNG file.'))
   filePickerWindow:recursiveGetChildById('filePickerUseButton'):setEnabled(false)

   local ok, entries = pcall(g_platform.listDirectoryEntries, filePickerDirectory)
   if not ok then
      entries = {}
   end

   local visibleEntries = {}
   for _, path in ipairs(entries or {}) do
      local isDirectory = path:ends('/')
      if isDirectory or path:lower():ends('.png') then
         table.insert(visibleEntries, { path = path, isDirectory = isDirectory })
      end
   end
   table.sort(visibleEntries, function(a, b)
      if a.isDirectory ~= b.isDirectory then
         return a.isDirectory
      end
      return a.path:lower() < b.path:lower()
   end)

   local filter = filePickerWindow:recursiveGetChildById('filePickerFilterEdit'):getText():trim():lower()
   local shown = 0
   for _, entry in ipairs(visibleEntries) do
      local name = getPathName(entry.path)
      if filter == '' or name:lower():find(filter, 1, true) then
         local row = g_ui.createWidget('SpriteEditorFileEntry', list)
         row:setText(entry.isDirectory and tr('[Folder] %s', name) or name)
         row.filePickerPath = entry.path
         row.filePickerIsDirectory = entry.isDirectory
         if not entry.isDirectory and entry.path == previousSelection then
            filePickerSelection = entry.path
         end
         row.onClick = function(widget)
            if widget.filePickerIsDirectory then
               filePickerSelection = nil
               filePickerWindow:recursiveGetChildById('filePickerUseButton'):setEnabled(false)
               filePickerWindow:recursiveGetChildById('filePickerSelectedLabel'):setText(
                  tr('Double-click to open %s', getPathName(widget.filePickerPath)))
            else
               filePickerSelection = widget.filePickerPath
               filePickerWindow:recursiveGetChildById('filePickerUseButton'):setEnabled(true)
               local label = filePickerWindow:recursiveGetChildById('filePickerSelectedLabel')
               label:setText(widget.filePickerPath)
               label:setTooltip(widget.filePickerPath)
            end
         end
         row.onDoubleClick = function(widget)
            if widget.filePickerIsDirectory then
               filePickerDirectory = widget.filePickerPath
               renderPngFilePicker()
            else
               filePickerSelection = widget.filePickerPath
               modules.game_sprite_editor.useSelectedPngFile()
            end
         end
         shown = shown + 1
      end
   end

   local parentButton = filePickerWindow:recursiveGetChildById('filePickerParentButton')
   parentButton:setEnabled(getParentDirectory(filePickerDirectory) ~= nil)
   filePickerWindow:recursiveGetChildById('filePickerCountLabel'):setText(
      tr('%d PNG files and folders', shown))
   if filePickerSelection then
      local label = filePickerWindow:recursiveGetChildById('filePickerSelectedLabel')
      label:setText(filePickerSelection)
      label:setTooltip(filePickerSelection)
      filePickerWindow:recursiveGetChildById('filePickerUseButton'):setEnabled(true)
   end
   if shown == 0 then
      filePickerWindow:recursiveGetChildById('filePickerSelectedLabel'):setText(
         tr('No PNG files or folders match this location and filter.'))
   end
end

local function destroyPngFilePicker()
   local picker = filePickerWindow
   filePickerWindow = nil
   filePickerSelection = nil
   filePickerTarget = nil

   if not picker then
      return
   end

   local ok, err = pcall(function()
      if not picker:isDestroyed() then
         picker:destroy()
      end
   end)
   if not ok then
      g_logger.error('[game_sprite_editor] Unable to close PNG file browser: ' .. tostring(err))
   end
end

function closePngFilePicker()
   destroyPngFilePicker()
end

function navigatePngFilePicker()
   if not filePickerWindow then
      return
   end
   filePickerDirectory = normalizeDirectoryPath(
      filePickerWindow:recursiveGetChildById('filePickerPathEdit'):getText())
   renderPngFilePicker()
end

function goToParentPngFilePicker()
   if not filePickerWindow then
      return
   end
   filePickerDirectory = getParentDirectory(filePickerDirectory)
   if filePickerDirectory then
      renderPngFilePicker()
   end
end

function filterPngFilePicker()
   renderPngFilePicker()
end

function useSelectedPngFile()
   if not filePickerWindow or not filePickerSelection then
      return
   end
   local path = filePickerSelection
   local target = filePickerTarget
   filePickerDirectory = getParentDirectory(path) or filePickerDirectory
   if target == 'create' then
      window:recursiveGetChildById('newAppearancePngPathEdit'):setText(path)
      setStatus(tr('PNG selected for the new appearance: %s', getPathName(path)))
   else
      preparedSpritePath = path
      setSpritePath(path)
      updateSpriteReplacementTarget()
      setStatus(tr('PNG selected: %s', getPathName(path)))
   end
   destroyPngFilePicker()
end

function openPngFilePicker(target)
   target = target or 'replace'
   if target ~= 'replace' and target ~= 'create' then
      return
   end
   if not window or not activeVersion or g_game.isOnline() or (target == 'replace' and not selectedSpriteId) then
      return
   end
   if not g_platform.isDesktop() then
      setStatus(tr('Browsing local files is available in desktop builds.'))
      return
   end
   if not g_platform.getCurrentDir or not g_platform.listDirectoryEntries then
      setStatus(tr('Restart the client to enable PNG file browsing.'))
      return
   end
   destroyPngFilePicker()
   filePickerTarget = target
   local pathEditId = target == 'create' and 'newAppearancePngPathEdit' or 'previewSpritePathEdit'
   local existingPath = window:recursiveGetChildById(pathEditId):getText():gsub('\\', '/')
   if existingPath ~= '' and existingPath:lower():ends('.png') then
      filePickerDirectory = getParentDirectory(existingPath) or g_platform.getCurrentDir()
      filePickerSelection = g_platform.fileExists(existingPath) and existingPath or nil
   elseif not filePickerDirectory then
      filePickerDirectory = getDefaultPngDirectory()
   end
   local opened, picker = pcall(g_ui.displayUI, 'sprite_editor_file_picker')
   if not opened or not picker then
      filePickerWindow = nil
      if not opened then
         g_logger.error('[game_sprite_editor] Unable to open PNG file browser: ' .. tostring(picker))
      end
      setStatus(tr('Could not open the PNG file browser. Check the client log.'))
      return
   end
   filePickerWindow = picker
   local initialized, err = pcall(function()
      filePickerWindow:recursiveGetChildById('filePickerGoButton').onClick = navigatePngFilePicker
      filePickerWindow:recursiveGetChildById('filePickerParentButton').onClick = goToParentPngFilePicker
      filePickerWindow:recursiveGetChildById('filePickerUseButton').onClick = useSelectedPngFile
      filePickerWindow:recursiveGetChildById('filePickerCancelButton').onClick = closePngFilePicker
      local pathEdit = filePickerWindow:recursiveGetChildById('filePickerPathEdit')
      pathEdit.onEnter = navigatePngFilePicker
      pathEdit.onTextChange = function()
         filePickerSelection = nil
         filePickerWindow:recursiveGetChildById('filePickerUseButton'):setEnabled(false)
      end
      local filterEdit = filePickerWindow:recursiveGetChildById('filePickerFilterEdit')
      filterEdit.onTextChange = filterPngFilePicker
      renderPngFilePicker()
      if filePickerSelection then
         filePickerWindow:recursiveGetChildById('filePickerSelectedLabel'):setText(filePickerSelection)
         filePickerWindow:recursiveGetChildById('filePickerSelectedLabel'):setTooltip(filePickerSelection)
         filePickerWindow:recursiveGetChildById('filePickerUseButton'):setEnabled(true)
      end
      filePickerWindow:raise()
      filePickerWindow:focus()
   end)
   if not initialized then
      g_logger.error('[game_sprite_editor] Unable to initialize PNG file browser: ' .. tostring(err))
      destroyPngFilePicker()
      setStatus(tr('Could not initialize the PNG file browser. Check the client log.'))
   end
end

local function updatePreviewTitle()
   if not window or not canvas or not selectedSpriteId then
      return
   end

   window:recursiveGetChildById('spriteInfoLabel'):setText(tr('Sprite ID %d | %d x %d | Zoom %dx',
      selectedSpriteId, canvas:getSpriteWidth(), canvas:getSpriteHeight(), canvas:getZoom()))
   local contextLabel = window:recursiveGetChildById('spriteContextLabel')
   contextLabel:setText(selectedSpriteContext or '')
   contextLabel:setVisible(selectedSpriteContext ~= nil and selectedSpriteContext ~= '')
end

local function setPreviewMessage(message)
   if not window then
      return
   end
   window:recursiveGetChildById('spriteInfoLabel'):setText(message)
   local contextLabel = window:recursiveGetChildById('spriteContextLabel')
   contextLabel:setText('')
   contextLabel:setVisible(false)
end

updateSpriteReplacementTarget = function()
   if not window then
      return
   end
   local hasTarget = selectedSpriteId ~= nil
   local canReplace = hasTarget and activeVersion ~= nil and not g_game.isOnline()
   local canEditAssets = activeVersion ~= nil and not g_game.isOnline()
   local showImport = currentPage == 'import'
   local showReplace = showImport and currentImportSection == 'replace'
   local showCreate = showImport and currentImportSection == 'create'
   if spritePickerSourceId ~= selectedSpriteId then
      spritePickerSourceId = selectedSpriteId
      selectedReplacementSpriteId = nil
   end
   local targetPanel = window:recursiveGetChildById('replaceFramePanel')
   targetPanel:setVisible(showReplace)
   window:recursiveGetChildById('newAppearancePanel'):setVisible(showCreate)
   window:recursiveGetChildById('replaceSourceModes'):setVisible(showReplace and hasTarget)
   window:recursiveGetChildById('selectedSpriteTargetLabel'):setText(
      hasTarget and tr('Current frame | Sprite %d', selectedSpriteId) or tr('Select a sprite frame to continue'))
   window:recursiveGetChildById('spriteIdReplacePanel'):setVisible(showReplace and hasTarget and currentReplaceMode == 'sprite')
   window:recursiveGetChildById('pngReplacePanel'):setVisible(showReplace and hasTarget and currentReplaceMode == 'png')
   window:recursiveGetChildById('editCurrentSpritePanel'):setVisible(showReplace and (hasTarget or pendingSpriteEdit ~= nil))
   window:recursiveGetChildById('spriteIdModeButton'):setOn(currentReplaceMode == 'sprite')
   window:recursiveGetChildById('pngModeButton'):setOn(currentReplaceMode == 'png')
   window:recursiveGetChildById('spriteSearchEdit'):setEnabled(canReplace)
   window:recursiveGetChildById('newAppearanceSourceModes'):setVisible(showCreate)
   window:recursiveGetChildById('newAppearanceSpriteModeButton'):setOn(currentNewAppearanceSourceMode == 'sprite')
   window:recursiveGetChildById('newAppearancePngModeButton'):setOn(currentNewAppearanceSourceMode == 'png')
   window:recursiveGetChildById('newAppearanceSpritePanel'):setVisible(
      showCreate and currentNewAppearanceSourceMode == 'sprite')
   window:recursiveGetChildById('newAppearancePngPanel'):setVisible(
      showCreate and currentNewAppearanceSourceMode == 'png')
   window:recursiveGetChildById('newAppearanceSpriteSearchEdit'):setEnabled(canEditAssets)
   window:recursiveGetChildById('newAppearanceCategory'):setEnabled(canEditAssets)
   local pngPathEdit = window:recursiveGetChildById('previewSpritePathEdit')
   pngPathEdit:setEnabled(canReplace)
   window:recursiveGetChildById('browsePngButton'):setEnabled(canReplace and g_platform.isDesktop())
   window:recursiveGetChildById('importPngReplaceButton'):setEnabled(canReplace and pngPathEdit:getText() ~= '')
   local newAppearancePngPathEdit = window:recursiveGetChildById('newAppearancePngPathEdit')
   newAppearancePngPathEdit:setEnabled(canEditAssets)
   window:recursiveGetChildById('browseNewAppearancePngButton'):setEnabled(canEditAssets and g_platform.isDesktop())
   window:recursiveGetChildById('createAppearanceButton'):setEnabled(canEditAssets and (
      (currentNewAppearanceSourceMode == 'sprite' and selectedCreateSpriteId ~= nil) or
      (currentNewAppearanceSourceMode == 'png' and newAppearancePngPathEdit:getText() ~= '')))
   window:recursiveGetChildById('newAppearanceSourceHintLabel'):setText(
      currentNewAppearanceSourceMode == 'sprite' and tr('Choose the category above, then create the appearance.') or
      tr('The PNG will be added as a new sprite ID when you create the appearance.'))
   window:recursiveGetChildById('spriteEditHelpLabel'):setText(pendingSpriteEdit and
      tr('Temporary PNG: %s', pendingSpriteEdit.path) or
      tr('Edit the current sprite in an external app, then apply it to the work copy.'))
   window:recursiveGetChildById('editAppearanceSpriteButton'):setEnabled(canReplace)
   local applyButton = window:recursiveGetChildById('applyEditedSpriteButton')
   applyButton:setVisible(pendingSpriteEdit ~= nil)
   applyButton:setEnabled(pendingSpriteEdit ~= nil and not g_game.isOnline())
   applyButton:setText(tr('Apply edit'))
   applyButton:setTooltip(pendingSpriteEdit and tr('Apply the edited PNG to sprite %d in the work copy.', pendingSpriteEdit.spriteId) or '')
   window:recursiveGetChildById('configureSpriteEditorButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('newAppearanceSpriteModeButton'):setEnabled(canEditAssets)
   window:recursiveGetChildById('newAppearancePngModeButton'):setEnabled(canEditAssets)
   window:recursiveGetChildById('duplicateAppearanceButton'):setEnabled(
      selectedAppearanceId ~= nil and activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('createAppearanceShortcutButton'):setEnabled(
      activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('previewHintLabel'):setText(
      showReplace and currentReplaceMode == 'sprite' and
         tr('Drop a sprite here to replace this frame | Wheel over preview: zoom | Middle-drag: pan') or
         tr('Wheel over preview: zoom | Middle-drag: pan | Checkerboard: transparency'))
   if hasTarget then updatePreviewTitle() end
   if renderSpritePickerRows then
      local pickerList = getSpritePickerWidget('list')
      renderSpritePickerRows(pickerList and pickerList:getVirtualOffset().y or 0)
   end
end

local function setPreviewControlsVisible(visible, panelHeight)
   local controls = window:recursiveGetChildById('previewControls')
   controls:setVisible(visible)
   controls:setHeight(visible and panelHeight or 0)
   canvas:setMarginBottom(visible and panelHeight + PREVIEW_CONTROLS_BOTTOM_MARGIN or PREVIEW_CANVAS_BOTTOM_MARGIN)
   window:recursiveGetChildById('previewHintLabel'):setMarginBottom(
      visible and panelHeight + PREVIEW_CONTROLS_BOTTOM_MARGIN or PREVIEW_HINT_BOTTOM_MARGIN)
end

local function updatePreviewTimelineLayout(phaseCount, hasFrameControls, hasAnimation)
   local showFrameButtons = hasFrameControls and phaseCount <= MAX_PREVIEW_TIMELINE_FRAMES
   local showNumericFrameSelector = hasFrameControls and phaseCount > MAX_PREVIEW_TIMELINE_FRAMES
   local showAnimationFrameRow = showNumericFrameSelector or hasAnimation
   local timelinePanel = window:recursiveGetChildById('previewTimelinePanel')
   local timelineLabel = window:recursiveGetChildById('previewTimelineLabel')
   local timeline = window:recursiveGetChildById('previewTimeline')
   local timelineScroll = window:recursiveGetChildById('previewTimelineScroll')
   local phaseActions = window:recursiveGetChildById('previewPhaseActions')
   local frameRow = window:recursiveGetChildById('previewAnimationFrameRow')
   local frameSelectionGroup = window:recursiveGetChildById('previewFrameSelectionGroup')
   local durationGroup = window:recursiveGetChildById('previewDurationGroup')

   timelinePanel:setVisible(hasFrameControls)
   local panelHeight = showAnimationFrameRow and PREVIEW_TIMELINE_HEIGHT or PREVIEW_TIMELINE_ONLY_HEIGHT
   timelinePanel:setHeight(panelHeight)
   timelineLabel:setVisible(hasFrameControls)
   timeline:setVisible(showFrameButtons)
   timelineScroll:setVisible(showFrameButtons and phaseCount * 30 > timeline:getWidth())
   phaseActions:setVisible(hasFrameControls)
   frameRow:setVisible(showAnimationFrameRow)
   frameRow:setMarginBottom(showFrameButtons and showAnimationFrameRow and 11 or 0)
   frameSelectionGroup:setVisible(showNumericFrameSelector)
   durationGroup:setVisible(hasAnimation)
   durationGroup:setMarginLeft(showNumericFrameSelector and
      PREVIEW_FRAME_SELECTION_WIDTH + PREVIEW_DURATION_GROUP_GAP or 0)
   return showFrameButtons, showNumericFrameSelector, panelHeight
end

local function setPropertiesTab(tab)
   if not window then
      return
   end
   local flagsAvailable = appearanceOriginal ~= nil and next(appearanceOriginal.bools or {}) ~= nil
   local valuesAvailable = appearanceOriginal ~= nil and next(appearanceOriginal.values or {}) ~= nil
   window:recursiveGetChildById('flagsTabButton'):setVisible(flagsAvailable)
   window:recursiveGetChildById('valuesTabButton'):setVisible(valuesAvailable)
   local tabBar = window:recursiveGetChildById('propertiesTabBar')
   local hasTabs = flagsAvailable or valuesAvailable
   tabBar:setVisible(hasTabs)
   tabBar:setHeight(hasTabs and 24 or 0)
   window:recursiveGetChildById('noPropertyOptionsLabel'):setVisible(
      appearanceOriginal ~= nil and not flagsAvailable and not valuesAvailable)
   window:recursiveGetChildById('noPropertyOptionsLabel'):setText(
      tr('No additional editable properties for this appearance.'))

   if tab == 'values' and valuesAvailable then
      currentPropertiesTab = 'values'
   elseif tab == 'flags' and flagsAvailable then
      currentPropertiesTab = 'flags'
   elseif flagsAvailable then
      currentPropertiesTab = 'flags'
   elseif valuesAvailable then
      currentPropertiesTab = 'values'
   else
      currentPropertiesTab = 'flags'
   end
   local flagsVisible = currentPropertiesTab == 'flags'
   local valuesVisible = currentPropertiesTab == 'values'
   window:recursiveGetChildById('appearanceFlagsList'):setVisible(flagsVisible and flagsAvailable)
   window:recursiveGetChildById('appearanceFlagsScroll'):setVisible(flagsVisible and flagsAvailable)
   window:recursiveGetChildById('appearanceValuesList'):setVisible(valuesVisible and valuesAvailable)
   window:recursiveGetChildById('appearanceValuesScroll'):setVisible(valuesVisible and valuesAvailable)
   window:recursiveGetChildById('flagsTabButton'):setOn(flagsVisible)
   window:recursiveGetChildById('valuesTabButton'):setOn(valuesVisible)
end

local function buildEquipmentSlotEditor(valuesList, data)
   local slot = data.values['clothes.slot'] or 0
   local row = g_ui.createWidget('AppearanceValueSelectRow', valuesList)
   row:setWidth(285)
   row:recursiveGetChildById('propertyLabel'):setText(tr('Equipment slot'))
   local comboBox = row:recursiveGetChildById('propertySelection')
   for _, option in ipairs(EQUIPMENT_SLOT_OPTIONS) do
      comboBox:addOption(tr(option.label), option.data)
   end
   comboBox:setCurrentOptionByData(slot, true)
   comboBox.onOptionChange = function(_, _, value)
      if buildingAppearanceProperties then
         return
      end
      if value == slot then
         appearanceChanges.values['clothes.slot'] = nil
      else
         appearanceChanges.values['clothes.slot'] = value
      end
      updateAppearanceSaveButton()
   end
end

local function buildAppearanceProperties(data)
   local flagsList = window:recursiveGetChildById('appearanceFlagsList')
   local valuesList = window:recursiveGetChildById('appearanceValuesList')
   flagsList:destroyChildren()
   valuesList:destroyChildren()
   appearanceValueWidgets = {}
   appearanceStringWidgets = {}
   clearAppearanceChanges()
   appearanceOriginal = data
   data.values = data.values or {}
   if selectedAppearanceCategory == 0 then
      data.values['clothes.slot'] = data.values['clothes.slot'] or 0
   end
   buildingAppearanceProperties = true

   local nameEdit = window:recursiveGetChildById('appearanceName')
   local descriptionEdit = window:recursiveGetChildById('appearanceDescription')
   nameEdit:setEnabled(true)
   descriptionEdit:setEnabled(true)
   nameEdit:setText(data.name or '')
   descriptionEdit:setText(data.description or '')
   appearanceStringWidgets.name = nameEdit
   appearanceStringWidgets.description = descriptionEdit
   for _, key in ipairs({ 'name', 'description' }) do
      appearanceStringWidgets[key].onTextChange = function(widget)
         if buildingAppearanceProperties then
            return
         end
         local value = widget:getText()
         if value == (appearanceOriginal[key] or '') then
            appearanceChanges.strings[key] = nil
         else
            appearanceChanges.strings[key] = value
         end
         updateAppearanceSaveButton()
      end
   end

   for _, key in ipairs(sortedKeys(data.bools)) do
      local checkbox = g_ui.createWidget('AppearanceFlagCheckBox', flagsList)
      checkbox:setWidth(285)
      checkbox:setText(propertyLabel(key))
      checkbox:setChecked(data.bools[key])
      checkbox.onCheckChange = function(widget)
         if buildingAppearanceProperties then
            return
         end
         local checked = widget:isChecked()
         if checked == data.bools[key] then
            appearanceChanges.bools[key] = nil
         else
            appearanceChanges.bools[key] = checked
         end
         updateAppearanceSaveButton()
      end
   end

   if selectedAppearanceCategory == 0 then
      buildEquipmentSlotEditor(valuesList, data)
   end

   for _, key in ipairs(sortedKeys(data.values)) do
      if key ~= 'clothes.slot' or selectedAppearanceCategory ~= 0 then
         local row = g_ui.createWidget('AppearanceValueRow', valuesList)
         row:setWidth(285)
         row:recursiveGetChildById('propertyLabel'):setText(propertyLabel(key))
         local edit = row:recursiveGetChildById('propertyValue')
         edit:setText(tostring(data.values[key]))
         appearanceValueWidgets[key] = edit
         edit.onTextChange = function(widget)
            if buildingAppearanceProperties then
               return
            end
            local value = tonumber(widget:getText())
            if value and value >= 0 and value % 1 == 0 and value ~= data.values[key] then
               appearanceChanges.values[key] = value
            else
               appearanceChanges.values[key] = nil
            end
            updateAppearanceSaveButton()
         end
      end
   end

   configurePreviewControls(data.frameGroups or {})
   updateAnimationEditor()
   buildingAppearanceProperties = false
   updateAppearanceSaveButton()
   setPropertiesTab(currentPropertiesTab)
end

local function clearAppearanceProperties()
   buildingAppearanceProperties = true
   window:recursiveGetChildById('appearanceInfoLabel'):setText(tr('Select an appearance from the list.'))
   setAppearanceStatus(tr('Open a work copy and select an appearance to edit.'))
   selectedAppearanceId = nil
   appearanceOriginal = nil
   window:recursiveGetChildById('appearanceName'):setText('')
   window:recursiveGetChildById('appearanceDescription'):setText('')
   window:recursiveGetChildById('appearanceFlagsList'):destroyChildren()
   window:recursiveGetChildById('appearanceValuesList'):destroyChildren()
   window:recursiveGetChildById('previewTimelineFrames'):destroyChildren()
   setPreviewMessage(tr('Select an appearance to see its sprite.'))
   window:recursiveGetChildById('appearanceName'):setEnabled(false)
   window:recursiveGetChildById('appearanceDescription'):setEnabled(false)
   selectedSpriteId = nil
   selectedSpriteContext = nil
   canvas:setVisible(false)
   setSpritePath(preparedSpritePath)
   updateSpriteReplacementTarget()
   appearanceValueWidgets = {}
   appearanceStringWidgets = {}
   animationWidgets = {}
   configurePreviewControls({})
   updateAnimationEditor()
   clearAppearanceChanges()
   buildingAppearanceProperties = false
   setPropertiesTab(currentPropertiesTab)
   updateAppearanceSaveButton()
end

local function resetAppearanceDraft()
   if appearanceOriginal then
      buildAppearanceProperties(appearanceOriginal)
   else
      clearAppearanceChanges()
   end
end

local function confirmUnsavedChanges(message, continueAction)
   local messageBox
   local function saveAndContinue()
      messageBox:ok()
      saveAppearanceProperties()
      if not hasAppearanceChanges() then
         continueAction()
      end
   end
   local function cancelMessageBox()
      messageBox:cancel()
   end
   messageBox = displayGeneralBox(tr('Unsaved changes'), message, {
      { text = tr('Save and continue'), callback = saveAndContinue },
      { text = tr('Discard edits'), callback = function()
         messageBox:ok()
         resetAppearanceDraft()
         continueAction()
      end },
      { text = tr('Cancel'), callback = cancelMessageBox },
   }, saveAndContinue, cancelMessageBox)
end

selectSprite = function(id)
   if not canvas or not activeVersion then
      return false
   end
   if not canvas:setSpriteId(id) then
      canvas:setVisible(false)
      selectedSpriteId = nil
      selectedSpriteContext = nil
      updateDirectionPadLayout()
      updateSpriteReplacementTarget()
      setStatus(tr('Sprite %d is not available in this 15.x work copy.', id))
      return false
   end

   canvas:setVisible(true)
   selectedSpriteId = id
   updatePreviewTitle()
   updateDirectionPadLayout()
   updateSpriteReplacementTarget()
   return true
end

local function frameGroupName(group, index)
   local names = {
      [0] = tr('Idle'),
      [1] = tr('Moving'),
      [2] = tr('Initial'),
   }
   return names[group.type] or tr('Group %d', index)
end

local function currentPreviewGroup()
   return previewFrameGroups[previewFrameGroupIndex]
end

local function setAnimationChange(groupIndex, field, value, phaseIndex)
   local group = previewFrameGroups[groupIndex + 1]
   if not group or not group.animation.enabled then
      return
   end

   local groupKey = tostring(groupIndex)
   local groupChanges = appearanceChanges.animation.groups[groupKey]
   if not groupChanges then
      groupChanges = { phases = {} }
      appearanceChanges.animation.groups[groupKey] = groupChanges
   end

   local original
   local changeContainer = groupChanges
   if phaseIndex ~= nil then
      local originalPhase = group.animation.phases[phaseIndex + 1]
      if not originalPhase then
         return
      end
      local phaseKey = tostring(phaseIndex)
      groupChanges.phases = groupChanges.phases or {}
      changeContainer = groupChanges.phases[phaseKey]
      if not changeContainer then
         changeContainer = {}
         groupChanges.phases[phaseKey] = changeContainer
      end
      original = originalPhase[field]
   else
      original = group.animation[field]
   end

   if value == original then
      changeContainer[field] = nil
   else
      changeContainer[field] = value
   end

   if next(changeContainer) == nil and phaseIndex ~= nil then
      groupChanges.phases[tostring(phaseIndex)] = nil
   end
   if groupChanges.phases and next(groupChanges.phases) == nil then
      groupChanges.phases = nil
   end
   if next(groupChanges) == nil then
      appearanceChanges.animation.groups[groupKey] = nil
   end
   updateAppearanceSaveButton()
end

local function updatePreviewAnimationPhaseCount(groupIndex, phaseCount)
   local group = previewFrameGroups[groupIndex + 1]
   local originalGroup = appearanceOriginal and appearanceOriginal.frameGroups[groupIndex + 1]
   if not group or not originalGroup or phaseCount < 1 then
      return false
   end

   local spritesPerPhase = math.max(1, originalGroup.layers or 1) *
      math.max(1, originalGroup.patternWidth or 1) *
      math.max(1, originalGroup.patternHeight or 1) *
      math.max(1, originalGroup.patternDepth or 1)
   local originalPhaseCount = math.max(1, originalGroup.phaseCount or 1)
   local maximumPhaseCount = math.floor(2147483647 / spritesPerPhase)
   if phaseCount > maximumPhaseCount then
      setAppearanceStatus(tr('This frame group cannot contain more animation frames.'))
      return false
   end

   local groupKey = tostring(groupIndex)
   local groupChanges = appearanceChanges.animation.groups[groupKey]
   if not groupChanges then
      groupChanges = { phases = {} }
      appearanceChanges.animation.groups[groupKey] = groupChanges
   end
   local function getAnimationValue(field, fallback)
      if groupChanges[field] ~= nil then
         return groupChanges[field]
      end
      return fallback
   end

   local sprites = {}
   local originalSprites = originalGroup.sprites or {}
   local copiedPhaseCount = math.min(phaseCount, originalPhaseCount)
   for index = 1, math.min(#originalSprites, copiedPhaseCount * spritesPerPhase) do
      sprites[index] = originalSprites[index]
   end
   for phaseIndex = originalPhaseCount, phaseCount - 1 do
      for spriteOffset = 1, spritesPerPhase do
         local spriteIndex = phaseIndex * spritesPerPhase + spriteOffset
         local previousSpriteIndex = (phaseIndex - 1) * spritesPerPhase + spriteOffset
         sprites[spriteIndex] = sprites[previousSpriteIndex] or 0
      end
   end

   local originalAnimation = originalGroup.animation or {}
   local animation = {
      enabled = phaseCount > 1,
      defaultStartPhase = getAnimationValue('defaultStartPhase', originalAnimation.defaultStartPhase or 0),
      randomStartPhase = getAnimationValue('randomStartPhase', originalAnimation.randomStartPhase or false),
      synchronized = getAnimationValue('synchronized', originalAnimation.synchronized or false),
      loopType = getAnimationValue('loopType', originalAnimation.enabled and originalAnimation.loopType or 0),
      loopCount = getAnimationValue('loopCount', originalAnimation.loopCount or 0),
      phases = {},
   }
   if phaseCount > 1 then
      for phaseIndex = 1, phaseCount do
         local originalPhase = originalAnimation.phases and originalAnimation.phases[phaseIndex]
         local phaseChanges = groupChanges.phases and groupChanges.phases[tostring(phaseIndex - 1)] or {}
         animation.phases[phaseIndex] = {
            durationMin = phaseChanges.durationMin ~= nil and phaseChanges.durationMin or
               originalPhase and originalPhase.durationMin or 100,
            durationMax = phaseChanges.durationMax ~= nil and phaseChanges.durationMax or
               originalPhase and originalPhase.durationMax or 100,
         }
      end
      animation.defaultStartPhase = math.min(animation.defaultStartPhase, phaseCount - 1)
   else
      animation.defaultStartPhase = 0
      animation.randomStartPhase = false
      animation.synchronized = false
      animation.loopType = 0
      animation.loopCount = 0
   end

   group.phaseCount = phaseCount
   group.sprites = sprites
   group.animation = animation

   groupChanges.phaseCount = phaseCount ~= originalPhaseCount and phaseCount or nil
   if phaseCount == 1 then
      groupChanges.defaultStartPhase = nil
      groupChanges.randomStartPhase = nil
      groupChanges.synchronized = nil
      groupChanges.loopType = nil
      groupChanges.loopCount = nil
   end
   if phaseCount == 1 then
      groupChanges.phases = nil
   else
      groupChanges.phases = groupChanges.phases or {}
      for phaseKey in pairs(groupChanges.phases) do
         if tonumber(phaseKey) >= phaseCount then
            groupChanges.phases[phaseKey] = nil
         end
      end
      if next(groupChanges.phases) == nil then
         groupChanges.phases = nil
      end
   end
   if next(groupChanges) == nil then
      appearanceChanges.animation.groups[groupKey] = nil
   end

   previewPhase = math.min(previewPhase, phaseCount - 1)
   updateAppearanceSaveButton()
   return true
end

local function changeAnimationPhaseCount(delta)
   local group = currentPreviewGroup()
   if not group or not collectAnimationWidgetChanges() then
      return false
   end
   local phaseCount = math.max(1, group.phaseCount or 1)
   local newPhaseCount = phaseCount + delta
   if newPhaseCount < 1 then
      return false
   end
   if not updatePreviewAnimationPhaseCount(group.index, newPhaseCount) then
      return false
   end
   updatePreviewPatternControls()
   updateAnimationEditor()
   refreshAppearancePreview()
   setAppearanceStatus(delta > 0 and tr('Frame added. Replace its sprite if needed, then save the appearance.') or
      tr('Last frame removed. Save the appearance to apply the change.'))
   return true
end

local function setComboOptions(comboBox, options, selectedData)
   local onOptionChange = comboBox.onOptionChange
   comboBox.onOptionChange = nil
   comboBox:clearOptions()
   for _, option in ipairs(options) do
      comboBox:addOption(option.label, option.data)
   end
   if options[1] then
      comboBox:setCurrentOptionByData(selectedData or options[1].data, true)
   end
   comboBox.onOptionChange = onOptionChange
end

local function buildPatternOptions(comboBox, label, count, selectedIndex)
   local options = {}
   for index = 0, count - 1 do
      table.insert(options, { label = string.format('%s %d', label, index + 1), data = index })
   end
   setComboOptions(comboBox, options, math.min(selectedIndex or 0, count - 1))
   comboBox:setVisible(count > 1)
end

local function setCheckBoxState(checkBox, checked)
   local onCheckChange = checkBox.onCheckChange
   checkBox.onCheckChange = nil
   checkBox:setChecked(checked)
   checkBox.onCheckChange = onCheckChange
end

local function directionName(index, width)
   if (width == 4 or width == 8) and PREVIEW_DIRECTIONS[index + 1] then
      return tr(PREVIEW_DIRECTIONS[index + 1].name)
   end
   return tr('Pattern X %d', index + 1)
end

updateDirectionPadLayout = function()
   if not window or not canvas then
      return
   end

   local directionPad = window:recursiveGetChildById('previewDirectionPad')
   local group = currentPreviewGroup()
   local visible = selectedSpriteId ~= nil and selectedAppearanceCategory == 1 and group and
      group.patternWidth >= 4 or false
   directionPad:setVisible(visible)
   if not visible then
      return
   end

   local spriteWidth = canvas:getSpriteWidth()
   local spriteHeight = canvas:getSpriteHeight()
   if spriteWidth > 0 and spriteHeight > 0 then
      local zoom = canvas:getZoom()
      local padWidth = spriteWidth * zoom + 2 * (PREVIEW_DIRECTION_BUTTON_WIDTH + PREVIEW_DIRECTION_PAD_GAP)
      local padHeight = spriteHeight * zoom + 2 * (PREVIEW_DIRECTION_BUTTON_HEIGHT + PREVIEW_DIRECTION_PAD_GAP)
      local maxWidth = math.max(PREVIEW_DIRECTION_BUTTON_WIDTH, canvas:getWidth() - 16)
      local maxHeight = math.max(PREVIEW_DIRECTION_BUTTON_HEIGHT, canvas:getHeight() - 16)
      local width = math.min(padWidth, maxWidth)
      local height = math.min(padHeight, maxHeight)
      directionPad:setWidth(width)
      directionPad:setHeight(height)

      local canvasRect = canvas:getPaddingRect()
      local spriteCenter = canvas:getSpriteRenderCenter()
      local maxOffsetX = math.max(0, (canvasRect.width - width) / 2)
      local maxOffsetY = math.max(0, (canvasRect.height - height) / 2)
      local offsetX = math.max(-maxOffsetX, math.min(maxOffsetX, spriteCenter.x - canvasRect.width / 2))
      local offsetY = math.max(-maxOffsetY, math.min(maxOffsetY, spriteCenter.y - canvasRect.height / 2))
      directionPad:setMarginLeft(offsetX)
      directionPad:setMarginTop(offsetY)
   end
end

updatePreviewPatternControls = function()
   if not window then
      return
   end
   local group = currentPreviewGroup()
   if not group then
      setPreviewControlsVisible(false)
      updateDirectionPadLayout()
      return
   end

   local isOutfit = selectedAppearanceCategory == 1
   local useDirectionPad = isOutfit and group.patternWidth >= 4
   local groupBox = window:recursiveGetChildById('previewFrameGroup')
   local movingCheck = window:recursiveGetChildById('previewMoving')
   local mountedCheck = window:recursiveGetChildById('previewMounted')
   local directionBox = window:recursiveGetChildById('previewPatternX')
   local addonBox = window:recursiveGetChildById('previewPatternY')
   local layerBox = window:recursiveGetChildById('previewLayer')
   local patternZBox = window:recursiveGetChildById('previewPatternZ')
   local settings = window:recursiveGetChildById('previewTopControls')
   local phaseLabel = window:recursiveGetChildById('previewPhaseLabel')

   settings:setMarginLeft(8)
   local hasAnimation = group.animation and group.animation.enabled and group.animation.phases and
      #group.animation.phases > 0 or false
   local phaseCount = math.max(1, group.phaseCount or 1)
   local hasFrameControls = group ~= nil
   local _, showNumericFrameSelector, framePanelHeight =
      updatePreviewTimelineLayout(phaseCount, hasFrameControls, hasAnimation)

   groupBox:setVisible(#previewFrameGroups > 1 and not previewHasMovementToggle)
   movingCheck:setVisible(previewHasMovementToggle)
   setCheckBoxState(movingCheck, previewMoving)
   mountedCheck:setVisible(isOutfit and group.patternDepth > 1)
   setCheckBoxState(mountedCheck, previewMounted)
   local animationSettingsRow = window:recursiveGetChildById('previewAnimationSettingsRow')
   animationSettingsRow:setVisible(hasAnimation)

   if useDirectionPad then
      directionBox:setVisible(false)
      for _, direction in ipairs(PREVIEW_DIRECTIONS) do
         local button = window:recursiveGetChildById(direction.id)
         local visible = direction.index < group.patternWidth
         button:setVisible(visible)
         if visible then
            local selected = direction.index == previewPatternX
            button:setChecked(selected)
            button:setColor(selected and '#d9c7ff' or '#dfdfdf')
         end
      end
   else
      buildPatternOptions(directionBox, isOutfit and tr('Direction') or tr('Pattern X'), group.patternWidth, previewPatternX)
   end

   buildPatternOptions(addonBox, isOutfit and tr('Addon') or tr('Pattern Y'), group.patternHeight, previewPatternY)
   buildPatternOptions(layerBox, tr('Layer'), group.layers, previewLayer)
   if isOutfit then
      patternZBox:setVisible(false)
   else
      buildPatternOptions(patternZBox, tr('Pattern Z'), group.patternDepth, previewPatternZ)
   end

   local metaRow = window:recursiveGetChildById('previewMetaRow')
   local patternRow = window:recursiveGetChildById('previewPatternRow')
   local hasMetaControls = (#previewFrameGroups > 1 and not previewHasMovementToggle) or
      previewHasMovementToggle or (isOutfit and group.patternDepth > 1)
   local hasPatternControls = (not useDirectionPad and group.patternWidth > 1) or group.patternHeight > 1 or
      group.layers > 1 or (not isOutfit and group.patternDepth > 1)
   local hasTopSettings = hasMetaControls or hasPatternControls or hasAnimation
   metaRow:setVisible(hasMetaControls)
   patternRow:setVisible(hasPatternControls)
   local settingsRowCount = (hasMetaControls and 1 or 0) + (hasPatternControls and 1 or 0) +
      (hasAnimation and 1 or 0)
   local settingsHeight = settingsRowCount > 0 and
      (hasMetaControls and 22 or 0) + (hasPatternControls and 22 or 0) + (hasAnimation and 28 or 0) +
      (settingsRowCount - 1) * 4 or 1
   settings:setHeight(settingsHeight)

   local groupOptions = {}
   for index, frameGroup in ipairs(previewFrameGroups) do
      table.insert(groupOptions, { label = frameGroupName(frameGroup, index), data = index })
   end
   setComboOptions(groupBox, groupOptions, previewFrameGroupIndex)

   phaseLabel:setVisible(showNumericFrameSelector)
   previewPhase = math.min(previewPhase, phaseCount - 1)
   local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
   phaseStepper:setVisible(showNumericFrameSelector)
   local onValueChange = phaseStepper.onValueChange
   phaseStepper.onValueChange = nil
   phaseStepper:setMinimum(1)
   phaseStepper:setMaximum(phaseCount)
   phaseStepper:setStep(1)
   phaseStepper:setMouseScroll(true)
   phaseStepper:setValue(previewPhase + 1, true)
   phaseStepper.onValueChange = onValueChange
   local phaseCountLabel = window:recursiveGetChildById('previewPhaseCount')
   phaseCountLabel:setVisible(showNumericFrameSelector)
   phaseCountLabel:setText(tr('of %d', phaseCount))
   local panelHeight = 8 + settingsHeight + (hasFrameControls and 6 or 0) + framePanelHeight + 8
   setPreviewControlsVisible(hasTopSettings or hasFrameControls, panelHeight)
   updateDirectionPadLayout()
   updateSpriteReplacementTarget()
end

refreshAppearancePreview = function()
   local group = currentPreviewGroup()
   if not group then
      return false
   end

   local directionBox = window:recursiveGetChildById('previewPatternX')
   local addonBox = window:recursiveGetChildById('previewPatternY')
   local layerBox = window:recursiveGetChildById('previewLayer')
   local patternZBox = window:recursiveGetChildById('previewPatternZ')
   local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
   local useDirectionPad = selectedAppearanceCategory == 1 and group.patternWidth >= 4
   if not useDirectionPad then
      previewPatternX = selectedOption(directionBox) or 0
   end
   previewPatternY = selectedOption(addonBox) or 0
   previewLayer = selectedOption(layerBox) or 0
   previewPhase = (phaseStepper:getValue() or 1) - 1
   if selectedAppearanceCategory == 1 and group.patternDepth > 1 then
      previewMounted = window:recursiveGetChildById('previewMounted'):isChecked()
      previewPatternZ = previewMounted and group.patternDepth - 1 or 0
   else
      previewPatternZ = selectedOption(patternZBox) or 0
   end

   local spriteIndex = (((previewPhase * group.patternDepth + previewPatternZ) * group.patternHeight +
      previewPatternY) * group.patternWidth + previewPatternX) * group.layers + previewLayer + 1
   local spriteId = group.sprites[spriteIndex]
   if spriteId and spriteId > 0 then
      local selected = selectSprite(spriteId)
      if selected then
         local details = { frameGroupName(group, previewFrameGroupIndex) }
         if selectedAppearanceCategory == 1 and group.patternDepth > 1 then
            table.insert(details, previewMounted and tr('Mounted') or tr('Unmounted'))
         end
         if selectedAppearanceCategory == 1 then
            if useDirectionPad or group.patternWidth > 1 then
               table.insert(details, directionName(previewPatternX, group.patternWidth))
            end
         elseif group.patternWidth > 1 then
            table.insert(details, tr('Pattern X %d', previewPatternX + 1))
         end
         if group.patternHeight > 1 then
            table.insert(details, tr('%s %d', selectedAppearanceCategory == 1 and tr('Addon') or tr('Pattern Y'), previewPatternY + 1))
         end
         if group.layers > 1 then
            table.insert(details, tr('Layer %d', previewLayer + 1))
         end
         table.insert(details, tr('Frame %d/%d', previewPhase + 1, math.max(1, group.phaseCount or 1)))
         selectedSpriteContext = table.concat(details, ' | ')
         updateSpriteReplacementTarget()
      end
      return selected
   end

   selectedSpriteId = nil
   selectedSpriteContext = nil
   canvas:setVisible(false)
   updateDirectionPadLayout()
   setPreviewMessage(tr('No sprite is linked to this frame selection.'))
   updateSpriteReplacementTarget()
   setStatus(tr('No sprite is linked to this frame selection.'))
   return false
end

local function capturePreviewSelection()
   local group = currentPreviewGroup()
   if not group then
      return nil
   end
   return {
      groupType = group.type,
      groupId = group.id,
      groupIndex = previewFrameGroupIndex,
      patternX = previewPatternX,
      patternY = previewPatternY,
      patternZ = previewPatternZ,
      layer = previewLayer,
      phase = previewPhase,
      mounted = previewMounted,
   }
end

local function restorePreviewSelection(selection)
   if not selection then
      return
   end

   local matchingIndex
   for index, group in ipairs(previewFrameGroups) do
      if group.type == selection.groupType and group.id == selection.groupId then
         matchingIndex = index
         break
      end
   end
   previewFrameGroupIndex = matchingIndex or math.min(selection.groupIndex, #previewFrameGroups)
   local group = currentPreviewGroup()
   if not group then
      return
   end

   previewMoving = previewHasMovementToggle and group.type == 1
   previewPatternX = math.min(selection.patternX, math.max(0, group.patternWidth - 1))
   previewPatternY = math.min(selection.patternY, math.max(0, group.patternHeight - 1))
   previewPatternZ = math.min(selection.patternZ, math.max(0, group.patternDepth - 1))
   previewLayer = math.min(selection.layer, math.max(0, group.layers - 1))
   previewPhase = math.min(selection.phase, math.max(0, (group.phaseCount or 1) - 1))
   previewMounted = selectedAppearanceCategory == 1 and group.patternDepth > 1 and selection.mounted

   updatePreviewPatternControls()
   updateAnimationEditor()
   refreshAppearancePreview()
end

configurePreviewControls = function(frameGroups)
   previewFrameGroups = frameGroups or {}
   previewFrameGroupIndex = math.min(math.max(1, previewFrameGroupIndex), math.max(1, #previewFrameGroups))
   previewIdleGroupIndex = nil
   previewMovingGroupIndex = nil
   for index, group in ipairs(previewFrameGroups) do
      if group.type == 0 and not previewIdleGroupIndex then
         previewIdleGroupIndex = index
      elseif group.type == 1 and not previewMovingGroupIndex then
         previewMovingGroupIndex = index
      end
   end
   previewHasMovementToggle = selectedAppearanceCategory == 1 and #previewFrameGroups == 2 and
      previewIdleGroupIndex ~= nil and previewMovingGroupIndex ~= nil
   previewMoving = false
   if previewHasMovementToggle then
      previewFrameGroupIndex = previewIdleGroupIndex
   end
   previewPatternX = 0
   previewPatternY = 0
   previewPatternZ = 0
   previewLayer = 0
   previewPhase = 0
   previewMounted = false
   previewMoving = false
   if not window then
      return
   end

   setPreviewControlsVisible(false)
   if #previewFrameGroups == 0 then
      return
   end

   local frameGroupBox = window:recursiveGetChildById('previewFrameGroup')
   frameGroupBox.onOptionChange = function(_, _, frameGroupIndex)
      if frameGroupIndex then
         if not collectAnimationWidgetChanges() then
            frameGroupBox:setCurrentOptionByData(previewFrameGroupIndex, true)
            return
         end
         previewFrameGroupIndex = frameGroupIndex
         previewPatternX = 0
         previewPatternY = 0
         previewPatternZ = 0
         previewLayer = 0
         previewPhase = 0
         previewMounted = false
         updatePreviewPatternControls()
         updateAnimationEditor()
         refreshAppearancePreview()
      end
   end

   for _, controlId in ipairs({ 'previewPatternX', 'previewPatternY', 'previewLayer', 'previewPatternZ' }) do
      window:recursiveGetChildById(controlId).onOptionChange = function()
         refreshAppearancePreview()
      end
   end
   window:recursiveGetChildById('previewPhaseStepper').onValueChange = function(_, value)
      if not collectAnimationWidgetChanges() then
         local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
         local onValueChange = phaseStepper.onValueChange
         phaseStepper.onValueChange = nil
         phaseStepper:setValue(previewPhase + 1, true)
         phaseStepper.onValueChange = onValueChange
         return
      end
      previewPhase = (value or 1) - 1
      updateAnimationEditor()
      refreshAppearancePreview()
   end
   window:recursiveGetChildById('previewMoving').onCheckChange = function(widget)
      if not previewHasMovementToggle then
         return
      end
      if not collectAnimationWidgetChanges() then
         setCheckBoxState(widget, not widget:isChecked())
         return
      end
      previewMoving = widget:isChecked()
      previewFrameGroupIndex = previewMoving and previewMovingGroupIndex or previewIdleGroupIndex
      previewPhase = 0
      updatePreviewPatternControls()
      updateAnimationEditor()
      refreshAppearancePreview()
   end

   window:recursiveGetChildById('previewMounted').onCheckChange = function()
      refreshAppearancePreview()
   end

   updatePreviewPatternControls()
   updateAnimationEditor()
   refreshAppearancePreview()
end

updateAnimationEditor = function()
   if not window then
      return
   end
   local wasBuildingProperties = buildingAppearanceProperties
   buildingAppearanceProperties = true
   local frameList = window:recursiveGetChildById('previewTimelineFrames')
   frameList:destroyChildren()
   animationWidgets = {}
   local group = currentPreviewGroup()
   local enabled = group and group.animation and group.animation.enabled == true or false
   local phaseCount = group and math.max(1, group.phaseCount or 1) or 1
   local isAnimated = enabled and group.animation.phases and #group.animation.phases > 0 or false
   local settingsRow = window:recursiveGetChildById('previewAnimationSettingsRow')
   local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
   local addFrameButton = window:recursiveGetChildById('addAnimationFrameButton')
   local removeFrameButton = window:recursiveGetChildById('removeAnimationFrameButton')
   local phaseCountLabel = window:recursiveGetChildById('previewPhaseCount')
   local minLabel = window:recursiveGetChildById('animationDurationMinLabel')
   local minEdit = window:recursiveGetChildById('animationDurationMin')
   local maxLabel = window:recursiveGetChildById('animationDurationMaxLabel')
   local maxEdit = window:recursiveGetChildById('animationDurationMax')
   local frameSelectionGroup = window:recursiveGetChildById('previewFrameSelectionGroup')
   local durationGroup = window:recursiveGetChildById('previewDurationGroup')
   local hasFrameControls = group ~= nil
   local showFrameButtons, showNumericFrameSelector =
      updatePreviewTimelineLayout(phaseCount, hasFrameControls, isAnimated)

   frameSelectionGroup:setVisible(showNumericFrameSelector)
   durationGroup:setVisible(isAnimated)
   phaseStepper:setMinimum(1)
   phaseStepper:setMaximum(phaseCount)
   phaseStepper:setStep(1)
   phaseStepper:setMouseScroll(true)
   phaseStepper:setVisible(showNumericFrameSelector)
   phaseCountLabel:setVisible(showNumericFrameSelector)
   phaseCountLabel:setText(tr('of %d', phaseCount))
   minLabel:setVisible(isAnimated)
   minEdit:setVisible(isAnimated)
   maxLabel:setVisible(isAnimated)
   maxEdit:setVisible(isAnimated)
   settingsRow:setVisible(isAnimated)
   local canEditFrames = group ~= nil and activeVersion ~= nil and not g_game.isOnline()
   addFrameButton:setEnabled(canEditFrames and phaseCount < math.floor(2147483647 /
      (math.max(1, group.layers or 1) * math.max(1, group.patternWidth or 1) *
      math.max(1, group.patternHeight or 1) * math.max(1, group.patternDepth or 1))))
   removeFrameButton:setEnabled(canEditFrames and phaseCount > 1)
   addFrameButton.onClick = function()
      changeAnimationPhaseCount(1)
   end
   removeFrameButton.onClick = function()
      if not canEditFrames or phaseCount <= 1 or not collectAnimationWidgetChanges() then
         return
      end
      local messageBox
      messageBox = displayGeneralBox(tr('Remove animation frame'),
         tr('Remove the last frame (%d) and its sprite links? This change will be applied when you save the appearance.', phaseCount), {
            { text = tr('Remove frame'), callback = function()
               messageBox:ok()
               changeAnimationPhaseCount(-1)
            end },
            { text = tr('Cancel'), callback = function() messageBox:cancel() end },
         })
   end

   local onValueChange = phaseStepper.onValueChange
   phaseStepper.onValueChange = nil
   phaseStepper:setValue(previewPhase + 1, true)
   phaseStepper.onValueChange = onValueChange

   if isAnimated then
      local groupIndex = group.index
      local groupKey = tostring(groupIndex)
      local changes = appearanceChanges.animation.groups[groupKey] or {}
      local animation = group.animation
      local defaultPhase = window:recursiveGetChildById('animationDefaultPhase')
      local randomStart = window:recursiveGetChildById('animationRandomStart')
      local synchronized = window:recursiveGetChildById('animationSynchronized')
      local loopTypeBox = window:recursiveGetChildById('animationLoopType')
      local loopCountLabel = window:recursiveGetChildById('animationLoopCountLabel')
      local loopCount = window:recursiveGetChildById('animationLoopCount')
      local loopCountControls = window:recursiveGetChildById('animationLoopCountControls')
      local randomStartValue = changes.randomStartPhase
      if randomStartValue == nil then
         randomStartValue = animation.randomStartPhase
      end
      local synchronizedValue = changes.synchronized
      if synchronizedValue == nil then
         synchronizedValue = animation.synchronized
      end
      local defaultPhaseValue = changes.defaultStartPhase
      if defaultPhaseValue == nil then
         defaultPhaseValue = animation.defaultStartPhase
      end
      defaultPhase:setText(tostring(defaultPhaseValue))
      randomStart:setChecked(randomStartValue)
      synchronized:setChecked(synchronizedValue)
      loopCount:setText(tostring(changes.loopCount ~= nil and changes.loopCount or animation.loopCount))
      setComboOptions(loopTypeBox, {
         { label = tr('Ping pong'), data = -1 },
         { label = tr('Infinite'), data = 0 },
         { label = tr('Counted'), data = 1 },
      }, changes.loopType ~= nil and changes.loopType or animation.loopType)
      local loopType = changes.loopType ~= nil and changes.loopType or animation.loopType
      loopCountLabel:setVisible(loopType == 1)
      loopCount:setVisible(loopType == 1)
      loopCountControls:setVisible(loopType == 1)
      loopCountControls:setWidth(loopType == 1 and 100 or 0)

      animationWidgets.groupIndex = groupIndex
      animationWidgets.fields = { defaultStartPhase = defaultPhase, loopCount = loopCount }

      defaultPhase.onTextChange = function(widget)
         if not buildingAppearanceProperties then
            local value = tonumber(widget:getText())
            if value and value >= 0 and value % 1 == 0 and value < phaseCount then
               setAnimationChange(groupIndex, 'defaultStartPhase', value)
            end
         end
      end
      randomStart.onCheckChange = function(widget)
         if not buildingAppearanceProperties then
            setAnimationChange(groupIndex, 'randomStartPhase', widget:isChecked())
         end
      end
      synchronized.onCheckChange = function(widget)
         if not buildingAppearanceProperties then
            setAnimationChange(groupIndex, 'synchronized', widget:isChecked())
         end
      end
      loopTypeBox.onOptionChange = function(_, _, value)
         if not buildingAppearanceProperties and value ~= nil then
            setAnimationChange(groupIndex, 'loopType', value)
            loopCountLabel:setVisible(value == 1)
            loopCount:setVisible(value == 1)
            loopCountControls:setVisible(value == 1)
            loopCountControls:setWidth(value == 1 and 100 or 0)
         end
      end
      loopCount.onTextChange = function(widget)
         if not buildingAppearanceProperties then
            local value = tonumber(widget:getText())
            if value and value >= 0 and value % 1 == 0 then
               setAnimationChange(groupIndex, 'loopCount', value)
            end
         end
      end

      local phase = animation.phases[previewPhase + 1]
      if phase then
         local phaseChanges = changes.phases and changes.phases[tostring(previewPhase)] or {}
         minEdit:setText(tostring(phaseChanges.durationMin ~= nil and phaseChanges.durationMin or phase.durationMin))
         maxEdit:setText(tostring(phaseChanges.durationMax ~= nil and phaseChanges.durationMax or phase.durationMax))
         animationWidgets.phaseIndex = previewPhase
         animationWidgets.phaseFields = { durationMin = minEdit, durationMax = maxEdit }
         local function updatePhaseDurationChanges()
            if buildingAppearanceProperties then
               return
            end
            local durationMin = tonumber(minEdit:getText())
            local durationMax = tonumber(maxEdit:getText())
            if not durationMin or not durationMax or durationMin < 0 or durationMax < 0 or
                  durationMin % 1 ~= 0 or durationMax % 1 ~= 0 or durationMin > durationMax then
               return
            end
            setAnimationChange(groupIndex, 'durationMin', durationMin, previewPhase)
            setAnimationChange(groupIndex, 'durationMax', durationMax, previewPhase)
         end
         minEdit.onTextChange = updatePhaseDurationChanges
         maxEdit.onTextChange = updatePhaseDurationChanges
      end
   else
      local loopTypeBox = window:recursiveGetChildById('animationLoopType')
      loopTypeBox.onOptionChange = nil
      loopTypeBox:clearOptions()
      local loopCountControls = window:recursiveGetChildById('animationLoopCountControls')
      loopCountControls:setVisible(false)
      loopCountControls:setWidth(0)
      window:recursiveGetChildById('animationLoopCountLabel'):setVisible(false)
      window:recursiveGetChildById('animationDefaultPhase'):setText('0')
      window:recursiveGetChildById('animationRandomStart'):setChecked(false)
      window:recursiveGetChildById('animationSynchronized'):setChecked(false)
      window:recursiveGetChildById('animationLoopCount'):setText('0')
      minEdit:setText('')
      maxEdit:setText('')
   end

   if showFrameButtons then
      for phaseIndex = 0, phaseCount - 1 do
         local currentPhaseIndex = phaseIndex
         local frameButton = g_ui.createWidget('AppearanceTimelineFrame', frameList)
         frameButton:setText(tostring(currentPhaseIndex + 1))
         frameButton:setTooltip(tr('Frame %d', currentPhaseIndex + 1))
         frameButton:setOn(currentPhaseIndex == previewPhase)
         frameButton:setColor(currentPhaseIndex == previewPhase and '#d9c7ff' or '#dfdfdf')
         frameButton.onClick = function()
            if not collectAnimationWidgetChanges() then
               return
            end
            previewPhase = currentPhaseIndex
            updateAnimationEditor()
            refreshAppearancePreview()
         end

         if currentPhaseIndex == previewPhase then
            local phaseToReveal = currentPhaseIndex
            addEvent(function()
               if not window or not window:isVisible() then
                  return
               end

               local currentTimeline = window:recursiveGetChildById('previewTimeline')
               local currentFrameList = window:recursiveGetChildById('previewTimelineFrames')
               local currentFrameButton = currentFrameList:getChildByIndex(phaseToReveal + 1)
               local ensureChildVisible = UIScrollArea and UIScrollArea.ensureChildVisible
               if currentTimeline and currentFrameButton and ensureChildVisible then
                  ensureChildVisible(currentTimeline, currentFrameButton)
               end
            end)
         end
      end
   end
   frameList:setWidth(showFrameButtons and math.max(1, phaseCount * 30 - 2) or 1)
   buildingAppearanceProperties = wasBuildingProperties
end

local function refreshSelectedAppearance()
   if not window or not activeVersion or not selectedAppearanceId then
      return
   end
   local thing = g_things.getThingType(selectedAppearanceId, selectedAppearanceCategory)
   if not thing or thing:getId() ~= selectedAppearanceId then
      setStatus(tr('Appearance %d is not available.', selectedAppearanceId))
      return
   end

   local category = categories[selectedAppearanceCategory + 1]
   local categoryName = category and tr(category.singular) or tr('Appearance')
   window:recursiveGetChildById('appearanceInfoLabel'):setText(
      tr('%s properties', categoryName))
   if #previewFrameGroups > 0 then
      refreshAppearancePreview()
   else
      local sprites = thing:getSprites()
      if #sprites > 0 then
         selectSprite(sprites[1])
      else
         selectedSpriteId = nil
         selectedSpriteContext = nil
         canvas:setVisible(false)
         setPreviewMessage(tr('This appearance has no linked sprites.'))
         updateSpriteReplacementTarget()
      end
   end
end

local function getThingEntries(category)
   local entries = {}
   for _, thing in pairs(g_things.getThingTypes(category)) do
      local id = thing:getId()
      if id and id > 0 then
         local sprites = thing:getSprites()
         local name = thing:getName()
         local seenSpriteIds = {}
         local spriteId
         local minSpriteId
         local maxSpriteId
         local linkedSpriteCount = 0
         for _, linkedSpriteId in ipairs(sprites or {}) do
            if linkedSpriteId > 0 then
               spriteId = spriteId or linkedSpriteId
               if not seenSpriteIds[linkedSpriteId] then
                  seenSpriteIds[linkedSpriteId] = true
                  minSpriteId = not minSpriteId and linkedSpriteId or math.min(minSpriteId, linkedSpriteId)
                  maxSpriteId = not maxSpriteId and linkedSpriteId or math.max(maxSpriteId, linkedSpriteId)
                  linkedSpriteCount = linkedSpriteCount + 1
               end
            end
         end
         table.insert(entries, {
            id = id,
            category = category,
            name = name ~= '' and name or nil,
            spriteId = spriteId,
            minSpriteId = minSpriteId,
            maxSpriteId = maxSpriteId,
            linkedSpriteCount = linkedSpriteCount,
         })
      end
   end
   table.sort(entries, function(a, b) return a.id < b.id end)
   return entries
end

local function getAppearanceTooltip(entry)
   local lines = {}
   if entry.name then
      table.insert(lines, entry.name)
   end

   if entry.linkedSpriteCount == 1 then
      table.insert(lines, tr('Sprite ID: %d', entry.minSpriteId))
   elseif entry.linkedSpriteCount > 1 then
      table.insert(lines, tr('Sprite ID span: %d-%d (%d linked)',
         entry.minSpriteId, entry.maxSpriteId, entry.linkedSpriteCount))
   else
      table.insert(lines, tr('No linked sprites'))
   end
   return table.concat(lines, '\n')
end

renderAppearanceRows = function(scrollY)
   if not window or not activeVersion then
      return
   end
   local list = window:recursiveGetChildById('appearanceList')
   local content = window:recursiveGetChildById('appearanceListContent')
   content:setHeight(math.max(1, #filteredAppearanceEntries * APPEARANCE_ROW_HEIGHT))
   local firstIndex = math.floor(math.max(0, scrollY or 0) / APPEARANCE_ROW_HEIGHT) + 1
   local viewportHeight = math.max(list:getHeight(), 1)
   local poolSize = math.ceil(math.max(viewportHeight, 400) / APPEARANCE_ROW_HEIGHT) + 2
   local thumbnailsUpdated = false
   while #appearanceRows < poolSize do
      local row = g_ui.createWidget('AppearanceResultRow', content)
      table.insert(appearanceRows, row)
   end

   for slot, row in ipairs(appearanceRows) do
      local index = firstIndex + slot - 1
      local entry = filteredAppearanceEntries[index]
      row:setVisible(entry ~= nil)
      if entry then
         row:setMarginTop((index - 1) * APPEARANCE_ROW_HEIGHT)
         row:setText('')
         row:recursiveGetChildById('appearanceId'):setText(tostring(entry.id))
         row:setTooltip(getAppearanceTooltip(entry))
         local thumbnail = row:recursiveGetChildById('thumbnail')
         thumbnail:setVisible(entry.spriteId ~= nil)
         local lastVisibleIndex = math.floor(((scrollY or 0) + viewportHeight) / APPEARANCE_ROW_HEIGHT) + 1
         if entry.spriteId and index <= lastVisibleIndex and row.thumbnailEntry ~= entry then
            local loaded
            local thing = g_things.getThingType(entry.id, entry.category)
            local animationSprites = getThumbnailAnimationSprites(thing)
            if #animationSprites > 1 then
               loaded = thumbnail:setSpriteAnimationIds(animationSprites)
            else
               loaded = thumbnail:setThumbnailSpriteId(entry.spriteId)
            end
            if not loaded and #animationSprites > 1 then
               loaded = thumbnail:setThumbnailSpriteId(entry.spriteId)
            end
            if loaded then
               thumbnailsUpdated = true
               row.thumbnailEntry = entry
            else
               row.thumbnailEntry = nil
            end
         end
         local selected = entry.id == selectedAppearanceId and entry.category == selectedAppearanceCategory
         row:setOn(selected)
         row.onClick = function()
            selectAppearance(entry.category, entry.id)
         end
      end
   end

   if thumbnailsUpdated and g_spriteAppearances.releaseDecodedSpriteSheets then
      g_spriteAppearances.releaseDecodedSpriteSheets()
   end
end

local function applyAppearanceFilter()
   if not window then
      return
   end
   local search = window:recursiveGetChildById('appearanceSearch'):getText():lower():match('^%s*(.-)%s*$')
   local exactId = search:match('^%d+$') and tonumber(search) or nil
   filteredAppearanceEntries = {}
   for _, entry in ipairs(appearanceEntries) do
      local nameText = entry.name and entry.name:lower() or ''
      if search == '' or (exactId and entry.id == exactId) or
            (not exactId and nameText:find(search, 1, true)) then
         table.insert(filteredAppearanceEntries, entry)
      end
   end
   local list = window:recursiveGetChildById('appearanceList')
   list:setVirtualOffset({ x = 0, y = 0 })
   renderAppearanceRows(0)
   list:updateScrollBars()
end

local function refreshAppearanceCatalog(category)
   if not window or not activeVersion then
      appearanceEntries = {}
      filteredAppearanceEntries = {}
      return
   end
   appearanceEntries = getThingEntries(category)
   categoryAppearanceCounts[category] = #appearanceEntries
   updateCategoryOptions()
   applyAppearanceFilter()
end

local function loadAppearanceRecord(category, id, forceDiscard, forceReload)
   if not window or not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before editing appearances.'))
      return false
   end
   if selectedAppearanceCategory == category and selectedAppearanceId == id and appearanceOriginal and not forceReload then
      refreshSelectedAppearance()
      return true
   end
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before selecting another appearance?'), function()
         loadAppearanceRecord(category, id, true)
      end)
      return false
   end

   local ok, encoded = pcall(g_things.getAppearanceEditorData, activeVersion, category, id)
   if not ok then
      setStatus(getUserFacingError(encoded))
      return false
   end
   local decoded, data = pcall(json.decode, encoded)
   if not decoded or type(data) ~= 'table' or type(data.bools) ~= 'table' or type(data.values) ~= 'table' then
      setStatus(tr('Appearance properties could not be read.'))
      return false
   end
   local thing = g_things.getThingType(id, category)
   if not thing or thing:getId() ~= id then
      setStatus(tr('Appearance %d is not loaded by the client.', id))
      return false
   end

   selectedAppearanceCategory = category
   selectedAppearanceId = id
   selectedSpriteId = nil
   selectedSpriteContext = nil
   updateSpriteReplacementTarget()
   window:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(category, true)
   buildAppearanceProperties(data)
   refreshSelectedAppearance()
   local categoryInfo = categories[category + 1]
   setStatus(tr('%s %d loaded.', categoryInfo and tr(categoryInfo.singular) or tr('Appearance'), id))
   renderAppearanceRows(window:recursiveGetChildById('appearanceList'):getVirtualOffset().y)
   return true
end

selectAppearance = function(category, id, forceDiscard)
   loadAppearanceRecord(category, id, forceDiscard)
end

local function changeAppearanceCategory(category, forceDiscard)
   if not category then
      return
   end
   if hasAppearanceChanges() and not forceDiscard then
      window:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(selectedAppearanceCategory, true)
      confirmUnsavedChanges(tr('Save changes before switching categories?'), function()
         changeAppearanceCategory(category, true)
      end)
      return
   end
   selectedAppearanceCategory = category
   selectedAppearanceId = nil
   appearanceOriginal = nil
   clearAppearanceChanges()
   local searchEdit = window:recursiveGetChildById('appearanceSearch')
   if searchEdit:getText() ~= '' then
      searchEdit:setText('')
   end
   refreshAppearanceCatalog(category)
   if filteredAppearanceEntries[1] then
      loadAppearanceRecord(category, filteredAppearanceEntries[1].id, true)
   else
      clearAppearanceProperties()
      setStatus(#appearanceEntries > 0 and tr('No appearances match this search.') or tr('No appearances in this category.'))
   end
end

local function reloadAssets()
   if not activeAssetPath then
      return false
   end
   g_things.invalidateTextureCache()
   if not g_things.loadAppearances(activeAssetPath) or not g_things.loadStaticData(activeAssetPath) then
      return false
   end
   if refreshSpritePicker then refreshSpritePicker() end
   return true
end

local function unmountWorkRoot(root)
   if not root or not mountedRoots[root] then
      return true, false
   end
   if not g_resources.removeSearchPath(root) then
      return false, false
   end
   mountedRoots[root] = nil
   return true, true
end

local function restoreWorkRoot(root, wasMounted)
   if not wasMounted then
      return true
   end
   if not g_resources.addSearchPath(root, true) then
      return false
   end
   mountedRoots[root] = true
   return true
end

local function releaseActiveWorkCopy()
   if not activeVersion then
      return true
   end

   local version = activeVersion
   local root = activeWorkRoot
   local workAssetPath = activeAssetPath
   local unmounted = true
   if root then
      unmounted = unmountWorkRoot(root)
   end
   if not unmounted then
      return false, tr('Could not unmount the sprite editor working copy.')
   end

   local installedAssetPath = resolvepath(string.format('/data/things/%d/', version))
   local reloaded, loaded = pcall(function()
      g_things.invalidateTextureCache()
      if not g_things.loadAppearances(installedAssetPath) then
         return false
      end
      return g_things.loadStaticData(installedAssetPath)
   end)
   if not reloaded or not loaded then
      local remounted = not root or mountedRoots[root] or g_resources.addSearchPath(root, true)
      if remounted and root then
         mountedRoots[root] = true
      end
      if remounted and workAssetPath then
         pcall(function()
            g_things.invalidateTextureCache()
            g_things.loadAppearances(workAssetPath)
            g_things.loadStaticData(workAssetPath)
         end)
      end
      local detail = not reloaded and getUserFacingError(loaded) or
         tr('The installed client assets could not be reloaded.')
      return false, detail
   end

   activeVersion = nil
   activeAssetPath = nil
   activeWorkRoot = nil
   return true
end

local function updateExportControls()
   if not window then
      return
   end

   local offline = not g_game.isOnline()
   local selectedVersion = selectedOption(window:recursiveGetChildById('versionComboBox'))
   window:recursiveGetChildById('loadAssetsButton'):setEnabled(offline and selectedVersion ~= nil)
   window:recursiveGetChildById('exportButton'):setEnabled(activeVersion ~= nil and offline)
   window:recursiveGetChildById('importPageButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('exportPageButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('reloadButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('newAppearanceTabButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
end

local function setActivePage(page)
   if not window then
      return
   end
   currentPage = page
   window:recursiveGetChildById('propertiesPanel'):setVisible(page == 'editor')
   window:recursiveGetChildById('importPanel'):setVisible(page == 'import')
   window:recursiveGetChildById('exportPanel'):setVisible(page == 'export')
   window:recursiveGetChildById('editorPageButton'):setOn(page == 'editor')
   window:recursiveGetChildById('importPageButton'):setOn(page == 'import')
   window:recursiveGetChildById('exportPageButton'):setOn(page == 'export')
   updateSpriteReplacementTarget()
   updateExportControls()
   if page == 'export' then
      local packagePath = activeWorkRoot and activeVersion and
         string.format('%s/data/things/%d', activeWorkRoot, activeVersion)
      local copyLabel = window:recursiveGetChildById('activeWorkCopyLabel')
      copyLabel:setText(packagePath or tr('No work copy is open.'))
      copyLabel:setTooltip(packagePath or '')
      window:recursiveGetChildById('installTargetLabel'):setText(activeVersion and
         string.format('data/things/%d', activeVersion) or tr('No assets version selected.'))
   end
end

local function createWindow()
   if window then
      window:destroy()
   end
   window = g_ui.displayUI('sprite_editor')
   if not window then
      displayErrorBox(tr('Assets Editor'), tr('Could not create the editor window. Check the client log for UI errors.'))
      return false
   end

   canvas = window:recursiveGetChildById('canvas')
   if not canvas then
      window:destroy()
      window = nil
      displayErrorBox(tr('Assets Editor'), tr('The editor canvas could not be initialized.'))
      return false
   end
   canvas.onStateChange = function()
      if canvas and window then
         updatePreviewTitle()
         updateDirectionPadLayout()
      end
   end
   canvas.onPositionChange = function()
      if canvas and window then
         updateDirectionPadLayout()
      end
   end
   canvas.onDrop = function(_, draggedWidget)
      if not draggedWidget or not draggedWidget.isSpritePickerCell or
            currentPage ~= 'import' or currentImportSection ~= 'replace' or currentReplaceMode ~= 'sprite' then
         return false
      end
      local spriteId = tonumber(draggedWidget.spriteId)
      if not spriteId or not activeVersion or g_game.isOnline() or not selectedSpriteId then
         return false
      end

      selectSpritePickerSprite(spriteId)
      replaceSelectedFrameWithSprite(spriteId)
      return true
   end

   local spritePathEdit = window:recursiveGetChildById('previewSpritePathEdit')
   spritePathEdit.onTextChange = function(widget)
      if not settingSpritePath and
            (not pendingSpriteEdit or widget:getText() ~= pendingSpriteEdit.path) then
         preparedSpritePath = widget:getText()
      end
      window:recursiveGetChildById('importPngReplaceButton'):setEnabled(
         activeVersion ~= nil and not g_game.isOnline() and selectedSpriteId ~= nil and widget:getText() ~= '')
   end
   setSpritePath(preparedSpritePath)

   local categoryBox = window:recursiveGetChildById('appearanceCategory')
   updateCategoryOptions()
   categoryBox:setCurrentOptionByData(selectedAppearanceCategory, true)
   categoryBox.onOptionChange = function(_, _, category)
      changeAppearanceCategory(category)
   end
   local newAppearanceCategoryBox = window:recursiveGetChildById('newAppearanceCategory')
   for _, category in ipairs(categories) do
      newAppearanceCategoryBox:addOption(tr(category.name), category.data)
   end
   newAppearanceCategoryBox:setCurrentOptionByData(selectedAppearanceCategory, true)
   local searchEdit = window:recursiveGetChildById('appearanceSearch')
   searchEdit.onTextChange = function()
      applyAppearanceFilter()
   end
   local list = window:recursiveGetChildById('appearanceList')
   list.onScrollChange = function(_, offset)
      renderAppearanceRows(offset.y)
   end
   local function scheduleSpritePickerFilter()
      if spriteSearchEvent then
         removeEvent(spriteSearchEvent)
      end
      spriteSearchEvent = scheduleEvent(function()
         spriteSearchEvent = nil
         applySpritePickerFilter()
      end, 120)
   end
   for _, searchId in ipairs({ 'spriteSearchEdit', 'newAppearanceSpriteSearchEdit' }) do
      window:recursiveGetChildById(searchId).onTextChange = scheduleSpritePickerFilter
   end
   for _, listId in ipairs({ 'spritePickerList', 'newAppearanceSpritePickerList' }) do
      window:recursiveGetChildById(listId).onScrollChange = function(_, offset)
         renderSpritePickerRows(offset.y)
      end
   end
   window:recursiveGetChildById('newAppearancePngPathEdit').onTextChange = function(widget)
      window:recursiveGetChildById('createAppearanceButton'):setEnabled(
         activeVersion ~= nil and not g_game.isOnline() and currentNewAppearanceSourceMode == 'png' and
         widget:getText() ~= '')
   end

   local versionBox = window:recursiveGetChildById('versionComboBox')
   local versions = getVersions()
   for _, version in ipairs(versions) do
      versionBox:addOption(formatClientVersion(version), version)
   end
   local selectedVersion = activeVersion or versions[1]
   if selectedVersion then
      versionBox:setCurrentOptionByData(selectedVersion, true)
   end
   versionBox.onOptionChange = function()
      updateExportControls()
   end

   setActivePage(currentPage)
   setPropertiesTab(currentPropertiesTab)
   setImportSection(currentImportSection)
   window:show()
   window:raise()
   window:focus()
   if activeVersion then
      refreshAppearanceCatalog(selectedAppearanceCategory)
      refreshSpritePicker()
      if filteredAppearanceEntries[1] then
         loadAppearanceRecord(selectedAppearanceCategory, filteredAppearanceEntries[1].id, true)
      end
   else
      clearAppearanceProperties()
   end
   return true
end

local function destroyWindow()
   destroyPngFilePicker()
   if spriteSearchEvent then
      removeEvent(spriteSearchEvent)
      spriteSearchEvent = nil
   end
   appearanceValueWidgets = {}
   appearanceStringWidgets = {}
   animationWidgets = {}
   if window then
      window:destroy()
      window = nil
      canvas = nil
   end
   appearanceRows = {}
   spritePickerCells = { replace = {}, create = {} }
   spritePickerRanges = {}
   spritePickerIds = nil
   spritePickerCount = 0
   spritePickerSourceId = nil
   selectedReplacementSpriteId = nil
   selectedCreateSpriteId = nil
   spritePickerQuery = ''
   appearanceEntries = {}
   filteredAppearanceEntries = {}
   selectedAppearanceId = nil
   selectedSpriteId = nil
   appearanceOriginal = nil
   clearAppearanceChanges()
   if g_spriteAppearances.releaseDecodedSpriteSheets then
      g_spriteAppearances.releaseDecodedSpriteSheets()
   end
end

local function loadAssets(version)
   if g_game.isOnline() then
      displayErrorBox(tr('Assets Editor'), tr('Disconnect before opening the offline assets editor.'))
      return false
   end
   local ok, workRoot = pcall(g_spriteAppearances.createWorkCopy, version)
   if not ok then
      displayErrorBox(tr('Assets Editor'), getUserFacingError(workRoot))
      return false
   end

   if not mountedRoots[workRoot] then
      if not g_resources.addSearchPath(workRoot, true) then
         displayErrorBox(tr('Assets Editor'), tr('Could not mount the work copy.'))
         return false
      end
      mountedRoots[workRoot] = true
   end

   g_things.invalidateTextureCache()
   if g_game.getClientVersion() ~= version then
      g_game.setClientVersion(version)
   end
   local assetPath = resolvepath(string.format('/data/things/%d/', version))
   if not g_things.loadAppearances(assetPath) or not g_things.loadStaticData(assetPath) then
      displayErrorBox(tr('Assets Editor'), tr('Could not load the selected work copy. Check the client log for details.'))
      return false
   end

   activeVersion = version
   activeAssetPath = assetPath
   activeWorkRoot = workRoot
   categoryAppearanceCounts = {}
   selectedAppearanceCategory = 0
   return true
end

function init()
   if not g_spriteAppearances.createWorkCopy then
      return
   end
   gameStartCallback = function()
      if topMenuButton then topMenuButton:setVisible(false) end
   end
   gameEndCallback = function()
      if topMenuButton then topMenuButton:setVisible(true) end
   end
   topMenuButton = modules.client_topmenu.addTopRightRegularButton(
      'offlineAssetsEditorButton', tr('Assets'), nil, toggle)
   topMenuButton:setVisible(not g_game.isOnline())
   connect(g_game, { onGameStart = gameStartCallback, onGameEnd = gameEndCallback })
end

function terminate()
   disconnect(g_game, { onGameStart = gameStartCallback, onGameEnd = gameEndCallback })
   if activeVersion then
      local released, err = releaseActiveWorkCopy()
      if not released then
         g_logger.error('[game_sprite_editor] Unable to restore installed assets during shutdown: ' .. tostring(err))
      end
   end
   destroyWindow()
   if topMenuButton then
      topMenuButton:destroy()
      topMenuButton = nil
   end
   activeVersion = nil
   activeAssetPath = nil
   activeWorkRoot = nil
   gameStartCallback = nil
   gameEndCallback = nil
end

function toggle()
   if g_game.isOnline() then
      displayErrorBox(tr('Assets Editor'), tr('Disconnect before opening the offline assets editor.'))
      return
   end
   if window then
      requestClose()
   elseif activeVersion then
      createWindow()
   else
      local version = getVersions()[1]
      if version then
         openWorkCopyVersion(version)
      else
         createWindow()
         setStatus(tr('No installed client assets in version 15.x were found.'))
      end
   end
end

function loadSelectedAssets()
   if not window or g_game.isOnline() then
      return
   end
   local version = selectedOption(window:recursiveGetChildById('versionComboBox'))
   if not version then
      displayErrorBox(tr('Assets Editor'), tr('No installed client version 15.x assets were found.'))
      return
   end

   local ok, hasWorkCopy = pcall(g_spriteAppearances.workCopyExists, version)
   if not ok then
      displayErrorBox(tr('Assets Editor'), getUserFacingError(hasWorkCopy))
      return
   end
   if not hasWorkCopy then
      if hasAppearanceChanges() then
         confirmUnsavedChanges(tr('Save changes before loading another assets version?'), function()
            openWorkCopyVersion(version)
         end)
         return
      end
      openWorkCopyVersion(version)
      return
   end

   local messageBox
   local function cancelReset()
      messageBox:cancel()
   end
   local function resetAndLoad()
      messageBox:ok()
      local mountedRoot = activeWorkRoot
      local unmountOk, wasMounted = unmountWorkRoot(mountedRoot)
      if not unmountOk then
         displayErrorBox(tr('Assets Editor'), tr('Could not unmount the working copy before reloading assets.'))
         return
      end

      local resetOk, result = pcall(g_spriteAppearances.resetWorkCopy, version)
      if not resetOk then
         if not restoreWorkRoot(mountedRoot, wasMounted) then
            displayErrorBox(tr('Assets Editor'), tr('%s The working copy could not be remounted.', getUserFacingError(result)))
            return
         end
         displayErrorBox(tr('Assets Editor'), getUserFacingError(result))
         return
      end
      openWorkCopyVersion(version)
   end
   messageBox = displayGeneralBox(tr('Reload assets from the installed version?'),
      tr('This replaces the selected working copy with the installed assets and discards its saved edits and any unsaved editor changes.'), {
         { text = tr('Reload assets'), callback = resetAndLoad },
         { text = tr('Cancel'), callback = cancelReset },
      }, cancelReset, cancelReset)
end

function openWorkCopyVersion(version)
   if activeVersion then
      local released, err = releaseActiveWorkCopy()
      if not released then
         displayErrorBox(tr('Assets Editor'), err)
         return false
      end
   end
   destroyWindow()
   if not loadAssets(version) then
      createWindow()
      return false
   end
   currentPage = 'editor'
   createWindow()
   window:recursiveGetChildById('versionComboBox'):setCurrentOptionByData(version, true)
   setStatus(tr('Working copy ready for client %s.', formatClientVersion(version)))
   return true
end

function applyAppearanceSearch()
   applyAppearanceFilter()
end

function showEditorPage()
   setActivePage('editor')
end

local function getSpritePickerIdAt(index)
   if spritePickerIds then
      return spritePickerIds[index]
   end

   local first = 1
   local last = #spritePickerRanges
   while first <= last do
      local middle = math.floor((first + last) / 2)
      if index <= spritePickerRanges[middle][3] then
         last = middle - 1
      else
         first = middle + 1
      end
   end
   local range = spritePickerRanges[first]
   if not range then return nil end
   local previousCount = first > 1 and spritePickerRanges[first - 1][3] or 0
   return range[1] + index - previousCount - 1
end

local function getSpriteSizeTier(width, height)
   local size = math.max(width, height)
   local tier = 32
   while tier < size do
      tier = tier * 2
   end
   return tier
end

applySpritePickerFilter = function()
   if not window then
      return
   end

   local query = getSpritePickerWidget('search'):getText():lower():match('^%s*(.-)%s*$')
   if query ~= spritePickerQuery then
      setSelectedSpritePickerId(nil)
      spritePickerQuery = query
   end
   spritePickerIds = nil
   if query ~= '' then
      spritePickerIds = {}
      for _, range in ipairs(spritePickerRanges) do
         local firstId = math.max(1, range[1])
         for spriteId = firstId, range[2] do
            if tostring(spriteId):find(query, 1, true) then
               table.insert(spritePickerIds, spriteId)
            end
         end
      end
      spritePickerCount = #spritePickerIds
   else
      spritePickerCount = #spritePickerRanges > 0 and spritePickerRanges[#spritePickerRanges][3] or 0
   end

   local list = getSpritePickerWidget('list')
   list:setVirtualOffset({ x = 0, y = 0 })
   renderSpritePickerRows(0)
   list:updateScrollBars()
end

refreshSpritePicker = function()
   if not window or not activeVersion then
      spritePickerRanges = {}
      spritePickerIds = nil
      spritePickerCount = 0
      return
   end

   local ok, encoded = pcall(g_spriteAppearances.getSpriteRanges)
   local decoded, ranges = false, nil
   if ok then decoded, ranges = pcall(json.decode, encoded) end
   if not decoded or type(ranges) ~= 'table' then
      spritePickerRanges = {}
      spritePickerIds = nil
      spritePickerCount = 0
      setStatus(tr('The sprite list could not be loaded.'))
      return
   end

   local validRanges = {}
   for _, range in ipairs(ranges) do
      local firstId = tonumber(range[1])
      local lastId = tonumber(range[2])
      if firstId and lastId and firstId % 1 == 0 and lastId % 1 == 0 and lastId >= firstId then
         table.insert(validRanges, { math.max(1, firstId), lastId })
      end
   end
   table.sort(validRanges, function(a, b) return a[1] < b[1] end)
   spritePickerRanges = {}
   for _, range in ipairs(validRanges) do
      local previous = spritePickerRanges[#spritePickerRanges]
      if previous and range[1] <= previous[2] + 1 then
         previous[2] = math.max(previous[2], range[2])
      else
         table.insert(spritePickerRanges, { range[1], range[2] })
      end
   end
   local cumulativeCount = 0
   for _, range in ipairs(spritePickerRanges) do
      cumulativeCount = cumulativeCount + math.max(0, range[2] - range[1] + 1)
      range[3] = cumulativeCount
   end
   for _, cells in pairs(spritePickerCells) do
      for _, cell in ipairs(cells) do
         cell.spriteId = nil
         cell.thumbnailSpriteId = nil
      end
   end
   applySpritePickerFilter()
end

selectSpritePickerSprite = function(spriteId)
   if not window or not spriteId then
      return
   end
   setSelectedSpritePickerId(spriteId)
   updateSpriteReplacementTarget()
end

renderSpritePickerRows = function(scrollY)
   if not window then
      return
   end

   local list = getSpritePickerWidget('list')
   local content = getSpritePickerWidget('content')
   local cellWidth = 70
   local cellHeight = 60
   local columnGap = 3
   local columnCount = math.max(1, math.floor((list:getWidth() + columnGap) / (cellWidth + columnGap)))
   local cells = spritePickerCells[currentImportSection]
   local totalRows = math.ceil(spritePickerCount / columnCount)
   content:setHeight(math.max(1, totalRows * cellHeight))

   local firstRow = math.floor(math.max(0, scrollY or 0) / cellHeight)
   local viewportHeight = math.max(list:getHeight(), cellHeight)
   local poolSize = (math.ceil(viewportHeight / cellHeight) + 2) * columnCount
   while #cells < poolSize do
      table.insert(cells, g_ui.createWidget('SpritePickerCell', content))
   end

   local updatedThumbnails = false
   for slot, cell in ipairs(cells) do
      local index = firstRow * columnCount + slot
      local spriteId = index <= spritePickerCount and getSpritePickerIdAt(index) or nil
      cell:setVisible(spriteId ~= nil)
      if spriteId then
         cell.isSpritePickerCell = true
         cell:setDraggable(currentImportSection == 'replace' and activeVersion ~= nil and
            not g_game.isOnline() and selectedSpriteId ~= nil)
         cell:setMarginTop(math.floor((index - 1) / columnCount) * cellHeight)
         cell:setMarginLeft(((index - 1) % columnCount) * (cellWidth + columnGap))
         cell:recursiveGetChildById('spritePickerId'):setText(tostring(spriteId))
         cell:setOn(spriteId == getSelectedSpritePickerId())
         cell.spriteId = spriteId
         if cell.thumbnailSpriteId ~= spriteId then
            local thumbnail = cell:recursiveGetChildById('thumbnail')
            local sizeBadge = cell:recursiveGetChildById('spriteSizeBadge')
            if thumbnail:setThumbnailSpriteId(spriteId) then
               cell.thumbnailSpriteId = spriteId
               updatedThumbnails = true
               local width = thumbnail:getSpriteWidth()
               local height = thumbnail:getSpriteHeight()
               local largestDimension = math.max(width, height)
               thumbnail:setThumbnailSizeBadge(largestDimension)
               sizeBadge:setText(tostring(getSpriteSizeTier(width, height)))
               sizeBadge:setColor(largestDimension <= 32 and '#ffffff' or '#171717')
               cell:setTooltip(tr('Sprite dimensions: %d x %d', width, height))
               sizeBadge:setVisible(true)
            else
               cell.thumbnailSpriteId = nil
               cell:setTooltip('')
               sizeBadge:setVisible(false)
            end
         end
         cell.onClick = function()
            selectSpritePickerSprite(spriteId)
         end
         cell.onDragEnter = function(widget)
            if not widget.spriteId or not activeVersion or g_game.isOnline() or not selectedSpriteId then
               return false
            end
            selectSpritePickerSprite(widget.spriteId)
            return true
         end
         cell.onDragMove = function(widget, mousePos)
            local overCanvas = canvas and canvas:isVisible() and canvas:containsPoint(mousePos)
            if canvas then
               canvas:setBorderWidth(overCanvas and 2 or 0)
               canvas:setBorderColor(overCanvas and '#8f69d3' or 'alpha')
            end
            return true
         end
         cell.onDragLeave = function()
            if canvas then
               canvas:setBorderWidth(0)
               canvas:setBorderColor('alpha')
            end
            return true
         end
      else
         cell.spriteId = nil
         cell.thumbnailSpriteId = nil
         cell.isSpritePickerCell = false
         cell:setDraggable(false)
         cell:setTooltip('')
         cell:recursiveGetChildById('spriteSizeBadge'):setVisible(false)
      end
   end

   local countLabel = getSpritePickerWidget('count')
   countLabel:setText(spritePickerCount == 1 and tr('%d sprite', spritePickerCount) or
      tr('%d sprites', spritePickerCount))
   local selectionLabel = getSpritePickerWidget('selection')
   local selectedSprite = getSelectedSpritePickerId()
   if currentImportSection == 'create' then
      selectionLabel:setText(selectedSprite and tr('Selected sprite ID %d.', selectedSprite) or
         tr('Choose a sprite from the list.'))
   else
      selectionLabel:setText(selectedSprite and tr('Drag sprite %d onto the preview.', selectedSprite) or
         tr('Select or drag a sprite onto the preview.'))
   end

   if updatedThumbnails and g_spriteAppearances.releaseDecodedSpriteSheets then
      g_spriteAppearances.releaseDecodedSpriteSheets()
   end
end

function setImportSection(section)
   if section ~= 'replace' and section ~= 'create' then
      return
   end
   local search = getSpritePickerWidget('search')
   local query = search and search:getText() or ''
   if section ~= currentImportSection and section == 'create' then
      selectedCreateSpriteId = nil
   end
   currentImportSection = section
   if window then
      getSpritePickerWidget('search'):setText(query)
      window:recursiveGetChildById('replaceFramePanel'):setVisible(section == 'replace')
      window:recursiveGetChildById('newAppearancePanel'):setVisible(section == 'create')
      window:recursiveGetChildById('replaceFrameTabButton'):setOn(section == 'replace')
      window:recursiveGetChildById('newAppearanceTabButton'):setOn(section == 'create')
      applySpritePickerFilter()
   end
   updateSpriteReplacementTarget()
end

function setReplaceMode(mode)
   if mode ~= 'sprite' and mode ~= 'png' then
      return
   end
   currentReplaceMode = mode
   updateSpriteReplacementTarget()
end

function setNewAppearanceSourceMode(mode)
   if mode ~= 'sprite' and mode ~= 'png' then
      return
   end
   currentNewAppearanceSourceMode = mode
   updateSpriteReplacementTarget()
end

function duplicateSelectedAppearance(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before duplicating this appearance?'), function()
         duplicateSelectedAppearance(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() or not selectedAppearanceId then
      setStatus(tr('Select an appearance in an offline 15.x work copy first.'))
      return
   end

   local sourceId = selectedAppearanceId
   local category = selectedAppearanceCategory
   local ok, duplicateId = pcall(g_things.duplicateAppearance, activeVersion, category, sourceId)
   if not ok then
      setStatus(getUserFacingError(duplicateId))
      return
   end
   if not reloadAssets() then
      setStatus(tr('Appearance %d was duplicated, but the work copy could not be reloaded.', duplicateId))
      return
   end

   local searchEdit = window:recursiveGetChildById('appearanceSearch')
   if searchEdit:getText() ~= '' then
      searchEdit:setText('')
   end
   refreshAppearanceCatalog(category)
   if loadAppearanceRecord(category, duplicateId, true, true) then
      setActivePage('editor')
      local list = window:recursiveGetChildById('appearanceList')
      local targetOffset = math.max(0, (#filteredAppearanceEntries - 1) * APPEARANCE_ROW_HEIGHT)
      list:setVirtualOffset({ x = 0, y = targetOffset })
      renderAppearanceRows(list:getVirtualOffset().y)
      list:updateScrollBars()
      setStatus(tr('Duplicated %d as %d. Sprite IDs remain shared.', sourceId, duplicateId))
   end
end

function importPngAndReplace(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before importing a PNG for this frame?'), function()
         importPngAndReplace(true)
      end)
      return
   end
   importPngAsNewSprite()
end

function showImportPage()
   setActivePage('import')
   setImportSection(currentImportSection)
   if refreshSpritePicker then refreshSpritePicker() end
end

function openNewAppearance()
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Load an offline 15.x work copy before creating an appearance.'))
      return
   end

   showImportPage()
   setImportSection('create')
   window:recursiveGetChildById('newAppearanceCategory'):setCurrentOptionByData(selectedAppearanceCategory, true)
end

function selectPreviewDirection(directionIndex)
   local group = currentPreviewGroup()
   if not group or selectedAppearanceCategory ~= 1 or directionIndex < 0 or directionIndex >= group.patternWidth then
      return
   end
   previewPatternX = directionIndex
   updatePreviewPatternControls()
   refreshAppearancePreview()
end

function showExportPage()
   setActivePage('export')
end

function showPropertiesTab(tab)
   setPropertiesTab(tab)
end

function zoomIn()
   if canvas then canvas:zoomIn() end
end

function zoomOut()
   if canvas then canvas:zoomOut() end
end

local function getSelectedSpriteReference()
   local group = currentPreviewGroup()
   if not group or not selectedAppearanceId or not selectedSpriteId then
      setStatus(tr('Select a linked sprite frame before replacing it.'))
      return nil
   end

   local spriteIndex = (((previewPhase * group.patternDepth + previewPatternZ) * group.patternHeight +
      previewPatternY) * group.patternWidth + previewPatternX) * group.layers + previewLayer + 1
   if group.sprites[spriteIndex] ~= selectedSpriteId then
      setStatus(tr('The selected sprite frame is no longer current. Select it again and retry.'))
      return nil
   end

   return previewFrameGroupIndex - 1, spriteIndex - 1
end

local function refreshAfterSpriteReferenceChange(category, appearanceId, previewSelection, returnToImport)
   if not reloadAssets() then
      setStatus(tr('The sprite link was saved, but the work copy could not be reloaded.'))
      return false
   end
   refreshAppearanceCatalog(category)
   if not loadAppearanceRecord(category, appearanceId, true, true) then
      setStatus(tr('The sprite link was saved, but the appearance preview could not be reloaded.'))
      return false
   end
   restorePreviewSelection(previewSelection)
   setActivePage(returnToImport and 'import' or 'editor')
   return true
end

linkSpriteToSelectedFrame = function(spriteId)
   local category = selectedAppearanceCategory
   local appearanceId = selectedAppearanceId
   local frameGroupIndex, spriteIndex = getSelectedSpriteReference()
   if not frameGroupIndex then
      return false
   end

   local previewSelection = capturePreviewSelection()
   local ok, result = pcall(g_things.replaceAppearanceSprite, activeVersion, category,
      appearanceId, frameGroupIndex, spriteIndex, spriteId)
   if not ok then
      setStatus(getUserFacingError(result))
      return false
   end
   if not refreshAfterSpriteReferenceChange(category, appearanceId, previewSelection, true) then
      return false
   end

   setStatus(tr('Frame linked to sprite %d; other appearances are unchanged.', spriteId))
   return true
end

replaceSelectedFrameWithSprite = function(spriteId, forceDiscard)
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before replacing a sprite.'))
      return false
   end
   if currentPage ~= 'import' or currentImportSection ~= 'replace' or currentReplaceMode ~= 'sprite' then
      return false
   end
   if not getSelectedSpriteReference() then
      return false
   end
   if spriteId == selectedSpriteId then
      setStatus(tr('This frame already uses sprite %d.', spriteId))
      return false
   end

   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before replacing this frame sprite?'), function()
         replaceSelectedFrameWithSprite(spriteId, true)
      end)
      return false
   end

   return linkSpriteToSelectedFrame(spriteId)
end

importPngAsNewSprite = function()
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before importing a sprite.'))
      return
   end
   local path = window:recursiveGetChildById('previewSpritePathEdit'):getText()
   if path == '' then
      setStatus(tr('Enter the absolute PNG path in the Import PNG section.'))
      window:recursiveGetChildById('previewSpritePathEdit'):focus()
      return
   end
   local category = selectedAppearanceCategory
   local appearanceId = selectedAppearanceId
   local frameGroupIndex, spriteIndex = getSelectedSpriteReference()
   if not frameGroupIndex then
      return
   end
   local previewSelection = capturePreviewSelection()
   local imported, spriteId = pcall(g_spriteAppearances.importSpriteForAppearance, selectedSpriteId, path, activeVersion)
   if not imported then
      setStatus(getUserFacingError(spriteId))
      return
   end
   if not reloadAssets() then
      setStatus(tr('PNG was imported as sprite %d, but the work copy could not be reloaded. The current link is unchanged.', spriteId))
      return
   end

   local linked, result = pcall(g_things.replaceAppearanceSprite, activeVersion, category,
      appearanceId, frameGroupIndex, spriteIndex, spriteId)
   if not linked then
      setStatus(tr('PNG was imported as sprite %d, but it could not be linked: %s', spriteId, getUserFacingError(result)))
      return
   end
   if not refreshAfterSpriteReferenceChange(category, appearanceId, previewSelection) then
      return
   end
   setStatus(tr('PNG imported as sprite %d and linked to this frame.', spriteId))
end

function replaceSprite(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before replacing this frame sprite?'), function()
         replaceSprite(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before replacing a sprite.'))
      return
   end
   if not getSelectedSpriteReference() then
      return
   end

   setActivePage('import')
   setImportSection('replace')
   setReplaceMode(currentReplaceMode)
end

local function saveExternalEditorPath(path)
   local editorPath = path:gsub('^%s+', ''):gsub('%s+$', '')
   if editorPath == '' or not g_platform.fileExists(editorPath) then
      setStatus(tr('Choose an existing editor executable or launcher path.'))
      return false
   end

   g_settings.setValue(EXTERNAL_EDITOR_SETTING, editorPath)
   if not g_settings.save() then
      setStatus(tr('The editor path was set for this session but could not be saved.'))
   else
      setStatus(tr('External editor saved: %s', editorPath))
   end
   return true
end

function configureSpriteEditor(onConfigured)
   if not g_platform.isDesktop() then
      setStatus(tr('External sprite editors are available in desktop builds.'))
      return
   end
   displayInputBox(tr('External sprite editor'),
      tr('Enter the absolute path to an editor executable or launcher. The PNG path will be passed to it.'),
      function(path)
         if saveExternalEditorPath(path) and onConfigured then
            onConfigured(path:gsub('^%s+', ''):gsub('%s+$', ''))
         end
      end, nil, g_settings.getValue(EXTERNAL_EDITOR_SETTING), 1024)
end

local function launchSpriteInEditor(editorPath, pngPath)
   local ok, launched = pcall(g_platform.spawnProcess, editorPath, { pngPath })
   if not ok or not launched then
      setStatus(tr('Could not start the external editor. Check its executable path.'))
      return false
   end
   setStatus(tr('Editing sprite %d in the external editor. Save the PNG there, then return and apply it.',
      pendingSpriteEdit.spriteId))
   return true
end

function editSprite(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before opening the sprite editor?'), function()
         editSprite(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() or not selectedSpriteId then
      setStatus(tr('Select a sprite in an offline 15.x work copy before editing it.'))
      return
   end
   if not g_platform.isDesktop() then
      setStatus(tr('External sprite editors are available in desktop builds.'))
      return
   end
   if pendingSpriteEdit and (pendingSpriteEdit.spriteId ~= selectedSpriteId or
         pendingSpriteEdit.version ~= activeVersion) then
      setStatus(tr('Apply the pending edit for sprite %d before opening another sprite.', pendingSpriteEdit.spriteId))
      return
   end

   local pngPath
   if pendingSpriteEdit then
      pngPath = pendingSpriteEdit.path
   else
      local writeRoot = g_resources.getWriteDir()
      if not writeRoot or writeRoot == '' then
         setStatus(tr('Could not find the client profile directory for the temporary PNG.'))
         return
      end
      writeRoot = writeRoot:gsub('[\\/]+$', '')
      local fileName = string.format('otclient-sprite-editor-%d-%d-%d-%d.png',
         g_platform.getProcessId(), activeVersion, selectedSpriteId, g_clock.millis())
      pngPath = string.format('%s/%s', writeRoot, fileName)
      local saved, errorMessage = pcall(g_spriteAppearances.saveSpriteToFile, selectedSpriteId, fileName)
      if not saved or not g_platform.fileExists(pngPath) then
         setStatus(saved and tr('Could not create the temporary PNG for this sprite.') or getUserFacingError(errorMessage))
         return
      end
      pendingSpriteEdit = {
         spriteId = selectedSpriteId,
         version = activeVersion,
         path = pngPath,
         width = canvas:getSpriteWidth(),
         height = canvas:getSpriteHeight(),
      }
      updateSpriteReplacementTarget()
   end

   local editorPath = g_settings.getValue(EXTERNAL_EDITOR_SETTING)
   if editorPath == '' then
      configureSpriteEditor(function(path)
         launchSpriteInEditor(path, pngPath)
      end)
      return
   end
   launchSpriteInEditor(editorPath, pngPath)
end

function applyEditedSprite(forceDiscard, confirmed, closeAfterApply)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before applying the edited sprite?'), function()
         applyEditedSprite(true)
      end)
      return
   end
   if not pendingSpriteEdit then
      setStatus(tr('Open a sprite in the external editor before applying an edit.'))
      return
   end
   if not activeVersion or g_game.isOnline() or activeVersion ~= pendingSpriteEdit.version then
      setStatus(tr('Reopen the matching offline 15.x work copy before applying this sprite edit.'))
      return
   end
   if not confirmed then
      local edit = pendingSpriteEdit
      local dialog
      dialog = displayGeneralBox(tr('Apply edited sprite'),
         tr('Update sprite %d in the work copy? Every appearance sharing this sprite will change; installed assets remain untouched.', edit.spriteId), {
            { text = tr('Apply to work copy'), callback = function()
               dialog:ok()
               applyEditedSprite(true, true)
            end },
            { text = tr('Cancel'), callback = function() dialog:cancel() end },
         })
      return
   end

   local edit = pendingSpriteEdit
   local category = selectedAppearanceCategory
   local appearanceId = selectedAppearanceId
   local previewSelection = capturePreviewSelection()
   local imported, result = pcall(g_spriteAppearances.importSpriteFromFile,
      edit.spriteId, edit.path, edit.version)
   if not imported then
      local errorMessage = getUserFacingError(result)
      if errorMessage:find('prepared PNG dimensions must match the selected sprite', 1, true) then
         errorMessage = tr('Sprite %d needs a %d x %d PNG. The working copy was not changed.',
            edit.spriteId, edit.width, edit.height)
      end
      setStatus(errorMessage)
      return
   end
   if not reloadAssets() then
      setStatus(tr('Sprite %d was written, but the work copy could not be reloaded. The edited PNG was kept.', edit.spriteId))
      return
   end
   if category ~= nil and appearanceId ~= nil then
      refreshAppearanceCatalog(category)
      if loadAppearanceRecord(category, appearanceId, true, true) then
         restorePreviewSelection(previewSelection)
      end
   end

   pendingSpriteEdit = nil
   pcall(g_platform.removeFile, edit.path)
   updateSpriteReplacementTarget()
   setStatus(tr('Sprite %d was updated in the work copy. All appearances sharing this sprite use the edited image.', edit.spriteId))
   if closeAfterApply then
      requestClose(true, true)
   end
end

function createAppearance(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before creating an appearance?'), function()
         createAppearance(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before creating an appearance.'))
      return
   end
   local category = selectedOption(window:recursiveGetChildById('newAppearanceCategory'))
   local sourceMode = currentNewAppearanceSourceMode
   if not category then
      setStatus(tr('Choose an appearance category.'))
      return
   end

   local spriteId
   local importedNewSprite = false
   if sourceMode == 'png' then
      local path = window:recursiveGetChildById('newAppearancePngPathEdit'):getText()
      if path == '' then
         setStatus(tr('Choose a PNG file first.'))
         return
      end
      local imported, result = pcall(g_spriteAppearances.importSpriteFromFile, 0, path, activeVersion)
      if not imported then
         setStatus(getUserFacingError(result))
         return
      end
      spriteId = result
      importedNewSprite = true
      if not reloadAssets() then
         displayErrorBox(tr('Assets Editor'), tr('Sprite %d was imported, but the work copy could not be reloaded.', spriteId))
         return
      end
   elseif sourceMode == 'sprite' then
      spriteId = selectedCreateSpriteId
      if not spriteId or spriteId < 1 or spriteId > MAX_SPRITE_ID then
         setStatus(tr('Search for a sprite ID and select its thumbnail first.'))
         return
      end
   else
      setStatus(tr('Choose a PNG file or an existing sprite ID.'))
      return
   end

   local created, appearanceId = pcall(g_things.createAppearanceFromSprite,
      activeVersion, category, spriteId)
   if not created then
      if importedNewSprite then reloadAssets() end
      setStatus(tr('Sprite %d is ready, but the appearance could not be created: %s', spriteId, getUserFacingError(appearanceId)))
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('Appearance %d was created, but the work copy could not be reloaded.', appearanceId))
      return
   end

   window:recursiveGetChildById('newAppearancePngPathEdit'):setText('')
   selectedCreateSpriteId = nil
   window:recursiveGetChildById('newAppearanceCategory'):setCurrentOptionByData(category, true)
   updateSpriteReplacementTarget()
   refreshAppearanceCatalog(category)
   loadAppearanceRecord(category, appearanceId, true)
   selectSprite(spriteId)
   showEditorPage()
   setStatus(tr('Created appearance %d with sprite %d.', appearanceId, spriteId))
end

collectAnimationWidgetChanges = function()
   if not animationWidgets.groupIndex then
      return true
   end

   local group = previewFrameGroups[animationWidgets.groupIndex + 1]
   if not group or not group.animation.enabled then
      return true
   end

   for field, edit in pairs(animationWidgets.fields or {}) do
      local value = tonumber(edit:getText())
      if not value or value < 0 or value % 1 ~= 0 or value > 4294967295 then
         setAppearanceStatus(tr('Animation values must be non-negative 32-bit integers.'))
         return false
      end
      if field == 'defaultStartPhase' and value >= group.phaseCount then
         setAppearanceStatus(tr('Default phase must be within the frame group.'))
         return false
      end
      setAnimationChange(animationWidgets.groupIndex, field, value)
   end

   local phaseFields = animationWidgets.phaseFields
   if phaseFields then
      local durationMin = tonumber(phaseFields.durationMin:getText())
      local durationMax = tonumber(phaseFields.durationMax:getText())
      if not durationMin or not durationMax or durationMin < 0 or durationMax < 0 or
            durationMin % 1 ~= 0 or durationMax % 1 ~= 0 or
            durationMin > 4294967295 or durationMax > 4294967295 then
         setAppearanceStatus(tr('Frame durations must be non-negative 32-bit integers.'))
         return false
      end
      if durationMin > durationMax then
         setAppearanceStatus(tr('Minimum frame duration cannot exceed maximum duration.'))
         return false
      end
      setAnimationChange(animationWidgets.groupIndex, 'durationMin', durationMin, animationWidgets.phaseIndex)
      setAnimationChange(animationWidgets.groupIndex, 'durationMax', durationMax, animationWidgets.phaseIndex)
   end
   return true
end

function saveAppearanceProperties()
   if not appearanceOriginal or not activeVersion or g_game.isOnline() then
      return
   end
   for key, edit in pairs(appearanceValueWidgets) do
      local value = tonumber(edit:getText())
      if not value or value < 0 or value % 1 ~= 0 then
         setAppearanceStatus(tr('Appearance values must be non-negative integers.'))
         return
      end
      if value == appearanceOriginal.values[key] then
         appearanceChanges.values[key] = nil
      else
         appearanceChanges.values[key] = value
      end
   end
   for key, edit in pairs(appearanceStringWidgets) do
      local value = edit:getText()
      if value == (appearanceOriginal[key] or '') then
         appearanceChanges.strings[key] = nil
      else
         appearanceChanges.strings[key] = value
      end
   end
   if not collectAnimationWidgetChanges() then
      return
   end
   if not hasAppearanceChanges() then
      setAppearanceStatus(tr('There are no appearance changes to save.'))
      return
   end

   local previewSelection = capturePreviewSelection()
   local updates = {}
   for section, values in pairs(appearanceChanges) do
      local hasSectionChanges = section == 'animation' and next(values.groups) ~= nil or
         section ~= 'animation' and next(values) ~= nil
      if hasSectionChanges then
         updates[section] = values
      end
   end
   local ok, err = pcall(g_things.saveAppearanceEditorData,
      activeVersion, selectedAppearanceCategory, selectedAppearanceId, json.encode(updates))
   if not ok then
      setAppearanceStatus(getUserFacingError(err))
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('Properties were saved, but the work copy could not be reloaded.'))
      return
   end
   refreshAppearanceCatalog(selectedAppearanceCategory)
   if not loadAppearanceRecord(selectedAppearanceCategory, selectedAppearanceId, true, true) then
      setAppearanceStatus(tr('Changes were saved, but the appearance could not be reloaded.'))
      return
   end
   restorePreviewSelection(previewSelection)
   setAppearanceStatus(tr('Appearance %d saved to the work copy.', selectedAppearanceId))
end

function exportWorkCopy(forceContinue, confirmed)
   if hasAppearanceChanges() and not forceContinue then
      local messageBox
      local function saveAndExport()
         messageBox:ok()
         saveAppearanceProperties()
         if not hasAppearanceChanges() then
            exportWorkCopy(true, false)
         end
      end
      local function cancelMessageBox()
         messageBox:cancel()
      end
      messageBox = displayGeneralBox(tr('Unsaved appearance properties'), tr('Save or discard the pending changes before exporting the work copy.'), {
         { text = tr('Save and continue'), callback = saveAndExport },
         { text = tr('Discard edits'), callback = function()
            messageBox:ok()
            resetAppearanceDraft()
            exportWorkCopy(true, false)
         end },
         { text = tr('Cancel'), callback = cancelMessageBox },
      }, saveAndExport, cancelMessageBox)
      return
   end
   if not activeVersion or g_game.isOnline() then
      window:recursiveGetChildById('exportStatus'):setText(tr('Load an offline 15.x work copy before exporting.'))
      return
   end
   if not confirmed then
      local messageBox
      local function cancelInstall()
         messageBox:cancel()
      end
      local function confirmInstall()
         messageBox:ok()
         exportWorkCopy(true, true)
      end
      messageBox = displayGeneralBox(tr('Replace installed client assets?'),
         tr('This installs the full working copy into data/things/%d. The current package is first preserved in data/things/backup, then the editor reloads appearances and static data. Use this copy when you next enter a world.', activeVersion), {
            { text = tr('Export and replace'), callback = confirmInstall },
            { text = tr('Cancel'), callback = cancelInstall },
         }, cancelInstall, cancelInstall)
      return
   end

   local mountedRoot = activeWorkRoot
   local unmountOk, wasMounted = unmountWorkRoot(mountedRoot)
   if not unmountOk then
      window:recursiveGetChildById('exportStatus'):setText(tr('Could not unmount the working copy before installing assets.'))
      return
   end

   local ok, backupPath = pcall(g_spriteAppearances.installWorkCopy, activeVersion)
   local remountOk = restoreWorkRoot(mountedRoot, wasMounted)
   if not remountOk then
      local message = ok and tr('Assets were installed, but the working copy could not be remounted. Backup: %s', backupPath) or
         tr('%s The working copy could not be remounted.', getUserFacingError(backupPath))
      window:recursiveGetChildById('exportStatus'):setText(message)
      displayErrorBox(tr('Assets Editor'), message)
      return
   end
   if not ok then
      window:recursiveGetChildById('exportStatus'):setText(getUserFacingError(backupPath))
      return
   end
   if not reloadAssets() then
      local message = tr('Assets were installed, but the editor could not reload them. Backup: %s', backupPath)
      window:recursiveGetChildById('exportStatus'):setText(message)
      displayErrorBox(tr('Assets Editor'), message)
      return
   end

   refreshAppearanceCatalog(selectedAppearanceCategory)
   if selectedAppearanceId then
      loadAppearanceRecord(selectedAppearanceCategory, selectedAppearanceId, true, true)
   end
   local status = tr('Assets installed and reloaded. Backup: %s', backupPath)
   window:recursiveGetChildById('exportStatus'):setText(status)
   setStatus(tr('Client %s is installed and reloaded.', formatClientVersion(activeVersion)))
end

function reloadPackage()
   if not activeVersion or g_game.isOnline() then
      return
   end
   if hasAppearanceChanges() then
      confirmUnsavedChanges(tr('Save changes before reloading the work copy?'), function()
         reloadPackageNow()
      end)
      return
   end
   reloadPackageNow()
end

function reloadPackageNow()
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('Could not reload the selected work copy.'))
      return
   end
   refreshAppearanceCatalog(selectedAppearanceCategory)
   if selectedAppearanceId then
      loadAppearanceRecord(selectedAppearanceCategory, selectedAppearanceId, true, true)
   end
   setStatus(tr('Work copy reloaded from disk.'))
end

function requestClose(forceDiscard, pendingEditConfirmed)
   if not window then
      return
   end
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes to the working copy before closing?'), function()
         requestClose(true, pendingEditConfirmed)
      end)
      return
   end
   if pendingSpriteEdit and not pendingEditConfirmed then
      local edit = pendingSpriteEdit
      local messageBox
      local function keepEditing()
         messageBox:cancel()
      end
      local function applyEditAndClose()
         messageBox:ok()
         applyEditedSprite(true, true, true)
      end
      local function discardEditAndClose()
         messageBox:ok()
         if pendingSpriteEdit then
            pcall(g_platform.removeFile, pendingSpriteEdit.path)
            pendingSpriteEdit = nil
            updateSpriteReplacementTarget()
         end
         requestClose(true, true)
      end
      messageBox = displayGeneralBox(tr('Pending sprite edit'),
         tr('Sprite %d has a temporary PNG open in the external editor. Save it there before applying, or discard the temporary edit before closing.', edit.spriteId), {
            { text = tr('Apply edit and close'), callback = applyEditAndClose },
            { text = tr('Discard edit and close'), callback = discardEditAndClose },
            { text = tr('Keep editing'), callback = keepEditing },
         }, keepEditing, keepEditing)
      return
   end
   if activeVersion then
      local released, err = releaseActiveWorkCopy()
      if not released then
         displayErrorBox(tr('Assets Editor'), err)
         return
      end
   end
   destroyWindow()
end
