-- Claude Code monitoring and integration
local M = {}

local events = require("bareme.events")
local logger = require("bareme.logger")

-- Get Claude events file path
local function get_claude_events_file()
  local dir = vim.fn.expand("~/.local/state/bareme")
  vim.fn.mkdir(dir, "p")
  return dir .. "/claude_events.jsonl"
end

-- File watcher handle
local watcher = nil

-- Parse Claude event from hook
local function parse_claude_event(line)
  local ok, event = pcall(vim.fn.json_decode, line)
  if not ok then
    return nil
  end

  return event
end

-- Process Claude event
local function process_claude_event(claude_event)
  if not claude_event or not claude_event.event then
    return
  end

  -- Map Claude events to bareme events
  if claude_event.event == "message" then
    events.emit(events.TYPES.CLAUDE_MESSAGE, {
      worktree = claude_event.worktree,
      type = claude_event.type,
      count = claude_event.count,
      timestamp = claude_event.timestamp,
    })
  elseif claude_event.event == "needs_input" then
    events.emit(events.TYPES.CLAUDE_NEEDS_INPUT, {
      worktree = claude_event.worktree,
      timestamp = claude_event.timestamp,
    })

    -- Show notification
    vim.schedule(function()
      vim.notify(
        string.format("[Claude - %s] Waiting for your input", claude_event.worktree),
        vim.log.levels.WARN
      )
    end)
  elseif claude_event.event == "error" then
    events.emit(events.TYPES.CLAUDE_ERROR, {
      worktree = claude_event.worktree,
      error = claude_event.error,
      timestamp = claude_event.timestamp,
    })
  end

  logger.info("claude", string.format("[%s] %s", claude_event.worktree, claude_event.event), claude_event)
end

-- Start watching Claude events file
function M.start_watching()
  if watcher then
    return -- Already watching
  end

  local file_path = get_claude_events_file()

  -- Create file if it doesn't exist
  if vim.fn.filereadable(file_path) == 0 then
    local file = io.open(file_path, "w")
    if file then
      file:close()
    end
  end

  -- Watch file for changes
  watcher = vim.loop.new_fs_event()
  if watcher then
    watcher:start(file_path, {}, function(err, filename, events_mask)
      if err then
        logger.error("claude", "File watch error: " .. err)
        return
      end

      -- Read new lines from file
      vim.schedule(function()
        local file = io.open(file_path, "r")
        if file then
          -- Seek to end and read new lines
          -- For simplicity, we'll read the last few lines
          local cmd = string.format("tail -n 10 '%s'", file_path)
          local output = vim.fn.system(cmd)

          for line in output:gmatch("[^\r\n]+") do
            local claude_event = parse_claude_event(line)
            if claude_event then
              process_claude_event(claude_event)
            end
          end

          file:close()
        end
      end)
    end)

    logger.info("claude", "Started watching Claude events file")
  end
end

-- Stop watching Claude events file
function M.stop_watching()
  if watcher then
    watcher:stop()
    watcher = nil
    logger.info("claude", "Stopped watching Claude events file")
  end
end

-- Cache for process detection (to avoid frequent lsof calls)
local process_cache = {
  sessions = {},
  last_check = 0,
  ttl = 10000, -- Check processes every 10 seconds only
}

-- Detect running Claude sessions via process inspection (cached)
local function detect_running_sessions()
  local now = vim.loop.now()

  -- Return cached result if still valid
  if process_cache.sessions and (now - process_cache.last_check) < process_cache.ttl then
    return process_cache.sessions
  end

  local git = require("bareme.git")
  local worktrees = git.list_worktrees()
  local sessions = {}

  -- Get all Claude processes with their working directories
  local cmd = "ps aux | grep '[c]laude' | grep -v grep"
  local output = vim.fn.system(cmd)

  if vim.v.shell_error == 0 and output ~= "" then
    -- Match each worktree path against running processes
    for _, wt in ipairs(worktrees) do
      -- Check if there's a Claude process in this directory
      local check_cmd = string.format(
        "lsof -c claude 2>/dev/null | grep -F '%s' | head -1",
        wt.path
      )
      local result = vim.fn.system(check_cmd)

      if vim.v.shell_error == 0 and result ~= "" then
        sessions[wt.branch] = {
          worktree = wt.branch,
          path = wt.path,
          status = "active",
          detected = "process",
          -- Don't set last_activity here - let it be determined by actual events
          message_count = 0,
          needs_input_count = 0,
          error_count = 0,
        }
      end
    end
  end

  -- Update cache
  process_cache.sessions = sessions
  process_cache.last_check = now

  return sessions
end

-- Get Claude session stats by worktree
-- skip_process_detection: if true, skips slow lsof calls (for initial dashboard load)
function M.get_session_stats(skip_process_detection)
  local file_path = get_claude_events_file()
  local stats = {}

  -- First, try to detect via process inspection (skip on initial load for speed)
  if not skip_process_detection then
    local running_sessions = detect_running_sessions()
    for branch, session in pairs(running_sessions) do
      stats[branch] = session
    end
  end

  -- Then merge with hook-based events (if file exists)
  if vim.fn.filereadable(file_path) == 1 then
    local file = io.open(file_path, "r")
    if file then
      for line in file:lines() do
        local event = parse_claude_event(line)
        if event and event.worktree then
          if not stats[event.worktree] then
            stats[event.worktree] = {
              worktree = event.worktree,
              message_count = 0,
              needs_input_count = 0,
              error_count = 0,
              last_activity = 0,
              status = "idle",
            }
          end

          local wt_stats = stats[event.worktree]

          -- Update based on event type
          if event.event == "message" then
            -- Use the count from the event itself (not cumulative)
            if event.count then
              wt_stats.message_count = event.count
            end
            if wt_stats.status ~= "needs_input" then
              wt_stats.status = "active"
            end
          elseif event.event == "needs_input" then
            wt_stats.status = "needs_input"
          elseif event.event == "error" then
            wt_stats.error_count = wt_stats.error_count + 1
          end

          -- Update last activity (keep the most recent)
          if event.timestamp and (not wt_stats.last_activity or event.timestamp > wt_stats.last_activity) then
            wt_stats.last_activity = event.timestamp
          end
        end
      end
      file:close()
    end
  end

  -- Determine status based on last activity
  local now = os.time()
  for _, wt_stats in pairs(stats) do
    if wt_stats.last_activity > 0 then
      local idle_time = now - wt_stats.last_activity

      if wt_stats.status ~= "needs_input" then
        if idle_time > 3600 then -- 1 hour
          wt_stats.status = "idle"
        elseif idle_time > 300 then -- 5 minutes
          wt_stats.status = "paused"
        elseif idle_time > 60 then -- 1-5 minutes = working
          wt_stats.status = "working"
        else -- < 1 minute = active
          wt_stats.status = "active"
        end
      end

      wt_stats.idle_time = idle_time
    end
  end

  return stats
end

-- Get pending notifications (worktrees needing input)
function M.get_pending_notifications()
  local stats = M.get_session_stats()
  local notifications = {}

  for _, wt_stats in pairs(stats) do
    if wt_stats.status == "needs_input" then
      table.insert(notifications, {
        worktree = wt_stats.worktree,
        age = os.time() - wt_stats.last_activity,
      })
    end
  end

  -- Sort by age (oldest first)
  table.sort(notifications, function(a, b)
    return a.age > b.age
  end)

  return notifications
end

-- Clear old Claude events (older than days)
function M.prune_events(days)
  days = days or 7
  local cutoff = os.time() - (days * 24 * 60 * 60)

  local file_path = get_claude_events_file()
  if vim.fn.filereadable(file_path) == 0 then
    return 0
  end

  local temp_file = file_path .. ".tmp"
  local kept = 0

  local file = io.open(file_path, "r")
  local temp = io.open(temp_file, "w")

  if file and temp then
    for line in file:lines() do
      local event = parse_claude_event(line)
      if event and event.timestamp and event.timestamp >= cutoff then
        temp:write(line .. "\n")
        kept = kept + 1
      end
    end

    file:close()
    temp:close()

    os.remove(file_path)
    os.rename(temp_file, file_path)
  end

  return kept
end

-- Install Claude hooks in a worktree
function M.install_hooks(worktree_path, branch_name)
  local hooks_dir = worktree_path .. "/.claude/hooks"
  vim.fn.mkdir(hooks_dir, "p")

  -- Create on-message hook
  local on_message_hook = hooks_dir .. "/on-message.sh"
  local on_message_content = string.format(
    [[#!/bin/bash
# Auto-generated by bareme.nvim

WORKTREE_PATH='%s'
WORKTREE_BRANCH='%s'
MESSAGE_TYPE="$1"
MESSAGE_COUNT="$2"

echo "{\"worktree\":\"$WORKTREE_BRANCH\",\"path\":\"$WORKTREE_PATH\",\"event\":\"message\",\"type\":\"$MESSAGE_TYPE\",\"count\":$MESSAGE_COUNT,\"timestamp\":$(date +%%s)}" >> ~/.local/state/bareme/claude_events.jsonl
]],
    worktree_path,
    branch_name
  )

  local file = io.open(on_message_hook, "w")
  if file then
    file:write(on_message_content)
    file:close()
    vim.fn.system(string.format("chmod +x '%s'", on_message_hook))
  end

  -- Create on-await-input hook
  local on_await_hook = hooks_dir .. "/on-await-input.sh"
  local on_await_content = string.format(
    [[#!/bin/bash
# Auto-generated by bareme.nvim

WORKTREE_BRANCH='%s'

echo "{\"worktree\":\"$WORKTREE_BRANCH\",\"event\":\"needs_input\",\"timestamp\":$(date +%%s)}" >> ~/.local/state/bareme/claude_events.jsonl
]],
    branch_name
  )

  file = io.open(on_await_hook, "w")
  if file then
    file:write(on_await_content)
    file:close()
    vim.fn.system(string.format("chmod +x '%s'", on_await_hook))
  end

  logger.info("claude", string.format("Installed Claude hooks for %s", branch_name))
  return true
end

-- Check if hooks are installed
function M.has_hooks(worktree_path)
  local hooks_dir = worktree_path .. "/.claude/hooks"
  return vim.fn.isdirectory(hooks_dir) == 1
end

return M
