local window
local topMenuButton
local canvas
local workCopyService
local activeVersion
local activeAssetPath
local activeWorkRoot
local selectedAppearanceCategory = 0
local selectedAppearanceId
local selectedSpriteId
local appearanceCatalog
local appearanceProperties
local appearanceOriginal
local appearanceChanges = { bools = {}, values = {}, strings = {}, textValues = {}, multiValues = {}, animation = { groups = {} } }
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
local previewAnimationPlayer
local timelineScrubbing = false
local selectedSpriteContext
local gameStartCallback
local gameEndCallback
local pendingSpriteEdit
local preparedSpritePath = ''
local settingSpritePath = false
local spritePickerSourceId
local selectedReplacementSpriteId
local selectedCreateSpriteId
local spritePicker
local currentImportSection = 'replace'
local currentReplaceMode = 'sprite'
local currentNewAppearanceSourceMode = 'sprite'
local currentExportMode = 'replace'
local pngFilePicker

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
local PREVIEW_CONTROLS_BOTTOM_MARGIN = 14
local PREVIEW_CANVAS_BOTTOM_MARGIN = 4
local PREVIEW_HINT_BOTTOM_MARGIN = 8
local MAX_PREVIEW_TIMELINE_FRAMES = 20
local PREVIEW_TIMELINE_HEIGHT = 100
local PREVIEW_TIMELINE_ONLY_HEIGHT = 56
local PREVIEW_TIMELINE_CELL_WIDTH = 30
local PREVIEW_TIMELINE_TRACK_HEIGHT = 22
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

local selectAppearance
local selectSprite
local renderAppearanceRows
local configurePreviewControls
local updateAnimationEditor
local stopPreviewAnimation
local updatePreviewTimelineSelection
local selectPreviewPhase
local updatePreviewPatternControls
local refreshAppearancePreview
local collectAnimationWidgetChanges
local updateDirectionPadLayout
local refreshSpritePicker
local renderSpritePickerRows
local applySpritePickerFilter
local refreshAppearanceCatalog
local applyAppearanceFilter
local updateCategoryOptions
local updateExportControls
local importPngAsNewSprite
local selectSpritePickerSprite
local linkSpriteToSelectedFrame
local replaceSelectedFrameWithSprite
local updateSpriteReplacementTarget
local getAppearancePropertiesEditor

local function getSpritePickerWidget(name)
   if not window then
      return nil
   end
   local section = currentImportSection
   if name:sub(1, 7) == 'create_' then
      section = 'create'
      name = name:sub(8)
   end
   local ids = SPRITE_PICKER_WIDGET_IDS[section]
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
      window:recursiveGetChildById('statusLabel'):setText(tr('Status: %s', message))
   end
end

local function getWorkCopyService()
   if not workCopyService then
      workCopyService = SpriteEditorWorkCopyService.new()
   end
   return workCopyService
end

local function getAppearanceCatalogComponent()
   if appearanceCatalog then
      return appearanceCatalog
   end

   appearanceCatalog = SpriteEditorAppearanceCatalog.new(categories, {
      get_widget = function(id)
         return window and window:recursiveGetChildById(id) or nil
      end,
      get_window = function() return window end,
      get_active_version = function() return activeVersion end,
      get_selected_category = function() return selectedAppearanceCategory end,
      get_selected_appearance_id = function() return selectedAppearanceId end,
      select_appearance = function(category, id)
         selectAppearance(category, id)
      end,
      on_filter_change = function()
         if updateExportControls then
            updateExportControls()
         end
      end,
   })
   return appearanceCatalog
end

renderAppearanceRows = function(scrollY)
   getAppearanceCatalogComponent():render_rows(scrollY)
end

refreshAppearanceCatalog = function(category)
   getAppearanceCatalogComponent():refresh(category)
end

applyAppearanceFilter = function()
   getAppearanceCatalogComponent():apply_filter()
end

updateCategoryOptions = function()
   getAppearanceCatalogComponent():update_category_options()
end

local function getFilteredAppearanceEntry(index)
   return getAppearanceCatalogComponent():get_filtered_entry(index)
end

local function getAppearanceEntryCount()
   return getAppearanceCatalogComponent():get_entry_count()
end

local function getSpritePickerComponent()
   if spritePicker then
      return spritePicker
   end

   spritePicker = SpriteEditorSpritePicker.new({
      get_widget = getSpritePickerWidget,
      get_window = function() return window end,
      get_active_version = function() return activeVersion end,
      get_section = function() return currentImportSection end,
      get_selected_id = getSelectedSpritePickerId,
      get_selected_frame_sprite_id = function() return selectedSpriteId end,
      get_canvas = function() return canvas end,
      clear_selection = function() setSelectedSpritePickerId(nil) end,
      select_sprite = function(spriteId)
         setSelectedSpritePickerId(spriteId)
         updateSpriteReplacementTarget()
      end,
      set_status = function(message) setStatus(message) end,
   })
   return spritePicker
end

refreshSpritePicker = function()
   getSpritePickerComponent():refresh()
end

renderSpritePickerRows = function(scrollY)
   getSpritePickerComponent():render_rows(scrollY)
end

applySpritePickerFilter = function()
   getSpritePickerComponent():apply_filter()
end

selectSpritePickerSprite = function(spriteId)
   getSpritePickerComponent():select(spriteId)
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

local function parseClientVersion(value)
   local major, minor = tostring(value):match('^%s*(%d+)%.(%d%d)%s*$')
   if tonumber(major) ~= 15 or not minor then
      return nil
   end
   return 1500 + tonumber(minor)
end

local function getVersionDirectories()
   local directories = {}
   for _, entry in ipairs(g_resources.listDirectoryFiles('/data/things/')) do
      local version = tonumber(entry)
      if version and version >= 1500 and version < 1600 and version % 1 == 0 then
         directories[version] = true
      end
   end
   return directories
end

local function getNextAvailableVersion(sourceVersion)
   local directories = getVersionDirectories()
   for version = sourceVersion + 1, 1599 do
      if version ~= sourceVersion and not directories[version] then
         return version
      end
   end
   for version = 1500, sourceVersion - 1 do
      if not directories[version] then
         return version
      end
   end
   return nil
end

local function hasAppearanceChanges()
   if next(appearanceChanges.bools) ~= nil or
         next(appearanceChanges.values) ~= nil or
         next(appearanceChanges.strings) ~= nil or
         next(appearanceChanges.textValues) ~= nil or
         next(appearanceChanges.multiValues) ~= nil or
         next(appearanceChanges.animation.groups) ~= nil then
      return true
   end

   if not appearanceOriginal then
      return false
   end

   if appearanceProperties and appearanceProperties:has_widget_changes() then
      return true
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
   appearanceChanges = { bools = {}, values = {}, strings = {}, textValues = {}, multiValues = {}, animation = { groups = {} } }
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

getAppearancePropertiesEditor = function()
   if appearanceProperties then
      return appearanceProperties
   end

   appearanceProperties = SpriteEditorAppearanceProperties.new({
      get_widget = function(id)
         return window and window:recursiveGetChildById(id) or nil
      end,
      get_category = function() return selectedAppearanceCategory end,
      get_original = function() return appearanceOriginal end,
      get_changes = function() return appearanceChanges end,
      is_building = function() return buildingAppearanceProperties end,
      update = updateAppearanceSaveButton,
      set_status = setAppearanceStatus,
   })
   return appearanceProperties
end

local function setSpritePath(path)
   if not window then
      return
   end
   settingSpritePath = true
   window:recursiveGetChildById('previewSpritePathEdit'):setText(path or '')
   settingSpritePath = false
end

local function destroyPngFilePicker()
   if pngFilePicker then
      pngFilePicker:destroy()
   end
end

function closePngFilePicker()
   destroyPngFilePicker()
end

local function createPngFilePicker()
   pngFilePicker = SpriteEditorPngFilePicker.new({
      on_status = setStatus,
      on_selected = function(target, path)
         if target == 'export' then
            window:recursiveGetChildById('exportFolderEdit'):setText(path)
            updateExportControls()
            setStatus(tr('Export destination selected: %s', path))
            return
         end
         if target == 'batch' then
            window:recursiveGetChildById('batchPngFolderEdit'):setText(path)
            updateSpriteReplacementTarget()
            setStatus(tr('PNG folder selected: %s', path))
            return
         end
         if target == 'appearanceImport' then
            window:recursiveGetChildById('appearanceBundlePathEdit'):setText(path)
            setStatus(tr('Appearance bundle selected: %s', path:match('([^/]+)$') or path))
            return
         end
         if target == 'appearanceExport' then
            window:recursiveGetChildById('exportFolderEdit'):setText(path)
            updateExportControls()
            setStatus(tr('Appearance bundle destination selected: %s', path))
            return
         end
         if target == 'sheet' then
            window:recursiveGetChildById('spriteSheetPathEdit'):setText(path)
            updateSpriteReplacementTarget()
            setStatus(tr('Sprite sheet selected: %s', path:match('([^/]+)$') or path))
            return
         end
         if target == 'create' then
            window:recursiveGetChildById('newAppearancePngPathEdit'):setText(path)
            setStatus(tr('PNG selected for the new appearance: %s', path:match('([^/]+)$') or path))
            return
         end

         preparedSpritePath = path
         setSpritePath(path)
         updateSpriteReplacementTarget()
         setStatus(tr('PNG selected: %s', path:match('([^/]+)$') or path))
      end,
   })
end

function openPngFilePicker(target)
   target = target or 'replace'
   if target ~= 'replace' and target ~= 'create' and target ~= 'export' and target ~= 'batch' and
         target ~= 'sheet' and target ~= 'appearanceImport' and target ~= 'appearanceExport' then
      return
   end
   local isExportTarget = target == 'export' or target == 'appearanceExport'
   if not window or (not isExportTarget and not activeVersion) or g_game.isOnline() or
         (target == 'replace' and not selectedSpriteId) then
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
   if not pngFilePicker then
      createPngFilePicker()
   end

   local pathEditId = target == 'create' and 'newAppearancePngPathEdit' or
      ((target == 'export' or target == 'appearanceExport') and 'exportFolderEdit' or
         (target == 'appearanceImport' and 'appearanceBundlePathEdit' or
            (target == 'batch' and 'batchPngFolderEdit' or
               (target == 'sheet' and 'spriteSheetPathEdit' or 'previewSpritePathEdit'))))
   local existingPath = window:recursiveGetChildById(pathEditId):getText()
   pngFilePicker:open(target, existingPath)
end

function openExportFolderPicker()
   openPngFilePicker(currentExportMode == 'appearance' and 'appearanceExport' or 'export')
end

function openAppearanceBundleExportPicker()
   openPngFilePicker('appearanceExport')
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
   local showBatch = showImport and currentImportSection == 'batch'
   local showSheet = showImport and currentImportSection == 'sheet'
   local showBundle = showImport and currentImportSection == 'bundle'
   if spritePickerSourceId ~= selectedSpriteId then
      spritePickerSourceId = selectedSpriteId
      selectedReplacementSpriteId = nil
   end
   local targetPanel = window:recursiveGetChildById('replaceFramePanel')
   targetPanel:setVisible(showReplace)
   window:recursiveGetChildById('newAppearancePanel'):setVisible(showCreate)
   window:recursiveGetChildById('batchPngsPanel'):setVisible(showBatch)
   window:recursiveGetChildById('spriteSheetPanel'):setVisible(showSheet)
   window:recursiveGetChildById('appearanceBundlePanel'):setVisible(showBundle)
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
   window:recursiveGetChildById('replaceFrameTabButton'):setOn(currentImportSection == 'replace')
   window:recursiveGetChildById('newAppearanceTabButton'):setOn(currentImportSection == 'create')
   window:recursiveGetChildById('batchPngsTabButton'):setOn(currentImportSection == 'batch')
   window:recursiveGetChildById('spriteSheetTabButton'):setOn(currentImportSection == 'sheet')
   window:recursiveGetChildById('newAppearanceSpriteSearchEdit'):setEnabled(canEditAssets)
   window:recursiveGetChildById('newAppearanceCategory'):setEnabled(canEditAssets)
   local batchFolderEdit = window:recursiveGetChildById('batchPngFolderEdit')
   batchFolderEdit:setEnabled(canEditAssets)
   window:recursiveGetChildById('batchPngFolderBrowseButton'):setEnabled(canEditAssets and g_platform.isDesktop())
   window:recursiveGetChildById('batchPngImportButton'):setEnabled(
      canEditAssets and batchFolderEdit:getText():trim() ~= '')
   local spriteSheetPathEdit = window:recursiveGetChildById('spriteSheetPathEdit')
   spriteSheetPathEdit:setEnabled(canEditAssets)
   window:recursiveGetChildById('spriteSheetBrowseButton'):setEnabled(canEditAssets and g_platform.isDesktop())
   window:recursiveGetChildById('spriteSheetCellWidth'):setEnabled(canEditAssets)
   window:recursiveGetChildById('spriteSheetCellHeight'):setEnabled(canEditAssets)
   window:recursiveGetChildById('spriteSheetFirstCell'):setEnabled(canEditAssets)
   window:recursiveGetChildById('spriteSheetLastCell'):setEnabled(canEditAssets)
   window:recursiveGetChildById('spriteSheetSkipTransparent'):setEnabled(canEditAssets)
   window:recursiveGetChildById('spriteSheetImportButton'):setEnabled(
      canEditAssets and spriteSheetPathEdit:getText():trim() ~= '')
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
   window:recursiveGetChildById('deleteAppearanceButton'):setEnabled(
      selectedAppearanceId ~= nil and activeVersion ~= nil and not g_game.isOnline() and pendingSpriteEdit == nil)
   window:recursiveGetChildById('createAppearanceShortcutButton'):setEnabled(
      activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('previewHintLabel'):setText(
      showReplace and currentReplaceMode == 'sprite' and
         tr('Drop a sprite here to replace this frame | Wheel over preview: zoom | Middle-drag: pan') or
         tr('Wheel over preview: zoom | Middle-drag: pan | Checkerboard: transparency'))
   if hasTarget then updatePreviewTitle() end
   if renderSpritePickerRows and currentImportSection ~= 'batch' then
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
   local playButton = window:recursiveGetChildById('previewPlayButton')
   local frameRow = window:recursiveGetChildById('previewAnimationFrameRow')
   local frameSelectionGroup = window:recursiveGetChildById('previewFrameSelectionGroup')
   local durationGroup = window:recursiveGetChildById('previewDurationGroup')

   timelinePanel:setVisible(hasFrameControls)
   local panelHeight = showAnimationFrameRow and PREVIEW_TIMELINE_HEIGHT or PREVIEW_TIMELINE_ONLY_HEIGHT
   timelinePanel:setHeight(panelHeight)
   timelineLabel:setVisible(hasFrameControls)
   timeline:setVisible(showFrameButtons)
   timelineScroll:setVisible(showFrameButtons and phaseCount * PREVIEW_TIMELINE_CELL_WIDTH > timeline:getWidth())
   phaseActions:setVisible(hasFrameControls)
   local showPlayButton = hasAnimation and phaseCount > 1
   playButton:setVisible(showPlayButton)
   playButton:setEnabled(showPlayButton)
   phaseActions:setWidth(showPlayButton and 104 or 54)
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

local function buildAppearanceProperties(data)
   clearAppearanceChanges()
   appearanceOriginal = data
   data.values = data.values or {}
   if selectedAppearanceCategory == 0 then
      data.values['clothes.slot'] = data.values['clothes.slot'] or 0
   end
   buildingAppearanceProperties = true
   getAppearancePropertiesEditor():build_fields(data)
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
   getAppearancePropertiesEditor():clear_fields()
   getAppearancePropertiesEditor():set_enabled(false)
   window:recursiveGetChildById('previewTimelineFrames'):destroyChildren()
   setPreviewMessage(tr('Select an appearance to see its sprite.'))
   selectedSpriteId = nil
   selectedSpriteContext = nil
   canvas:setVisible(false)
   setSpritePath(preparedSpritePath)
   updateSpriteReplacementTarget()
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

stopPreviewAnimation = function()
   if previewAnimationPlayer then
      previewAnimationPlayer:stop()
   end
end

updatePreviewTimelineSelection = function(phaseCount)
   if not window then
      return
   end
   local frameList = window:recursiveGetChildById('previewTimelineFrames')
   for index, frameCell in ipairs(frameList:getChildren()) do
      local selected = index - 1 == previewPhase
      local frameButton = frameCell:getChildById('previewTimelineFrameButton')
      frameButton:setOn(selected)
      frameButton:setColor(selected and '#d9c7ff' or '#dfdfdf')
      local thumb = frameCell:recursiveGetChildById('previewTimelineThumb')
      if thumb then
         thumb:setVisible(selected)
      end
   end

   local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
   if phaseStepper then
      local onValueChange = phaseStepper.onValueChange
      phaseStepper.onValueChange = nil
      phaseStepper:setValue(previewPhase + 1, true)
      phaseStepper.onValueChange = onValueChange
   end
   if phaseCount then
      local phaseCountLabel = window:recursiveGetChildById('previewPhaseCount')
      phaseCountLabel:setText(tr('of %d', phaseCount))
   end
   local selectedPhase = previewPhase
   local timelineWindow = window
   addEvent(function()
      if not window or window ~= timelineWindow or not window:isVisible() then
         return
      end
      local timeline = window:recursiveGetChildById('previewTimeline')
      local frameCell = window:recursiveGetChildById('previewTimelineFrames'):getChildByIndex(selectedPhase + 1)
      local ensureChildVisible = UIScrollArea and UIScrollArea.ensureChildVisible
      if timeline and frameCell and ensureChildVisible then
         ensureChildVisible(timeline, frameCell)
      end
   end)
end

local function updatePreviewPhaseDurationFields(group)
   if not group or not group.animation or not group.animation.enabled then
      return
   end
   local phase = group.animation.phases[previewPhase + 1]
   if not phase then
      return
   end
   local groupChanges = appearanceChanges.animation.groups[tostring(group.index)] or {}
   local phaseChanges = groupChanges.phases and groupChanges.phases[tostring(previewPhase)] or {}
   local minEdit = window:recursiveGetChildById('animationDurationMin')
   local maxEdit = window:recursiveGetChildById('animationDurationMax')
   local wasBuildingProperties = buildingAppearanceProperties
   buildingAppearanceProperties = true
   minEdit:setText(tostring(phaseChanges.durationMin ~= nil and phaseChanges.durationMin or phase.durationMin))
   maxEdit:setText(tostring(phaseChanges.durationMax ~= nil and phaseChanges.durationMax or phase.durationMax))
   buildingAppearanceProperties = wasBuildingProperties
   animationWidgets.phaseIndex = previewPhase
end

selectPreviewPhase = function(phaseIndex, playbackTick)
   local group = currentPreviewGroup()
   if not group then
      return false
   end
   if not playbackTick then
      stopPreviewAnimation()
   end
   if not collectAnimationWidgetChanges() then
      return false
   end

   previewPhase = math.max(0, math.min(phaseIndex, math.max(0, (group.phaseCount or 1) - 1)))
   updatePreviewTimelineSelection(group.phaseCount)
   updatePreviewPhaseDurationFields(group)
   return refreshAppearancePreview()
end

local function getPreviewPhaseDuration(group, phaseIndex)
   local phase = group.animation.phases[phaseIndex + 1]
   local groupChanges = appearanceChanges.animation.groups[tostring(group.index)] or {}
   local phaseChanges = groupChanges.phases and groupChanges.phases[tostring(phaseIndex)] or {}
   local minimum = phaseChanges.durationMin ~= nil and phaseChanges.durationMin or phase.durationMin
   local maximum = phaseChanges.durationMax ~= nil and phaseChanges.durationMax or phase.durationMax
   if minimum == 0 and maximum == 0 then
      for _, candidate in ipairs(group.animation.phases) do
         if candidate.durationMin > 0 or candidate.durationMax > 0 then
            minimum = candidate.durationMin
            maximum = candidate.durationMax
            break
         end
      end
   end
   return math.max(1, math.floor((minimum + maximum) / 2))
end

local function getPreviewAnimationPlayer()
   if previewAnimationPlayer then
      return previewAnimationPlayer
   end

   previewAnimationPlayer = SpriteEditorAnimationPlayer.new({
      get_group = currentPreviewGroup,
      get_appearance_id = function() return selectedAppearanceId end,
      get_phase = function() return previewPhase end,
      get_phase_duration = getPreviewPhaseDuration,
      get_group_changes = function(groupIndex)
         return appearanceChanges.animation.groups[tostring(groupIndex)] or {}
      end,
      get_play_button = function()
         return window and window:recursiveGetChildById('previewPlayButton') or nil
      end,
      is_window_visible = function()
         return window ~= nil and window:isVisible()
      end,
      collect_changes = function() return collectAnimationWidgetChanges() end,
      select_phase = function(phaseIndex)
         return selectPreviewPhase(phaseIndex, true)
      end,
   })
   return previewAnimationPlayer
end

function togglePreviewAnimation()
   if window then
      getPreviewAnimationPlayer():toggle()
   end
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
   stopPreviewAnimation()
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

local function buildPatternOptions(comboBox, label, count, selectedIndex, optionLabelForIndex)
   local options = {}
   for index = 0, count - 1 do
      local optionLabel = optionLabelForIndex and optionLabelForIndex(index) or
         string.format('%s %d', label, index + 1)
      table.insert(options, { label = optionLabel, data = index })
   end
   setComboOptions(comboBox, options, math.min(selectedIndex or 0, count - 1))
   comboBox:setVisible(count > 1)
end

local function outfitAddonOptionLabel(index)
   if index == 0 then
      return tr('No addon')
   elseif index == 1 then
      return tr('Addon 1')
   elseif index == 2 then
      return tr('Addon 2')
   elseif index == 3 then
      return tr('Both addons')
   end
   return tr('Addon pattern %d', index + 1)
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

   buildPatternOptions(addonBox, isOutfit and tr('Addon') or tr('Pattern Y'), group.patternHeight,
      previewPatternY, isOutfit and outfitAddonOptionLabel or nil)
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
            table.insert(details, selectedAppearanceCategory == 1 and outfitAddonOptionLabel(previewPatternY) or
               tr('Pattern Y %d', previewPatternY + 1))
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
   stopPreviewAnimation()
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
         stopPreviewAnimation()
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
      selectPreviewPhase(previewPhase, false)
   end
   window:recursiveGetChildById('previewMoving').onCheckChange = function(widget)
      if not previewHasMovementToggle then
         return
      end
      stopPreviewAnimation()
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
   local playButton = window:recursiveGetChildById('previewPlayButton')
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
   local showPlayButton = isAnimated and phaseCount > 1
   playButton:setVisible(showPlayButton)
   playButton:setEnabled(showPlayButton)
   window:recursiveGetChildById('previewPhaseActions'):setWidth(showPlayButton and 104 or 54)
   local previewIsPlaying = previewAnimationPlayer and previewAnimationPlayer:is_playing() or false
   playButton:setText(previewIsPlaying and tr('Pause') or tr('Play'))
   playButton:setTooltip(previewIsPlaying and tr('Pause the animation preview.') or
      tr('Play the animation preview from the selected frame.'))
   playButton:setOn(previewIsPlaying)
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
         local frameCell = g_ui.createWidget('AppearanceTimelineCell', frameList)
         local frameButton = frameCell:getChildById('previewTimelineFrameButton')
         local frameTrack = frameCell:getChildById('previewTimelineTrack')
         frameTrack:setHeight(PREVIEW_TIMELINE_TRACK_HEIGHT)
         frameTrack:setVisible(phaseCount > 1)
         frameButton:setText(tostring(currentPhaseIndex + 1))
         frameButton:setTooltip(tr('Frame %d', currentPhaseIndex + 1))
         frameButton.onMousePress = function(_, _, mouseButton)
            if mouseButton ~= MouseLeftButton then
               return false
            end
            timelineScrubbing = false
            selectPreviewPhase(currentPhaseIndex, false)
            return true
         end
         frameTrack:setTooltip(tr('Drag to scrub through frames.'))
         frameTrack.onMousePress = function(_, _, mouseButton)
            if mouseButton ~= MouseLeftButton then
               return false
            end
            stopPreviewAnimation()
            timelineScrubbing = true
            selectPreviewPhase(currentPhaseIndex, true)
            return true
         end
         frameTrack.onMouseMove = function(_, mousePos)
            if not timelineScrubbing then
               return false
            end
            for index, candidate in ipairs(frameList:getChildren()) do
               local rect = candidate:getRect()
               if mousePos.x >= rect.x and mousePos.x < rect.x + rect.width then
                  if index - 1 ~= previewPhase then
                     selectPreviewPhase(index - 1, true)
                  end
                  return true
               end
            end
            return true
         end
         frameTrack.onMouseRelease = function(_, _, mouseButton)
            if mouseButton == MouseLeftButton then
               timelineScrubbing = false
               return true
            end
            return false
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
   frameList:setWidth(showFrameButtons and math.max(1, phaseCount * PREVIEW_TIMELINE_CELL_WIDTH) or 1)
   updatePreviewTimelineSelection(phaseCount)
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
   updateExportControls()
   return true
end

selectAppearance = function(category, id, forceDiscard)
   stopPreviewAnimation()
   loadAppearanceRecord(category, id, forceDiscard)
end

local function changeAppearanceCategory(category, forceDiscard)
   if not category then
      return
   end
   stopPreviewAnimation()
   if hasAppearanceChanges() and not forceDiscard then
      window:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(selectedAppearanceCategory, true)
      confirmUnsavedChanges(tr('Save changes before switching categories?'), function()
         changeAppearanceCategory(category, true)
      end)
      return
   end
   selectedAppearanceCategory = category
   selectedAppearanceId = nil
   updateExportControls()
   appearanceOriginal = nil
   clearAppearanceChanges()
   local searchEdit = window:recursiveGetChildById('appearanceSearch')
   if searchEdit:getText() ~= '' then
      searchEdit:setText('')
   end
   refreshAppearanceCatalog(category)
   local firstEntry = getFilteredAppearanceEntry(1)
   if firstEntry then
      loadAppearanceRecord(category, firstEntry.id, true)
   else
      clearAppearanceProperties()
      setStatus(getAppearanceEntryCount() > 0 and tr('No appearances match this search.') or
         tr('No appearances in this category.'))
   end
end

local function reloadAssets()
   if not activeAssetPath then
      return false
   end
   if not getWorkCopyService():reload(activeAssetPath) then
      return false
   end
   if refreshSpritePicker then refreshSpritePicker() end
   return true
end

local function releaseActiveWorkCopy()
   if not activeVersion then
      return true
   end

   local released, err = getWorkCopyService():release(activeVersion, activeWorkRoot, activeAssetPath)
   if not released then
      return false, getUserFacingError(err)
   end

   activeVersion = nil
   activeAssetPath = nil
   activeWorkRoot = nil
   return true
end

updateExportControls = function()
   if not window then
      return
   end

   local offline = not g_game.isOnline()
   local canExport = activeVersion ~= nil and offline
   local isNewVersion = currentExportMode == 'new'
   local isFolderExport = currentExportMode == 'folder'
   local isAppearanceExport = currentExportMode == 'appearance'
   local isDirectoryExport = isFolderExport or isAppearanceExport
   local canExportAppearance = canExport and selectedAppearanceId ~= nil and selectedAppearanceCategory ~= nil
   local batchAppearanceIds, filteredAppearanceCount = getAppearanceCatalogComponent():get_filtered_ids(8)
   local selectedVersion = selectedOption(window:recursiveGetChildById('versionComboBox'))
   local targetVersion = parseClientVersion(window:recursiveGetChildById('newVersionEdit'):getText())
   local destinationRoot = window:recursiveGetChildById('exportFolderEdit'):getText():trim()
   local isAbsoluteDestination = destinationRoot:sub(1, 1) == '/' or destinationRoot:match('^%a:[/\\]') ~= nil or
      destinationRoot:match('^[/\\][/\\]') ~= nil
   local versionDirectories = getVersionDirectories()
   local newVersionValid = targetVersion ~= nil and targetVersion ~= activeVersion and
      not versionDirectories[targetVersion]
   local folderDestinationValid = isAbsoluteDestination and activeVersion ~= nil

   window:recursiveGetChildById('replaceVersionModeButton'):setOn(not isNewVersion and not isFolderExport and not isAppearanceExport)
   window:recursiveGetChildById('newVersionModeButton'):setOn(isNewVersion)
   window:recursiveGetChildById('exportFolderModeButton'):setOn(isFolderExport)
   window:recursiveGetChildById('exportAppearanceModeButton'):setOn(isAppearanceExport)
   window:recursiveGetChildById('replaceVersionModeButton'):setEnabled(canExport)
   window:recursiveGetChildById('newVersionModeButton'):setEnabled(canExport)
   window:recursiveGetChildById('exportFolderModeButton'):setEnabled(canExport)
   window:recursiveGetChildById('exportAppearanceModeButton'):setEnabled(canExportAppearance)
   window:recursiveGetChildById('targetVersionLabel'):setText(isNewVersion and
      tr('New version (15.x)') or tr('Replace current version'))
   window:recursiveGetChildById('targetVersionLabel'):setVisible(not isDirectoryExport)
   window:recursiveGetChildById('newVersionEdit'):setEnabled(canExport and isNewVersion)
   window:recursiveGetChildById('newVersionEdit'):setVisible(isNewVersion)
   window:recursiveGetChildById('exportFolderEdit'):setEnabled(canExport and isDirectoryExport)
   window:recursiveGetChildById('exportFolderEdit'):setVisible(isDirectoryExport)
   window:recursiveGetChildById('exportFolderBrowseButton'):setEnabled(canExport and isDirectoryExport and g_platform.isDesktop())
   window:recursiveGetChildById('exportFolderBrowseButton'):setVisible(isDirectoryExport)
   local sourceCategory = categories[(selectedAppearanceCategory or -1) + 1]
   window:recursiveGetChildById('exportSourceLabel'):setText(isAppearanceExport and selectedAppearanceId and
      tr('Selected: %s %d', sourceCategory and tr(sourceCategory.singular) or tr('Appearance'), selectedAppearanceId) or
      (activeVersion and tr('Source version: %s', formatClientVersion(activeVersion)) or tr('No assets version loaded.')))
   local category = categories[(selectedAppearanceCategory or -1) + 1]
   local categoryName = category and category.name:lower() or 'appearance'
   local installTarget = isFolderExport and
      (folderDestinationValid and string.format('%s/data/things/%d', destinationRoot, activeVersion) or
         tr('Choose an absolute destination folder.')) or
      (isAppearanceExport and (folderDestinationValid and
         string.format('%s/appearance-%s-%d', destinationRoot, categoryName:lower(), selectedAppearanceId or 0) or
         tr('Choose an absolute destination folder.')) or
      (isNewVersion and (newVersionValid and string.format('data/things/%d', targetVersion) or
         tr('Enter a valid, unused 15.x version.')) or
         (activeVersion and string.format('data/things/%d', activeVersion) or tr('No install destination.'))))
   window:recursiveGetChildById('installTargetLabel'):setText(installTarget)
   local exportButton = window:recursiveGetChildById('exportButton')
   exportButton:setText(isAppearanceExport and tr('Export appearance bundle') or
      (isFolderExport and tr('Copy assets to folder') or
         (isNewVersion and tr('Install as new version') or
            tr('Replace %s', activeVersion and formatClientVersion(activeVersion) or ''))))
   window:recursiveGetChildById('exportHint'):setText(isFolderExport and
      tr('Creates a data/things/%d package. Existing packages are never overwritten.', activeVersion or 0) or
      (isAppearanceExport and tr('Includes appearance metadata and referenced sprites. Batch export follows the left list filter and handles up to 8 appearances.') or
         (isNewVersion and tr('The source stays unchanged. Choose an unused version to add it to the client.') or
            tr('The current package is backed up before replacement.'))))
   local exportTargetValid = isAppearanceExport and folderDestinationValid or isFolderExport and folderDestinationValid or
      (isNewVersion and newVersionValid) or (not isNewVersion and not isFolderExport)
   if isAppearanceExport then
      exportTargetValid = folderDestinationValid and selectedAppearanceId ~= nil
   end
   exportButton:setEnabled((isAppearanceExport and canExportAppearance or canExport) and exportTargetValid)
   local batchExportButton = window:recursiveGetChildById('exportAppearanceBatchButton')
   batchExportButton:setVisible(isAppearanceExport)
   batchExportButton:setText(filteredAppearanceCount > 8 and tr('Filter to 8 or fewer appearances') or
      tr('Export %d filtered bundle(s)', filteredAppearanceCount))
   batchExportButton:setEnabled(isAppearanceExport and canExport and folderDestinationValid and
      batchAppearanceIds ~= nil)
   window:recursiveGetChildById('loadAssetsButton'):setEnabled(offline and selectedVersion ~= nil)
   window:recursiveGetChildById('importPageButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('exportPageButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('reloadButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('newAppearanceTabButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('appearanceBundleTabButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
end

function setExportMode(mode)
   if mode ~= 'replace' and mode ~= 'new' and mode ~= 'folder' and mode ~= 'appearance' then
      return
   end
   currentExportMode = mode
   if window then
      window:recursiveGetChildById('exportStatus'):setText('')
      updateExportControls()
   end
end

function exportFilteredAppearanceBundles(confirmed)
   if currentExportMode ~= 'appearance' or not activeVersion or g_game.isOnline() or
         selectedAppearanceCategory == nil then
      return
   end
   local ids = getAppearanceCatalogComponent():get_filtered_ids(8)
   if not ids then
      setStatus(tr('Filter the appearance list to 8 or fewer results before batch export.'))
      return
   end
   local destination = window:recursiveGetChildById('exportFolderEdit'):getText():trim()
   local absolute = destination:sub(1, 1) == '/' or destination:match('^%a:[/\\]') ~= nil or
      destination:match('^[/\\][/\\]') ~= nil
   if not absolute then
      setStatus(tr('Choose an absolute destination folder.'))
      return
   end
   if hasAppearanceChanges() then
      confirmUnsavedChanges(tr('Save changes before exporting appearance bundles?'), function()
         exportFilteredAppearanceBundles(true)
      end)
      return
   end
   if not confirmed then
      local box
      local function cancelExport()
         box:cancel()
      end
      local function confirmExport()
         box:ok()
         exportFilteredAppearanceBundles(true)
      end
      box = displayGeneralBox(tr('Export filtered appearances?'),
         tr('Exports %d appearances from the current filtered list to %s. Existing bundle folders are kept unchanged.',
            #ids, destination), {
            { text = tr('Export bundles'), callback = confirmExport },
            { text = tr('Cancel'), callback = cancelExport },
         }, cancelExport, cancelExport)
      return
   end

   local called, response = pcall(g_things.exportAppearanceBundles, activeVersion,
      selectedAppearanceCategory, json.encode(ids), destination)
   if not called then
      setStatus(getUserFacingError(response))
      return
   end
   local decoded, result = pcall(json.decode, response)
   if not decoded or type(result) ~= 'table' or type(result.items) ~= 'table' or
         type(result.failures) ~= 'table' then
      setStatus(tr('The batch bundle export returned an invalid result. Check the client log.'))
      return
   end
   if tonumber(result.exported) == 0 then
      local failure = result.failures[1]
      setStatus(failure and tr('No bundles were exported. Appearance %d: %s', failure.id, failure.error) or
         tr('No appearance bundles were exported.'))
      return
   end
   if tonumber(result.failed) > 0 then
      local failure = result.failures[1]
      setStatus(tr('Exported %d bundle(s); %d failed. First failure for appearance %d: %s',
         result.exported, result.failed, failure.id, failure.error))
   else
      setStatus(tr('Exported %d appearance bundle(s) to %s.', result.exported, destination))
   end
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

   local rightPanel = window:recursiveGetChildById('rightPanel')
   if not rightPanel then
      window:destroy()
      window = nil
      displayErrorBox(tr('Assets Editor'), tr('The editor side panel could not be initialized.'))
      return false
   end
   for _, panelName in ipairs({ 'sprite_editor_properties', 'sprite_editor_import', 'sprite_editor_export' }) do
      local loaded, panel = pcall(g_ui.loadUI, panelName, rightPanel)
      if not loaded or not panel then
         g_logger.error('[game_sprite_editor] Unable to load panel ' .. panelName .. ': ' .. tostring(panel))
         window:destroy()
         window = nil
         displayErrorBox(tr('Assets Editor'), tr('Could not load the editor side panel. Check the client log.'))
         return false
      end
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
   getAppearanceCatalogComponent():attach_window()
   getSpritePickerComponent():attach_window()
   window:recursiveGetChildById('newAppearancePngPathEdit').onTextChange = function(widget)
      window:recursiveGetChildById('createAppearanceButton'):setEnabled(
         activeVersion ~= nil and not g_game.isOnline() and currentNewAppearanceSourceMode == 'png' and
         widget:getText() ~= '')
   end
   window:recursiveGetChildById('batchPngFolderEdit').onTextChange = function()
      updateSpriteReplacementTarget()
   end
   local spriteSheetPathEdit = window:recursiveGetChildById('spriteSheetPathEdit')
   spriteSheetPathEdit.onTextChange = function()
      updateSpriteReplacementTarget()
   end
   for _, id in ipairs({ 'spriteSheetCellWidth', 'spriteSheetCellHeight' }) do
      local sizeBox = window:recursiveGetChildById(id)
      for _, size in ipairs({ 32, 64, 96, 128, 192, 384 }) do
         sizeBox:addOption(tostring(size), size)
      end
      sizeBox:setCurrentOptionByData(64, true)
   end
   window:recursiveGetChildById('spriteSheetFirstCell'):setText('1')
   window:recursiveGetChildById('spriteSheetLastCell'):setText('0')

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
   local newVersionEdit = window:recursiveGetChildById('newVersionEdit')
   local suggestedVersion = activeVersion and getNextAvailableVersion(activeVersion)
   if suggestedVersion then
      newVersionEdit:setText(formatClientVersion(suggestedVersion))
   end
   newVersionEdit.onTextChange = function()
      updateExportControls()
   end
   local exportFolderEdit = window:recursiveGetChildById('exportFolderEdit')
   exportFolderEdit.onTextChange = function()
      updateExportControls()
   end

   setActivePage(currentPage)
   setPropertiesTab(currentPropertiesTab)
   setImportSection(currentImportSection)
   window:show()
   window:raise()
   window:focus()
   if topMenuButton then topMenuButton:setOn(true) end
   if activeVersion then
      refreshAppearanceCatalog(selectedAppearanceCategory)
      refreshSpritePicker()
      local firstEntry = getFilteredAppearanceEntry(1)
      if firstEntry then
         loadAppearanceRecord(selectedAppearanceCategory, firstEntry.id, true)
      end
   else
      clearAppearanceProperties()
   end
   return true
end

local function destroyWindow()
   stopPreviewAnimation()
   timelineScrubbing = false
   destroyPngFilePicker()
   if spritePicker then
      spritePicker:destroy()
   end
   if appearanceProperties then
      appearanceProperties:destroy()
   end
   animationWidgets = {}
   if window then
      window:destroy()
      window = nil
      canvas = nil
   end
   if appearanceCatalog then
      appearanceCatalog:destroy()
   end
   spritePickerSourceId = nil
   selectedReplacementSpriteId = nil
   selectedCreateSpriteId = nil
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
   local loaded, workRoot, assetPath = getWorkCopyService():load(version)
   if not loaded then
      displayErrorBox(tr('Assets Editor'), getUserFacingError(workRoot))
      return false
   end

   activeVersion = version
   activeAssetPath = assetPath
   activeWorkRoot = workRoot
   if appearanceCatalog then
      appearanceCatalog:clear_category_counts()
   end
   selectedAppearanceCategory = 0
   return true
end

function init()
   if not g_spriteAppearances.createWorkCopy then
      return
   end
   g_ui.importStyle('sprite_editor_widgets')
   gameStartCallback = function()
      if topMenuButton then
         topMenuButton:setOn(false)
         topMenuButton:setVisible(false)
      end
      if window then
         stopPreviewAnimation()
         window:hide()
      end
   end
   gameEndCallback = function()
      if topMenuButton then
         topMenuButton:setVisible(true)
         topMenuButton:setOn(false)
      end
   end
   topMenuButton = modules.client_topmenu.addTopRightToggleButton(
      'offlineAssetsEditorButton', tr('Offline Assets Editor'), '/images/topbuttons/assets_editor', toggle, true)
   topMenuButton:setVisible(not g_game.isOnline())
   topMenuButton:setOn(false)
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
      if topMenuButton then topMenuButton:setOn(false) end
      displayErrorBox(tr('Assets Editor'), tr('Disconnect before opening the offline assets editor.'))
      return
   end
   if window then
      if window:isVisible() then
         requestClose()
      else
         window:show()
         window:raise()
         window:focus()
         if topMenuButton then topMenuButton:setOn(true) end
      end
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

   local ok, hasWorkCopy = getWorkCopyService():exists(version)
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
      local resetOk, result, remountFailed = getWorkCopyService():reset(version, activeWorkRoot)
      if not resetOk then
         local message = getUserFacingError(result)
         if remountFailed then
            message = tr('%s The working copy could not be remounted.', message)
         end
         displayErrorBox(tr('Assets Editor'), message)
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

function setImportSection(section)
   if section ~= 'replace' and section ~= 'create' and section ~= 'batch' and section ~= 'sheet' and section ~= 'bundle' then
      return
   end
   local search = getSpritePickerWidget('search')
   local query = search and search:getText() or ''
   if section ~= currentImportSection and section == 'create' then
      selectedCreateSpriteId = nil
   end
   currentImportSection = section
   if window then
      if section == 'replace' or section == 'create' then
         local pickerSearch = getSpritePickerWidget('search')
         if pickerSearch then
            pickerSearch:setText(query)
         end
      end
      window:recursiveGetChildById('replaceFramePanel'):setVisible(section == 'replace')
      window:recursiveGetChildById('newAppearancePanel'):setVisible(section == 'create')
      window:recursiveGetChildById('batchPngsPanel'):setVisible(section == 'batch')
      window:recursiveGetChildById('spriteSheetPanel'):setVisible(section == 'sheet')
      window:recursiveGetChildById('appearanceBundlePanel'):setVisible(section == 'bundle')
      window:recursiveGetChildById('replaceFrameTabButton'):setOn(section == 'replace')
      window:recursiveGetChildById('newAppearanceTabButton'):setOn(section == 'create')
      window:recursiveGetChildById('batchPngsTabButton'):setOn(section == 'batch')
      window:recursiveGetChildById('spriteSheetTabButton'):setOn(section == 'sheet')
      window:recursiveGetChildById('appearanceBundleTabButton'):setOn(section == 'bundle')
      if section == 'replace' or section == 'create' then
         applySpritePickerFilter()
      end
   end
   updateSpriteReplacementTarget()
end

function importAppearanceBundle(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before importing an appearance bundle?'), function()
         importAppearanceBundle(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open an offline 15.x work copy before importing an appearance bundle.'))
      return
   end

   local bundleDirectory = window:recursiveGetChildById('appearanceBundlePathEdit'):getText():trim()
   if bundleDirectory == '' then
      setStatus(tr('Choose an appearance bundle folder.'))
      return
   end

   local imported, response = pcall(g_things.importAppearanceBundlesFromDirectory, activeVersion, bundleDirectory)
   if not imported then
      setStatus(getUserFacingError(response))
      return
   end
   local decoded, result = pcall(json.decode, response)
   if not decoded or type(result) ~= 'table' or type(result.items) ~= 'table' or
         type(result.failures) ~= 'table' then
      setStatus(tr('The appearance bundle import returned an invalid result. Check the client log.'))
      return
   end
   local firstItem = result.items[1]
   if not firstItem then
      local failure = result.failures[1]
      setStatus(failure and tr('No bundles were imported. %s: %s', failure.bundle, failure.error) or
         tr('No appearance bundles were imported.'))
      return
   end
   if not reloadAssets() then
      setStatus(tr('%d bundle(s) were imported, but the work copy could not be reloaded.', result.imported))
      return
   end

   refreshAppearanceCatalog(firstItem.category)
   if loadAppearanceRecord(firstItem.category, firstItem.id, true, true) then
      setActivePage('editor')
      if tonumber(result.failed) > 0 then
         local failure = result.failures[1]
         setStatus(tr('Imported %d bundle(s); %d failed. First failure: %s: %s', result.imported,
            result.failed, failure.bundle, failure.error))
      else
         setStatus(tr('Imported %d appearance bundle(s). Selected appearance %d has %d remapped sprites.',
            result.imported, firstItem.id, tonumber(firstItem.sprites) or 0))
      end
   end
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
      local targetOffset = getAppearanceCatalogComponent():get_bottom_offset()
      list:setVirtualOffset({ x = 0, y = targetOffset })
      renderAppearanceRows(list:getVirtualOffset().y)
      list:updateScrollBars()
      setStatus(tr('Duplicated %d as %d. Sprite IDs remain shared.', sourceId, duplicateId))
   end
end

function deleteSelectedAppearance(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before deleting this appearance?'), function()
         deleteSelectedAppearance(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() or not selectedAppearanceId then
      setStatus(tr('Select an appearance in an offline 15.x work copy first.'))
      return
   end
   if pendingSpriteEdit then
      setStatus(tr('Apply or discard the pending sprite edit before deleting an appearance.'))
      return
   end

   local appearanceId = selectedAppearanceId
   local category = selectedAppearanceCategory
   local messageBox
   local function cancelDeletion()
      messageBox:cancel()
   end
   local function confirmDeletion()
      messageBox:ok()
      local ok, deleted = pcall(g_things.deleteAppearance, activeVersion, category, appearanceId)
      if not ok then
         setStatus(getUserFacingError(deleted))
         return
      end
      if not deleted then
         setStatus(tr('Appearance %d could not be deleted.', appearanceId))
         return
      end
      if not reloadAssets() then
         selectedAppearanceId = nil
         appearanceOriginal = nil
         clearAppearanceProperties()
         updateExportControls()
         refreshAppearanceCatalog(category)
         setStatus(tr('Appearance %d was deleted, but the work copy could not be reloaded.', appearanceId))
         return
      end

      local searchEdit = window:recursiveGetChildById('appearanceSearch')
      if searchEdit:getText() ~= '' then
         searchEdit:setText('')
      end
      selectedAppearanceId = nil
      appearanceOriginal = nil
      refreshAppearanceCatalog(category)
      updateExportControls()
      local nextEntry = getFilteredAppearanceEntry(1)
      if nextEntry then
         loadAppearanceRecord(category, nextEntry.id, true, true)
      else
         clearAppearanceProperties()
      end
      setStatus(tr('Appearance %d was removed from the working copy. Its sprites were kept.', appearanceId))
   end
   messageBox = displayGeneralBox(tr('Delete appearance'),
      tr('Remove appearance %d from this working copy? Sprite data will be kept. To restore the appearance, reload assets from the installed version.', appearanceId), {
         { text = tr('Delete'), callback = confirmDeletion },
         { text = tr('Cancel'), callback = cancelDeletion },
      }, cancelDeletion, cancelDeletion)
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

function importPngFolder(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before importing PNGs?'), function()
         importPngFolder(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before importing PNGs.'))
      return
   end

   local folder = window:recursiveGetChildById('batchPngFolderEdit'):getText():trim()
   if folder == '' then
      setStatus(tr('Choose a folder containing prepared PNG sprites.'))
      return
   end

   local imported, response = pcall(g_spriteAppearances.importSpritesFromDirectory, folder, activeVersion)
   if not imported then
      setStatus(getUserFacingError(response))
      return
   end

   local decoded, result = pcall(json.decode, response)
   if not decoded or type(result) ~= 'table' then
      setStatus(tr('The PNG import returned an invalid result. Check the client log.'))
      return
   end

   local importedCount = tonumber(result.imported) or 0
   if importedCount > 0 then
      if not reloadAssets() then
         setStatus(tr('%d sprites were written, but the work copy could not be reloaded.', importedCount))
         return
      end
   end

   if result.error and result.error ~= '' then
      setStatus(result.error)
      return
   end
   if importedCount == 0 then
      setStatus(tr('No PNG sprites were imported.'))
      return
   end

   local firstId = math.huge
   local lastId = 0
   for _, item in ipairs(result.items or {}) do
      local spriteId = tonumber(item.id)
      if spriteId then
         firstId = math.min(firstId, spriteId)
         lastId = math.max(lastId, spriteId)
      end
   end
   if firstId == math.huge then
      setStatus(tr('%d sprites imported. They are ready in the Sprite ID picker.', importedCount))
   else
      setStatus(tr('%d sprites imported (IDs %d-%d). They are ready in the Sprite ID picker.',
         importedCount, firstId, lastId))
   end
end

function importSpriteSheet(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before importing this sprite sheet?'), function()
         importSpriteSheet(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before importing a sprite sheet.'))
      return
   end

   local fileName = window:recursiveGetChildById('spriteSheetPathEdit'):getText():trim()
   if fileName == '' then
      setStatus(tr('Choose a PNG sprite sheet.'))
      return
   end
   local spriteWidth = tonumber(selectedOption(window:recursiveGetChildById('spriteSheetCellWidth')))
   local spriteHeight = tonumber(selectedOption(window:recursiveGetChildById('spriteSheetCellHeight')))
   if not spriteWidth or not spriteHeight then
      setStatus(tr('Choose the width and height of each sprite cell.'))
      return
   end
   local firstCell = tonumber(window:recursiveGetChildById('spriteSheetFirstCell'):getText():trim())
   local lastCell = tonumber(window:recursiveGetChildById('spriteSheetLastCell'):getText():trim())
   if not firstCell or firstCell < 1 or firstCell % 1 ~= 0 or not lastCell or lastCell < 0 or
         lastCell % 1 ~= 0 or (lastCell ~= 0 and lastCell < firstCell) then
      setStatus(tr('Enter a valid cell range. The last cell can be 0 to include the rest of the sheet.'))
      return
   end

   local imported, response = pcall(g_spriteAppearances.importSpritesFromSheet,
      fileName, activeVersion, spriteWidth, spriteHeight, firstCell, lastCell,
      window:recursiveGetChildById('spriteSheetSkipTransparent'):isChecked())
   if not imported then
      setStatus(getUserFacingError(response))
      return
   end

   local decoded, result = pcall(json.decode, response)
   if not decoded or type(result) ~= 'table' then
      setStatus(tr('The sprite sheet import returned an invalid result. Check the client log.'))
      return
   end

   local importedCount = tonumber(result.imported) or 0
   if importedCount > 0 and not reloadAssets() then
      setStatus(tr('%d sprites were written, but the work copy could not be reloaded.', importedCount))
      return
   end
   if result.error and result.error ~= '' then
      setStatus(result.error)
      return
   end
   if importedCount == 0 then
      setStatus(tr('No sprite cells were imported.'))
      return
   end

   local firstId = tonumber(result.items[1].id)
   local lastId = tonumber(result.items[importedCount].id)
   local skippedCount = tonumber(result.skipped) or 0
   if skippedCount > 0 then
      setStatus(tr('Imported %d sprites as IDs %d-%d; skipped %d fully transparent cells.',
         importedCount, firstId, lastId, skippedCount))
   else
      setStatus(tr('Imported %d sprites as IDs %d-%d, in row-major order.', importedCount, firstId, lastId))
   end
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
   if not getAppearancePropertiesEditor():collect_changes() then
      return
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
      local unsavedMessage = currentExportMode == 'appearance' and
         tr('Save or discard the pending appearance changes before exporting this bundle.') or
         tr('Save or discard the pending changes before exporting the work copy.')
      messageBox = displayGeneralBox(tr('Unsaved appearance properties'), unsavedMessage, {
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
   local isNewVersion = currentExportMode == 'new'
   local isFolderExport = currentExportMode == 'folder'
   local isAppearanceExport = currentExportMode == 'appearance'
   local targetVersion = activeVersion
   local destinationRoot
   if isNewVersion then
      targetVersion = parseClientVersion(window:recursiveGetChildById('newVersionEdit'):getText())
   elseif isFolderExport or isAppearanceExport then
      destinationRoot = window:recursiveGetChildById('exportFolderEdit'):getText():trim()
      local isAbsoluteDestination = destinationRoot:sub(1, 1) == '/' or destinationRoot:match('^%a:[/\\]') ~= nil or
         destinationRoot:match('^[/\\][/\\]') ~= nil
      if not isAbsoluteDestination then
         window:recursiveGetChildById('exportStatus'):setText(tr('Choose an absolute destination folder.'))
         return
      end
   end
   if isAppearanceExport and not selectedAppearanceId then
      window:recursiveGetChildById('exportStatus'):setText(tr('Select an appearance in the list before exporting its bundle.'))
      return
   end
   if isNewVersion and (not targetVersion or targetVersion == activeVersion or getVersionDirectories()[targetVersion]) then
      window:recursiveGetChildById('exportStatus'):setText(tr('Choose an unused version from 15.00 to 15.99.'))
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
      local title = isAppearanceExport and tr('Export this appearance bundle?') or
         (isFolderExport and tr('Copy assets to the selected folder?') or
         (isNewVersion and tr('Install client version %s?', formatClientVersion(targetVersion)) or
            tr('Replace client version %s?', formatClientVersion(activeVersion))))
      local message = isAppearanceExport and
         tr('Creates a new bundle in %s with the selected appearance, its flags and animation data, and copies of its referenced sprites. Existing folders are never overwritten.',
            destinationRoot) or
         (isFolderExport and
         tr('Creates %s/data/things/%d. Existing packages are never overwritten.', destinationRoot, activeVersion) or
         (isNewVersion and
            tr('Creates data/things/%d. Existing versions are never overwritten; source %s stays unchanged.',
               targetVersion, formatClientVersion(activeVersion)) or
            tr('Replaces data/things/%d. The current package is backed up first.', activeVersion)))
      messageBox = displayGeneralBox(title, message, {
            { text = isAppearanceExport and tr('Export bundle') or
               (isFolderExport and tr('Copy assets') or
                  (isNewVersion and tr('Install new version') or tr('Replace version'))), callback = confirmInstall },
            { text = tr('Cancel'), callback = cancelInstall },
         }, cancelInstall, cancelInstall)
      return
   end

   if isFolderExport then
      local copied, result = pcall(g_spriteAppearances.exportWorkCopy, activeVersion, destinationRoot)
      if not copied then
         local errorMessage = getUserFacingError(result)
         window:recursiveGetChildById('exportStatus'):setText(errorMessage)
         setStatus(errorMessage)
         return
      end
      local status = tr('Assets copied to %s. The installed version was not changed.', result)
      window:recursiveGetChildById('exportStatus'):setText(status)
      setStatus(tr('Work copy exported to %s.', result))
      return
   end

   if isAppearanceExport then
      local ok, result = pcall(g_things.exportAppearanceBundle, activeVersion,
         selectedAppearanceCategory, selectedAppearanceId, destinationRoot)
      if not ok then
         local errorMessage = getUserFacingError(result)
         window:recursiveGetChildById('exportStatus'):setText(errorMessage)
         setStatus(errorMessage)
         return
      end
      local status = tr('Appearance bundle exported to %s.', result)
      window:recursiveGetChildById('exportStatus'):setText(status)
      setStatus(status)
      return
   end

   local result = isNewVersion and
      getWorkCopyService():install_as_new_version(activeVersion, targetVersion, activeWorkRoot) or
      getWorkCopyService():install(activeVersion, activeWorkRoot)
   if isNewVersion and result.installed then
      window:recursiveGetChildById('versionComboBox'):addOption(formatClientVersion(targetVersion), targetVersion)
   end
   if result.remount_failed then
      local details = isNewVersion and result.destination or result.backup_path
      local message = result.installed and
         tr('Assets were installed, but the working copy could not be remounted. Location: %s', details) or
         tr('%s The working copy could not be remounted.', getUserFacingError(result.error))
      window:recursiveGetChildById('exportStatus'):setText(message)
      displayErrorBox(tr('Assets Editor'), message)
      return
   end
   if not result.installed then
      window:recursiveGetChildById('exportStatus'):setText(getUserFacingError(result.error))
      return
   end
   if isNewVersion then
      local status = tr('Version %s installed. Select it in Assets version to load it.', formatClientVersion(targetVersion))
      window:recursiveGetChildById('exportStatus'):setText(status)
      setStatus(tr('Client version %s is available in data/things/%d.', formatClientVersion(targetVersion), targetVersion))
      return
   end

   local backupPath = result.backup_path
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
   stopPreviewAnimation()
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
   if topMenuButton then topMenuButton:setOn(false) end
end
