-- Port allocation and management for worktrees
local M = {}

-- Default port ranges for common services
local DEFAULT_RANGES = {
  app = { start = 3000, ["end"] = 3099 },
  api = { start = 4000, ["end"] = 4099 },
  db = { start = 5432, ["end"] = 5532 },
  redis = { start = 6379, ["end"] = 6479 },
  mongodb = { start = 27017, ["end"] = 27117 },
  postgres = { start = 5432, ["end"] = 5532 },
}

-- Get allocations file path
local function get_allocations_file()
  local home = os.getenv("HOME")
  local config_dir = home .. "/.config/bareme"
  vim.fn.mkdir(config_dir, "p")
  return config_dir .. "/ports.json"
end

-- Load port allocations from disk
function M.load_allocations()
  local file_path = get_allocations_file()
  local file = io.open(file_path, "r")
  if not file then
    return {}
  end

  local content = file:read("*all")
  file:close()

  local ok, data = pcall(vim.fn.json_decode, content)
  if ok and type(data) == "table" then
    return data
  end

  return {}
end

-- Save port allocations to disk
function M.save_allocations(allocations)
  local file_path = get_allocations_file()
  local content = vim.fn.json_encode(allocations)

  local file = io.open(file_path, "w")
  if file then
    file:write(content)
    file:close()
    return true
  end

  return false
end

-- Check if a port is available on the system using lsof
function M.is_port_available(port)
  local cmd = string.format("lsof -i :%d 2>/dev/null", port)
  local output = vim.fn.system(cmd)
  -- If output is empty, port is available
  return vim.trim(output) == ""
end

-- Find a free port in the given range
function M.find_free_port(range, allocated_ports)
  -- Build set of all currently allocated ports
  local used = {}
  for _, allocation in pairs(allocated_ports) do
    if type(allocation) == "table" then
      for _, port in pairs(allocation) do
        if type(port) == "number" then
          used[port] = true
        end
      end
    end
  end

  -- Try to find an available port in range
  for port = range.start, range["end"] do
    if not used[port] and M.is_port_available(port) then
      return port
    end
  end

  return nil, string.format("No available ports in range %d-%d", range.start, range["end"])
end

-- Allocate ports for a worktree
function M.allocate_ports(project_name, branch_name, port_ranges)
  local allocations = M.load_allocations()

  -- Create key for this worktree
  local key = project_name .. "/" .. branch_name

  -- Return existing allocation if present
  if allocations[key] then
    return allocations[key]
  end

  -- Use default ranges if not provided
  port_ranges = port_ranges or DEFAULT_RANGES

  -- Allocate a port for each service
  local ports = {}
  for service, range in pairs(port_ranges) do
    local port, err = M.find_free_port(range, allocations)
    if port then
      ports[service] = port
    else
      -- If we can't allocate all ports, clean up and return error
      return nil, string.format("Failed to allocate %s port: %s", service, err)
    end
  end

  -- Save allocation
  allocations[key] = ports
  M.save_allocations(allocations)

  return ports
end

-- Release ports for a worktree
function M.release_ports(project_name, branch_name)
  local allocations = M.load_allocations()
  local key = project_name .. "/" .. branch_name

  if allocations[key] then
    allocations[key] = nil
    M.save_allocations(allocations)
    return true
  end

  return false
end

-- Get allocated ports for a worktree
function M.get_ports(project_name, branch_name)
  local allocations = M.load_allocations()
  local key = project_name .. "/" .. branch_name
  return allocations[key]
end

-- Get port ranges from project config or bare repo
function M.get_port_ranges(bare_repo_path)
  -- Try to load from .bareme.json
  local config_file = bare_repo_path .. "/.bareme.json"
  if vim.fn.filereadable(config_file) == 1 then
    local file = io.open(config_file, "r")
    if file then
      local content = file:read("*all")
      file:close()

      local ok, config = pcall(vim.fn.json_decode, content)
      if ok and config.ports then
        return config.ports
      end
    end
  end

  -- Return defaults
  return DEFAULT_RANGES
end

-- List all port allocations
function M.list_allocations()
  return M.load_allocations()
end

-- Get formatted display of allocations
function M.format_allocations()
  local allocations = M.load_allocations()
  local lines = {}

  if vim.tbl_isempty(allocations) then
    return { "No port allocations found" }
  end

  table.insert(lines, "Port Allocations:")
  table.insert(lines, "")

  -- Sort by key
  local keys = vim.tbl_keys(allocations)
  table.sort(keys)

  for _, key in ipairs(keys) do
    local ports = allocations[key]
    table.insert(lines, string.format("  %s:", key))

    -- Sort ports by service name
    local services = vim.tbl_keys(ports)
    table.sort(services)

    for _, service in ipairs(services) do
      table.insert(lines, string.format("    %s: %d", service, ports[service]))
    end

    table.insert(lines, "")
  end

  return lines
end

return M
