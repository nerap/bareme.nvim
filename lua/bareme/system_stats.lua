-- System statistics collector for bareme.nvim
local M = {}

local git = require("bareme.git")
local ports = require("bareme.ports")
local docker = require("bareme.docker")
local trash = require("bareme.trash")

-- Get detailed port statistics
function M.get_port_stats()
  local allocations = ports.load_allocations()
  local stats = {
    total_allocated = 0,
    by_service = {},
    conflicts = {},
    orphaned = {},
  }

  -- Count allocations by service
  for worktree_key, port_map in pairs(allocations) do
    for service, port in pairs(port_map) do
      stats.total_allocated = stats.total_allocated + 1

      -- Initialize service stats
      if not stats.by_service[service] then
        stats.by_service[service] = {
          count = 0,
          ports = {},
        }
      end

      stats.by_service[service].count = stats.by_service[service].count + 1
      table.insert(stats.by_service[service].ports, {
        port = port,
        worktree = worktree_key,
      })

      -- Check if port is actually in use
      if not ports.is_port_available(port) then
        -- Port is in use - check if it's a conflict
        local lsof_cmd = string.format("lsof -i :%d -t 2>/dev/null", port)
        local pid = vim.trim(vim.fn.system(lsof_cmd))

        table.insert(stats.conflicts, {
          port = port,
          service = service,
          worktree = worktree_key,
          pid = pid ~= "" and pid or "unknown",
        })
      end
    end
  end

  -- Find orphaned ports (allocated but worktree doesn't exist)
  local worktrees = git.list_worktrees()
  local worktree_paths = {}
  for _, wt in ipairs(worktrees) do
    worktree_paths[wt.path] = true
  end

  for worktree_key, port_map in pairs(allocations) do
    -- Extract path from key (format: project/branch)
    local found = false
    for path, _ in pairs(worktree_paths) do
      if path:match(worktree_key) then
        found = true
        break
      end
    end

    if not found then
      for service, port in pairs(port_map) do
        table.insert(stats.orphaned, {
          port = port,
          service = service,
          worktree = worktree_key,
        })
      end
    end
  end

  return stats
end

-- Get Docker statistics
function M.get_docker_stats()
  local stats = {
    available = docker.is_available(),
    containers = {},
    orphaned = {},
    total_memory = 0,
    total_cpu = 0,
  }

  if not stats.available then
    return stats
  end

  -- Get all containers (including stopped)
  local cmd = "docker ps -a --format '{{.ID}}|{{.Names}}|{{.Status}}|{{.Image}}' 2>/dev/null"
  local output = vim.fn.system(cmd)

  if vim.v.shell_error == 0 then
    for line in output:gmatch("[^\r\n]+") do
      local id, name, status, image = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)")
      if id then
        -- Check if this is a bareme container
        local is_bareme = name:match("^bareme_")

        table.insert(stats.containers, {
          id = id,
          name = name,
          status = status,
          image = image,
          is_bareme = is_bareme or false,
          is_running = status:match("^Up"),
        })

        -- Check if container is orphaned (bareme container but worktree doesn't exist)
        if is_bareme then
          local worktree_branch = name:match("^bareme_[^_]+_([^_]+)")
          if worktree_branch then
            local worktrees = git.list_worktrees()
            local found = false
            for _, wt in ipairs(worktrees) do
              if wt.branch == worktree_branch then
                found = true
                break
              end
            end

            if not found then
              table.insert(stats.orphaned, {
                id = id,
                name = name,
                branch = worktree_branch,
              })
            end
          end
        end
      end
    end
  end

  -- Get detailed stats for running containers
  cmd = "docker stats --no-stream --format '{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}' 2>/dev/null"
  output = vim.fn.system(cmd)

  if vim.v.shell_error == 0 then
    for line in output:gmatch("[^\r\n]+") do
      local name, cpu, mem = line:match("([^|]+)|([^|]+)|([^|]+)")
      if name then
        -- Find matching container
        for _, container in ipairs(stats.containers) do
          if container.name == name then
            container.cpu = cpu
            container.memory = mem

            -- Parse CPU percentage
            local cpu_num = tonumber(cpu:match("([%d.]+)"))
            if cpu_num then
              stats.total_cpu = stats.total_cpu + cpu_num
            end
          end
        end
      end
    end
  end

  return stats
end

-- Get worktree statistics
function M.get_worktree_stats()
  local worktrees = git.list_worktrees()
  local stats = {
    total = #worktrees,
    by_branch = {},
    disk_usage = 0,
    total_files = 0,
  }

  for _, wt in ipairs(worktrees) do
    -- Get disk usage
    local du_cmd = string.format("du -sm '%s' 2>/dev/null | cut -f1", wt.path)
    local size = tonumber(vim.trim(vim.fn.system(du_cmd))) or 0
    stats.disk_usage = stats.disk_usage + size

    -- Get file count
    local count_cmd = string.format("find '%s' -type f 2>/dev/null | wc -l", wt.path)
    local files = tonumber(vim.trim(vim.fn.system(count_cmd))) or 0
    stats.total_files = stats.total_files + files

    -- Get last activity (last commit time)
    local log_cmd = string.format("git -C '%s' log -1 --format=%%ct 2>/dev/null", wt.path)
    local last_commit = tonumber(vim.trim(vim.fn.system(log_cmd))) or 0

    stats.by_branch[wt.branch] = {
      path = wt.path,
      size_mb = size,
      files = files,
      last_activity = last_commit,
    }
  end

  return stats
end

-- Get trash statistics
function M.get_trash_stats()
  local status = trash.get_status()

  return {
    count = status.count,
    size_mb = status.size_mb,
    entries = status.entries,
  }
end

-- Get overall system health summary
function M.get_health_summary()
  local port_stats = M.get_port_stats()
  local docker_stats = M.get_docker_stats()
  local worktree_stats = M.get_worktree_stats()
  local trash_stats = M.get_trash_stats()

  local issues = {}
  local warnings = {}

  -- Port issues
  if #port_stats.conflicts > 0 then
    table.insert(issues, string.format("%d port conflict(s)", #port_stats.conflicts))
  end

  if #port_stats.orphaned > 0 then
    table.insert(warnings, string.format("%d orphaned port allocation(s)", #port_stats.orphaned))
  end

  -- Docker issues
  if docker_stats.available then
    if #docker_stats.orphaned > 0 then
      table.insert(warnings, string.format("%d orphaned container(s)", #docker_stats.orphaned))
    end

    -- Check for high resource usage
    if docker_stats.total_cpu > 80 then
      table.insert(warnings, string.format("High Docker CPU usage (%.1f%%)", docker_stats.total_cpu))
    end
  end

  -- Disk usage warnings
  if worktree_stats.disk_usage > 10000 then
    table.insert(warnings, string.format("High worktree disk usage (%d MB)", worktree_stats.disk_usage))
  end

  if trash_stats.size_mb > 5000 then
    table.insert(warnings, string.format("Large trash size (%d MB)", trash_stats.size_mb))
  end

  return {
    healthy = #issues == 0,
    issues = issues,
    warnings = warnings,
    stats = {
      ports = port_stats,
      docker = docker_stats,
      worktrees = worktree_stats,
      trash = trash_stats,
    },
  }
end

-- Get performance metrics
function M.get_performance_metrics()
  -- This would track operation timings
  -- For now, return placeholder structure
  return {
    avg_worktree_creation = 0,
    avg_worktree_switch = 0,
    avg_docker_startup = 0,
  }
end

return M
