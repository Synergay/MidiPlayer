-- Tabs
-- Adds a simple tab bar to switch between UI screens

local midiPlayer = script:FindFirstAncestor("MidiPlayer")

local Tabs = {
    _active = "Player";
}

local TAB_NAMES = { "Player", "Library", "Settings" }

local frame -- root frame (gui.Frame)
local tabBar
local screens = {}
local buttons = {}

local function createTabBar(parent)
    local bar = Instance.new("Frame")
    bar.Name = "TabBar"
    bar.BackgroundTransparency = 1
    bar.BorderSizePixel = 0
    bar.Size = UDim2.new(0, 280, 1, 0) -- width fits three buttons
    bar.AnchorPoint = Vector2.new(1, 0)
    bar.Position = UDim2.new(1, -8, 0, 0) -- right-aligned with small padding
    bar.ZIndex = 10
    bar.Parent = parent

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = bar

    return bar
end

local function createButton(name)
    local btn = Instance.new("TextButton")
    btn.Name = name .. "Tab"
    btn.Text = name
    btn.AutoButtonColor = true
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 14
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.BackgroundTransparency = 0.3
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    btn.BorderSizePixel = 0
    btn.Size = UDim2.fromOffset(80, 24)
    btn.ZIndex = 11
    return btn
end

local function ensureScreen(name)
    if screens[name] then return screens[name] end

    local scr = Instance.new("Frame")
    scr.Name = name .. "Screen"
    scr.BackgroundTransparency = 0
    scr.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    scr.BorderSizePixel = 0
    scr.ZIndex = 2

    -- Try to position over the content area (below Handle if present)
    local contentTop = 0
    local handle = frame:FindFirstChild("Handle")
    if handle then
        contentTop = handle.AbsoluteSize.Y
        -- If AbsoluteSize not ready yet, fall back to a reasonable default
        if contentTop == 0 then contentTop = 28 end
    else
        contentTop = 28
    end

    scr.Position = UDim2.new(0, 0, 0, contentTop)
    scr.Size = UDim2.new(1, 0, 1, -contentTop)

    -- Simple placeholder content
    local label = Instance.new("TextLabel")
    label.Name = "Title"
    label.AnchorPoint = Vector2.new(0.5, 0.5)
    label.Position = UDim2.fromScale(0.5, 0.5)
    label.Size = UDim2.fromOffset(300, 40)
    label.BackgroundTransparency = 1
    label.Text = name .. " (placeholder)"
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 24
    label.Parent = scr

    scr.Visible = false
    scr.Parent = frame

    screens[name] = scr
    return scr
end

function Tabs:_setActive(name)
    self._active = name

    -- Visual state for buttons
    for tabName, btn in pairs(buttons) do
        if tabName == name then
            btn.BackgroundTransparency = 0.1
        else
            btn.BackgroundTransparency = 0.3
        end
    end

    -- Toggle built-in Player UI and custom screens
    local hasPlayer = frame:FindFirstChild("Main") and frame:FindFirstChild("Sidebar") and frame:FindFirstChild("Preview")
    if hasPlayer then
        local isPlayer = (name == "Player")
        frame.Main.Visible = isPlayer
        frame.Sidebar.Visible = isPlayer
        frame.Preview.Visible = isPlayer
    end

    for _, scrName in ipairs(TAB_NAMES) do
        if scrName ~= "Player" then
            local scr = ensureScreen(scrName)
            scr.Visible = (scrName == name)
        end
    end
end

function Tabs:Init(root)
    frame = root

    -- Place the tab bar inside Handle if available (top header), else at top of root frame
    local host = frame:FindFirstChild("Handle") or frame
    tabBar = host:FindFirstChild("TabBar") or createTabBar(host)

    -- Build buttons
    for i, name in ipairs(TAB_NAMES) do
        if not buttons[name] then
            local btn = createButton(name)
            btn.LayoutOrder = i
            btn.Parent = tabBar
            btn.MouseButton1Click:Connect(function()
                Tabs:_setActive(name)
            end)
            buttons[name] = btn
        end
    end

    -- Ensure non-player screens exist (placeholders for now)
    for _, name in ipairs(TAB_NAMES) do
        if name ~= "Player" then
            ensureScreen(name)
        end
    end

    -- Start in Player tab
    self:_setActive("Player")
end

return Tabs
