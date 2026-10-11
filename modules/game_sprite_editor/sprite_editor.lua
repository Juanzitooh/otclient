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
local appearanceChanges = { bools = {}, values = {}, strings = {} }
local appearanceValueWidgets = {}
local appearanceStringWidgets = {}
local buildingAppearanceProperties = false
local currentPage = 'editor'
local currentPropertiesTab = 'flags'
local gameStartCallback
local gameEndCallback

local APPEARANCE_ROW_HEIGHT = 52

local categories = {
   { name = 'Objects', data = 0 },
   { name = 'Outfits', data = 1 },
   { name = 'Effects', data = 2 },
   { name = 'Missiles', data = 3 },
}

local selectAppearance
local renderAppearanceRows

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

local function updateAppearanceSaveButton()
   if window then
      window:recursiveGetChildById('saveAppearanceButton'):setEnabled(hasAppearanceChanges())
   end
end

local function setPropertiesTab(tab)
   if not window then
      return
   end
   currentPropertiesTab = tab == 'values' and 'values' or 'flags'
   local flagsVisible = currentPropertiesTab == 'flags'
   window:recursiveGetChildById('appearanceFlagsList'):setVisible(flagsVisible)
   window:recursiveGetChildById('appearanceFlagsScroll'):setVisible(flagsVisible)
   window:recursiveGetChildById('appearanceValuesList'):setVisible(not flagsVisible)
   window:recursiveGetChildById('appearanceValuesScroll'):setVisible(not flagsVisible)
   window:recursiveGetChildById('flagsTabButton'):setBackgroundColor(flagsVisible and '#603bb0' or '#363636')
   window:recursiveGetChildById('valuesTabButton'):setBackgroundColor(not flagsVisible and '#603bb0' or '#363636')
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
   window:recursiveGetChildById('spriteInfoLabel'):setText(tr('Select an appearance to preview its sprite.'))
   appearanceOriginal = nil
   appearanceValueWidgets = {}
   appearanceStringWidgets = {}
   clearAppearanceChanges()
   buildingAppearanceProperties = false
   updateAppearanceSaveButton()
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
   window:recursiveGetChildById('spriteInfoLabel'):setText(
      string.format('ID %d | %d x %d | %dx', id, canvas:getSpriteWidth(), canvas:getSpriteHeight(), canvas:getZoom()))
   window:recursiveGetChildById('selectedSpriteLabel'):setText(
      tr('Selected sprite ID: %d', id))
   setStatus(tr('Previewing sprite %d.', id))
   return true
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
   local sprites = thing:getSprites()
   if #sprites > 0 then
      selectSprite(sprites[1])
   else
      selectedSpriteId = nil
      window:recursiveGetChildById('spriteInfoLabel'):setText(tr('This appearance has no linked sprites.'))
      window:recursiveGetChildById('selectedSpriteLabel'):setText(tr('This appearance has no linked sprites.'))
   end
end

local function getThingEntries(category)
   local entries = {}
   for _, thing in pairs(g_things.getThingTypes(category)) do
      local id = thing:getId()
      if id and id > 0 then
         local sprites = thing:getSprites()
         local name = thing:getName()
         table.insert(entries, {
            id = id,
            category = category,
            name = name ~= '' and name or tr('Unnamed appearance'),
            spriteId = sprites and sprites[1] or nil,
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
         row:recursiveGetChildById('appearanceName'):setText(entry.name)
         row:recursiveGetChildById('appearanceId'):setText(
            entry.spriteId and tr('ID %d · Sprite %d', entry.id, entry.spriteId) or tr('ID %d · No sprite', entry.id))
         local thumbnail = row:recursiveGetChildById('thumbnail')
         if entry.spriteId then
            thumbnail:setSpriteId(entry.spriteId)
         else
            thumbnail:clearSprite()
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
      tr('Open a work copy to browse appearances.'))
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
         window:recursiveGetChildById('appearanceResultsLabel'):setText(tr('Open a work copy to browse appearances.'))
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
   window:recursiveGetChildById('appearanceCategory'):setCurrentOptionByData(category, true)
   buildAppearanceProperties(data)
   refreshSelectedAppearance()
   setStatus(tr('Appearance %d loaded.', id))
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
   refreshAppearanceCatalog(category)
   if filteredAppearanceEntries[1] then
      loadAppearanceRecord(category, filteredAppearanceEntries[1].id, true)
   else
      clearAppearanceProperties()
      setStatus(tr('No appearances in this category.'))
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
      window:recursiveGetChildById('selectedSpriteLabel'):setText(tr('Selected sprite ID: %d', selectedSpriteId))
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
   loadAppearanceRecord(selectedAppearanceCategory, selectedAppearanceId, true, true)
   selectSprite(result)
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

   window:recursiveGetChildById('newAppearanceName'):setText('')
   window:recursiveGetChildById('newAppearanceDescription'):setText('')
   refreshAppearanceCatalog(category)
   loadAppearanceRecord(category, appearanceId, true)
   selectSprite(spriteId)
   showEditorPage()
   setStatus(tr('Created appearance %d with sprite %d.', appearanceId, spriteId))
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
