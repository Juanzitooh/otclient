SpriteEditorPngFilePicker = {}

local PngFilePicker = {}

local function normalize_directory_path(path)
   path = (path or ''):trim():gsub('\\', '/')
   if path == '' then
      path = g_platform.getCurrentDir()
   end
   if path:match('^%a:/$') or path == '/' then
      return path
   end
   return path:gsub('/+$', '')
end

local function get_parent_directory(path)
   path = normalize_directory_path(path)
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

local function get_path_name(path)
   return path:gsub('/+$', ''):match('([^/]+)$') or path
end

local function get_default_directory()
   local base_directory
   local ok, real_directory = pcall(g_resources.getRealDir, '/data/things/README.md')
   if ok and real_directory and real_directory ~= '' then
      base_directory = real_directory
   else
      base_directory = g_platform.getCurrentDir()
   end
   base_directory = base_directory:gsub('\\', '/'):gsub('/+$', '')
   return normalize_directory_path(base_directory .. '/data/things/pngs')
end

local function get_widget(window, id)
   return window and window:recursiveGetChildById(id) or nil
end

function PngFilePicker:get_widget(id)
   return get_widget(self.window, id)
end

function PngFilePicker:is_open()
   return self.window ~= nil
end

function PngFilePicker:render()
   if not self.window then
      return
   end

   local previous_selection = self.selection
   self.directory = normalize_directory_path(self.directory)
   self.selection = nil
   local list = self:get_widget('filePickerEntries')
   list:destroyChildren()
   self:get_widget('filePickerPathEdit'):setText(self.directory)
   self:get_widget('filePickerSelectedLabel'):setText(tr('Choose a PNG file.'))
   self:get_widget('filePickerUseButton'):setEnabled(false)

   local ok, entries = pcall(g_platform.listDirectoryEntries, self.directory)
   if not ok then
      entries = {}
   end

   local visible_entries = {}
   for _, path in ipairs(entries or {}) do
      local is_directory = path:ends('/')
      if is_directory or path:lower():ends('.png') then
         table.insert(visible_entries, { path = path, is_directory = is_directory })
      end
   end
   table.sort(visible_entries, function(a, b)
      if a.is_directory ~= b.is_directory then
         return a.is_directory
      end
      return a.path:lower() < b.path:lower()
   end)

   local filter = self:get_widget('filePickerFilterEdit'):getText():trim():lower()
   local shown = 0
   for _, entry in ipairs(visible_entries) do
      local name = get_path_name(entry.path)
      if filter == '' or name:lower():find(filter, 1, true) then
         local row = g_ui.createWidget('SpriteEditorFileEntry', list)
         row:setText(entry.is_directory and tr('[Folder] %s', name) or name)
         row.filePickerPath = entry.path
         row.filePickerIsDirectory = entry.is_directory
         if not entry.is_directory and entry.path == previous_selection then
            self.selection = entry.path
         end
         row.onClick = function(widget)
            self:select_entry(widget)
         end
         row.onDoubleClick = function(widget)
            self:activate_entry(widget)
         end
         shown = shown + 1
      end
   end

   self:get_widget('filePickerParentButton'):setEnabled(get_parent_directory(self.directory) ~= nil)
   self:get_widget('filePickerCountLabel'):setText(tr('%d PNG files and folders', shown))
   if self.selection then
      local label = self:get_widget('filePickerSelectedLabel')
      label:setText(self.selection)
      label:setTooltip(self.selection)
      self:get_widget('filePickerUseButton'):setEnabled(true)
   end
   if shown == 0 then
      self:get_widget('filePickerSelectedLabel'):setText(
         tr('No PNG files or folders match this location and filter.'))
   end
end

function PngFilePicker:select_entry(widget)
   if widget.filePickerIsDirectory then
      self.selection = nil
      self:get_widget('filePickerUseButton'):setEnabled(false)
      self:get_widget('filePickerSelectedLabel'):setText(
         tr('Double-click to open %s', get_path_name(widget.filePickerPath)))
      return
   end

   self.selection = widget.filePickerPath
   local label = self:get_widget('filePickerSelectedLabel')
   label:setText(widget.filePickerPath)
   label:setTooltip(widget.filePickerPath)
   self:get_widget('filePickerUseButton'):setEnabled(true)
end

function PngFilePicker:activate_entry(widget)
   if widget.filePickerIsDirectory then
      self.directory = widget.filePickerPath
      self:render()
      return
   end

   self.selection = widget.filePickerPath
   self:use_selected()
end

function PngFilePicker:destroy()
   local window = self.window
   self.window = nil
   self.selection = nil
   self.target = nil
   if not window then
      return
   end

   local ok, err = pcall(function()
      if not window:isDestroyed() then
         window:destroy()
      end
   end)
   if not ok then
      g_logger.error('[game_sprite_editor] Unable to close PNG file browser: ' .. tostring(err))
   end
end

function PngFilePicker:close()
   self:destroy()
end

function PngFilePicker:navigate()
   if not self.window then
      return
   end
   self.directory = normalize_directory_path(self:get_widget('filePickerPathEdit'):getText())
   self:render()
end

function PngFilePicker:go_to_parent()
   if not self.window then
      return
   end
   local parent = get_parent_directory(self.directory)
   if parent then
      self.directory = parent
      self:render()
   end
end

function PngFilePicker:filter()
   self:render()
end

function PngFilePicker:use_selected()
   if not self.window or not self.selection then
      return
   end

   local path = self.selection
   local target = self.target
   self.directory = get_parent_directory(path) or self.directory
   self.callbacks.on_selected(target, path)
   self:destroy()
end

function PngFilePicker:open(target, initial_path)
   self:destroy()
   self.target = target
   initial_path = (initial_path or ''):gsub('\\', '/')
   if initial_path ~= '' and initial_path:lower():ends('.png') then
      self.directory = get_parent_directory(initial_path) or g_platform.getCurrentDir()
      self.selection = g_platform.fileExists(initial_path) and initial_path or nil
   elseif not self.directory then
      self.directory = get_default_directory()
   end

   local opened, window = pcall(g_ui.displayUI, 'sprite_editor_file_picker')
   if not opened or not window then
      self.window = nil
      if not opened then
         g_logger.error('[game_sprite_editor] Unable to open PNG file browser: ' .. tostring(window))
      end
      self.callbacks.on_status(tr('Could not open the PNG file browser. Check the client log.'))
      return false
   end
   self.window = window

   local initialized, err = pcall(function()
      self:get_widget('filePickerGoButton').onClick = function()
         self:navigate()
      end
      self:get_widget('filePickerParentButton').onClick = function()
         self:go_to_parent()
      end
      self:get_widget('filePickerUseButton').onClick = function()
         self:use_selected()
      end
      self:get_widget('filePickerCancelButton').onClick = function()
         self:close()
      end
      local path_edit = self:get_widget('filePickerPathEdit')
      path_edit.onEnter = function()
         self:navigate()
      end
      path_edit.onTextChange = function()
         self.selection = nil
         self:get_widget('filePickerUseButton'):setEnabled(false)
      end
      self:get_widget('filePickerFilterEdit').onTextChange = function()
         self:filter()
      end
      self:render()
      if self.selection then
         self:get_widget('filePickerSelectedLabel'):setText(self.selection)
         self:get_widget('filePickerSelectedLabel'):setTooltip(self.selection)
         self:get_widget('filePickerUseButton'):setEnabled(true)
      end
      self.window:raise()
      self.window:focus()
   end)
   if not initialized then
      g_logger.error('[game_sprite_editor] Unable to initialize PNG file browser: ' .. tostring(err))
      self:destroy()
      self.callbacks.on_status(tr('Could not initialize the PNG file browser. Check the client log.'))
      return false
   end
   return true
end

function SpriteEditorPngFilePicker.new(callbacks)
   return setmetatable({
      callbacks = callbacks,
      directory = nil,
      selection = nil,
      target = nil,
      window = nil,
   }, { __index = PngFilePicker })
end
