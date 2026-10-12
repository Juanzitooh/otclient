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
local appearanceRows = {}
local appearanceOriginal
local appearanceChanges = { bools = {}, values = {}, strings = {}, animation = { groups = {} } }
local appearanceValueWidgets = {}
local appearanceStringWidgets = {}
local animationWidgets = {}
local buildingAppearanceProperties = false
local currentPage = 'editor'
local suggestedExportRoot
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

local APPEARANCE_ROW_HEIGHT = 52
local PREVIEW_CONTROLS_BOTTOM_MARGIN = 14
local PREVIEW_CANVAS_BOTTOM_MARGIN = 4
local PREVIEW_HINT_BOTTOM_MARGIN = 8

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
local collectAnimationWidgetChanges

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

local function getSuggestedExportRoot(version)
   local writeRoot = g_resources.getWriteDir()
   if not writeRoot or writeRoot == '' then
      return ''
   end
   writeRoot = writeRoot:gsub('[\\/]+$', '')
   return string.format('%s/sprite-editor/exports/otclient-%s', writeRoot, formatClientVersion(version))
end

local function addCategories(comboBox)
   for _, category in ipairs(categories) do
      comboBox:addOption(tr(category.name), category.data)
   end
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

local function hasEditableAnimation(data)
   for _, group in ipairs(data.frameGroups or {}) do
      if group.animation and group.animation.enabled then
         return true
      end
   end
   return false
end

local function updateSpriteReplacementTarget()
   if not window then
      return
   end
   local hasTarget = selectedSpriteId ~= nil
   local canReplace = hasTarget and activeVersion ~= nil and not g_game.isOnline()
   local targetPanel = window:recursiveGetChildById('spriteReplacementPanel')
   targetPanel:setVisible(currentPage == 'editor' and canReplace)
   targetPanel:setHeight(canReplace and 58 or 0)
   targetPanel:setMarginTop(canReplace and 6 or 0)
   window:recursiveGetChildById('replaceAppearanceSpriteButton'):setEnabled(canReplace)
   if not hasTarget then
      window:recursiveGetChildById('selectedSpriteLabel'):setText(tr('Select a linked sprite to replace its PNG.'))
      return
   end

   local size = string.format('%d x %d', canvas:getSpriteWidth(), canvas:getSpriteHeight())
   local targetLabel = window:recursiveGetChildById('selectedSpriteLabel')
   targetLabel:setText(tr('Sprite ID %d | %s', selectedSpriteId, selectedSpriteContext or tr('current frame')))
   targetLabel:setTooltip(tr('This PNG replaces sprite %d wherever that ID is shared. Use a %s PNG.',
      selectedSpriteId, size))
end

local function setPreviewControlsVisible(visible, panelHeight)
   local controls = window:recursiveGetChildById('previewControls')
   controls:setVisible(visible)
   controls:setHeight(visible and panelHeight or 0)
   canvas:setMarginBottom(visible and panelHeight + PREVIEW_CONTROLS_BOTTOM_MARGIN or PREVIEW_CANVAS_BOTTOM_MARGIN)
   window:recursiveGetChildById('previewHintLabel'):setMarginBottom(
      visible and panelHeight + PREVIEW_CONTROLS_BOTTOM_MARGIN or PREVIEW_HINT_BOTTOM_MARGIN)
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
   window:recursiveGetChildById('flagsTabButton'):setBackgroundColor(flagsVisible and '#603bb0' or '#363636')
   window:recursiveGetChildById('valuesTabButton'):setBackgroundColor(valuesVisible and '#603bb0' or '#363636')
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

   for _, key in ipairs(sortedKeys(data.values)) do
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
   window:recursiveGetChildById('spriteInfoLabel'):setText(tr('Select an appearance to preview its sprite.'))
   window:recursiveGetChildById('appearanceName'):setEnabled(false)
   window:recursiveGetChildById('appearanceDescription'):setEnabled(false)
   selectedSpriteId = nil
   selectedSpriteContext = nil
   canvas:setVisible(false)
   window:recursiveGetChildById('previewSpritePathEdit'):setText('')
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
   displayGeneralBox(tr('Unsaved changes'), message, {
      { text = tr('Save and continue'), callback = function()
         saveAppearanceProperties()
         if not hasAppearanceChanges() then
            continueAction()
         end
      end },
      { text = tr('Discard edits'), callback = function()
         resetAppearanceDraft()
         continueAction()
      end },
      { text = tr('Cancel'), callback = function() end },
   })
end

selectSprite = function(id)
   if not canvas or not activeVersion then
      return false
   end
   if not canvas:setSpriteId(id) then
      canvas:setVisible(false)
      selectedSpriteId = nil
      selectedSpriteContext = nil
      window:recursiveGetChildById('previewSpritePathEdit'):setText('')
      updateSpriteReplacementTarget()
      setStatus(tr('Sprite %d is not available in this 15.x work copy.', id))
      return false
   end

   if selectedSpriteId and selectedSpriteId ~= id then
      window:recursiveGetChildById('previewSpritePathEdit'):setText('')
   end
   canvas:setVisible(true)
   selectedSpriteId = id
   window:recursiveGetChildById('spriteInfoLabel'):setText(
      tr('Preview %d x %d | Zoom %dx', canvas:getSpriteWidth(), canvas:getSpriteHeight(), canvas:getZoom()))
   updateSpriteReplacementTarget()
   setStatus(tr('Sprite preview updated.'))
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
   if next(groupChanges.phases) == nil then
      groupChanges.phases = nil
   end
   if next(groupChanges) == nil then
      appearanceChanges.animation.groups[groupKey] = nil
   end
   updateAppearanceSaveButton()
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

local function updatePreviewPatternControls()
   if not window then
      return
   end
   local group = currentPreviewGroup()
   if not group then
      setPreviewControlsVisible(false)
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
   local directionPad = window:recursiveGetChildById('previewDirectionPad')
   local settings = window:recursiveGetChildById('previewSettings')
   local timelinePanel = window:recursiveGetChildById('previewTimelinePanel')
   local phaseLabel = window:recursiveGetChildById('previewPhaseLabel')

   directionPad:setVisible(useDirectionPad)
   settings:setMarginLeft(useDirectionPad and 166 or 8)
   local hasAnimation = group.animation and group.animation.enabled and group.animation.phases and
      #group.animation.phases > 0 or false
   timelinePanel:setVisible((group.phaseCount or 1) > 1 or hasAnimation)

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
            button:setOn(selected)
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
   local controls = window:recursiveGetChildById('previewControls')
   local hasMetaControls = groupBox:isVisible() or movingCheck:isVisible() or mountedCheck:isVisible()
   local hasPatternControls = directionBox:isVisible() or addonBox:isVisible() or layerBox:isVisible() or
      patternZBox:isVisible()
   local hasTopSettings = hasMetaControls or hasPatternControls or hasAnimation
   metaRow:setVisible(hasMetaControls)
   patternRow:setVisible(hasPatternControls)
   directionPad:setMarginLeft(useDirectionPad and
      (hasTopSettings and 8 or math.max(8, math.floor((controls:getWidth() - 150) / 2))) or 8)

   local settingsRowCount = (hasMetaControls and 1 or 0) + (hasPatternControls and 1 or 0) +
      (hasAnimation and 1 or 0)
   local settingsHeight = settingsRowCount > 0 and settingsRowCount * 22 + (settingsRowCount - 1) * 4 or 1
   settings:setHeight(settingsHeight)

   local groupOptions = {}
   for index, frameGroup in ipairs(previewFrameGroups) do
      table.insert(groupOptions, { label = frameGroupName(frameGroup, index), data = index })
   end
   setComboOptions(groupBox, groupOptions, previewFrameGroupIndex)

   local phaseCount = math.max(1, group.phaseCount or 1)
   local hasMultipleFrames = phaseCount > 1
   phaseLabel:setVisible(hasMultipleFrames or hasAnimation)
   previewPhase = math.min(previewPhase, phaseCount - 1)
   local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
   phaseStepper:setVisible(hasMultipleFrames or hasAnimation)
   local onValueChange = phaseStepper.onValueChange
   phaseStepper.onValueChange = nil
   phaseStepper:setMinimum(1)
   phaseStepper:setMaximum(phaseCount)
   phaseStepper:setStep(1)
   phaseStepper:setMouseScroll(true)
   phaseStepper:setValue(previewPhase + 1, true)
   phaseStepper.onValueChange = onValueChange
   local phaseCountLabel = window:recursiveGetChildById('previewPhaseCount')
   phaseCountLabel:setVisible(hasMultipleFrames or hasAnimation)
   phaseCountLabel:setText(tr('of %d', phaseCount))
   local timeline = window:recursiveGetChildById('previewTimeline')
   local timelineScroll = window:recursiveGetChildById('previewTimelineScroll')
   timelineScroll:setVisible(hasMultipleFrames and phaseCount * 30 > timeline:getWidth())
   local hasTimeline = hasMultipleFrames or hasAnimation
   local topAreaHeight = math.max(useDirectionPad and 68 or 0, settingsHeight)
   local panelHeight = 8 + topAreaHeight + (hasTimeline and 74 or 0) + 8
   setPreviewControlsVisible(useDirectionPad or hasTopSettings or hasTimeline, panelHeight)
   updateSpriteReplacementTarget()
end

local function refreshAppearancePreview()
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
         setStatus(tr('Preview: %s', selectedSpriteContext))
      end
      return selected
   end

   selectedSpriteId = nil
   selectedSpriteContext = nil
   canvas:setVisible(false)
   window:recursiveGetChildById('spriteInfoLabel'):setText(tr('No sprite is linked to this frame selection.'))
   window:recursiveGetChildById('previewSpritePathEdit'):setText('')
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
   local timelinePanel = window:recursiveGetChildById('previewTimelinePanel')
   local timeline = window:recursiveGetChildById('previewTimeline')
   local timelineScroll = window:recursiveGetChildById('previewTimelineScroll')
   local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
   local phaseCountLabel = window:recursiveGetChildById('previewPhaseCount')
   local minLabel = window:recursiveGetChildById('animationDurationMinLabel')
   local minEdit = window:recursiveGetChildById('animationDurationMin')
   local maxLabel = window:recursiveGetChildById('animationDurationMaxLabel')
   local maxEdit = window:recursiveGetChildById('animationDurationMax')
   local hasMultipleFrames = phaseCount > 1
   local hasFrameControls = hasMultipleFrames or isAnimated

   timelinePanel:setVisible(hasFrameControls)
   phaseStepper:setMinimum(1)
   phaseStepper:setMaximum(phaseCount)
   phaseStepper:setStep(1)
   phaseStepper:setMouseScroll(true)
   phaseStepper:setVisible(hasFrameControls)
   phaseCountLabel:setVisible(hasFrameControls)
   phaseCountLabel:setText(tr('of %d', phaseCount))
   minLabel:setVisible(isAnimated)
   minEdit:setVisible(isAnimated)
   maxLabel:setVisible(isAnimated)
   maxEdit:setVisible(isAnimated)
   settingsRow:setVisible(isAnimated)

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
      window:recursiveGetChildById('animationLoopCountLabel'):setVisible(false)
      window:recursiveGetChildById('animationDefaultPhase'):setText('0')
      window:recursiveGetChildById('animationRandomStart'):setChecked(false)
      window:recursiveGetChildById('animationSynchronized'):setChecked(false)
      window:recursiveGetChildById('animationLoopCount'):setText('0')
      minEdit:setText('')
      maxEdit:setText('')
   end

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
         addEvent(function()
            if timeline and frameButton then
               timeline:ensureChildVisible(frameButton)
            end
         end)
      end
   end
   frameList:setWidth(math.max(1, phaseCount * 30 - 2))
   timelineScroll:setVisible(phaseCount * 30 > timeline:getWidth())
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
         window:recursiveGetChildById('spriteInfoLabel'):setText(tr('This appearance has no linked sprites.'))
         window:recursiveGetChildById('previewSpritePathEdit'):setText('')
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
         local spriteIds = {}
         local seenSpriteIds = {}
         local spriteId
         for _, linkedSpriteId in ipairs(sprites or {}) do
            if linkedSpriteId > 0 then
               spriteId = spriteId or linkedSpriteId
               if not seenSpriteIds[linkedSpriteId] then
                  table.insert(spriteIds, linkedSpriteId)
                  seenSpriteIds[linkedSpriteId] = true
               end
            end
         end
         table.sort(spriteIds)
         table.insert(entries, {
            id = id,
            category = category,
            name = name ~= '' and name or nil,
            spriteId = spriteId,
            spriteIds = spriteIds,
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

   if #entry.spriteIds == 1 then
      table.insert(lines, tr('Sprite ID: %d', entry.spriteIds[1]))
   elseif #entry.spriteIds > 1 then
      table.insert(lines, tr('Sprite ID span: %d-%d (%d linked)', entry.spriteIds[1], entry.spriteIds[#entry.spriteIds], #entry.spriteIds))
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
   local viewportHeight = math.max(list:getHeight(), 400)
   local poolSize = math.ceil(viewportHeight / APPEARANCE_ROW_HEIGHT) + 2
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
         row:recursiveGetChildById('appearanceId'):setText(tr('ID %d', entry.id))
         row:setTooltip(getAppearanceTooltip(entry))
         local thumbnail = row:recursiveGetChildById('thumbnail')
         thumbnail:setVisible(entry.spriteId ~= nil)
         if entry.spriteId then
            thumbnail:setSpriteId(entry.spriteId)
         end
         local selected = entry.id == selectedAppearanceId and entry.category == selectedAppearanceCategory
         row:setBackgroundColor(selected and '#514276' or '#363636')
         row.onClick = function()
            selectAppearance(entry.category, entry.id)
         end
      end
   end

   if g_spriteAppearances.releaseDecodedSpriteSheets then
      g_spriteAppearances.releaseDecodedSpriteSheets()
   end
end

local function applyAppearanceFilter()
   if not window then
      return
   end
   local search = window:recursiveGetChildById('appearanceSearch'):getText():lower()
   filteredAppearanceEntries = {}
   for _, entry in ipairs(appearanceEntries) do
      local idText = tostring(entry.id)
      local nameText = entry.name and entry.name:lower() or ''
      local spriteMatch = false
      for _, spriteId in ipairs(entry.spriteIds) do
         if tostring(spriteId):find(search, 1, true) then
            spriteMatch = true
            break
         end
      end
      if search == '' or nameText:find(search, 1, true) or
            idText:find(search, 1, true) or spriteMatch then
         table.insert(filteredAppearanceEntries, entry)
      end
   end
   local countLabel = window:recursiveGetChildById('appearanceResultsLabel')
   countLabel:setText(activeVersion and tr('%d appearances', #filteredAppearanceEntries) or
      tr('Open a work copy to browse.'))
   local list = window:recursiveGetChildById('appearanceList')
   list:setVirtualOffset({ x = 0, y = 0 })
   renderAppearanceRows(0)
   list:updateScrollBars()
end

local function refreshAppearanceCatalog(category)
   if not window or not activeVersion then
      appearanceEntries = {}
      filteredAppearanceEntries = {}
      if window then
         window:recursiveGetChildById('appearanceResultsLabel'):setText(tr('Open a work copy to browse.'))
      end
      return
   end
   appearanceEntries = getThingEntries(category)
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

   if selectedAppearanceCategory ~= category or selectedAppearanceId ~= id then
      window:recursiveGetChildById('previewSpritePathEdit'):setText('')
   end
   selectedAppearanceCategory = category
   selectedAppearanceId = id
   selectedSpriteId = nil
   selectedSpriteContext = nil
   updateSpriteReplacementTarget()
   window:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(category, true)
   buildAppearanceProperties(data)
   refreshSelectedAppearance()
   if not selectedSpriteId then
      local categoryInfo = categories[category + 1]
      setStatus(tr('%s loaded.', categoryInfo and tr(categoryInfo.singular) or tr('Appearance')))
   end
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
   return true
end

local function updateExportControls()
   if not window then
      return
   end

   local pathEdit = window:recursiveGetChildById('exportPathEdit')
   local exportButton = window:recursiveGetChildById('exportButton')
   if activeVersion then
      local currentPath = pathEdit:getText()
      if currentPath == '' or currentPath == suggestedExportRoot then
         suggestedExportRoot = getSuggestedExportRoot(activeVersion)
         pathEdit:setText(suggestedExportRoot)
      end
   else
      suggestedExportRoot = nil
   end

   local enabled = activeVersion ~= nil and not g_game.isOnline() and pathEdit:getText() ~= ''
   exportButton:setEnabled(enabled)
   window:recursiveGetChildById('importPageButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('exportPageButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
   window:recursiveGetChildById('reloadButton'):setEnabled(activeVersion ~= nil and not g_game.isOnline())
end

local function setActivePage(page)
   if not window then
      return
   end
   currentPage = page
   window:recursiveGetChildById('propertiesPanel'):setVisible(page == 'editor')
   window:recursiveGetChildById('importPanel'):setVisible(page == 'import')
   window:recursiveGetChildById('exportPanel'):setVisible(page == 'export')
   window:recursiveGetChildById('editorPageButton'):setBackgroundColor(page == 'editor' and '#603bb0' or '#363636')
   window:recursiveGetChildById('importPageButton'):setBackgroundColor(page == 'import' and '#603bb0' or '#363636')
   window:recursiveGetChildById('exportPageButton'):setBackgroundColor(page == 'export' and '#603bb0' or '#363636')
   updateSpriteReplacementTarget()
   updateExportControls()
   if page == 'export' then
      local packagePath = activeWorkRoot and activeVersion and
         string.format('%s/data/things/%d', activeWorkRoot, activeVersion)
      local copyLabel = window:recursiveGetChildById('activeWorkCopyLabel')
      copyLabel:setText(packagePath or tr('No work copy is open.'))
      copyLabel:setTooltip(packagePath or '')
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
         window:recursiveGetChildById('spriteInfoLabel'):setText(
            tr('Preview %d x %d | Zoom %dx', canvas:getSpriteWidth(), canvas:getSpriteHeight(), canvas:getZoom()))
      end
   end

   local categoryBox = window:recursiveGetChildById('appearanceCategory')
   addCategories(categoryBox)
   categoryBox:setCurrentOptionByData(selectedAppearanceCategory, true)
   categoryBox.onOptionChange = function(_, _, category)
      changeAppearanceCategory(category)
   end
   local searchEdit = window:recursiveGetChildById('appearanceSearch')
   searchEdit.onTextChange = function()
      applyAppearanceFilter()
   end
   local list = window:recursiveGetChildById('appearanceList')
   list.onScrollChange = function(_, offset)
      renderAppearanceRows(offset.y)
   end

   local versionBox = window:recursiveGetChildById('versionComboBox')
   for _, version in ipairs(getVersions()) do
      versionBox:addOption(formatClientVersion(version), version)
   end
   if activeVersion then
      versionBox:setCurrentOptionByData(activeVersion, true)
   end
   window:recursiveGetChildById('exportPathEdit').onTextChange = function(widget)
      local destination = widget:getText()
      local exportButton = window:recursiveGetChildById('exportButton')
      local enabled = activeVersion ~= nil and not g_game.isOnline() and destination ~= ''
      exportButton:setEnabled(enabled)
   end

   setActivePage(currentPage)
   setPropertiesTab(currentPropertiesTab)
   window:show()
   window:raise()
   window:focus()
   if activeVersion then
      refreshAppearanceCatalog(selectedAppearanceCategory)
      if filteredAppearanceEntries[1] then
         loadAppearanceRecord(selectedAppearanceCategory, filteredAppearanceEntries[1].id, true)
      end
   else
      clearAppearanceProperties()
   end
   return true
end

local function destroyWindow()
   appearanceValueWidgets = {}
   appearanceStringWidgets = {}
   animationWidgets = {}
   if window then
      window:destroy()
      window = nil
      canvas = nil
   end
   appearanceRows = {}
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
   else
      createWindow()
   end
end

function openWorkCopy()
   if not window or g_game.isOnline() then
      return
   end
   local version = selectedOption(window:recursiveGetChildById('versionComboBox'))
   if not version then
      displayErrorBox(tr('Assets Editor'), tr('No installed client version 15.x assets were found.'))
      return
   end
   if hasAppearanceChanges() then
      confirmUnsavedChanges(tr('Save changes before opening another working copy?'), function()
         openWorkCopyVersion(version)
      end)
      return
   end
   openWorkCopyVersion(version)
end

function openWorkCopyVersion(version)
   destroyWindow()
   activeVersion = nil
   activeAssetPath = nil
   activeWorkRoot = nil
   if not loadAssets(version) then
      createWindow()
      return
   end
   currentPage = 'editor'
   createWindow()
   window:recursiveGetChildById('versionComboBox'):setCurrentOptionByData(version, true)
   setStatus(tr('Working copy ready for client %s.', formatClientVersion(version)))
end

function applyAppearanceSearch()
   applyAppearanceFilter()
end

function showEditorPage()
   setActivePage('editor')
end

function showImportPage()
   setActivePage('import')
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

function replaceSprite(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes before replacing this sprite?'), function()
         replaceSprite(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before importing a sprite.'))
      return
   end
   local id = selectedSpriteId
   local path = window:recursiveGetChildById('previewSpritePathEdit'):getText()
   if not id or path == '' then
      setStatus(tr('Select a sprite and enter an absolute PNG path.'))
      return
   end
   local previewSelection = capturePreviewSelection()
   local ok, result = pcall(g_spriteAppearances.importSpriteFromFile, id, path, activeVersion)
   if not ok then
      local errorMessage = getUserFacingError(result)
      if errorMessage:find('prepared PNG dimensions must match the selected sprite', 1, true) then
         errorMessage = tr('This sprite needs a %d x %d PNG. The work copy was not changed.',
            canvas:getSpriteWidth(), canvas:getSpriteHeight())
      end
      setStatus(errorMessage)
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('The sprite was written, but the work copy could not be reloaded.'))
      return
   end
   refreshAppearanceCatalog(selectedAppearanceCategory)
   if not loadAppearanceRecord(selectedAppearanceCategory, selectedAppearanceId, true, true) then
      setStatus(tr('Sprite %d was replaced, but the appearance preview could not be reloaded.', result))
      return
   end
   restorePreviewSelection(previewSelection)
   setActivePage('editor')
   setStatus(tr('Sprite PNG replaced in the working copy; preview restored.'))
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
   local category = selectedOption(window:recursiveGetChildById('appearanceCategory'))
   local name = window:recursiveGetChildById('newAppearanceName'):getText()
   local description = window:recursiveGetChildById('newAppearanceDescription'):getText()
   local path = window:recursiveGetChildById('newAppearancePngPathEdit'):getText()
   if not category or name == '' or path == '' then
      setStatus(tr('Choose a category, enter a name, and provide an absolute PNG path.'))
      return
   end

   local imported, spriteId = pcall(g_spriteAppearances.importSpriteFromFile, 0, path, activeVersion)
   if not imported then
      setStatus(getUserFacingError(spriteId))
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('Sprite %d was imported, but the work copy could not be reloaded.', spriteId))
      return
   end

   local created, appearanceId = pcall(g_things.createAppearanceFromSprite,
      activeVersion, category, spriteId, name, description)
   if not created then
      reloadAssets()
      setStatus(tr('Sprite %d was imported, but the appearance could not be created: %s', spriteId,
         getUserFacingError(appearanceId)))
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('Appearance %d was created, but the work copy could not be reloaded.', appearanceId))
      return
   end

   window:recursiveGetChildById('newAppearanceName'):setText('')
   window:recursiveGetChildById('newAppearanceDescription'):setText('')
   refreshAppearanceCatalog(category)
   loadAppearanceRecord(category, appearanceId, true)
   selectSprite(spriteId)
   showEditorPage()
   setStatus(tr('New appearance created in the working copy.'))
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
   loadAppearanceRecord(selectedAppearanceCategory, selectedAppearanceId, true, true)
   setAppearanceStatus(tr('Saved in the working copy.'))
end

function exportWorkCopy(forceContinue)
   if hasAppearanceChanges() and not forceContinue then
      confirmUnsavedChanges(tr('Save changes to the working copy before exporting?'), function()
         exportWorkCopy(true)
      end)
      return
   end
   if not activeVersion or g_game.isOnline() then
      window:recursiveGetChildById('exportStatus'):setText(tr('Open a 15.x work copy before exporting.'))
      return
   end
   local destination = window:recursiveGetChildById('exportPathEdit'):getText()
   if destination == '' then
      window:recursiveGetChildById('exportStatus'):setText(tr('Enter an absolute destination folder.'))
      return
   end
   local ok, result = pcall(g_spriteAppearances.exportWorkCopy, activeVersion, destination)
   if not ok then
      window:recursiveGetChildById('exportStatus'):setText(getUserFacingError(result))
      return
   end
   window:recursiveGetChildById('exportStatus'):setText(tr('Asset package exported to %s.', result))
   setStatus(tr('Exported client %s to a separate asset package.', formatClientVersion(activeVersion)))
end

function reloadPackage()
   if not activeVersion or g_game.isOnline() then
      return
   end
   if hasAppearanceChanges() then
      confirmUnsavedChanges(tr('Save changes before reloading the working copy?'), function()
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

function requestClose(forceDiscard)
   if not window then
      return
   end
   if hasAppearanceChanges() and not forceDiscard then
      confirmUnsavedChanges(tr('Save changes to the working copy before closing?'), function()
         requestClose(true)
      end)
      return
   end
   destroyWindow()
end
