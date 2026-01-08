-- Event bus and storage for bareme.nvim
local M = {}

local logger = require("bareme.logger")

-- Event types
M.TYPES = {
  WORKTREE_CREATED = "worktree_created",
  WORKTREE_DELETED = "worktree_deleted",
  WORKTREE_SWITCHED = "worktree_switched",
  WORKTREE_RECOVERED = "worktree_recovered",
  PORT_ALLOCATED = "port_allocated",
  PORT_RELEASED = "port_released",
  PORT_CONFLICT = "port_conflict",
  DOCKER_STARTED = "docker_started",
  DOCKER_STOPPED = "docker_stopped",
  DOCKER_FAILED = "docker_failed",
  ENV_GENERATED = "env_generated",
  ENV_FAILED = "env_failed",
  CLAUDE_MESSAGE = "claude_message",
  CLAUDE_NEEDS_INPUT = "claude_needs_input",
  CLAUDE_ERROR = "claude_error",
  BUFFER_CLEANUP = "buffer_cleanup",
  HOOK_EXECUTED = "hook_executed",
  HOOK_FAILED = "hook_failed",
}

-- Event listeners
local listeners = {}

-- Recent events (in-memory cache)
local recent_events = {}
local max_recent = 1000

-- Events file path
local function get_events_file()
  local dir = vim.fn.expand("~/.local/state/bareme")
  vim.fn.mkdir(dir, "p")
  return dir .. "/events.jsonl"
end

-- Emit an event
function M.emit(event_type, data)
  local event = {
    type = event_type,
    timestamp = os.time(),
    data = data or {},
  }

  -- Add to recent events
  table.insert(recent_events, event)
  if #recent_events > max_recent then
    table.remove(recent_events, 1)
  end

  -- Write to file (JSONL format)
  local file = io.open(get_events_file(), "a")
  if file then
    file:write(vim.fn.json_encode(event) .. "\n")
    file:close()
  end

  -- Log the event
  local level = "INFO"
  if event_type:match("FAILED") or event_type:match("CONFLICT") or event_type:match("ERROR") then
    level = "ERROR"
  elseif event_type:match("NEEDS_INPUT") then
    level = "WARN"
  end

  local message = string.format("Event: %s", event_type)
  if level == "ERROR" then
    logger.error("events", message, data)
  elseif level == "WARN" then
    logger.warn("events", message, data)
  else
    logger.info("events", message, data)
  end

  -- Notify listeners
  if listeners[event_type] then
    for _, callback in ipairs(listeners[event_type]) do
      pcall(callback, event)
    end
  end

  -- Notify wildcard listeners
  if listeners["*"] then
    for _, callback in ipairs(listeners["*"]) do
      pcall(callback, event)
    end
  end

  return event
end

-- Subscribe to events
function M.on(event_type, callback)
  if not listeners[event_type] then
    listeners[event_type] = {}
  end
  table.insert(listeners[event_type], callback)
end

-- Unsubscribe from events
function M.off(event_type, callback)
  if not listeners[event_type] then
    return
  end

  for i, cb in ipairs(listeners[event_type]) do
    if cb == callback then
      table.remove(listeners[event_type], i)
      break
    end
  end
end

-- Get recent events from memory
function M.get_recent(count, filter)
  count = count or 100
  filter = filter or {}

  local filtered = {}
  for i = #recent_events, 1, -1 do
    local event = recent_events[i]
    local matches = true

    -- Filter by type
    if filter.type and event.type ~= filter.type then
      matches = false
    end

    -- Filter by worktree
    if filter.worktree and event.data.worktree ~= filter.worktree then
      matches = false
    end

    -- Filter by time range
    if filter.since and event.timestamp < filter.since then
      matches = false
    end

    if matches then
      table.insert(filtered, event)
      if #filtered >= count then
        break
      end
    end
  end

  return filtered
end

-- Read events from file
function M.read_events(count, filter)
  count = count or 100
  filter = filter or {}

  local events_file = get_events_file()
  if vim.fn.filereadable(events_file) == 0 then
    return {}
  end

  -- Read last N lines from file
  local cmd = string.format("tail -n %d '%s'", count * 2, events_file) -- Read more to account for filtering
  local output = vim.fn.system(cmd)

  local events = {}
  for line in output:gmatch("[^\r\n]+") do
    local ok, event = pcall(vim.fn.json_decode, line)
    if ok then
      local matches = true

      -- Apply filters
      if filter.type and event.type ~= filter.type then
        matches = false
      end

      if filter.worktree and event.data.worktree ~= filter.worktree then
        matches = false
      end

      if filter.since and event.timestamp < filter.since then
        matches = false
      end

      if matches then
        table.insert(events, event)
      end
    end
  end

  -- Reverse to get newest first
  local reversed = {}
  for i = #events, 1, -1 do
    table.insert(reversed, events[i])
    if #reversed >= count then
      break
    end
  end

  return reversed
end

-- Format event for display
function M.format_event(event)
  local time = os.date("%H:%M:%S", event.timestamp)
  local type_display = event.type:gsub("_", " "):upper()

  local message = string.format("[%s] %s", time, type_display)

  -- Add worktree if present
  if event.data.worktree then
    message = message .. string.format(" [%s]", event.data.worktree)
  end

  -- Add specific details based on event type
  if event.type == M.TYPES.PORT_ALLOCATED then
    message = message .. string.format(" %s:%d", event.data.service, event.data.port)
  elseif event.type == M.TYPES.PORT_CONFLICT then
    message = message .. string.format(" port %d (PID %s)", event.data.port, event.data.pid or "unknown")
  elseif event.type == M.TYPES.DOCKER_STARTED then
    if event.data.duration then
      message = message .. string.format(" (%.1fs)", event.data.duration)
    end
  elseif event.type == M.TYPES.DOCKER_FAILED then
    if event.data.error then
      message = message .. string.format(" - %s", event.data.error)
    end
  elseif event.type == M.TYPES.BUFFER_CLEANUP then
    message = message .. string.format(" (%d buffers)", event.data.count or 0)
  end

  return message
end

-- Get event statistics
function M.get_stats(since)
  since = since or (os.time() - 3600) -- Last hour by default

  local events = M.read_events(10000, { since = since }) -- Read up to 10k events

  local stats = {
    total = #events,
    by_type = {},
    by_worktree = {},
    errors = 0,
  }

  for _, event in ipairs(events) do
    -- Count by type
    stats.by_type[event.type] = (stats.by_type[event.type] or 0) + 1

    -- Count by worktree
    if event.data.worktree then
      stats.by_worktree[event.data.worktree] = (stats.by_worktree[event.data.worktree] or 0) + 1
    end

    -- Count errors
    if event.type:match("FAILED") or event.type:match("CONFLICT") or event.type:match("ERROR") then
      stats.errors = stats.errors + 1
    end
  end

  return stats
end

-- Clear old events (older than days)
function M.prune_events(days)
  days = days or 30
  local cutoff = os.time() - (days * 24 * 60 * 60)

  local events_file = get_events_file()
  if vim.fn.filereadable(events_file) == 0 then
    return 0
  end

  local temp_file = events_file .. ".tmp"
  local kept = 0

  -- Read and filter events
  local file = io.open(events_file, "r")
  local temp = io.open(temp_file, "w")

  if file and temp then
    for line in file:lines() do
      local ok, event = pcall(vim.fn.json_decode, line)
      if ok and event.timestamp >= cutoff then
        temp:write(line .. "\n")
        kept = kept + 1
      end
    end

    file:close()
    temp:close()

    -- Replace old file with new file
    os.remove(events_file)
    os.rename(temp_file, events_file)
  end

  return kept
end

-- Clear all events
function M.clear_events()
  local events_file = get_events_file()
  if vim.fn.filereadable(events_file) == 1 then
    os.remove(events_file)
  end
  recent_events = {}
end

return M
