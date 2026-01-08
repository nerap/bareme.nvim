-- Health check system for bareme.nvim (Neovim checkhealth compatible)
local M = {}

local system_stats = require("bareme.system_stats")
local git = require("bareme.git")
local logger = require("bareme.logger")

local health = vim.health or require("health")

-- Check port health
local function check_ports()
  health.start("Port Allocations")

  local port_stats = system_stats.get_port_stats()

  health.info(string.format("Total ports allocated: %d", port_stats.total_allocated))

  -- Check conflicts
  if #port_stats.conflicts > 0 then
    health.error(string.format("Port conflicts detected: %d", #port_stats.conflicts))
    for _, conflict in ipairs(port_stats.conflicts) do
      health.error(
        string.format(
          "  Port %d (%s) allocated to '%s' but in use by PID %s",
          conflict.port,
          conflict.service,
          conflict.worktree,
          conflict.pid
        ),
        { "Check process with: lsof -i :" .. conflict.port, "Consider releasing port or stopping conflicting process" }
      )
    end
  else
    health.ok("No port conflicts")
  end

  -- Check orphaned ports
  if #port_stats.orphaned > 0 then
    health.warn(string.format("Orphaned port allocations: %d", #port_stats.orphaned))
    for _, orphan in ipairs(port_stats.orphaned) do
      health.warn(
        string.format("  Port %d (%s) allocated to '%s' (worktree not found)", orphan.port, orphan.service, orphan.worktree),
        { "Run :WorktreeCleanupPorts to release orphaned ports" }
      )
    end
  else
    health.ok("No orphaned ports")
  end

  -- Check service usage
  for service, stats in pairs(port_stats.by_service) do
    local service_upper = service:upper()
    health.info(string.format("  %s: %d port(s) allocated", service_upper, stats.count))
  end
end

-- Check Docker health
local function check_docker()
  health.start("Docker")

  local docker_stats = system_stats.get_docker_stats()

  if not docker_stats.available then
    health.warn("Docker not available", { "Install Docker or docker-compose if you need container support" })
    return
  end

  health.ok("Docker available")

  local running = 0
  local stopped = 0
  for _, container in ipairs(docker_stats.containers) do
    if container.is_running then
      running = running + 1
    else
      stopped = stopped + 1
    end
  end

  health.info(string.format("Containers: %d running, %d stopped", running, stopped))

  -- Check orphaned containers
  if #docker_stats.orphaned > 0 then
    health.warn(string.format("Orphaned containers: %d", #docker_stats.orphaned))
    for _, orphan in ipairs(docker_stats.orphaned) do
      health.warn(
        string.format("  %s (branch: %s) - worktree not found", orphan.name, orphan.branch),
        { "Run :WorktreeCleanupDocker to remove orphaned containers" }
      )
    end
  else
    health.ok("No orphaned containers")
  end

  -- Check resource usage
  if docker_stats.total_cpu > 80 then
    health.warn(string.format("High Docker CPU usage: %.1f%%", docker_stats.total_cpu), {
      "Consider stopping unused containers",
      "Check container logs for issues",
    })
  end
end

-- Check worktree health
local function check_worktrees()
  health.start("Worktrees")

  if not git.is_git_repo() then
    health.warn("Not in a git repository")
    return
  end

  local worktrees = git.list_worktrees()
  health.info(string.format("Total worktrees: %d", #worktrees))

  local worktree_stats = system_stats.get_worktree_stats()
  health.info(string.format("Disk usage: %d MB", worktree_stats.disk_usage))
  health.info(string.format("Total files: %d", worktree_stats.total_files))

  -- Check for broken worktrees
  local broken = 0
  for _, wt in ipairs(worktrees) do
    -- Check if .git file exists and is valid
    local git_file = wt.path .. "/.git"
    if vim.fn.filereadable(git_file) == 0 then
      broken = broken + 1
      health.error(string.format("Broken worktree: %s (missing .git file)", wt.branch), {
        "Try recovering with :WorktreeRecover",
        "Or delete and recreate the worktree",
      })
    end
  end

  if broken == 0 then
    health.ok("All worktrees have valid .git references")
  end

  -- Warn about large worktrees
  if worktree_stats.disk_usage > 10000 then
    health.warn(string.format("High disk usage: %d MB", worktree_stats.disk_usage), {
      "Consider cleaning up old worktrees",
      "Check for large node_modules or build artifacts",
    })
  end
end

-- Check environment configuration
local function check_environment()
  health.start("Environment Configuration")

  local bare_repo = git.get_bare_repo_path()
  if not bare_repo then
    health.info("Not in a worktree")
    return
  end

  -- Check for .env.template
  local template_file = bare_repo .. "/.env.template"
  if vim.fn.filereadable(template_file) == 1 then
    health.ok(".env.template exists")

    -- Check worktrees for .env files
    local worktrees = git.list_worktrees()
    local missing_env = {}
    for _, wt in ipairs(worktrees) do
      local env_file = wt.path .. "/.env"
      if vim.fn.filereadable(env_file) == 0 then
        table.insert(missing_env, wt.branch)
      end
    end

    if #missing_env > 0 then
      health.warn(string.format("%d worktree(s) missing .env file", #missing_env), {
        "Worktrees: " .. table.concat(missing_env, ", "),
        "Generate with :WorktreeInitEnv",
      })
    else
      health.ok("All worktrees have .env files")
    end
  else
    health.info(".env.template not found", { "Create one with :WorktreeInitEnv if needed" })
  end
end

-- Check trash
local function check_trash()
  health.start("Trash")

  local trash_stats = system_stats.get_trash_stats()

  if trash_stats.count == 0 then
    health.ok("Trash is empty")
    return
  end

  health.info(string.format("Trash: %d worktree(s), %d MB", trash_stats.count, trash_stats.size_mb))

  if trash_stats.size_mb > 5000 then
    health.warn(string.format("Large trash size: %d MB", trash_stats.size_mb), {
      "Run :WorktreeEmptyTrash to permanently delete",
      "Or :WorktreeRecover to restore specific worktrees",
    })
  end

  -- Show old items
  local now = os.time()
  for _, entry in ipairs(trash_stats.entries) do
    local age_days = math.floor((now - entry.deleted_at) / 86400)
    if age_days > 25 then
      health.info(string.format("  [%s] will auto-delete in %d days", entry.branch_name, 30 - age_days))
    end
  end
end

-- Check logging
local function check_logging()
  health.start("Logging")

  local log_stats = logger.get_stats()

  health.ok(string.format("Log file: %s", log_stats.path))
  health.info(string.format("Size: %.2f MB (%d lines)", log_stats.size_mb, log_stats.lines))

  if log_stats.size_mb > 50 then
    health.warn("Large log file", { "Logs are automatically rotated at 10MB", "Old logs are kept in .1, .2, etc." })
  end
end

-- Check Claude Code integration
local function check_claude()
  health.start("Claude Code Integration")

  local claude_monitor = require("bareme.claude_monitor")
  local stats = claude_monitor.get_session_stats()

  local active_count = 0
  local needs_input_count = 0

  for _, wt_stats in pairs(stats) do
    if wt_stats.status == "active" then
      active_count = active_count + 1
    elseif wt_stats.status == "needs_input" then
      needs_input_count = needs_input_count + 1
    end
  end

  if vim.tbl_count(stats) > 0 then
    health.ok(string.format("Claude sessions: %d active", active_count))

    if needs_input_count > 0 then
      health.warn(string.format("%d session(s) need input", needs_input_count), {
        "Check with :ClaudeStats",
        "Switch to worktree to continue conversation",
      })
    end
  else
    health.info("No Claude sessions detected", { "Claude hooks will auto-report activity when used" })
  end

  -- Check if hooks are installed in current worktree
  local cwd = vim.fn.getcwd()
  if claude_monitor.has_hooks(cwd) then
    health.ok("Claude hooks installed in current worktree")
  else
    health.info("Claude hooks not installed", { "Hooks enable Claude activity monitoring", "Auto-installed on new worktrees" })
  end
end

-- Main health check function (for :checkhealth)
function M.check()
  check_worktrees()
  check_ports()
  check_docker()
  check_environment()
  check_trash()
  check_logging()
  check_claude()

  health.start("System")
  health.ok("All checks complete")
end

-- Get health summary (for monitor UI)
function M.get_summary()
  return system_stats.get_health_summary()
end

return M
