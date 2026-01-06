-- Main entry point for bareme.nvim
local M = {}

local git = require("bareme.git")
local tmux = require("bareme.tmux")
local config = require("bareme.config")

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

  vim.notify(string.format("Created worktree: %s", result), vim.log.levels.INFO)

  -- Optionally switch to the new worktree
  local switch = vim.fn.confirm("Switch to new worktree?", "&Yes\n&No", 1)
  if switch == 1 then
    vim.cmd("cd " .. result)

    -- Create/switch tmux session if configured
    if config.options.auto_switch_tmux and tmux.is_tmux_running() then
      local session_name = tmux.get_session_name_for_path(result, branch_name)
      local ok, msg = tmux.switch_to_session(session_name, result)
      if ok then
        vim.notify(string.format("Switched to session: %s", session_name), vim.log.levels.INFO)
      else
        vim.notify("Error switching tmux session: " .. msg, vim.log.levels.WARN)
      end
    end
  end
end

-- Delete a worktree
function M.delete_worktree(path)
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

  -- Confirm deletion
  if config.options.confirm_delete then
    local confirm = vim.fn.confirm(string.format("Delete worktree: %s?", path), "&Yes\n&No", 2)
    if confirm ~= 1 then
      return
    end
  end

  -- Get session name before deleting
  local worktrees = git.list_worktrees()
  local session_name
  for _, wt in ipairs(worktrees) do
    if wt.path == path then
      session_name = tmux.get_session_name_for_path(wt.path, wt.branch)
      break
    end
  end

  -- Delete worktree
  local success, result = git.delete_worktree(path)
  if not success then
    vim.notify("Failed to delete worktree: " .. result, vim.log.levels.ERROR)
    return
  end

  vim.notify(string.format("Deleted worktree: %s", path), vim.log.levels.INFO)

  -- Kill tmux session if configured
  if config.options.auto_kill_session and session_name then
    local ok, msg = tmux.kill_session(session_name)
    if ok then
      vim.notify(string.format("Killed session: %s", session_name), vim.log.levels.INFO)
    end
  end
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

          M.delete_worktree(selection.value.path)
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

return M
