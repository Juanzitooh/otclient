local window
local appearanceWindow
local topMenuButton
local canvas
local mountedRoots = {}
local activeVersion
local activeAssetPath
local selectedAppearanceCategory = 0
local selectedAppearanceId
local selectedSpriteId
local appearanceOriginal
local appearanceChanges = { bools = {}, values = {}, strings = {} }
local appearanceValueWidgets = {}
local appearanceStringWidgets = {}
local buildingAppearanceProperties = false
local gameStartCallback
local gameEndCallback

local categories = {
   { name = 'Objects', data = 0 },
   { name = 'Outfits', data = 1 },
   { name = 'Effects', data = 2 },
   { name = 'Missiles', data = 3 },
}

local function setStatus(message)
   if window then
      window:recursiveGetChildById('statusLabel'):setText(message)
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
      next(appearanceChanges.strings) ~= nil
end

local function clearAppearanceChanges()
   appearanceChanges = { bools = {}, values = {}, strings = {} }
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

local function selectSprite(id)
   if not canvas or not activeVersion then
      return false
   end
   if not canvas:setSpriteId(id) then
      setStatus(tr('Sprite %d is not available in this 15.x work copy.', id))
      return false
   end

   selectedSpriteId = id
   window:recursiveGetChildById('spriteIdEdit'):setText(tostring(id))
   window:recursiveGetChildById('spriteInfoLabel'):setText(
      string.format('ID %d | %d x %d', id, canvas:getSpriteWidth(), canvas:getSpriteHeight()))
   window:recursiveGetChildById('zoomLabel'):setText(string.format('%dx', canvas:getZoom()))
   setStatus(tr('Previewing sprite %d.', id))
   return true
end

local function addSpriteRows(list, thing)
   list:destroyChildren()
   if not thing or thing:getId() ~= selectedAppearanceId then
      local row = g_ui.createWidget('AppearanceSpriteButton', list)
      row:setText(tr('No sprites found'))
      row:setEnabled(false)
      return
   end

   local seen = {}
   for _, spriteId in ipairs(thing:getSprites()) do
      if not seen[spriteId] then
         seen[spriteId] = true
         local row = g_ui.createWidget('AppearanceSpriteButton', list)
         row:setWidth(175)
         row:setText(tostring(spriteId))
         row.onClick = function()
            selectSprite(spriteId)
         end
      end
   end
   if not next(seen) then
      local row = g_ui.createWidget('AppearanceSpriteButton', list)
      row:setText(tr('No sprites found'))
      row:setEnabled(false)
   end
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

   window:recursiveGetChildById('appearanceInfoLabel'):setText(
      string.format('%s | ID %d', thing:getName() ~= '' and thing:getName() or tr('Unnamed appearance'), selectedAppearanceId))
   addSpriteRows(window:recursiveGetChildById('assetSpriteList'), thing)
   local sprites = thing:getSprites()
   if #sprites > 0 then
      selectSprite(sprites[1])
   else
      selectedSpriteId = nil
      window:recursiveGetChildById('spriteInfoLabel'):setText(tr('This appearance has no linked sprites.'))
   end
end

local function updateAppearanceSaveButton()
   if appearanceWindow then
      appearanceWindow:recursiveGetChildById('saveAppearanceButton'):setEnabled(hasAppearanceChanges())
   end
end

local function setAppearanceStatus(message)
   if appearanceWindow then
      appearanceWindow:recursiveGetChildById('appearanceStatus'):setText(message)
   end
end

local function buildAppearanceProperties(data, thing)
   local flagsList = appearanceWindow:recursiveGetChildById('appearanceFlagsList')
   local valuesList = appearanceWindow:recursiveGetChildById('appearanceValuesList')
   flagsList:destroyChildren()
   valuesList:destroyChildren()
   appearanceValueWidgets = {}
   appearanceStringWidgets = {}
   clearAppearanceChanges()
   appearanceOriginal = data
   buildingAppearanceProperties = true

   local nameEdit = appearanceWindow:recursiveGetChildById('appearanceName')
   local descriptionEdit = appearanceWindow:recursiveGetChildById('appearanceDescription')
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
      checkbox:setWidth(230)
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

   if appearanceWindow then
      local spriteList = appearanceWindow:recursiveGetChildById('appearanceSpriteList')
      spriteList:destroyChildren()
      if thing and thing:getId() == selectedAppearanceId then
         local seen = {}
         for _, spriteId in ipairs(thing:getSprites()) do
            if not seen[spriteId] then
               seen[spriteId] = true
               local row = g_ui.createWidget('AppearanceSpriteButton', spriteList)
               row:setWidth(125)
               row:setText(tostring(spriteId))
               row.onClick = function()
                  selectSprite(spriteId)
               end
            end
         end
      end
   end

   buildingAppearanceProperties = false
   updateAppearanceSaveButton()
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

local function createWindow()
   if window then
      window:destroy()
   end
   window = g_ui.displayUI('/game_sprite_editor/sprite_editor.otui')
   if not window then
      displayErrorBox(tr('Assets Editor'), tr('Could not create the editor window. Check the client log for UI errors.'))
      return false
   end

   canvas = window:recursiveGetChildById('canvas')
   canvas.onStateChange = function()
      if canvas then
         window:recursiveGetChildById('zoomLabel'):setText(string.format('%dx', canvas:getZoom()))
      end
   end
   addCategories(window:recursiveGetChildById('appearanceCategory'))

   local versionBox = window:recursiveGetChildById('versionComboBox')
   for _, version in ipairs(getVersions()) do
      versionBox:addOption(tostring(version), version)
   end
   if activeVersion then
      versionBox:setCurrentOptionByData(activeVersion, true)
   end
   window:show()
   window:raise()
   window:focus()
   return true
end

local function destroyWindow()
   if appearanceWindow then
      appearanceWindow:destroy()
      appearanceWindow = nil
   end
   if window then
      window:destroy()
      window = nil
      canvas = nil
   end
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
   if not loadAssets(version) then
      createWindow()
      return
   end
   createWindow()
   window:recursiveGetChildById('versionComboBox'):setCurrentOptionByData(version, true)
   setStatus(tr('Work copy loaded for client %d.', version))
end

function loadAppearanceFromMain(forceDiscard)
   if not window or not activeVersion or g_game.isOnline() then
      setStatus(tr('Open a 15.x work copy before loading appearances.'))
      return
   end
   if hasAppearanceChanges() and not forceDiscard then
      displayGeneralBox(tr('Discard appearance edits?'), tr('Loading another appearance discards unsaved property changes.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() loadAppearanceFromMain(true) end },
         { text = tr('Cancel'), callback = function() end },
      })
      return
   end
   local category = selectedOption(window:recursiveGetChildById('appearanceCategory'))
   local id = tonumber(window:recursiveGetChildById('appearanceIdEdit'):getText())
   if not category or not id or id < 1 or id % 1 ~= 0 then
      setStatus(tr('Select a category and enter a positive appearance ID.'))
      return
   end
   local ok, data = pcall(g_things.getAppearanceEditorData, activeVersion, category, id)
   if not ok then
      setStatus(tostring(data))
      return
   end
   local decoded, appearanceData = pcall(json.decode, data)
   if not decoded or type(appearanceData) ~= 'table' then
      setStatus(tr('Appearance data could not be read.'))
      return
   end
   selectedAppearanceCategory = category
   selectedAppearanceId = id
   local thing = g_things.getThingType(id, category)
   if not thing or thing:getId() ~= id then
      setStatus(tr('Appearance %d was read from the work copy but is not loaded by the client.', id))
      return
   end
   refreshSelectedAppearance()
   setStatus(tr('Appearance %d loaded.', id))
   if appearanceWindow then
      appearanceWindow:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(category, true)
      appearanceWindow:recursiveGetChildById('appearanceId'):setText(tostring(id))
      loadAppearance(true)
   end
end

function loadSpriteId()
   if not window or not activeVersion then
      setStatus(tr('Open a work copy before previewing a sprite.'))
      return
   end
   local id = tonumber(window:recursiveGetChildById('spriteIdEdit'):getText())
   if not id or id < 1 or id % 1 ~= 0 then
      setStatus(tr('Enter a positive sprite ID.'))
      return
   end
   selectSprite(id)
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
   local id = tonumber(window:recursiveGetChildById('spriteIdEdit'):getText())
   local path = window:recursiveGetChildById('imagePathEdit'):getText()
   if not id or id < 1 or id % 1 ~= 0 or path == '' then
      setStatus(tr('Choose a sprite ID and enter an absolute PNG path.'))
      return
   end
   local ok, result = pcall(g_spriteAppearances.importSpriteFromFile, id, path, activeVersion)
   if not ok then
      setStatus(tostring(result))
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('The sprite was written, but the work copy could not be reloaded.'))
      return
   end
   selectSprite(result)
   refreshSelectedAppearance()
   setStatus(tr('Sprite %d replaced from the prepared PNG.', result))
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

   window:recursiveGetChildById('appearanceIdEdit'):setText(tostring(appearanceId))
   window:recursiveGetChildById('newAppearanceName'):setText('')
   window:recursiveGetChildById('newAppearanceDescription'):setText('')
   loadAppearanceFromMain(true)
   selectSprite(spriteId)
   setStatus(tr('Created appearance %d with sprite %d.', appearanceId, spriteId))
end

function openAppearanceEditor()
   if not window or not activeVersion or not selectedAppearanceId or g_game.isOnline() then
      setStatus(tr('Load an appearance from a 15.x work copy before editing its properties.'))
      return
   end
   if appearanceWindow then
      appearanceWindow:raise()
      appearanceWindow:focus()
      return
   end
   appearanceWindow = g_ui.displayUI('/game_sprite_editor/appearance_editor.otui')
   if not appearanceWindow then
      displayErrorBox(tr('Assets Editor'), tr('Could not create the appearance properties window.'))
      return
   end
   addCategories(appearanceWindow:recursiveGetChildById('appearanceCategory'))
   appearanceWindow:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(selectedAppearanceCategory, true)
   appearanceWindow:recursiveGetChildById('appearanceId'):setText(tostring(selectedAppearanceId))
   appearanceWindow:show()
   appearanceWindow:raise()
   appearanceWindow:focus()
   loadAppearance(true)
end

function loadAppearance(forceDiscard)
   if not appearanceWindow or not activeVersion then
      return
   end
   if hasAppearanceChanges() and not forceDiscard then
      displayGeneralBox(tr('Discard appearance edits?'), tr('Loading another appearance discards the unsaved property changes.'), {
         { text = tr('Discard'), callback = function() clearAppearanceChanges() loadAppearance(true) end },
         { text = tr('Cancel'), callback = function() end },
      })
      return
   end
   local category = selectedOption(appearanceWindow:recursiveGetChildById('appearanceCategory'))
   local id = tonumber(appearanceWindow:recursiveGetChildById('appearanceId'):getText())
   if not category or not id or id < 1 or id % 1 ~= 0 then
      setAppearanceStatus(tr('Select a category and enter a positive appearance ID.'))
      return
   end
   local ok, encoded = pcall(g_things.getAppearanceEditorData, activeVersion, category, id)
   if not ok then
      setAppearanceStatus(tostring(encoded))
      return
   end
   local decoded, data = pcall(json.decode, encoded)
   if not decoded or type(data) ~= 'table' or type(data.bools) ~= 'table' or type(data.values) ~= 'table' then
      setAppearanceStatus(tr('Appearance properties could not be read.'))
      return
   end
   selectedAppearanceCategory = category
   selectedAppearanceId = id
   window:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(category, true)
   window:recursiveGetChildById('appearanceIdEdit'):setText(tostring(id))
   local thing = g_things.getThingType(id, category)
   if not thing or thing:getId() ~= id then thing = nil end
   buildAppearanceProperties(data, thing)
   setAppearanceStatus(tr('Appearance %d loaded.', id))
   refreshSelectedAppearance()
end

function saveAppearanceProperties()
   if not appearanceWindow or not appearanceOriginal or not activeVersion or g_game.isOnline() then
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
   if not hasAppearanceChanges() then
      setAppearanceStatus(tr('There are no appearance changes to save.'))
      return
   end

   local changesJson = json.encode(appearanceChanges)
   local ok, err = pcall(g_things.saveAppearanceEditorData,
      activeVersion, selectedAppearanceCategory, selectedAppearanceId, changesJson)
   if not ok then
      setAppearanceStatus(tostring(err))
      return
   end
   if not reloadAssets() then
      displayErrorBox(tr('Assets Editor'), tr('Properties were saved, but the work copy could not be reloaded.'))
      return
   end
   setAppearanceStatus(tr('Appearance %d saved to the work copy.', selectedAppearanceId))
   loadAppearance(true)
end

function closeAppearanceEditor(forceDiscard)
   if not appearanceWindow then
      return
   end
   if hasAppearanceChanges() and not forceDiscard then
      displayGeneralBox(tr('Discard appearance edits?'), tr('Closing this window discards unsaved property changes.'), {
         { text = tr('Discard'), callback = function() closeAppearanceEditor(true) end },
         { text = tr('Cancel'), callback = function() end },
      })
      return
   end
   appearanceWindow:destroy()
   appearanceWindow = nil
   appearanceOriginal = nil
   clearAppearanceChanges()
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
   refreshSelectedAppearance()
   if appearanceWindow and selectedAppearanceId then
      appearanceWindow:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(selectedAppearanceCategory, true)
      appearanceWindow:recursiveGetChildById('appearanceId'):setText(tostring(selectedAppearanceId))
      loadAppearance(true)
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
