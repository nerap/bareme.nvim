-- Docker Compose management for worktrees
local M = {}

local logger = require("bareme.logger")
local events = require("bareme.events")

-- Check if docker-compose is available
function M.is_available()
  -- Try docker compose (new command)
  local check = vim.fn.system("docker compose version 2>/dev/null")
  if vim.v.shell_error == 0 then
    return true
  end

  -- Try docker-compose (legacy command)
  check = vim.fn.system("docker-compose --version 2>/dev/null")
  return vim.v.shell_error == 0
end

-- Get the appropriate docker compose command
function M.get_compose_cmd()
  -- Prefer new 'docker compose' command
  local check = vim.fn.system("docker compose version 2>/dev/null")
  if vim.v.shell_error == 0 then
    return "docker compose"
  end

  -- Fall back to legacy 'docker-compose'
  return "docker-compose"
end

-- Find compose file in worktree
local function find_compose_file(worktree_path)
  local files = {
    "docker-compose.yml",
    "docker-compose.yaml",
    "compose.yml",
    "compose.yaml",
  }

  for _, file in ipairs(files) do
    local path = worktree_path .. "/" .. file
    if vim.fn.filereadable(path) == 1 then
      return file
    end
  end

  return nil
end

-- Start Docker services
function M.start_services(worktree_path)
  if not M.is_available() then
    logger.warn("docker", "docker-compose not available")
    return false, "docker-compose not installed"
  end

  local compose_file = find_compose_file(worktree_path)
  if not compose_file then
    logger.warn("docker", string.format("No compose file in %s", worktree_path))
    return false, "No docker-compose.yml found"
  end

  logger.info("docker", string.format("Starting services in %s", worktree_path))
  local start_time = vim.loop.hrtime()

  local compose_cmd = M.get_compose_cmd()
  local cmd = string.format("cd '%s' && %s -f '%s' up -d 2>&1", worktree_path, compose_cmd, compose_file)

  local handle = io.popen(cmd)
  if not handle then
    logger.error("docker", "Failed to execute docker-compose")
    return false, "Failed to execute docker-compose"
  end

  local output = handle:read("*all")
  local success = handle:close()

  local duration = (vim.loop.hrtime() - start_time) / 1e9 -- Convert to seconds

  if success then
    logger.info("docker", string.format("Services started in %.2fs", duration))
    events.emit(events.TYPES.DOCKER_STARTED, {
      worktree = vim.fn.fnamemodify(worktree_path, ":t"),
      duration = duration,
    })
    return true, "Docker services started"
  else
    logger.error("docker", string.format("Failed to start services: %s", output))
    events.emit(events.TYPES.DOCKER_FAILED, {
      worktree = vim.fn.fnamemodify(worktree_path, ":t"),
      error = output,
    })
    return false, output
  end
end

-- Stop Docker services
function M.stop_services(worktree_path, remove_volumes)
  if not M.is_available() then
    return false, "docker-compose not installed"
  end

  local compose_file = find_compose_file(worktree_path)
  if not compose_file then
    return false, "No docker-compose.yml found"
  end

  logger.info("docker", string.format("Stopping services in %s", worktree_path))

  local compose_cmd = M.get_compose_cmd()
  local volumes_flag = remove_volumes and " -v" or ""
  local cmd = string.format(
    "cd '%s' && %s -f '%s' down%s 2>&1",
    worktree_path,
    compose_cmd,
    compose_file,
    volumes_flag
  )

  local handle = io.popen(cmd)
  if not handle then
    logger.error("docker", "Failed to execute docker-compose")
    return false, "Failed to execute docker-compose"
  end

  local output = handle:read("*all")
  local success = handle:close()

  if success then
    logger.info("docker", "Services stopped successfully")
    events.emit(events.TYPES.DOCKER_STOPPED, {
      worktree = vim.fn.fnamemodify(worktree_path, ":t"),
      removed_volumes = remove_volumes or false,
    })
  else
    logger.error("docker", string.format("Failed to stop services: %s", output))
  end

  return success, success and "Docker services stopped" or output
end

-- Restart Docker services
function M.restart_services(worktree_path)
  local success, msg = M.stop_services(worktree_path, false)
  if not success then
    return false, msg
  end

  return M.start_services(worktree_path)
end

-- Get Docker services status
function M.get_status(worktree_path)
  if not M.is_available() then
    return nil, "docker-compose not installed"
  end

  local compose_file = find_compose_file(worktree_path)
  if not compose_file then
    return nil, "No docker-compose.yml found"
  end

  local compose_cmd = M.get_compose_cmd()
  local cmd = string.format("cd '%s' && %s -f '%s' ps 2>&1", worktree_path, compose_cmd, compose_file)

  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute docker-compose"
  end

  local output = handle:read("*all")
  handle:close()

  return output
end

-- Get logs for a service
function M.get_logs(worktree_path, service_name, lines)
  if not M.is_available() then
    return nil, "docker-compose not installed"
  end

  local compose_file = find_compose_file(worktree_path)
  if not compose_file then
    return nil, "No docker-compose.yml found"
  end

  lines = lines or 100
  local compose_cmd = M.get_compose_cmd()

  local service_arg = service_name and (" " .. service_name) or ""
  local cmd = string.format(
    "cd '%s' && %s -f '%s' logs --tail=%d%s 2>&1",
    worktree_path,
    compose_cmd,
    compose_file,
    lines,
    service_arg
  )

  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute docker-compose"
  end

  local output = handle:read("*all")
  handle:close()

  return output
end

-- List services defined in compose file
function M.list_services(worktree_path)
  if not M.is_available() then
    return nil, "docker-compose not installed"
  end

  local compose_file = find_compose_file(worktree_path)
  if not compose_file then
    return nil, "No docker-compose.yml found"
  end

  local compose_cmd = M.get_compose_cmd()
  local cmd = string.format("cd '%s' && %s -f '%s' config --services 2>&1", worktree_path, compose_cmd, compose_file)

  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute docker-compose"
  end

  local output = handle:read("*all")
  handle:close()

  local services = {}
  for service in output:gmatch("[^\r\n]+") do
    table.insert(services, vim.trim(service))
  end

  return services
end

-- Check health of services (running/stopped/etc)
function M.check_health(worktree_path)
  if not M.is_available() then
    return { healthy = false, message = "docker-compose not installed" }
  end

  local compose_file = find_compose_file(worktree_path)
  if not compose_file then
    return { healthy = false, message = "No docker-compose.yml found" }
  end

  local compose_cmd = M.get_compose_cmd()
  local cmd = string.format("cd '%s' && %s -f '%s' ps --format json 2>&1", worktree_path, compose_cmd, compose_file)

  local handle = io.popen(cmd)
  if not handle then
    return { healthy = false, message = "Failed to check status" }
  end

  local output = handle:read("*all")
  handle:close()

  -- Parse output to count running services
  local running = 0
  local total = 0

  for line in output:gmatch("[^\r\n]+") do
    if line:match('"State":"running"') then
      running = running + 1
    end
    total = total + 1
  end

  return {
    healthy = running == total and total > 0,
    running = running,
    total = total,
    message = string.format("%d/%d services running", running, total),
  }
end

-- Execute a command in a service container
function M.exec(worktree_path, service_name, command)
  if not M.is_available() then
    return nil, "docker-compose not installed"
  end

  local compose_file = find_compose_file(worktree_path)
  if not compose_file then
    return nil, "No docker-compose.yml found"
  end

  local compose_cmd = M.get_compose_cmd()
  local cmd = string.format(
    "cd '%s' && %s -f '%s' exec %s %s 2>&1",
    worktree_path,
    compose_cmd,
    compose_file,
    service_name,
    command
  )

  local handle = io.popen(cmd)
  if not handle then
    return nil, "Failed to execute command"
  end

  local output = handle:read("*all")
  handle:close()

  return output
end

return M
