-- Logging system for bareme.nvim
local M = {}

-- Log levels
M.LEVELS = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

-- Default configuration
local config = {
  level = M.LEVELS.INFO,
  max_size = 10 * 1024 * 1024, -- 10MB
  max_backups = 5,
  log_dir = vim.fn.expand("~/.local/state/bareme"),
  log_file = "bareme.log",
}

-- Ensure log directory exists
local function ensure_log_dir()
  vim.fn.mkdir(config.log_dir, "p")
end

-- Get full log file path
local function get_log_path()
  return config.log_dir .. "/" .. config.log_file
end

-- Get log file size
local function get_log_size()
  local path = get_log_path()
  local stat = vim.loop.fs_stat(path)
  return stat and stat.size or 0
end

-- Rotate log files
local function rotate_logs()
  local base_path = get_log_path()

  -- Delete oldest backup
  local oldest = base_path .. "." .. config.max_backups
  if vim.fn.filereadable(oldest) == 1 then
    os.remove(oldest)
  end

  -- Shift all backups
  for i = config.max_backups - 1, 1, -1 do
    local old_path = base_path .. "." .. i
    local new_path = base_path .. "." .. (i + 1)
    if vim.fn.filereadable(old_path) == 1 then
      os.rename(old_path, new_path)
    end
  end

  -- Move current log to .1
  if vim.fn.filereadable(base_path) == 1 then
    os.rename(base_path, base_path .. ".1")
  end
end

-- Format timestamp
local function format_timestamp()
  return os.date("%Y-%m-%d %H:%M:%S")
end

-- Format log level
local function format_level(level)
  for name, val in pairs(M.LEVELS) do
    if val == level then
      return string.format("%-5s", name)
    end
  end
  return "UNKNOWN"
end

-- Write log entry
local function write_log(level, module, message, data)
  -- Check log level
  if level < config.level then
    return
  end

  ensure_log_dir()

  -- Check if rotation needed
  if get_log_size() > config.max_size then
    rotate_logs()
  end

  -- Format message
  local timestamp = format_timestamp()
  local level_str = format_level(level)
  local module_str = string.format("%-12s", "[" .. module .. "]")

  local log_line = string.format("[%s] %s %s %s", timestamp, level_str, module_str, message)

  -- Add structured data if provided
  if data then
    log_line = log_line .. " | " .. vim.fn.json_encode(data)
  end

  -- Write to file
  local file = io.open(get_log_path(), "a")
  if file then
    file:write(log_line .. "\n")
    file:close()
  end

  -- Also output to console for ERROR level
  if level == M.LEVELS.ERROR then
    vim.schedule(function()
      vim.notify("[Bareme] " .. message, vim.log.levels.ERROR)
    end)
  end
end

-- Public logging functions
function M.debug(module, message, data)
  write_log(M.LEVELS.DEBUG, module, message, data)
end

function M.info(module, message, data)
  write_log(M.LEVELS.INFO, module, message, data)
end

function M.warn(module, message, data)
  write_log(M.LEVELS.WARN, module, message, data)
end

function M.error(module, message, data)
  write_log(M.LEVELS.ERROR, module, message, data)
end

-- Configure logger
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Get log file path for viewing
function M.get_log_path()
  return get_log_path()
end

-- Read recent log entries
function M.read_logs(lines)
  lines = lines or 100
  local path = get_log_path()

  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local cmd = string.format("tail -n %d '%s'", lines, path)
  local output = vim.fn.system(cmd)

  local log_lines = {}
  for line in output:gmatch("[^\r\n]+") do
    table.insert(log_lines, line)
  end

  return log_lines
end

-- Parse log line into structured format
function M.parse_log_line(line)
  -- Pattern: [timestamp] LEVEL [module] message | data
  local pattern = "%[([^%]]+)%] (%S+)%s+%[([^%]]+)%]%s+(.+)"
  local timestamp, level, module, rest = line:match(pattern)

  if not timestamp then
    return nil
  end

  -- Check if there's structured data
  local message, data_str = rest:match("(.+) | (.+)")
  if not message then
    message = rest
    data_str = nil
  end

  local data = nil
  if data_str then
    local ok, decoded = pcall(vim.fn.json_decode, data_str)
    if ok then
      data = decoded
    end
  end

  return {
    timestamp = timestamp,
    level = level,
    module = module,
    message = message,
    data = data,
  }
end

-- Clear all logs
function M.clear_logs()
  local path = get_log_path()
  if vim.fn.filereadable(path) == 1 then
    os.remove(path)
  end

  -- Remove backups
  for i = 1, config.max_backups do
    local backup_path = path .. "." .. i
    if vim.fn.filereadable(backup_path) == 1 then
      os.remove(backup_path)
    end
  end
end

-- Get log statistics
function M.get_stats()
  local path = get_log_path()
  local size = get_log_size()
  local lines = 0

  if vim.fn.filereadable(path) == 1 then
    local count_cmd = string.format("wc -l < '%s'", path)
    local output = vim.fn.system(count_cmd)
    lines = tonumber(vim.trim(output)) or 0
  end

  return {
    size_bytes = size,
    size_mb = math.floor(size / 1024 / 1024 * 100) / 100,
    lines = lines,
    path = path,
  }
end

return M
