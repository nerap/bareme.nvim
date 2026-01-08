-- Real-time monitoring dashboard for bareme.nvim
local M = {}

local components = require("bareme.ui.components")
local system_stats = require("bareme.system_stats")
local events = require("bareme.events")
local claude_monitor = require("bareme.claude_monitor")
local git = require("bareme.git")

-- Monitor state
local state = {
  float = nil,
  timer = nil,
  refresh_interval = 5000, -- 5 seconds
}

-- Stop monitoring
local function stop_monitor()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end

  if state.float and state.float.win and vim.api.nvim_win_is_valid(state.float.win) then
    vim.api.nvim_win_close(state.float.win, true)
  end

  state.float = nil
end

-- Render the dashboard
local function render()
  if not state.float or not vim.api.nvim_win_is_valid(state.float.win) then
    stop_monitor()
    return
  end

  local buf = state.float.buf
  local width = state.float.width

  -- Gather data
  local health_summary = system_stats.get_health_summary()
  local port_stats = health_summary.stats.ports
  local docker_stats = health_summary.stats.docker
  local worktree_stats = health_summary.stats.worktrees
  local trash_stats = health_summary.stats.trash
  local claude_stats = claude_monitor.get_session_stats()
  local claude_notifications = claude_monitor.get_pending_notifications()

  local lines = {}
  local highlights = {}

  -- Title
  table.insert(lines, components.pad("Bareme Monitor", width, "center"))
  table.insert(lines, components.pad("Auto-refresh: " .. (state.refresh_interval / 1000) .. "s", width, "center"))
  table.insert(lines, "")

  -- Overview
  table.insert(lines, "📊 Overview")
  table.insert(lines, "")

  local status_icon = health_summary.healthy and components.icons.success or components.icons.error
  local status_text = health_summary.healthy and "Healthy" or "Issues Detected"
  table.insert(lines, string.format("  Status: %s %s", status_icon, status_text))
  table.insert(lines, string.format("  Worktrees: %d", worktree_stats.total))
  table.insert(lines, string.format("  Ports: %d allocated", port_stats.total_allocated))

  if docker_stats.available then
    local docker_running = 0
    for _, container in ipairs(docker_stats.containers) do
      if container.is_running then
        docker_running = docker_running + 1
      end
    end
    table.insert(lines, string.format("  Docker: %d/%d running", docker_running, #docker_stats.containers))
  else
    table.insert(lines, "  Docker: not available")
  end

  table.insert(lines, string.format("  Trash: %d (%dMB)", trash_stats.count, trash_stats.size_mb))
  table.insert(lines, "")

  -- Issues & Warnings
  if #health_summary.issues > 0 or #health_summary.warnings > 0 then
    table.insert(lines, "⚠ Issues & Warnings")
    table.insert(lines, "")

    for _, issue in ipairs(health_summary.issues) do
      table.insert(lines, "  " .. components.icons.error .. " " .. issue)
    end

    for _, warning in ipairs(health_summary.warnings) do
      table.insert(lines, "  " .. components.icons.warning .. " " .. warning)
    end

    table.insert(lines, "")
  end

  -- Worktrees
  table.insert(lines, components.icons.worktree .. " Worktrees")
  table.insert(lines, "")

  if worktree_stats.total > 0 then
    local worktrees = git.list_worktrees()
    local wt_rows = {}

    for i, wt in ipairs(worktrees) do
      if i > 5 then
        break
      end -- Show max 5

      local branch_stats = worktree_stats.by_branch[wt.branch]
      local size = branch_stats and string.format("%dMB", branch_stats.size_mb) or "?"
      local last_activity = branch_stats and components.time_ago(branch_stats.last_activity) or "?"

      -- Check Claude status
      local claude_icon = components.icons.inactive
      if claude_stats[wt.branch] then
        local cs = claude_stats[wt.branch]
        if cs.status == "active" then
          claude_icon = components.icons.claude_active
        elseif cs.status == "needs_input" then
          claude_icon = components.icons.claude_needs_input
        elseif cs.status == "paused" then
          claude_icon = components.icons.claude_paused
        else
          claude_icon = components.icons.claude_idle
        end
      end

      table.insert(wt_rows, {
        claude_icon,
        wt.branch,
        size,
        last_activity,
      })
    end

    local table_lines = components.create_table({ "", "Branch", "Size", "Activity" }, wt_rows)
    for _, line in ipairs(table_lines) do
      table.insert(lines, "  " .. line)
    end

    if #worktrees > 5 then
      table.insert(lines, string.format("  ... and %d more", #worktrees - 5))
    end
  else
    table.insert(lines, "  No worktrees")
  end

  table.insert(lines, "")

  -- Claude Sessions
  if #claude_notifications > 0 then
    table.insert(lines, components.icons.claude_needs_input .. " Claude Notifications")
    table.insert(lines, "")

    for _, notif in ipairs(claude_notifications) do
      local age_str = components.time_ago(os.time() - notif.age)
      table.insert(lines, string.format("  [%s] needs input (%s)", notif.worktree, age_str))
    end

    table.insert(lines, "")
  end

  -- Port Status
  if port_stats.total_allocated > 0 then
    table.insert(lines, components.icons.port .. " Port Status")
    table.insert(lines, "")

    for service, stats in pairs(port_stats.by_service) do
      local service_upper = service:upper()
      table.insert(lines, string.format("  %s: %d port(s)", service_upper, stats.count))
    end

    if #port_stats.conflicts > 0 then
      table.insert(lines, "")
      table.insert(lines, string.format("  %s %d conflict(s) detected!", components.icons.error, #port_stats.conflicts))
    end

    table.insert(lines, "")
  end

  -- Docker Containers (if available)
  if docker_stats.available and #docker_stats.containers > 0 then
    table.insert(lines, components.icons.docker .. " Docker Containers")
    table.insert(lines, "")

    local docker_rows = {}
    for i, container in ipairs(docker_stats.containers) do
      if i > 5 or not container.is_bareme then
        goto continue
      end

      local status_icon = container.is_running and components.icons.active or components.icons.inactive
      local name = container.name:gsub("^bareme_[^_]+_", "")

      table.insert(docker_rows, {
        status_icon,
        name,
        container.cpu or "-",
        container.memory or "-",
      })

      ::continue::
    end

    if #docker_rows > 0 then
      local docker_table = components.create_table({ "", "Container", "CPU", "Memory" }, docker_rows)
      for _, line in ipairs(docker_table) do
        table.insert(lines, "  " .. line)
      end
    else
      table.insert(lines, "  No bareme containers")
    end

    table.insert(lines, "")
  end

  -- Recent Events
  local recent_events = events.get_recent(5)
  if #recent_events > 0 then
    table.insert(lines, "📋 Recent Events")
    table.insert(lines, "")

    for _, event in ipairs(recent_events) do
      table.insert(lines, "  " .. events.format_event(event))
    end

    table.insert(lines, "")
  end

  -- Footer
  table.insert(lines, "")
  table.insert(lines, components.pad("Press [r]efresh [h]ealth [q]uit", width, "center"))

  -- Update buffer
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Set cursor to top
  vim.api.nvim_win_set_cursor(state.float.win, { 1, 0 })
end

-- Setup keymaps
local function setup_keymaps(buf)
  local opts = { buffer = buf, nowait = true, silent = true }

  -- Quit
  vim.keymap.set("n", "q", function()
    stop_monitor()
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    stop_monitor()
  end, opts)

  -- Manual refresh
  vim.keymap.set("n", "r", function()
    render()
  end, opts)

  -- Open health
  vim.keymap.set("n", "h", function()
    stop_monitor()
    vim.cmd("checkhealth bareme")
  end, opts)

  -- Show help
  vim.keymap.set("n", "?", function()
    vim.notify([[
Bareme Monitor Keybindings:

  r - Manual refresh
  h - Open full health check
  q - Quit
  <Esc> - Quit
]], vim.log.levels.INFO)
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
    title = " Bareme Monitor ",
    border = "rounded",
    width = math.min(100, math.floor(vim.o.columns * 0.9)),
    height = math.min(40, math.floor(vim.o.lines * 0.9)),
  })

  -- Setup keymaps
  setup_keymaps(state.float.buf)

  -- Initial render
  render()

  -- Setup auto-refresh
  state.timer = vim.loop.new_timer()
  state.timer:start(
    state.refresh_interval,
    state.refresh_interval,
    vim.schedule_wrap(function()
      if state.float and vim.api.nvim_win_is_valid(state.float.win) then
        render()
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
