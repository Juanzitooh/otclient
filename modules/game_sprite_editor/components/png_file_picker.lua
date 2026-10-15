SpriteEditorPngFilePicker = {}

local PngFilePicker = {}
local CELL_WIDTH = 66
local CELL_HEIGHT = 62
local CELL_GAP = 3

local function is_directory_target(target)
   return target == 'export' or target == 'batch' or target == 'appearanceImport' or target == 'appearanceExport'
end

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

local function get_virtual_png_path(path)
   local ok, source_directory = pcall(g_resources.getRealDir, '/data/things/README.md')
   if not ok or not source_directory or source_directory == '' then
      return nil
   end

   source_directory = normalize_directory_path(source_directory)
   path = normalize_directory_path(path)
   local prefix = source_directory .. '/'
   if path:sub(1, #prefix):lower() ~= prefix:lower() then
      return nil
   end

   local virtual_path = '/' .. path:sub(#prefix + 1)
   local exists, file_exists = pcall(g_resources.fileExists, virtual_path)
   return exists and file_exists and virtual_path or nil
end

local function set_cell_preview(cell, path)
   path = path or ''
   if cell.filePickerPreviewPath == path then
      return true
   end

   local thumbnail = cell:recursiveGetChildById('filePickerThumbnail')
   local loaded, err = pcall(thumbnail.setImageSource, thumbnail, path)
   if not loaded then
      g_logger.warning('[game_sprite_editor] Unable to preview PNG file: ' .. tostring(err))
      return false
   end
   cell.filePickerPreviewPath = path
   return true
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

function PngFilePicker:render_entries(scroll_y)
   if not self.window then
      return
   end

   local list = self:get_widget('filePickerEntries')
   local content = self:get_widget('filePickerContent')
   if not list or not content then
      return
   end

   local column_count = math.max(1, math.floor((list:getWidth() + CELL_GAP) / (CELL_WIDTH + CELL_GAP)))
   local row_height = CELL_HEIGHT + CELL_GAP
   local total_rows = math.ceil(#self.visible_entries / column_count)
   content:setHeight(math.max(1, total_rows * row_height))

   local first_row = math.floor(math.max(0, scroll_y or 0) / row_height)
   local viewport_height = math.max(list:getHeight(), CELL_HEIGHT)
   local pool_size = (math.ceil(viewport_height / row_height) + 2) * column_count
   while #self.cells < pool_size do
      local cell = g_ui.createWidget('SpriteEditorFileEntry', content)
      cell.onClick = function(widget)
         self:select_entry(widget)
      end
      cell.onDoubleClick = function(widget)
         self:activate_entry(widget)
      end
      cell.onDragEnter = function(widget)
         if not widget.filePickerPath or not self.callbacks.can_drag(self.target) then
            return false
         end
         return true
      end
      cell.onDragMove = function(_, mouse_position)
         local canvas = self.callbacks.get_canvas()
         local over_canvas = canvas and canvas:isVisible() and canvas:containsPoint(mouse_position)
         if canvas then
            canvas:setBorderWidth(over_canvas and 2 or 0)
            canvas:setBorderColor(over_canvas and '#8f69d3' or 'alpha')
         end
         return true
      end
      cell.onDragLeave = function()
         local canvas = self.callbacks.get_canvas()
         if canvas then
            canvas:setBorderWidth(0)
            canvas:setBorderColor('alpha')
         end
         return true
      end
      table.insert(self.cells, cell)
   end

   local first_index = first_row * column_count + 1
   for slot, cell in ipairs(self.cells) do
      local index = first_index + slot - 1
      local entry = self.visible_entries[index]
      cell:setVisible(entry ~= nil)
      if not entry then
         cell.filePickerPath = nil
         cell.filePickerIsDirectory = false
         cell.isPngFilePickerCell = false
         cell:setDraggable(false)
         cell:setOn(false)
         cell:setTooltip('')
         set_cell_preview(cell, '')
         cell:recursiveGetChildById('filePickerFolderLabel'):setVisible(false)
      else
         local name = get_path_name(entry.path)
         cell:setMarginTop(math.floor((index - 1) / column_count) * row_height)
         cell:setMarginLeft(((index - 1) % column_count) * (CELL_WIDTH + CELL_GAP))
         cell.filePickerPath = entry.path
         cell.filePickerIsDirectory = entry.is_directory
         cell.isPngFilePickerCell = not entry.is_directory
         cell:setOn((self.selection == entry.path) or
            (is_directory_target(self.target) and entry.is_directory and
               normalize_directory_path(entry.path) == self.selection))
         cell:setTooltip(entry.is_directory and tr('[Folder] %s', name) or name)
         cell:setDraggable(not entry.is_directory and self.target == 'replace' and
            self.callbacks.can_drag(self.target))

         local folder_label = cell:recursiveGetChildById('filePickerFolderLabel')
         if entry.is_directory then
            set_cell_preview(cell, '')
            folder_label:setText(tr('Folder'))
            folder_label:setVisible(true)
         else
            local virtual_path = get_virtual_png_path(entry.path)
            local preview_loaded = set_cell_preview(cell, virtual_path)
            folder_label:setText(tr('PNG'))
            folder_label:setVisible(not preview_loaded)
         end
      end
   end
end

function PngFilePicker:render()
   if not self.window then
      return
   end

   local previous_selection = self.selection
   local directory_mode = is_directory_target(self.target)
   local folder_title = (self.target == 'export' or self.target == 'appearanceExport') and
      tr('Choose a destination folder') or
      (self.target == 'appearanceImport' and tr('Choose appearance bundle folder(s)') or
         tr('Choose a folder with prepared PNGs'))
   local folder_hint = (self.target == 'export' or self.target == 'appearanceExport') and
      tr('Choose where the package will be created.') or
      (self.target == 'appearanceImport' and tr('Choose one folder containing manifest.json, or a parent folder containing several appearance bundle folders.') or
         tr('Choose a folder containing individual prepared PNG sprites.'))
   self.directory = normalize_directory_path(self.directory)
   self.selection = directory_mode and normalize_directory_path(previous_selection or self.directory) or previous_selection
   self.rendering = true
   self:get_widget('filePickerPathEdit'):setText(self.directory)
   self.rendering = false
   self:get_widget('filePickerUseButton'):setVisible(directory_mode)
   self:get_widget('filePickerUseButton'):setEnabled(directory_mode and self.selection ~= nil)

   local ok, entries = pcall(g_platform.listDirectoryEntries, self.directory)
   if not ok then
      entries = {}
      self.callbacks.on_status(tr('Could not read this folder. Check its path and permissions.'))
   end

   local visible_entries = {}
   for _, path in ipairs(entries or {}) do
      local is_directory = path:ends('/')
      if is_directory or (not directory_mode and path:lower():ends('.png')) then
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
   self.visible_entries = {}
   for _, entry in ipairs(visible_entries) do
      local name = get_path_name(entry.path)
      if filter == '' or name:lower():find(filter, 1, true) then
         table.insert(self.visible_entries, entry)
         if (directory_mode and entry.is_directory and normalize_directory_path(entry.path) == previous_selection) or
               (not directory_mode and not entry.is_directory and entry.path == previous_selection) then
            self.selection = entry.path
         end
      end
   end

   self:get_widget('filePickerEntries'):setVirtualOffset({ x = 0, y = 0 })
   self:render_entries(0)
   self:get_widget('filePickerEntries'):updateScrollBars()
   self:get_widget('filePickerParentButton'):setEnabled(get_parent_directory(self.directory) ~= nil)
   self:get_widget('filePickerCountLabel'):setText(directory_mode and tr('%d folders', #self.visible_entries) or
      tr('%d PNG files and folders', #self.visible_entries))
   self.window:setText(directory_mode and folder_title or tr('Choose a PNG file'))
   self:get_widget('filePickerHintLabel'):setText(directory_mode and folder_hint or
      (self.target == 'replace' and
         tr('Click selects. Hover shows name. Drag to replace.') or
         tr('Click a PNG to select it.')))
   self:get_widget('filePickerUseButton'):setText(directory_mode and tr('Use folder') or tr('Use PNG'))

   if self.selection then
      local selected_path = directory_mode and normalize_directory_path(self.selection) or self.selection
      local label = self:get_widget('filePickerSelectedLabel')
      label:setText(directory_mode and selected_path or get_path_name(selected_path))
      label:setTooltip(selected_path)
   elseif #self.visible_entries == 0 then
      self:get_widget('filePickerSelectedLabel'):setText(directory_mode and
         tr('No folders match this location and filter.') or
         tr('No PNG files or folders match this location and filter.'))
      self:get_widget('filePickerSelectedLabel'):setTooltip('')
   else
      self:get_widget('filePickerSelectedLabel'):setText(directory_mode and
         tr('Select a folder or double-click to open it.') or tr('Click a PNG to select it.'))
      self:get_widget('filePickerSelectedLabel'):setTooltip('')
   end
end

function PngFilePicker:select_entry(widget)
   if widget.filePickerIsDirectory then
      if is_directory_target(self.target) then
         self.selection = normalize_directory_path(widget.filePickerPath)
         local label = self:get_widget('filePickerSelectedLabel')
         label:setText(self.selection)
         label:setTooltip(self.selection)
         self:get_widget('filePickerUseButton'):setEnabled(true)
         return
      end
      self.selection = nil
      self:get_widget('filePickerUseButton'):setEnabled(false)
      self:get_widget('filePickerSelectedLabel'):setText(
         tr('Double-click to open %s', get_path_name(widget.filePickerPath)))
      return
   end

   self.selection = widget.filePickerPath
   self:use_selected()
end

function PngFilePicker:activate_entry(widget)
   if widget.filePickerIsDirectory then
      self.directory = widget.filePickerPath
      if is_directory_target(self.target) then
         self.selection = normalize_directory_path(widget.filePickerPath)
      end
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
   self.visible_entries = {}
   self.cells = {}
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
   if is_directory_target(self.target) then
      self.selection = self.directory
   else
      self.selection = nil
   end
   self:render()
end

function PngFilePicker:go_to_parent()
   if not self.window then
      return
   end
   local parent = get_parent_directory(self.directory)
   if parent then
      self.directory = parent
      if is_directory_target(self.target) then
         self.selection = self.directory
      end
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
   if not is_directory_target(target) then
      self.directory = get_parent_directory(path) or self.directory
   end
   self.callbacks.on_selected(target, path)
   self:destroy()
end

function PngFilePicker:open(target, initial_path)
   self:destroy()
   self.target = target
   initial_path = (initial_path or ''):gsub('\\', '/')
   if is_directory_target(target) then
      self.directory = normalize_directory_path(initial_path ~= '' and initial_path or g_platform.getCurrentDir())
      self.selection = nil
   elseif initial_path ~= '' and initial_path:lower():ends('.png') then
      self.directory = get_parent_directory(initial_path) or g_platform.getCurrentDir()
      self.selection = g_platform.fileExists(initial_path) and initial_path or nil
   elseif not self.directory then
      self.directory = get_default_directory()
   end

   local opened, window = pcall(g_ui.displayUI, '/game_sprite_editor/sprite_editor_file_picker')
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
         if self.rendering then
            return
         end
         self.selection = nil
         self:get_widget('filePickerUseButton'):setEnabled(false)
      end
      self:get_widget('filePickerFilterEdit').onTextChange = function()
         self:filter()
      end
      self:get_widget('filePickerEntries').onScrollChange = function(_, offset)
         self:render_entries(offset.y)
      end
      self:render()
      if self.selection then
         self:get_widget('filePickerSelectedLabel'):setText(get_path_name(self.selection))
         self:get_widget('filePickerSelectedLabel'):setTooltip(self.selection)
         self:get_widget('filePickerUseButton'):setEnabled(is_directory_target(self.target))
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
      rendering = false,
      visible_entries = {},
      cells = {},
   }, { __index = PngFilePicker })
end
