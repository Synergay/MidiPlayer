-- Playlist
-- Manage playlists: create, rename, delete, add songs, and auto-advance playback

local midiPlayer = script:FindFirstAncestor("MidiPlayer")

local Controller = require(midiPlayer.Components.Controller)
local Thread = require(midiPlayer.Util.Thread)

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local Playlist = {
    _playlists = {}, -- [name] = { paths }
    _selected = nil,
    _isPlaying = false,
    _currentIndex = 0,

    _ui = {},
}

local DEFAULT_PLAYLIST_NAME = "Default"
local PLAYLISTS_FILE = "midi/playlists.json"

local frame -- root Frame (gui.Frame)
local screen -- PlaylistScreen created by Tabs

-- Utilities
local function safeReadFile(path)
    local ok, res = pcall(readfile, path)
    if ok then return res end
    return nil
end

local function safeWriteFile(path, contents)
    pcall(writefile, path, contents)
end

local function encodeJson(data)
    return HttpService:JSONEncode(data)
end

local function decodeJson(data)
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(data)
    end)
    if ok then return decoded end
    return nil
end

local function savePlaylists(self)
    local data = {
        selected = self._selected,
        playlists = self._playlists,
    }
    safeWriteFile(PLAYLISTS_FILE, encodeJson(data))
end

local function loadPlaylists(self)
    local raw = safeReadFile(PLAYLISTS_FILE)
    if raw then
        local decoded = decodeJson(raw)
        if decoded and type(decoded) == "table" then
            self._playlists = decoded.playlists or {}
            self._selected = decoded.selected or next(self._playlists)
        end
    end
    if not self._selected then
        self._selected = DEFAULT_PLAYLIST_NAME
    end
    if not self._playlists[self._selected] then
        self._playlists[self._selected] = {}
    end
end

-- UI helpers
local function clearChildren(parent)
    for _, child in ipairs(parent:GetChildren()) do
        child:Destroy()
    end
end

local function createText(parent, name, text, size, pos, anchor)
    local l = Instance.new("TextLabel")
    l.Name = name
    l.BackgroundTransparency = 1
    l.Text = text
    l.Font = Enum.Font.Gotham
    l.TextSize = size or 14
    l.TextColor3 = Color3.fromRGB(230, 230, 230)
    l.AnchorPoint = anchor or Vector2.new(0, 0)
    l.Position = pos or UDim2.new()
    l.Size = UDim2.fromOffset(200, size and (size + 8) or 20)
    l.Parent = parent
    return l
end

local function createButton(parent, name, text, size, pos, anchor)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Text = text
    b.AutoButtonColor = true
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = size or 14
    b.TextColor3 = Color3.fromRGB(240, 240, 240)
    b.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    b.BackgroundTransparency = 0.1
    b.BorderSizePixel = 0
    b.AnchorPoint = anchor or Vector2.new(0, 0)
    b.Position = pos or UDim2.new()
    b.Size = UDim2.fromOffset(120, 28)
    b.Parent = parent
    return b
end

local function createInput(parent, name, placeholder, size, pos, anchor)
    local t = Instance.new("TextBox")
    t.Name = name
    t.PlaceholderText = placeholder or ""
    t.Text = ""
    t.Font = Enum.Font.Gotham
    t.TextSize = size or 14
    t.TextColor3 = Color3.fromRGB(240, 240, 240)
    t.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    t.BorderSizePixel = 0
    t.AnchorPoint = anchor or Vector2.new(0, 0)
    t.Position = pos or UDim2.new()
    t.Size = UDim2.fromOffset(180, 28)
    t.ClearTextOnFocus = false
    t.Parent = parent
    return t
end

local function createList(parent, name, pos, size)
    local s = Instance.new("ScrollingFrame")
    s.Name = name
    s.BackgroundTransparency = 0.2
    s.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    s.BorderSizePixel = 0
    s.Position = pos
    s.Size = size
    s.CanvasSize = UDim2.new(0, 0, 0, 0)
    s.ScrollBarThickness = 6

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    layout.Parent = s

    s.Parent = parent
    return s
end

-- Build UI
function Playlist:_buildUI()
    screen:ClearAllChildren()

    -- Header Row: playlist dropdown + actions + play controls
    local header = Instance.new("Frame")
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Size = UDim2.new(1, -16, 0, 36)
    header.Position = UDim2.new(0, 8, 0, 8)
    header.ZIndex = 50
    header.Parent = screen

    local currentBtn = createButton(header, "PlaylistSelect", self._selected, 16, UDim2.new(0, 0, 0, 0))
    currentBtn.ZIndex = 51
    currentBtn.Size = UDim2.fromOffset(180, 28)

    local newBtn = createButton(header, "NewBtn", "+ New", 14, UDim2.new(0, 188, 0, 0))
    newBtn.ZIndex = 51
    newBtn.Size = UDim2.fromOffset(80, 28)
    local renameBtn = createButton(header, "RenameBtn", "Rename", 14, UDim2.new(0, 272, 0, 0))
    renameBtn.ZIndex = 51
    renameBtn.Size = UDim2.fromOffset(90, 28)
    local deleteBtn = createButton(header, "DeleteBtn", "Delete", 14, UDim2.new(0, 366, 0, 0))
    deleteBtn.ZIndex = 51
    deleteBtn.Size = UDim2.fromOffset(80, 28)

    local playBtn = createButton(header, "PlayBtn", "Play", 16, UDim2.new(1, -280, 0, 0), Vector2.new(1, 0))
    playBtn.ZIndex = 51
    playBtn.Size = UDim2.fromOffset(120, 28)
    local stopBtn = createButton(header, "StopBtn", "Stop", 16, UDim2.new(1, -150, 0, 0), Vector2.new(1, 0))
    stopBtn.ZIndex = 51
    stopBtn.Size = UDim2.fromOffset(120, 28)

    -- Dropdown panel (hidden by default)
    local dropdown = Instance.new("Frame")
    dropdown.Name = "Dropdown"
    dropdown.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    dropdown.BackgroundTransparency = 0.1
    dropdown.BorderSizePixel = 0
    dropdown.Position = UDim2.new(0, 0, 0, 32)
    dropdown.Size = UDim2.fromOffset(180, 160)
    dropdown.Visible = false
    dropdown.ZIndex = 60
    dropdown.Parent = header

    local dropList = createList(dropdown, "Playlists", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))
    dropList.ZIndex = 61

    -- Body: left list (all songs), right list (playlist)
    local body = Instance.new("Frame")
    body.Name = "Body"
    body.BackgroundTransparency = 1
    body.Position = UDim2.new(0, 8, 0, 52)
    body.Size = UDim2.new(1, -16, 1, -60)
    body.ZIndex = 50
    body.Parent = screen

    local asTitle = createText(body, "AllSongsTitle", "All Songs", 16, UDim2.new(0, 0, 0, 0))
    asTitle.ZIndex = 51
    local songsList = createList(body, "AllSongs", UDim2.new(0, 0, 0, 24), UDim2.new(0.5, -6, 1, -24))
    songsList.ZIndex = 51

    local plTitle = createText(body, "PlaylistTitle", "Playlist", 16, UDim2.new(0.5, 6, 0, 0))
    plTitle.ZIndex = 51
    local playlistList = createList(body, "PlaylistSongs", UDim2.new(0.5, 6, 0, 24), UDim2.new(0.5, -6, 1, -60))
    playlistList.ZIndex = 51

    local removeBtn = createButton(body, "RemoveBtn", "Remove", 14, UDim2.new(0.5, 6, 1, -30))
    removeBtn.ZIndex = 51
    removeBtn.Size = UDim2.fromOffset(90, 28)
    local upBtn = createButton(body, "UpBtn", "Up", 14, UDim2.new(0.5, 102, 1, -30))
    upBtn.ZIndex = 51
    upBtn.Size = UDim2.fromOffset(60, 28)
    local downBtn = createButton(body, "DownBtn", "Down", 14, UDim2.new(0.5, 168, 1, -30))
    downBtn.ZIndex = 51
    downBtn.Size = UDim2.fromOffset(60, 28)

    -- Store refs
    self._ui = {
        header = header,
        currentBtn = currentBtn,
        dropdown = dropdown,
        dropList = dropList,
        songsList = songsList,
        playlistList = playlistList,
        removeBtn = removeBtn,
        upBtn = upBtn,
        downBtn = downBtn,
        playBtn = playBtn,
        stopBtn = stopBtn,
        renameBtn = renameBtn,
        deleteBtn = deleteBtn,
        newBtn = newBtn,
    }
end

-- Populate lists
function Playlist:_refreshPlaylistsDropdown()
    local ui = self._ui
    clearChildren(ui.dropList)
    local layout = ui.dropList:FindFirstChildOfClass("UIListLayout")
    local total = 0
    for name, _ in pairs(self._playlists) do
        local btn = createButton(ui.dropList, name .. "Item", name)
        btn.Size = UDim2.new(1, -8, 0, 28)
        btn.AnchorPoint = Vector2.new(0, 0)
        btn.Position = UDim2.new(0, 4, 0, total)
        btn.ZIndex = 62
        btn.MouseButton1Click:Connect(function()
            self._selected = name
            ui.currentBtn.Text = name
            ui.dropdown.Visible = false
            self:_refreshPlaylistSongs()
            savePlaylists(self)
        end)
        total = total + 32
    end
    ui.dropList.CanvasSize = UDim2.new(0, 0, 0, total)
end

local function basename(path)
    local fullname = path:match("([^\\]+)$") or path
    local name = fullname:match("^([^%.]+)") or fullname
    return name
end

function Playlist:_refreshAllSongs()
    local ui = self._ui
    clearChildren(ui.songsList)
    local files = listfiles("midi")
    local total = 0
    for _, filePath in ipairs(files) do
        if filePath:sub(-4) ~= ".mid" then continue end
        local row = createButton(ui.songsList, filePath, "+ " .. basename(filePath))
        row.Size = UDim2.new(1, -8, 0, 28)
        row.AnchorPoint = Vector2.new(0, 0)
        row.Position = UDim2.new(0, 4, 0, total)
        row.ZIndex = 52
        row.MouseButton1Click:Connect(function()
            local list = self._playlists[self._selected]
            table.insert(list, filePath)
            self:_refreshPlaylistSongs()
            savePlaylists(self)
        end)
        total = total + 32
    end
    ui.songsList.CanvasSize = UDim2.new(0, 0, 0, total)
end

function Playlist:_refreshPlaylistSongs()
    local ui = self._ui
    clearChildren(ui.playlistList)
    local list = self._playlists[self._selected] or {}
    local total = 0
    for i, filePath in ipairs(list) do
        local isCurrent = (self._isPlaying and i == self._currentIndex)
        local row = createButton(ui.playlistList, filePath .. "_row", (isCurrent and "▶ " or "") .. basename(filePath))
        row.Size = UDim2.new(1, -8, 0, 28)
        row.AnchorPoint = Vector2.new(0, 0)
        row.BackgroundColor3 = isCurrent and Color3.fromRGB(60, 60, 60) or Color3.fromRGB(40, 40, 40)
        row.Position = UDim2.new(0, 4, 0, total)
        row.ZIndex = 52
        row.MouseButton1Click:Connect(function()
            -- select and load this song
            self._currentIndex = i
            self._isPlaying = false -- selecting doesn't auto-play until Play pressed
            Controller:Select(filePath)
            self:_refreshPlaylistSongs()
            savePlaylists(self)
        end)
        total = total + 32
    end
    ui.playlistList.CanvasSize = UDim2.new(0, 0, 0, total)
end

-- Actions
function Playlist:_newPlaylist(name)
    name = name or (DEFAULT_PLAYLIST_NAME .. " " .. tostring(#self._playlists + 1))
    if not self._playlists[name] then
        self._playlists[name] = {}
        self._selected = name
        self._currentIndex = 0
        savePlaylists(self)
        self:_refreshPlaylistsDropdown()
        self._ui.currentBtn.Text = name
        self:_refreshPlaylistSongs()
    end
end

function Playlist:_renamePlaylist(newName)
    if not newName or newName == "" then return end
    if newName == self._selected then return end
    local existing = self._playlists[self._selected]
    if not existing then return end
    self._playlists[self._selected] = nil
    self._playlists[newName] = existing
    self._selected = newName
    savePlaylists(self)
    self:_refreshPlaylistsDropdown()
    self._ui.currentBtn.Text = newName
end

function Playlist:_deletePlaylist()
    if self._selected == DEFAULT_PLAYLIST_NAME and (self._playlists[self._selected] and #self._playlists[self._selected] > 0) then
        -- allow deletion, will fallback to creating a new default
    end
    self._playlists[self._selected] = nil
    self._selected = next(self._playlists) or DEFAULT_PLAYLIST_NAME
    if not self._playlists[self._selected] then
        self._playlists[self._selected] = {}
    end
    self._currentIndex = 0
    self._isPlaying = false
    savePlaylists(self)
    self:_refreshPlaylistsDropdown()
    self._ui.currentBtn.Text = self._selected
    self:_refreshPlaylistSongs()
end

function Playlist:_removeSelected(index)
    local list = self._playlists[self._selected]
    if not list or not list[index] then return end
    table.remove(list, index)
    if self._currentIndex > #list then
        self._currentIndex = #list
    end
    savePlaylists(self)
    self:_refreshPlaylistSongs()
end

function Playlist:_move(index, delta)
    local list = self._playlists[self._selected]
    if not list or not list[index] then return end
    local newIndex = math.clamp(index + delta, 1, #list)
    if newIndex == index then return end
    local item = table.remove(list, index)
    table.insert(list, newIndex, item)
    if self._currentIndex == index then
        self._currentIndex = newIndex
    end
    savePlaylists(self)
    self:_refreshPlaylistSongs()
end

function Playlist:_startPlayback(fromIndex)
    local list = self._playlists[self._selected]
    if not list or #list == 0 then return end
    self._isPlaying = true
    self._currentIndex = math.clamp(fromIndex or (self._currentIndex ~= 0 and self._currentIndex or 1), 1, #list)
    Controller:Select(list[self._currentIndex])
    -- will auto-play on FileLoaded below
end

function Playlist:_stopPlayback()
    self._isPlaying = false
end

-- Wiring
function Playlist:_wire()
    local ui = self._ui

    ui.currentBtn.MouseButton1Click:Connect(function()
        ui.dropdown.Visible = not ui.dropdown.Visible
        self:_refreshPlaylistsDropdown()
    end)

    ui.newBtn.MouseButton1Click:Connect(function()
        -- inline simple naming via a quick input field overlay
        local nameBox = createInput(ui.header, "NameBox", "New playlist name", 14, UDim2.new(0, 454, 0, 0))
        nameBox.FocusLost:Connect(function(enter)
            local text = nameBox.Text
            nameBox:Destroy()
            if enter and text ~= "" then
                self:_newPlaylist(text)
            end
        end)
        nameBox:CaptureFocus()
    end)

    ui.renameBtn.MouseButton1Click:Connect(function()
        local nameBox = createInput(ui.header, "RenameBox", "Rename to...", 14, UDim2.new(0, 454, 0, 0))
        nameBox.Text = self._selected
        nameBox.FocusLost:Connect(function(enter)
            local text = nameBox.Text
            nameBox:Destroy()
            if enter and text ~= "" then
                self:_renamePlaylist(text)
            end
        end)
        nameBox:CaptureFocus()
    end)

    ui.deleteBtn.MouseButton1Click:Connect(function()
        self:_deletePlaylist()
    end)

    ui.removeBtn.MouseButton1Click:Connect(function()
        if self._currentIndex > 0 then
            self:_removeSelected(self._currentIndex)
        end
    end)

    ui.upBtn.MouseButton1Click:Connect(function()
        if self._currentIndex > 0 then
            self:_move(self._currentIndex, -1)
        end
    end)

    ui.downBtn.MouseButton1Click:Connect(function()
        if self._currentIndex > 0 then
            self:_move(self._currentIndex, 1)
        end
    end)

    ui.playBtn.MouseButton1Click:Connect(function()
        local startIndex = (self._currentIndex > 0) and self._currentIndex or 1
        self:_startPlayback(startIndex)
    end)

    ui.stopBtn.MouseButton1Click:Connect(function()
        self:_stopPlayback()
    end)

    -- Auto-play on file loaded while playlist mode is active
    Controller.FileLoaded:Connect(function(song)
        if self._isPlaying then
            -- align index to current song if needed
            local list = self._playlists[self._selected]
            for i, path in ipairs(list) do
                if path == song.Path then
                    self._currentIndex = i
                    break
                end
            end
            -- begin play
            Thread.Delay(0, function()
                song:Play()
                self:_refreshPlaylistSongs()
            end)
        end
    end)

    -- Detect end of song to advance
    local lastPlaying = false
    RunService.Heartbeat:Connect(function()
        local current = Controller.CurrentSong
        if self._isPlaying and current then
            local nowPlaying = current.IsPlaying
            if lastPlaying and (not nowPlaying) and (current.TimePosition >= current.TimeLength - 0.01) then
                -- advance
                local list = self._playlists[self._selected]
                if list and #list > 0 then
                    local nextIndex = self._currentIndex + 1
                    if nextIndex > #list then
                        -- reached end
                        self:_stopPlayback()
                    else
                        self._currentIndex = nextIndex
                        Controller:Select(list[self._currentIndex])
                    end
                    self:_refreshPlaylistSongs()
                end
            end
            lastPlaying = nowPlaying
        else
            lastPlaying = false
        end
    end)
end

function Playlist:Init(root)
    frame = root
    screen = frame:FindFirstChild("PlaylistScreen")
    if not screen then
        -- Tabs should have created this, but create defensively
        screen = Instance.new("Frame")
        screen.Name = "PlaylistScreen"
        screen.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        screen.Size = UDim2.fromScale(1, 1)
        screen.Parent = frame
        screen.Visible = false
    end

    loadPlaylists(self)
    self:_buildUI()
    self:_refreshPlaylistsDropdown()
    self:_refreshAllSongs()
    self:_refreshPlaylistSongs()
    self:_wire()
end

return Playlist
