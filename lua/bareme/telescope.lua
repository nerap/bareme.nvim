-- Telescope integration for worktree switching
local M = {}

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  vim.notify("bareme.nvim: telescope.nvim is not installed", vim.log.levels.ERROR)
  return M
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local previewers = require("telescope.previewers")

local git = require("bareme.git")
local tmux = require("bareme.tmux")
local config = require("bareme.config")
local buffer = require("bareme.buffer")

-- Worktree picker for switching
function M.switch_worktree(opts)
  opts = opts or {}

  local worktrees = git.list_worktrees()
  if #worktrees == 0 then
    vim.notify("No worktrees found", vim.log.levels.WARN)
    return
  end

  -- Get current sessions
  local sessions = tmux.list_sessions()
  local session_set = {}
  for _, session in ipairs(sessions) do
    session_set[session] = true
  end

  -- Prepare entries with session status
  local entries = {}
  for _, wt in ipairs(worktrees) do
    local session_name = tmux.get_session_name_for_path(wt.path, wt.branch)
    local has_session = session_set[session_name] or false

    table.insert(entries, {
      path = wt.path,
      branch = wt.branch,
      head = wt.head,
      session_name = session_name,
      has_session = has_session,
      display = string.format("%-30s [%s]%s", wt.path, wt.branch, has_session and " 󰆍" or ""),
    })
  end

  local picker_opts = vim.tbl_deep_extend("force", config.options.telescope or {}, opts)

  pickers
    .new(picker_opts, {
      prompt_title = "Switch Worktree",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.path .. " " .. entry.branch,
            path = entry.path,
          }
        end,
      }),
      sorter = conf.generic_sorter(picker_opts),
      previewer = previewers.new_termopen_previewer({
        get_command = function(entry)
          return { "ls", "-la", entry.value.path }
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)

          if not selection then
            return
          end

          local entry = selection.value
          local path = entry.path
          local session_name = entry.session_name

          -- Change to the worktree directory
          vim.cmd("cd " .. path)

          -- Clean up buffers from other worktrees
          local cleaned = buffer.cleanup_foreign_buffers()

          -- Open a default file in the new worktree
          buffer.open_default_file()

          -- Build notification message
          local messages = { string.format("Switched to: [%s]", entry.branch) }
          if cleaned > 0 then
            table.insert(messages, string.format("Cleaned %d buffer(s)", cleaned))
          end

          -- Switch or create tmux session if configured
          if config.options.auto_switch_tmux and tmux.is_tmux_running() then
            local success, msg = tmux.switch_to_session(session_name, path)
            if success then
              table.insert(messages, string.format("Session: %s", session_name))
            else
              table.insert(messages, "Warning: Failed to switch tmux session")
            end
          end

          -- Show notification
          vim.schedule(function()
            vim.notify(table.concat(messages, " | "), vim.log.levels.INFO)
          end)
        end)

        return true
      end,
    })
    :find()
end

-- Worktree list viewer
function M.list_worktrees(opts)
  opts = opts or {}

  local worktrees = git.list_worktrees()
  if #worktrees == 0 then
    vim.notify("No worktrees found", vim.log.levels.WARN)
    return
  end

  -- Get current sessions
  local sessions = tmux.list_sessions()
  local session_set = {}
  for _, session in ipairs(sessions) do
    session_set[session] = true
  end

  -- Prepare entries with session status
  local entries = {}
  local cwd = vim.fn.getcwd()
  for _, wt in ipairs(worktrees) do
    local session_name = tmux.get_session_name_for_path(wt.path, wt.branch)
    local has_session = session_set[session_name] or false
    local is_current = wt.path == cwd

    local status = ""
    if is_current then
      status = status .. " "
    end
    if has_session then
      status = status .. " 󰆍"
    end

    table.insert(entries, {
      path = wt.path,
      branch = wt.branch,
      head = wt.head,
      session_name = session_name,
      has_session = has_session,
      is_current = is_current,
      display = string.format("%-30s [%-20s]%s", wt.path, wt.branch, status),
    })
  end

  local picker_opts = vim.tbl_deep_extend("force", config.options.telescope or {}, opts)

  pickers
    .new(picker_opts, {
      prompt_title = "Worktrees ( = current, 󰆍 = session)",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.display,
            ordinal = entry.path .. " " .. entry.branch,
            path = entry.path,
          }
        end,
      }),
      sorter = conf.generic_sorter(picker_opts),
      previewer = previewers.new_termopen_previewer({
        get_command = function(entry)
          return { "git", "-C", entry.value.path, "status" }
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
        end)
        return true
      end,
    })
    :find()
end

return M
