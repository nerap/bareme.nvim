-- Real-time card-based dashboard for bareme.nvim
local M = {}

local components = require("bareme.ui.components")
local card = require("bareme.ui.card")
local grid = require("bareme.ui.grid")
local system_stats = require("bareme.system_stats")
local events = require("bareme.events")
local claude_monitor = require("bareme.claude_monitor")
local git = require("bareme.git")
local ports = require("bareme.ports")

-- Monitor state
local state = {
  float = nil,
  timer = nil,
  refresh_interval = 5000, -- 5 seconds
  selected_idx = 1, -- Currently selected card
  worktree_cards = {}, -- Cached card data
  cached_data = nil, -- Cache worktree data to avoid recalculating on navigation
  last_data_fetch = 0, -- Timestamp of last data fetch
  data_cache_ttl = 3000, -- Cache data for 3 seconds (in ms)
}

-- Stop monitoring
local function stop_monitor()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  -- Restore cursor highlights
  vim.api.nvim_set_hl(0, "BaremeCursor", {})

  -- Restore guicursor to default
  vim.opt.guicursor = "n-v-c:block,i-ci-ve:ver25,r-cr-o:hor20"

  if state.float and state.float.win and vim.api.nvim_win_is_valid(state.float.win) then
    vim.api.nvim_win_close(state.float.win, true)
  end

  state.float = nil
  state.selected_idx = 1
  state.worktree_cards = {}
  state.cached_data = nil
  state.last_data_fetch = 0
end

-- Gather worktree data for cards (fast version - no shell commands!)
local function gather_worktree_data_fast()
  local worktrees = git.list_worktrees()
  local claude_stats = claude_monitor.get_session_stats()
  local allocations = ports.load_allocations()
  local cwd = vim.fn.getcwd()

  -- Get project name for port lookup
  local bare_repo = git.get_bare_repo_path()
  local project_name = bare_repo and vim.fn.fnamemodify(bare_repo, ":t:r") or "unknown"

  local worktree_data = {}

  for _, wt in ipairs(worktrees) do
    -- Get Claude status
    local claude_status = claude_stats[wt.branch]

    -- Get allocated ports
    local port_key = project_name .. "/" .. wt.branch
    local wt_ports = allocations[port_key] or {}

    -- Get Docker info (simplified for now)
    local docker_info = {
      available = false,
      containers = {},
    }

    -- Use Neovim's builtin file stat (much faster than shell!)
    local last_activity = 0
    local stat = vim.loop.fs_stat(wt.path)
    if stat and stat.mtime then
      last_activity = stat.mtime.sec
    end

    table.insert(worktree_data, {
      branch = wt.branch,
      path = wt.path,
      is_current = wt.path == cwd,
      claude_status = claude_status,
      ports = wt_ports,
      docker_info = docker_info,
      size_mb = nil,
      last_activity = last_activity,
    })
  end

  -- Sort: current first, then by Claude status (needs_input, active, idle, no_claude)
  table.sort(worktree_data, function(a, b)
    if a.is_current then
      return true
    elseif b.is_current then
      return false
    end

    local a_status = a.claude_status and a.claude_status.status or "none"
    local b_status = b.claude_status and b.claude_status.status or "none"

    local priority = {
      needs_input = 1,
      active = 2,
      paused = 3,
      idle = 4,
      none = 5,
    }

    return (priority[a_status] or 5) < (priority[b_status] or 5)
  end)

  return worktree_data
end

-- Render the dashboard
local function render(force_refresh)
  if not state.float or not vim.api.nvim_win_is_valid(state.float.win) then
    stop_monitor()
    return
  end

  local buf = state.float.buf
  local width = state.float.width

  -- Check if we should use cached data
  local now = vim.loop.now()
  local use_cache = not force_refresh and state.cached_data and (now - state.last_data_fetch) < state.data_cache_ttl

  -- Gather data (or use cache)
  local worktree_data
  local health_summary

  if use_cache then
    worktree_data = state.cached_data.worktree_data
    health_summary = state.cached_data.health_summary
  else
    -- Use fast version (no shell commands!)
    worktree_data = gather_worktree_data_fast()

    -- Only fetch health summary on force refresh (manual or timer)
    if force_refresh then
      health_summary = system_stats.get_health_summary()
    else
      -- Use cached health summary or empty one
      health_summary = state.cached_data and state.cached_data.health_summary or {
        healthy = true,
        issues = {},
        warnings = {},
        stats = { ports = {}, docker = {}, worktrees = {}, trash = {} },
      }
    end

    -- Cache the data
    state.cached_data = {
      worktree_data = worktree_data,
      health_summary = health_summary,
    }
    state.last_data_fetch = now
  end

  -- Calculate grid dimensions
  local card_width = 33
  local columns = grid.calculate_columns(width, card_width)

  -- Ensure selected index is valid
  if state.selected_idx > #worktree_data then
    state.selected_idx = #worktree_data
  end
  if state.selected_idx < 1 and #worktree_data > 0 then
    state.selected_idx = 1
  end

  -- Render cards
  local cards = {}
  for idx, wt_data in ipairs(worktree_data) do
    local is_selected = (idx == state.selected_idx)
    local rendered_card = card.render_card(wt_data, card_width, is_selected, wt_data.is_current)
    table.insert(cards, rendered_card)
  end

  -- Store for navigation
  state.worktree_cards = worktree_data

  -- Build output
  local lines = {}

  -- Show critical issues only (skip orphaned ports warnings)
  local critical_issues = {}
  for _, issue in ipairs(health_summary.issues) do
    if not issue:match("orphaned port") then
      table.insert(critical_issues, issue)
    end
  end

  if #critical_issues > 0 then
    for _, issue in ipairs(critical_issues) do
      table.insert(lines, "⚠ " .. issue)
    end
    table.insert(lines, "")
  end

  -- Grid of cards
  local grid_lines = grid.layout_cards(cards, columns)
  for _, line in ipairs(grid_lines) do
    -- Don't clean - box drawing characters are fine!
    -- The <e2> issue might be from terminal rendering, not our code
    table.insert(lines, line)
  end

  -- Add keybindings as window footer
  local height = state.float.height
  local footer_lines = {}
  table.insert(footer_lines, string.rep("─", width))
  table.insert(footer_lines, components.pad("[hjkl] Navigate • [Enter] Switch • [c] Create • [d] Delete", width, "center"))
  table.insert(footer_lines, components.pad("[r] Refresh • [q] Quit • [?] Help", width, "center"))

  -- Add empty lines to push footer to bottom
  local total_lines = #lines
  local empty_lines_needed = math.max(0, height - total_lines - #footer_lines - 2)
  for _ = 1, empty_lines_needed do
    table.insert(lines, "")
  end

  -- Add footer
  for _, line in ipairs(footer_lines) do
    table.insert(lines, line)
  end

  -- Update buffer (temporarily make modifiable)
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_option(buf, "readonly", false)

  -- Clear ALL existing content first
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})

  -- Then set new content
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Add blue highlighting for selected card borders ONLY
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)

  -- Define blue highlight for selected card borders
  vim.api.nvim_set_hl(0, "BaremeSelectedBorder", { fg = "#61afef", bold = true }) -- Nice blue

  -- Find and highlight only the border characters, not content
  local namespace = vim.api.nvim_create_namespace("bareme_selected")
  for line_num, line in ipairs(lines) do
    -- Highlight individual border characters (not the whole line)
    local col = 0
    for char in line:gmatch(".") do
      -- Only highlight the actual border characters
      if char:match("[╔═╗║╚╝]") then
        vim.api.nvim_buf_add_highlight(buf, namespace, "BaremeSelectedBorder", line_num - 1, col, col + #char)
      end
      col = col + #char
    end
  end

  vim.api.nvim_buf_set_option(buf, "readonly", true)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Keep cursor at top (invisible anyway)
  pcall(vim.api.nvim_win_set_cursor, state.float.win, { 1, 0 })
end

-- Switch to selected worktree
local function switch_to_selected()
  if state.selected_idx < 1 or state.selected_idx > #state.worktree_cards then
    return
  end

  local selected = state.worktree_cards[state.selected_idx]
  if not selected then
    return
  end

  -- Close monitor
  stop_monitor()

  -- Use bareme's switch function
  local bareme = require("bareme")
  local config = require("bareme.config")
  local tmux = require("bareme.tmux")

  if config.options.auto_switch_tmux and tmux.is_tmux_running() then
    -- Switch tmux session
    local session_name = tmux.get_session_name_for_path(selected.path, selected.branch)
    local success, msg = tmux.switch_to_session(session_name, selected.path)
    if success then
      vim.notify(string.format("Switched to [%s]", selected.branch), vim.log.levels.INFO)
    else
      vim.notify("Failed to switch: " .. (msg or "unknown error"), vim.log.levels.ERROR)
    end
  else
    -- Just change directory
    local buffer = require("bareme.buffer")
    buffer.cleanup_foreign_buffers()
    vim.cmd("cd " .. selected.path)
    buffer.cleanup_foreign_buffers()
    buffer.open_default_file()
    vim.notify(string.format("Switched to [%s]", selected.branch), vim.log.levels.INFO)
  end
end

-- Setup keymaps
local function setup_keymaps(buf)
  local opts = { buffer = buf, nowait = true, silent = true }

  -- Disable visual mode completely
  vim.keymap.set("n", "v", "<Nop>", opts)
  vim.keymap.set("n", "V", "<Nop>", opts)
  vim.keymap.set("n", "<C-v>", "<Nop>", opts)
  vim.keymap.set("v", "v", "<Nop>", opts)
  vim.keymap.set("v", "V", "<Nop>", opts)
  vim.keymap.set("v", "<C-v>", "<Nop>", opts)
  -- Force exit visual mode if somehow entered
  vim.keymap.set("v", "<Esc>", "<Esc>", opts)

  -- Disable ALL default navigation (arrows, hjkl in normal mode, etc.)
  -- Block arrow keys
  vim.keymap.set("n", "<Up>", "<Nop>", opts)
  vim.keymap.set("n", "<Down>", "<Nop>", opts)
  vim.keymap.set("n", "<Left>", "<Nop>", opts)
  vim.keymap.set("n", "<Right>", "<Nop>", opts)

  -- Block default hjkl (we'll override with our custom navigation)
  vim.keymap.set("n", "w", "<Nop>", opts)
  vim.keymap.set("n", "b", "<Nop>", opts)
  vim.keymap.set("n", "e", "<Nop>", opts)
  vim.keymap.set("n", "0", "<Nop>", opts)
  vim.keymap.set("n", "$", "<Nop>", opts)
  vim.keymap.set("n", "gg", "<Nop>", opts)
  vim.keymap.set("n", "G", "<Nop>", opts)
  vim.keymap.set("n", "{", "<Nop>", opts)
  vim.keymap.set("n", "}", "<Nop>", opts)
  vim.keymap.set("n", "<C-u>", "<Nop>", opts)
  vim.keymap.set("n", "<C-d>", "<Nop>", opts)
  vim.keymap.set("n", "<C-b>", "<Nop>", opts)
  vim.keymap.set("n", "<C-f>", "<Nop>", opts)

  -- Quit
  vim.keymap.set("n", "q", function()
    stop_monitor()
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    stop_monitor()
  end, opts)

  -- Manual refresh (force data reload)
  vim.keymap.set("n", "r", function()
    render(true)
  end, opts)

  -- Navigation (use cached data for instant response)
  vim.keymap.set("n", "h", function()
    local columns = grid.calculate_columns(state.float.width, 33)
    state.selected_idx = grid.navigate(state.selected_idx, "h", #state.worktree_cards, columns)
    render(false) -- Don't force refresh
  end, opts)

  vim.keymap.set("n", "l", function()
    local columns = grid.calculate_columns(state.float.width, 33)
    state.selected_idx = grid.navigate(state.selected_idx, "l", #state.worktree_cards, columns)
    render(false) -- Don't force refresh
  end, opts)

  vim.keymap.set("n", "k", function()
    local columns = grid.calculate_columns(state.float.width, 33)
    state.selected_idx = grid.navigate(state.selected_idx, "k", #state.worktree_cards, columns)
    render(false) -- Don't force refresh
  end, opts)

  vim.keymap.set("n", "j", function()
    local columns = grid.calculate_columns(state.float.width, 33)
    state.selected_idx = grid.navigate(state.selected_idx, "j", #state.worktree_cards, columns)
    render(false) -- Don't force refresh
  end, opts)

  -- Switch to selected
  vim.keymap.set("n", "<CR>", function()
    switch_to_selected()
  end, opts)

  vim.keymap.set("n", "<Enter>", function()
    switch_to_selected()
  end, opts)

  -- Lazygit-style shortcuts (without <leader>w prefix)
  -- Create new worktree
  vim.keymap.set("n", "c", function()
    stop_monitor()
    vim.schedule(function()
      -- Prompt for branch name
      local branch_name = vim.fn.input("Branch name: ")
      if branch_name == "" then
        vim.notify("Branch name required", vim.log.levels.ERROR)
        return
      end

      -- Ask if creating new branch or from existing
      local choice = vim.fn.input("Create new branch? (y/n): ")
      local create_new = (choice:lower() == "y" or choice:lower() == "yes")

      require("bareme").create_worktree(branch_name, create_new)
    end)
  end, opts)

  -- Delete worktree
  vim.keymap.set("n", "d", function()
    if state.selected_idx < 1 or state.selected_idx > #state.worktree_cards then
      return
    end
    local selected = state.worktree_cards[state.selected_idx]
    if not selected then
      return
    end

    -- Find the worktree path from branch name
    local git = require("bareme.git")
    local worktrees = git.list_worktrees()
    local worktree_path = nil

    for _, wt in ipairs(worktrees) do
      if wt.branch == selected.branch then
        worktree_path = wt.path
        break
      end
    end

    if not worktree_path then
      vim.notify("Could not find worktree path for branch: " .. selected.branch, vim.log.levels.ERROR)
      return
    end

    stop_monitor()
    vim.schedule(function()
      -- Confirm deletion
      local confirm = vim.fn.input(string.format("Delete worktree [%s]? (y/n): ", selected.branch))
      if confirm:lower() == "y" or confirm:lower() == "yes" then
        require("bareme").delete_worktree(worktree_path, true)
      end
    end)
  end, opts)

  -- Show help
  vim.keymap.set("n", "?", function()
    vim.notify(
      [[
Bareme Dashboard Keybindings:

  Navigation:
    h/j/k/l - Navigate cards (vim-style)
    <Enter> - Switch to selected worktree

  Actions:
    c - Create new worktree
    d - Delete selected worktree
    r - Manual refresh

  Other:
    q/<Esc> - Quit dashboard
    ? - Show this help
]],
      vim.log.levels.INFO
    )
  end, opts)
end

-- Start the monitor
function M.start()
  -- Stop existing monitor
  if state.float then
    stop_monitor()
  end

  -- Create floating window
  state.float = components.create_float({
    title = " Bareme Dashboard ",
    border = "rounded",
    width = math.min(120, math.floor(vim.o.columns * 0.95)),
    height = math.min(50, math.floor(vim.o.lines * 0.95)),
  })

  -- Setup buffer options (read-only, non-navigable like lazygit)
  local buf = state.float.buf
  -- Set encoding FIRST (before making readonly)
  vim.api.nvim_buf_set_option(buf, "fileencoding", "utf-8")
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "swapfile", false)
  -- Then make readonly
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "readonly", true)

  -- Setup window options (hide cursor completely)
  local win = state.float.win
  vim.api.nvim_win_set_option(win, "cursorline", false)
  vim.api.nvim_win_set_option(win, "cursorcolumn", false)
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "scrolloff", 0)

  -- Hide cursor completely by making it match the background
  -- Get the normal background color
  local normal_bg = vim.api.nvim_get_hl_by_name("Normal", true).background
  local float_bg = vim.api.nvim_get_hl_by_name("NormalFloat", true).background or normal_bg

  -- Create a custom highlight that matches the background exactly
  if float_bg then
    vim.api.nvim_set_hl(0, "BaremeCursor", { fg = float_bg, bg = float_bg })
  else
    -- Fallback: make cursor invisible
    vim.api.nvim_set_hl(0, "BaremeCursor", { fg = "NONE", bg = "NONE", blend = 100 })
  end

  -- Apply the invisible cursor to this window
  vim.api.nvim_win_set_option(win, "winhl", "Cursor:BaremeCursor,CursorLine:Normal")

  -- Also set guicursor to use our custom highlight
  vim.api.nvim_win_call(win, function()
    vim.opt_local.guicursor = "n-v-c:block-BaremeCursor/BaremeCursor"
  end)

  -- Setup keymaps
  setup_keymaps(state.float.buf)

  -- Initial render (force fresh data)
  render(true)

  -- Setup auto-refresh (force fresh data)
  state.timer = vim.loop.new_timer()
  state.timer:start(
    state.refresh_interval,
    state.refresh_interval,
    vim.schedule_wrap(function()
      if state.float and vim.api.nvim_win_is_valid(state.float.win) then
        render(true) -- Force refresh on timer
      else
        stop_monitor()
      end
    end)
  )

  -- Close on buffer delete
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.float.buf,
    once = true,
    callback = function()
      stop_monitor()
    end,
  })
end

-- Stop the monitor
function M.stop()
  stop_monitor()
end

return M
