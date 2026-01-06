-- Main entry point for bareme.nvim
local M = {}

local git = require("bareme.git")
local tmux = require("bareme.tmux")
local config = require("bareme.config")
local buffer = require("bareme.buffer")

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

  -- Create worktree
  local success, result
  if create_new then
    success, result = git.create_worktree(branch_name)
  else
    success, result = git.create_worktree_from_branch(branch_name)
  end

  if not success then
    vim.notify("Failed to create worktree: " .. result, vim.log.levels.ERROR)
    return
  end

  -- Build notification message
  local messages = {}
  table.insert(messages, string.format("Created: [%s]", branch_name))

  -- Auto-switch to the new worktree (no confirmation)
  vim.cmd("cd " .. result)

  -- Clean up buffers from other worktrees
  local cleaned = buffer.cleanup_foreign_buffers()
  if cleaned > 0 then
    table.insert(messages, string.format("Cleaned %d buffer(s)", cleaned))
  end

  -- Open a default file in the new worktree
  buffer.open_default_file()

  -- Create/switch tmux session if configured
  if config.options.auto_switch_tmux and tmux.is_tmux_running() then
    local session_name = tmux.get_session_name_for_path(result, branch_name)
    local ok, msg = tmux.switch_to_session(session_name, result)
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

-- Delete a worktree
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

  -- Save current directory to check if we're deleting current worktree
  local cwd = vim.fn.getcwd()
  local deleting_current = (cwd == path)

  -- Confirm deletion (skip if called from picker since selection is already intentional)
  if not skip_confirm and config.options.confirm_delete then
    local confirm = vim.fn.confirm(string.format("Delete worktree: %s?", path), "&Yes\n&No", 2)
    if confirm ~= 1 then
      return
    end
  end

  -- Get session name and branch before deleting
  local worktrees = git.list_worktrees()
  local session_name, branch_to_delete
  for _, wt in ipairs(worktrees) do
    if wt.path == path then
      session_name = tmux.get_session_name_for_path(wt.path, wt.branch)
      branch_to_delete = wt.branch
      break
    end
  end

  -- Delete worktree
  local success, result = git.delete_worktree(path)
  if not success then
    vim.notify("Failed to delete worktree: " .. result, vim.log.levels.ERROR)
    return
  end

  -- Build notification message
  local messages = {}
  table.insert(messages, string.format("Deleted: %s [%s]", path, branch_to_delete or "unknown"))

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

return M
