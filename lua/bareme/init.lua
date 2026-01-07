-- Main entry point for bareme.nvim
local M = {}

local git = require("bareme.git")
local tmux = require("bareme.tmux")
local config = require("bareme.config")
local buffer = require("bareme.buffer")
local project = require("bareme.project")
local ports = require("bareme.ports")
local env = require("bareme.env")
local docker = require("bareme.docker")
local trash = require("bareme.trash")

-- Setup function to configure the plugin
function M.setup(opts)
  config.setup(opts)
end

-- Create a new worktree
function M.create_worktree(branch_name, create_new)
  if not git.is_git_repo() then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end

  -- Prompt for branch name if not provided
  if not branch_name or branch_name == "" then
    branch_name = vim.fn.input("Branch name: ")
    if branch_name == "" then
      vim.notify("Branch name required", vim.log.levels.ERROR)
      return
    end
  end

  -- Get bare repo and detect project
  local bare_repo = git.get_bare_repo_path()
  if not bare_repo then
    vim.notify("Not in a worktree", vim.log.levels.ERROR)
    return
  end

  local proj = project.detect_project(bare_repo)
  vim.notify(string.format("Creating worktree for %s...", proj.name), vim.log.levels.INFO)

  -- Create worktree
  local success, worktree_path
  if create_new then
    success, worktree_path = git.create_worktree(branch_name)
  else
    success, worktree_path = git.create_worktree_from_branch(branch_name)
  end

  if not success then
    vim.notify("Failed to create worktree: " .. worktree_path, vim.log.levels.ERROR)
    return
  end

  local messages = {}
  table.insert(messages, string.format("Created: [%s]", branch_name))

  -- Detect package manager
  local package_manager = project.detect_package_manager(worktree_path)
  table.insert(messages, string.format("PM: %s", package_manager))

  -- Allocate ports
  local port_ranges = ports.get_port_ranges(bare_repo)
  local allocated_ports = ports.allocate_ports(proj.name, branch_name, port_ranges)

  if allocated_ports then
    local port_list = {}
    for service, port in pairs(allocated_ports) do
      table.insert(port_list, string.format("%s:%d", service:upper(), port))
    end
    if #port_list > 0 then
      table.insert(messages, string.format("Ports: %s", table.concat(port_list, " ")))
    end
  end

  -- Generate .env from template
  if project.has_env_template(bare_repo) then
    local env_success = env.generate_env(bare_repo, worktree_path, branch_name, allocated_ports, package_manager)
    if env_success then
      table.insert(messages, "Generated .env")
    else
      table.insert(messages, "Warning: Failed to generate .env")
    end
  end

  -- Start Docker services if docker-compose.yml exists
  if project.has_docker_compose(worktree_path) then
    local docker_success, docker_msg = docker.start_services(worktree_path)
    if docker_success then
      table.insert(messages, "Docker: started")
    else
      table.insert(messages, string.format("Docker: failed (%s)", docker_msg or "unknown"))
    end
  end

  -- Run onCreate hook if defined
  local hooks = project.get_hooks(proj.config)
  if hooks.onCreate then
    local hook_success, hook_output = project.run_hook("onCreate", worktree_path, proj.config)
    if hook_success then
      table.insert(messages, "Hook: onCreate")
    else
      vim.notify("onCreate hook failed: " .. (hook_output or "unknown"), vim.log.levels.WARN)
    end
  end

  -- Auto-switch to the new worktree
  vim.cmd("cd " .. worktree_path)

  -- Clean up buffers from other worktrees
  local cleaned = buffer.cleanup_foreign_buffers()
  if cleaned > 0 then
    table.insert(messages, string.format("Cleaned %d buffer(s)", cleaned))
  end

  -- Open a default file in the new worktree
  buffer.open_default_file()

  -- Create/switch tmux session if configured
  if config.options.auto_switch_tmux and tmux.is_tmux_running() then
    local session_name = tmux.get_session_name_for_path(worktree_path, branch_name)
    local ok, msg = tmux.switch_to_session(session_name, worktree_path)
    if ok then
      table.insert(messages, string.format("Session: %s", session_name))
    else
      table.insert(messages, "Warning: Failed to switch tmux session")
    end
  end

  -- Show single combined notification (scheduled to not block)
  vim.schedule(function()
    vim.notify(table.concat(messages, " | "), vim.log.levels.INFO)
  end)
end

-- Delete a worktree (soft delete to trash)
function M.delete_worktree(path, skip_confirm)
  if not git.is_git_repo() then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
    return
  end

  -- If no path provided, show picker
  if not path or path == "" then
    local worktrees = git.list_worktrees()
    if #worktrees == 0 then
      vim.notify("No worktrees to delete", vim.log.levels.WARN)
      return
    end

    -- Use telescope to pick worktree to delete
    local has_telescope = pcall(require, "telescope")
    if has_telescope then
      M.delete_worktree_picker()
      return
    else
      vim.notify("Telescope required for interactive deletion", vim.log.levels.ERROR)
      return
    end
  end

  -- Get branch name and other info before deleting
  local worktrees = git.list_worktrees()
  local branch_name, session_name
  for _, wt in ipairs(worktrees) do
    if wt.path == path then
      branch_name = wt.branch
      session_name = tmux.get_session_name_for_path(wt.path, wt.branch)
      break
    end
  end

  if not branch_name then
    vim.notify("Could not find branch name for worktree", vim.log.levels.ERROR)
    return
  end

  -- Check if we're deleting the current worktree
  local cwd = vim.fn.getcwd()
  local deleting_current = (cwd == path)

  -- Get bare repo and project info
  local bare_repo = git.get_bare_repo_path()
  local proj = project.detect_project(bare_repo)

  -- Run onDelete hook before deletion
  local hooks = project.get_hooks(proj.config)
  if hooks.onDelete then
    local hook_success, hook_output = project.run_hook("onDelete", path, proj.config)
    if not hook_success then
      vim.notify("onDelete hook failed: " .. (hook_output or "unknown"), vim.log.levels.WARN)
    end
  end

  -- Stop Docker services if running
  if project.has_docker_compose(path) then
    docker.stop_services(path, false) -- Don't remove volumes
  end

  -- Release allocated ports
  ports.release_ports(proj.name, branch_name)

  -- Soft delete to trash
  local success, result = trash.soft_delete(path, branch_name, skip_confirm)
  if not success then
    vim.notify("Failed to move to trash: " .. result, vim.log.levels.ERROR)
    return
  end

  -- Build notification messages
  local messages = { result }

  -- Kill tmux session if configured
  if config.options.auto_kill_session and session_name then
    local ok, msg = tmux.kill_session(session_name)
    if ok then
      table.insert(messages, string.format("Killed session: %s", session_name))
    end
  end

  -- If we deleted the current worktree, switch to another one
  local switched_to = nil
  if deleting_current then
    -- Get bare repo path before deletion affects state
    local bare_repo = git.get_bare_repo_path()
    if not bare_repo then
      -- Fallback: extract from deleted path
      bare_repo = vim.fn.fnamemodify(path, ":h")
    end

    -- Find another worktree to switch to (prefer main, master, or first available)
    -- Get worktrees directly from git in case lua cache is stale
    local remaining = {}
    local output = vim.fn.system(string.format("git -C '%s' worktree list --porcelain 2>/dev/null", bare_repo))
    if vim.v.shell_error == 0 then
      local current_entry = {}
      for line in output:gmatch("[^\r\n]+") do
        if line:match("^worktree ") then
          if current_entry.path and not current_entry.is_bare and current_entry.path ~= path then
            table.insert(remaining, current_entry)
          end
          current_entry = { path = line:sub(10) }
        elseif line:match("^branch ") then
          current_entry.branch = line:sub(8):match("refs/heads/(.+)")
        elseif line:match("^bare") then
          current_entry.is_bare = true
        end
      end
      -- Handle last entry
      if current_entry.path and not current_entry.is_bare and current_entry.path ~= path then
        table.insert(remaining, current_entry)
      end
    end

    local target_worktree = nil

    -- Try to find main or master
    for _, wt in ipairs(remaining) do
      if wt.branch == "main" or wt.branch == "master" then
        target_worktree = wt
        break
      end
    end

    -- If no main/master, use first available
    if not target_worktree and #remaining > 0 then
      target_worktree = remaining[1]
    end

    if target_worktree then
      -- Verify target path exists
      if vim.fn.isdirectory(target_worktree.path) == 1 then
        -- Change directory with explicit success check
        local ok, err = pcall(function()
          vim.cmd("cd " .. vim.fn.fnameescape(target_worktree.path))
        end)

        if ok then
          switched_to = target_worktree

          -- Clean up buffers from other worktrees
          local cleaned = buffer.cleanup_foreign_buffers()
          if cleaned > 0 then
            table.insert(messages, string.format("Cleaned %d buffer(s)", cleaned))
          end

          -- Open a default file in the new worktree
          buffer.open_default_file()

          table.insert(messages, string.format("Switched to: [%s]", target_worktree.branch))

          -- Switch tmux session if configured
          if config.options.auto_switch_tmux and tmux.is_tmux_running() then
            local new_session = tmux.get_session_name_for_path(target_worktree.path, target_worktree.branch)
            tmux.switch_to_session(new_session, target_worktree.path)
          end
        else
          table.insert(messages, "Error: Failed to switch directory - " .. tostring(err))
        end
      else
        table.insert(messages, "Error: Target worktree path does not exist")
      end
    else
      table.insert(messages, "Warning: No other worktrees available")
    end
  end

  -- Show single combined notification (scheduled to not block)
  local final_message = table.concat(messages, " | ")
  vim.schedule(function()
    vim.notify(final_message, vim.log.levels.INFO)
  end)
end

-- Delete worktree with telescope picker
function M.delete_worktree_picker()
  local has_telescope = pcall(require, "telescope")
  if not has_telescope then
    vim.notify("Telescope is required for this feature", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local worktrees = git.list_worktrees()
  if #worktrees == 0 then
    vim.notify("No worktrees to delete", vim.log.levels.WARN)
    return
  end

  local entries = {}
  for _, wt in ipairs(worktrees) do
    table.insert(entries, {
      path = wt.path,
      branch = wt.branch,
      display = string.format("%s [%s]", wt.path, wt.branch),
    })
  end

  pickers
    .new({}, {
      prompt_title = "Delete Worktree",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.path .. " " .. entry.branch,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if not selection then
            return
          end

          -- Skip confirmation since user already selected from picker
          M.delete_worktree(selection.value.path, true)
        end)
        return true
      end,
    })
    :find()
end

-- Switch worktree (using telescope)
function M.switch_worktree()
  local has_telescope = pcall(require, "telescope")
  if not has_telescope then
    vim.notify("Telescope is required for this feature", vim.log.levels.ERROR)
    return
  end

  local telescope = require("bareme.telescope")
  telescope.switch_worktree()
end

-- List all worktrees
function M.list_worktrees()
  local has_telescope = pcall(require, "telescope")
  if not has_telescope then
    vim.notify("Telescope is required for this feature", vim.log.levels.ERROR)
    return
  end

  local telescope = require("bareme.telescope")
  telescope.list_worktrees()
end

-- Cleanup orphaned worktrees (branches deleted remotely)
function M.cleanup_orphaned()
  local cleanup = require("bareme.cleanup")
  cleanup.cleanup_orphaned_worktrees()
end

-- Prune worktrees (cleanup + git worktree prune)
function M.prune()
  local cleanup = require("bareme.cleanup")
  cleanup.prune_worktrees()
end

-- Recover worktree from trash
function M.recover_worktree()
  local trashed = trash.list_trashed()
  if #trashed == 0 then
    vim.notify("Trash is empty", vim.log.levels.INFO)
    return
  end

  -- Show picker to select worktree to recover
  local choices = {}
  for i, entry in ipairs(trashed) do
    local age_days = math.floor((os.time() - entry.deleted_at) / 86400)
    table.insert(
      choices,
      string.format(
        "%d. [%s] %s (deleted %d days ago, %dMB)",
        i,
        entry.branch_name,
        entry.original_path,
        age_days,
        entry.size_mb
      )
    )
  end

  vim.ui.select(choices, {
    prompt = "Select worktree to recover:",
  }, function(choice, idx)
    if not idx then
      return
    end

    local entry = trashed[idx]
    local success, msg = trash.recover(entry.trash_path)
    if success then
      local messages = { msg }

      -- Recreate tmux session if configured and tmux is running
      if config.options.auto_switch_tmux and tmux.is_tmux_running() then
        local session_name = tmux.get_session_name_for_path(entry.original_path, entry.branch_name)

        -- Check if session already exists
        if not tmux.session_exists(session_name) then
          -- Create the session
          local tmux_success, tmux_msg = tmux.switch_to_session(session_name, entry.original_path)
          if tmux_success then
            table.insert(messages, string.format("Recreated session: %s", session_name))
          else
            table.insert(messages, "Warning: Failed to recreate tmux session")
          end
        end
      end

      vim.notify(table.concat(messages, " | "), vim.log.levels.INFO)
    else
      vim.notify("Recovery failed: " .. msg, vim.log.levels.ERROR)
    end
  end)
end

-- Empty trash
function M.empty_trash()
  local success, msg = trash.empty_trash(false)
  if success then
    vim.notify(msg, vim.log.levels.INFO)
  else
    vim.notify(msg, vim.log.levels.WARN)
  end
end

-- Show trash status
function M.trash_status()
  local status = trash.get_status()
  if status.count == 0 then
    vim.notify("Trash is empty", vim.log.levels.INFO)
    return
  end

  local lines = {
    string.format("Trash Status: %d worktree(s), %dMB total", status.count, status.size_mb),
    "",
  }

  for _, entry in ipairs(status.entries) do
    local age_days = math.floor((os.time() - entry.deleted_at) / 86400)
    table.insert(
      lines,
      string.format("  [%s] %dMB (deleted %d days ago)", entry.branch_name, entry.size_mb, age_days)
    )
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- Initialize env template
function M.init_env_template()
  local bare_repo = git.get_bare_repo_path()
  if not bare_repo then
    vim.notify("Not in a worktree", vim.log.levels.ERROR)
    return
  end

  local success, result = env.create_default_template(bare_repo)
  if success then
    vim.notify("Created .env.template at: " .. result, vim.log.levels.INFO)
    vim.cmd("edit " .. result)
  else
    vim.notify(result, vim.log.levels.WARN)
  end
end

-- Show port allocations
function M.show_ports()
  local lines = ports.format_allocations()
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

-- Docker commands
function M.docker_restart()
  local cwd = vim.fn.getcwd()
  local success, msg = docker.restart_services(cwd)
  if success then
    vim.notify(msg, vim.log.levels.INFO)
  else
    vim.notify("Failed to restart: " .. msg, vim.log.levels.ERROR)
  end
end

function M.docker_logs(service, lines)
  local cwd = vim.fn.getcwd()
  local output = docker.get_logs(cwd, service, lines)
  if output then
    -- Show in new buffer
    vim.cmd("new")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output, "\n"))
    vim.bo.buftype = "nofile"
    vim.bo.bufhidden = "wipe"
    vim.bo.filetype = "log"
  else
    vim.notify("Failed to get logs", vim.log.levels.ERROR)
  end
end

function M.docker_status()
  local cwd = vim.fn.getcwd()
  local output = docker.get_status(cwd)
  if output then
    vim.notify(output, vim.log.levels.INFO)
  else
    vim.notify("Failed to get status", vim.log.levels.ERROR)
  end
end

return M
