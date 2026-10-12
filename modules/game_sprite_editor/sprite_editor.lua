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
   { name = 'Objects', data = 0 },
   { name = 'Outfits', data = 1 },
   { name = 'Effects', data = 2 },
   { name = 'Missiles', data = 3 },
}

local selectAppearance
local selectSprite
local renderAppearanceRows
local configurePreviewControls
local updateAnimationEditor

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

local function addCategories(comboBox)
   for _, category in ipairs(categories) do
      comboBox:addOption(tr(category.name), category.data)
   end
end

local function hasAppearanceChanges()
   return next(appearanceChanges.bools) ~= nil or
      next(appearanceChanges.values) ~= nil or
      next(appearanceChanges.strings) ~= nil or
      next(appearanceChanges.animation.groups) ~= nil
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
      window:recursiveGetChildById('saveAppearanceButton'):setEnabled(hasAppearanceChanges())
   end
end

local function setPropertiesTab(tab)
   if not window then
      return
   end
   currentPropertiesTab = tab == 'values' and 'values' or tab == 'animation' and 'animation' or 'flags'
   local flagsVisible = currentPropertiesTab == 'flags'
   local valuesVisible = currentPropertiesTab == 'values'
   window:recursiveGetChildById('appearanceFlagsList'):setVisible(flagsVisible)
   window:recursiveGetChildById('appearanceFlagsScroll'):setVisible(flagsVisible)
   window:recursiveGetChildById('appearanceValuesList'):setVisible(valuesVisible)
   window:recursiveGetChildById('appearanceValuesScroll'):setVisible(valuesVisible)
   window:recursiveGetChildById('appearanceAnimationPanel'):setVisible(currentPropertiesTab == 'animation')
   window:recursiveGetChildById('appearanceAnimationScroll'):setVisible(currentPropertiesTab == 'animation')
   window:recursiveGetChildById('flagsTabButton'):setBackgroundColor(flagsVisible and '#603bb0' or '#363636')
   window:recursiveGetChildById('valuesTabButton'):setBackgroundColor(valuesVisible and '#603bb0' or '#363636')
   window:recursiveGetChildById('animationTabButton'):setBackgroundColor(currentPropertiesTab == 'animation' and '#603bb0' or '#363636')
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
   window:recursiveGetChildById('appearanceName'):setText('')
   window:recursiveGetChildById('appearanceDescription'):setText('')
   window:recursiveGetChildById('appearanceFlagsList'):destroyChildren()
   window:recursiveGetChildById('appearanceValuesList'):destroyChildren()
   window:recursiveGetChildById('animationFrameDurations'):destroyChildren()
   window:recursiveGetChildById('spriteInfoLabel'):setText(tr('Select an appearance to preview its sprite.'))
   selectedSpriteId = nil
   selectedSpriteContext = nil
   canvas:setVisible(false)
   window:recursiveGetChildById('replacePreviewSpriteButton'):setEnabled(false)
   appearanceOriginal = nil
   appearanceValueWidgets = {}
   appearanceStringWidgets = {}
   animationWidgets = {}
   configurePreviewControls({})
   updateAnimationEditor()
   clearAppearanceChanges()
   buildingAppearanceProperties = false
   updateAppearanceSaveButton()
end

selectSprite = function(id)
   if not canvas or not activeVersion then
      return false
   end
   if not canvas:setSpriteId(id) then
      canvas:setVisible(false)
      selectedSpriteId = nil
      selectedSpriteContext = nil
      window:recursiveGetChildById('replacePreviewSpriteButton'):setEnabled(false)
      setStatus(tr('Sprite %d is not available in this 15.x work copy.', id))
      return false
   end

   canvas:setVisible(true)
   selectedSpriteId = id
   window:recursiveGetChildById('spriteInfoLabel'):setText(
      string.format('ID %d | %d x %d | %dx', id, canvas:getSpriteWidth(), canvas:getSpriteHeight(), canvas:getZoom()))
   window:recursiveGetChildById('selectedSpriteLabel'):setText(
      tr('Selected sprite ID: %d', id))
   window:recursiveGetChildById('replacePreviewSpriteButton'):setEnabled(true)
   setStatus(tr('Previewing sprite %d.', id))
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
      window:recursiveGetChildById('previewControls'):setVisible(false)
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

   directionPad:setVisible(useDirectionPad)
   settings:setMarginLeft(useDirectionPad and 8 or -142)

   groupBox:setVisible(#previewFrameGroups > 1 and not previewHasMovementToggle)
   movingCheck:setVisible(previewHasMovementToggle)
   setCheckBoxState(movingCheck, previewMoving)
   mountedCheck:setVisible(isOutfit and group.patternDepth > 1)
   setCheckBoxState(mountedCheck, previewMounted)

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
      addonBox:setMarginLeft(190)
      layerBox:setMarginLeft(286)
      window:recursiveGetChildById('previewPhaseLabel'):setMarginLeft(0)
   else
      buildPatternOptions(directionBox, isOutfit and tr('Direction') or tr('Pattern X'), group.patternWidth, previewPatternX)
      local hasGroupSelector = #previewFrameGroups > 1 and not previewHasMovementToggle
      directionBox:setMarginLeft(hasGroupSelector and 100 or 0)
      addonBox:setMarginLeft(hasGroupSelector and 200 or 100)
      layerBox:setMarginLeft(hasGroupSelector and 294 or 194)
      window:recursiveGetChildById('previewPhaseLabel'):setMarginLeft(group.patternDepth > 1 and 100 or 0)
   end

   buildPatternOptions(addonBox, isOutfit and tr('Addon') or tr('Pattern Y'), group.patternHeight, previewPatternY)
   buildPatternOptions(layerBox, tr('Layer'), group.layers, previewLayer)
   if isOutfit then
      patternZBox:setVisible(false)
   else
      buildPatternOptions(patternZBox, tr('Pattern Z'), group.patternDepth, previewPatternZ)
   end

   local groupOptions = {}
   for index, frameGroup in ipairs(previewFrameGroups) do
      table.insert(groupOptions, { label = frameGroupName(frameGroup, index), data = index })
   end
   setComboOptions(groupBox, groupOptions, previewFrameGroupIndex)

   local phaseCount = math.max(1, group.phaseCount or 1)
   local hasMultipleFrames = phaseCount > 1
   window:recursiveGetChildById('previewPhaseLabel'):setVisible(hasMultipleFrames)
   previewPhase = math.min(previewPhase, phaseCount - 1)
   local phaseStepper = window:recursiveGetChildById('previewPhaseStepper')
   phaseStepper:setVisible(hasMultipleFrames)
   local onValueChange = phaseStepper.onValueChange
   phaseStepper.onValueChange = nil
   phaseStepper:setMinimum(1)
   phaseStepper:setMaximum(phaseCount)
   phaseStepper:setStep(1)
   phaseStepper:setMouseScroll(true)
   phaseStepper:setValue(previewPhase + 1, true)
   phaseStepper.onValueChange = onValueChange
   local phaseCountLabel = window:recursiveGetChildById('previewPhaseCount')
   phaseCountLabel:setVisible(hasMultipleFrames)
   phaseCountLabel:setText(tr('of %d', phaseCount))
   local replacementButton = window:recursiveGetChildById('replacePreviewSpriteButton')
   replacementButton:setEnabled(selectedSpriteId ~= nil and activeVersion ~= nil)
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
         local spriteSize = string.format('%d x %d', canvas:getSpriteWidth(), canvas:getSpriteHeight())
         window:recursiveGetChildById('selectedSpriteLabel'):setText(
            tr('Target: sprite ID %d | %s | %s. Same-size PNG required; shared IDs change everywhere.',
               spriteId, selectedSpriteContext, spriteSize))
         setStatus(tr('Preview: %s | Sprite ID %d', selectedSpriteContext, spriteId))
      end
      return selected
   end

   selectedSpriteId = nil
   selectedSpriteContext = nil
   canvas:setVisible(false)
   window:recursiveGetChildById('spriteInfoLabel'):setText(tr('No sprite is linked to this frame selection.'))
   window:recursiveGetChildById('selectedSpriteLabel'):setText(tr('No sprite is linked to this frame selection.'))
   window:recursiveGetChildById('replacePreviewSpriteButton'):setEnabled(false)
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

   local controls = window:recursiveGetChildById('previewControls')
   controls:setVisible(#previewFrameGroups > 0)
   if #previewFrameGroups == 0 then
      return
   end

   local frameGroupBox = window:recursiveGetChildById('previewFrameGroup')
   frameGroupBox.onOptionChange = function(_, _, frameGroupIndex)
      if frameGroupIndex then
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
      previewPhase = (value or 1) - 1
      refreshAppearancePreview()
   end
   window:recursiveGetChildById('previewMoving').onCheckChange = function(widget)
      if not previewHasMovementToggle then
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
   local hasChoice = #previewFrameGroups > 1
   for _, group in ipairs(previewFrameGroups) do
      hasChoice = hasChoice or group.patternWidth > 1 or group.patternHeight > 1 or
         group.patternDepth > 1 or group.layers > 1 or group.phaseCount > 1
   end
   controls:setVisible(hasChoice or activeVersion ~= nil)
   updateAnimationEditor()
   refreshAppearancePreview()
end

updateAnimationEditor = function()
   if not window then
      return
   end
   local wasBuildingProperties = buildingAppearanceProperties
   buildingAppearanceProperties = true
   local frameList = window:recursiveGetChildById('animationFrameDurations')
   frameList:destroyChildren()
   animationWidgets = {}
   local group = currentPreviewGroup()
   local info = window:recursiveGetChildById('animationGroupInfo')
   local enabled = group and group.animation and group.animation.enabled
   if not group then
      info:setText(tr('Select an appearance with animation data.'))
   elseif not enabled then
      info:setText(tr('%s has no editable animation metadata.', frameGroupName(group, previewFrameGroupIndex)))
   else
      info:setText(tr('%s | %d frames', frameGroupName(group, previewFrameGroupIndex), group.phaseCount))
   end

   local controls = {
      window:recursiveGetChildById('animationDefaultPhaseRow'),
      window:recursiveGetChildById('animationRandomStart'),
      window:recursiveGetChildById('animationSynchronized'),
      window:recursiveGetChildById('animationLoopTypeRow'),
      window:recursiveGetChildById('animationLoopCountRow'),
   }
   for _, control in ipairs(controls) do
      control:setEnabled(enabled)
   end
   if not enabled then
      window:recursiveGetChildById('animationLoopType'):clearOptions()
      window:recursiveGetChildById('animationDefaultPhase'):setText('0')
      window:recursiveGetChildById('animationRandomStart'):setChecked(false)
      window:recursiveGetChildById('animationSynchronized'):setChecked(false)
      window:recursiveGetChildById('animationLoopCount'):setText('0')
      frameList:setHeight(1)
      buildingAppearanceProperties = wasBuildingProperties
      return
   end

   local groupIndex = group.index
   local groupKey = tostring(groupIndex)
   local changes = appearanceChanges.animation.groups[groupKey] or {}
   local animation = group.animation
   local defaultPhase = window:recursiveGetChildById('animationDefaultPhase')
   local randomStart = window:recursiveGetChildById('animationRandomStart')
   local synchronized = window:recursiveGetChildById('animationSynchronized')
   local loopTypeBox = window:recursiveGetChildById('animationLoopType')
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
   buildingAppearanceProperties = wasBuildingProperties

   defaultPhase.onTextChange = function(widget)
      if not buildingAppearanceProperties then
         local value = tonumber(widget:getText())
         if value and value >= 0 and value % 1 == 0 then
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

   animationWidgets.groupIndex = groupIndex
   animationWidgets.fields = { defaultStartPhase = defaultPhase, loopCount = loopCount }
   for phaseIndex, phase in ipairs(animation.phases) do
      local row = g_ui.createWidget('AppearanceFrameDurationRow', frameList)
      row:setWidth(285)
      row:recursiveGetChildById('phaseLabel'):setText(tr('Frame %d', phaseIndex))
      local phaseChanges = changes.phases and changes.phases[tostring(phaseIndex - 1)] or {}
      local minEdit = row:recursiveGetChildById('durationMin')
      local maxEdit = row:recursiveGetChildById('durationMax')
      minEdit:setText(tostring(phaseChanges.durationMin ~= nil and phaseChanges.durationMin or phase.durationMin))
      maxEdit:setText(tostring(phaseChanges.durationMax ~= nil and phaseChanges.durationMax or phase.durationMax))
      if not animationWidgets.phases then
         animationWidgets.phases = {}
      end
      animationWidgets.phases[phaseIndex - 1] = { durationMin = minEdit, durationMax = maxEdit }
      minEdit.onTextChange = function(widget)
         if not buildingAppearanceProperties then
            local value = tonumber(widget:getText())
            if value and value >= 0 and value % 1 == 0 then
               setAnimationChange(groupIndex, 'durationMin', value, phaseIndex - 1)
            end
         end
      end
      maxEdit.onTextChange = function(widget)
         if not buildingAppearanceProperties then
            local value = tonumber(widget:getText())
            if value and value >= 0 and value % 1 == 0 then
               setAnimationChange(groupIndex, 'durationMax', value, phaseIndex - 1)
            end
         end
      end
   end
   frameList:setHeight(math.max(1, #animation.phases * 27))
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

   local name = thing:getName()
   window:recursiveGetChildById('appearanceInfoLabel'):setText(
      string.format('%s | ID %d', name ~= '' and name or tr('Unnamed appearance'), selectedAppearanceId))
   if #previewFrameGroups > 0 then
      refreshAppearancePreview()
   else
      local sprites = thing:getSprites()
      if #sprites > 0 then
         selectSprite(sprites[1])
      else
         selectedSpriteId = nil
         canvas:setVisible(false)
         window:recursiveGetChildById('spriteInfoLabel'):setText(tr('This appearance has no linked sprites.'))
         window:recursiveGetChildById('selectedSpriteLabel'):setText(tr('This appearance has no linked sprites.'))
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
         local spriteId = sprites and sprites[1] or nil
         table.insert(entries, {
            id = id,
            category = category,
            name = name ~= '' and name or tr('Unnamed appearance'),
            spriteId = spriteId and spriteId > 0 and spriteId or nil,
         })
      end
   end
   table.sort(entries, function(a, b) return a.id < b.id end)
   return entries
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
         row:recursiveGetChildById('appearanceResultName'):setText(entry.name)
         row:recursiveGetChildById('appearanceId'):setText(
            entry.spriteId and tr('ID %d | Sprite %d', entry.id, entry.spriteId) or tr('ID %d | No sprite', entry.id))
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
      local spriteText = entry.spriteId and tostring(entry.spriteId) or ''
      if search == '' or entry.name:lower():find(search, 1, true) or
            idText:find(search, 1, true) or spriteText:find(search, 1, true) then
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
      displayGeneralBox(tr('Discard appearance edits?'), tr('Selecting another appearance discards unsaved property changes.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() loadAppearanceRecord(category, id, true) end },
         { text = tr('Cancel'), callback = function() end },
      })
      return false
   end

   local ok, encoded = pcall(g_things.getAppearanceEditorData, activeVersion, category, id)
   if not ok then
      setStatus(tostring(encoded))
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
   window:recursiveGetChildById('replacePreviewSpriteButton'):setEnabled(false)
   window:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(category, true)
   buildAppearanceProperties(data)
   refreshSelectedAppearance()
   if not selectedSpriteId then
      setStatus(tr('Appearance %d loaded.', id))
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
      displayGeneralBox(tr('Discard appearance edits?'), tr('Changing category discards unsaved property changes.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() changeAppearanceCategory(category, true) end },
         { text = tr('Cancel'), callback = function() end },
      })
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
   if page == 'import' and selectedSpriteId then
      local size = canvas and string.format('%d x %d', canvas:getSpriteWidth(), canvas:getSpriteHeight()) or ''
      window:recursiveGetChildById('selectedSpriteLabel'):setText(
         tr('Target: sprite %d | %s | %s. Same-size PNG required; shared IDs change everywhere.',
            selectedSpriteId, selectedSpriteContext or tr('current preview'), size))
   elseif page == 'export' then
      window:recursiveGetChildById('activeWorkCopyLabel'):setText(activeWorkRoot or tr('No work copy is open.'))
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
            string.format('ID %d | %d x %d | %dx', selectedSpriteId or 0, canvas:getSpriteWidth(), canvas:getSpriteHeight(), canvas:getZoom()))
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
      versionBox:addOption(tostring(version), version)
   end
   if activeVersion then
      versionBox:setCurrentOptionByData(activeVersion, true)
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
      displayErrorBox(tr('Assets Editor'), tostring(workRoot))
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
      displayGeneralBox(tr('Unsaved appearance properties'), tr('Save or discard the property changes before opening another work copy.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() openWorkCopyVersion(version) end },
         { text = tr('Cancel'), callback = function() end },
      })
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
   setStatus(tr('Work copy loaded for client %d.', version))
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

function quickReplacePreviewSprite()
   if not selectedSpriteId then
      setStatus(tr('Select a linked sprite before replacing it.'))
      return
   end
   setActivePage('import')
   window:recursiveGetChildById('imagePathEdit'):focus()
   setStatus(tr('Paste a same-size PNG path for sprite %d.', selectedSpriteId))
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
      displayGeneralBox(tr('Discard appearance edits?'), tr('Importing a sprite reloads the work copy and discards unsaved properties.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() replaceSprite(true) end },
         { text = tr('Cancel'), callback = function() end },
      })
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before importing a sprite.'))
      return
   end
   local id = selectedSpriteId
   local path = window:recursiveGetChildById('imagePathEdit'):getText()
   if not id or path == '' then
      setStatus(tr('Select a sprite and enter an absolute PNG path.'))
      return
   end
   local previewSelection = capturePreviewSelection()
   local ok, result = pcall(g_spriteAppearances.importSpriteFromFile, id, path, activeVersion)
   if not ok then
      setStatus(tostring(result))
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
   setStatus(tr('Sprite %d replaced; preview restored: %s.', result, selectedSpriteContext or tr('current selection')))
end

function createAppearance(forceDiscard)
   if hasAppearanceChanges() and not forceDiscard then
      displayGeneralBox(tr('Discard appearance edits?'), tr('Creating an appearance reloads the work copy and discards unsaved properties.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() createAppearance(true) end },
         { text = tr('Cancel'), callback = function() end },
      })
      return
   end
   if not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before creating an appearance.'))
      return
   end
   local category = selectedOption(window:recursiveGetChildById('appearanceCategory'))
   local name = window:recursiveGetChildById('newAppearanceName'):getText()
   local description = window:recursiveGetChildById('newAppearanceDescription'):getText()
   local path = window:recursiveGetChildById('imagePathEdit'):getText()
   if not category or name == '' or path == '' then
      setStatus(tr('Choose a category, enter a name, and provide an absolute PNG path.'))
      return
   end

   local imported, spriteId = pcall(g_spriteAppearances.importSpriteFromFile, 0, path, activeVersion)
   if not imported then
      setStatus(tostring(spriteId))
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
      setStatus(tr('Sprite %d was imported, but the appearance could not be created: %s', spriteId, tostring(appearanceId)))
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
   setStatus(tr('Created appearance %d with sprite %d.', appearanceId, spriteId))
end

local function collectAnimationWidgetChanges()
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

   for phaseIndex, fields in pairs(animationWidgets.phases or {}) do
      local durationMin = tonumber(fields.durationMin:getText())
      local durationMax = tonumber(fields.durationMax:getText())
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
      setAnimationChange(animationWidgets.groupIndex, 'durationMin', durationMin, phaseIndex)
      setAnimationChange(animationWidgets.groupIndex, 'durationMax', durationMax, phaseIndex)
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
      if next(values) then
         updates[section] = values
      end
   end
   local ok, err = pcall(g_things.saveAppearanceEditorData,
      activeVersion, selectedAppearanceCategory, selectedAppearanceId, json.encode(updates))
   if not ok then
      setAppearanceStatus(tostring(err))
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('Properties were saved, but the work copy could not be reloaded.'))
      return
   end
   refreshAppearanceCatalog(selectedAppearanceCategory)
   loadAppearanceRecord(selectedAppearanceCategory, selectedAppearanceId, true, true)
   setAppearanceStatus(tr('Appearance %d saved to the work copy.', selectedAppearanceId))
end

function exportWorkCopy(forceContinue)
   if hasAppearanceChanges() and not forceContinue then
      displayGeneralBox(tr('Unsaved appearance properties'), tr('Save or discard the pending changes before exporting the work copy.'), {
         { text = tr('Save and export'), callback = function()
            saveAppearanceProperties()
            if not hasAppearanceChanges() then exportWorkCopy(true) end
         end },
         { text = tr('Discard and export'), callback = function() clearAppearanceChanges() exportWorkCopy(true) end },
         { text = tr('Cancel'), callback = function() end },
      })
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
      window:recursiveGetChildById('exportStatus'):setText(tostring(result))
      return
   end
   window:recursiveGetChildById('exportStatus'):setText(tr('Asset package exported to %s.', result))
   setStatus(tr('Exported the client %d work package.', activeVersion))
end

function reloadPackage()
   if not activeVersion or g_game.isOnline() then
      return
   end
   if hasAppearanceChanges() then
      displayGeneralBox(tr('Discard appearance edits?'), tr('Reloading the work copy discards unsaved property changes.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() reloadPackageNow() end },
         { text = tr('Cancel'), callback = function() end },
      })
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
      displayGeneralBox(tr('Discard appearance edits?'), tr('Closing the editor discards unsaved property changes.'), {
         { text = tr('Discard'), callback = function() requestClose(true) end },
         { text = tr('Cancel'), callback = function() end },
      })
      return
   end
   destroyWindow()
end
