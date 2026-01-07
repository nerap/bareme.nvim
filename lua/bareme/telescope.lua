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
local entry_display = require("telescope.pickers.entry_display")

local git = require("bareme.git")
local tmux = require("bareme.tmux")
local config = require("bareme.config")
local buffer = require("bareme.buffer")

-- Get git diff stats for a worktree (compared to main/master)
local function get_diff_stats(worktree_path)
  -- Find base branch (main or master)
  local base_branch = "main"
  local check_main = vim.fn.system(string.format(
    "git -C '%s' rev-parse --verify main 2>/dev/null",
    worktree_path
  ))
  if vim.v.shell_error ~= 0 then
    base_branch = "master"
  end

  -- Get current branch
  local current_branch = vim.fn.system(string.format(
    "git -C '%s' branch --show-current 2>/dev/null",
    worktree_path
  ))
  current_branch = vim.trim(current_branch)

  -- If current branch is the base branch, check for uncommitted changes
  if current_branch == base_branch then
    local uncommitted = vim.fn.system(string.format(
      "git -C '%s' diff --shortstat 2>/dev/null",
      worktree_path
    ))
    uncommitted = vim.trim(uncommitted)

    if uncommitted ~= "" then
      local insertions = tonumber(uncommitted:match("(%d+) insertion")) or 0
      local deletions = tonumber(uncommitted:match("(%d+) deletion")) or 0
      return { insertions = insertions, deletions = deletions, uncommitted = true }
    end

    return { insertions = 0, deletions = 0, is_base = true }
  end

  -- Get diff stats compared to base
  local cmd = string.format(
    "git -C '%s' diff --shortstat %s...HEAD 2>/dev/null",
    worktree_path,
    base_branch
  )
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 or output == "" or vim.trim(output) == "" then
    return { insertions = 0, deletions = 0 }
  end

  -- Parse output: "3 files changed, 153 insertions(+), 89 deletions(-)"
  local insertions = tonumber(output:match("(%d+) insertion")) or 0
  local deletions = tonumber(output:match("(%d+) deletion")) or 0

  return { insertions = insertions, deletions = deletions }
end

-- Get last commit time for worktree
local function get_last_commit_time(worktree_path)
  local cmd = string.format("git -C '%s' log -1 --format=%%ct 2>/dev/null", worktree_path)
  local output = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return 0
  end
  return tonumber(vim.trim(output)) or 0
end

-- Convert timestamp to "X ago" format (like sessionizer)
local function time_ago(timestamp)
  if timestamp == 0 then
    return ""
  end

  local now = os.time()
  local diff = now - timestamp

  if diff < 60 then
    return string.format("%ds ago", diff)
  elseif diff < 3600 then
    return string.format("%dm ago", math.floor(diff / 60))
  elseif diff < 86400 then
    return string.format("%dh ago", math.floor(diff / 3600))
  elseif diff < 2592000 then
    return string.format("%dd ago", math.floor(diff / 86400))
  elseif diff < 31536000 then
    return string.format("%dmo ago", math.floor(diff / 2592000))
  else
    return string.format("%dy ago", math.floor(diff / 31536000))
  end
end

-- Setup highlight groups for diff stats
local function setup_highlights()
  -- Define highlight groups for diff visualization
  vim.api.nvim_set_hl(0, "BaremeDiffAdd", { fg = "#28a745", bold = true })      -- Green like GitHub
  vim.api.nvim_set_hl(0, "BaremeDiffDelete", { fg = "#cb2431", bold = true })   -- Red like GitHub
  vim.api.nvim_set_hl(0, "BaremeDiffSquareAdd", { fg = "#28a745" })
  vim.api.nvim_set_hl(0, "BaremeDiffSquareDelete", { fg = "#cb2431" })
end

-- Format diff stats with colors (like GitHub PR)
local function format_diff_stats(stats)
  if stats.insertions == 0 and stats.deletions == 0 then
    return ""
  end

  local parts = {}
  if stats.insertions > 0 then
    table.insert(parts, string.format("+%d", stats.insertions))
  end
  if stats.deletions > 0 then
    table.insert(parts, string.format("-%d", stats.deletions))
  end

  -- Add colored squares (GitHub style)
  local total = stats.insertions + stats.deletions
  local insert_ratio = total > 0 and math.floor((stats.insertions / total) * 5) or 0
  local squares = ""
  for i = 1, 5 do
    if i <= insert_ratio then
      squares = squares .. "█"
    else
      squares = squares .. "█"
    end
  end

  return string.format("%s %s", table.concat(parts, " "), squares)
end

-- Get colored diff stats for display (returns table for entry_display)
local function get_colored_diff_display(stats)
  if stats.insertions == 0 and stats.deletions == 0 then
    return { "", "Comment" }
  end

  local total = stats.insertions + stats.deletions
  local insert_ratio = total > 0 and (stats.insertions / total) or 0
  local num_green = math.floor(insert_ratio * 5)

  local parts = {}

  -- Add +/- numbers
  if stats.insertions > 0 then
    parts[#parts + 1] = { string.format("+%d ", stats.insertions), "BaremeDiffAdd" }
  end
  if stats.deletions > 0 then
    parts[#parts + 1] = { string.format("-%d ", stats.deletions), "BaremeDiffDelete" }
  end

  -- Add colored squares
  local squares_green = string.rep("█", num_green)
  local squares_red = string.rep("█", 5 - num_green)

  if squares_green ~= "" then
    parts[#parts + 1] = { squares_green, "BaremeDiffSquareAdd" }
  end
  if squares_red ~= "" then
    parts[#parts + 1] = { squares_red, "BaremeDiffSquareDelete" }
  end

  return parts
end

-- Worktree picker for switching
function M.switch_worktree(opts)
  opts = opts or {}

  -- Setup custom highlights
  setup_highlights()

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

  -- Prepare entries with git stats and time info
  local entries = {}
  for _, wt in ipairs(worktrees) do
    local session_name = tmux.get_session_name_for_path(wt.path, wt.branch)
    local has_session = session_set[session_name] or false
    local diff_stats = get_diff_stats(wt.path)
    local last_commit = get_last_commit_time(wt.path)
    local time_str = time_ago(last_commit)

    table.insert(entries, {
      path = wt.path,
      branch = wt.branch,
      head = wt.head,
      session_name = session_name,
      has_session = has_session,
      diff_stats = diff_stats,
      time_ago = time_str,
      last_commit = last_commit,
    })
  end

  -- Sort by most recent commit
  table.sort(entries, function(a, b)
    return a.last_commit > b.last_commit
  end)

  local picker_opts = vim.tbl_deep_extend("force", config.options.telescope or {}, opts)

  pickers
    .new(picker_opts, {
      prompt_title = "Switch Worktree",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          -- Build diff display string
          local diff_str = ""
          if entry.diff_stats.is_base then
            diff_str = "(base)"
          elseif entry.diff_stats.uncommitted then
            local parts = {}
            if entry.diff_stats.insertions > 0 then
              table.insert(parts, string.format("+%d", entry.diff_stats.insertions))
            end
            if entry.diff_stats.deletions > 0 then
              table.insert(parts, string.format("-%d", entry.diff_stats.deletions))
            end
            diff_str = string.format("%s (uncommitted)", table.concat(parts, " "))
          elseif entry.diff_stats.insertions > 0 or entry.diff_stats.deletions > 0 then
            local parts = {}
            if entry.diff_stats.insertions > 0 then
              table.insert(parts, string.format("+%d", entry.diff_stats.insertions))
            end
            if entry.diff_stats.deletions > 0 then
              table.insert(parts, string.format("-%d", entry.diff_stats.deletions))
            end

            -- Add colored squares
            local total = entry.diff_stats.insertions + entry.diff_stats.deletions
            local insert_ratio = total > 0 and (entry.diff_stats.insertions / total) or 0
            local num_green = math.floor(insert_ratio * 5)
            local squares = string.rep("█", num_green) .. string.rep("█", 5 - num_green)

            diff_str = string.format("%s %s", table.concat(parts, " "), squares)
          end

          -- Build simple display string
          local display_str = string.format(
            "%-25s  %-30s  %-12s  %s",
            entry.branch,
            diff_str,
            entry.time_ago,
            entry.has_session and "󰆍" or ""
          )

          return {
            value = entry,
            display = display_str,
            ordinal = entry.branch .. " " .. entry.path,
            path = entry.path,
          }
        end,
      }),
      sorter = conf.generic_sorter(picker_opts),
      previewer = previewers.new_termopen_previewer({
        get_command = function(entry)
          -- Show git diff stat + actual diff
          local base_branch = "main"
          local check_main = vim.fn.system(string.format(
            "git -C '%s' rev-parse --verify main 2>/dev/null",
            entry.value.path
          ))
          if vim.v.shell_error ~= 0 then
            base_branch = "master"
          end

          return {
            "sh",
            "-c",
            string.format(
              "cd '%s' && echo '=== Diff Summary ===' && git diff --stat %s...HEAD && echo '' && echo '=== Changes ===' && git diff %s...HEAD",
              entry.value.path,
              base_branch,
              base_branch
            ),
          }
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

  -- Setup custom highlights
  setup_highlights()

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

  -- Prepare entries with git stats and time info
  local entries = {}
  local cwd = vim.fn.getcwd()
  for _, wt in ipairs(worktrees) do
    local session_name = tmux.get_session_name_for_path(wt.path, wt.branch)
    local has_session = session_set[session_name] or false
    local is_current = wt.path == cwd
    local diff_stats = get_diff_stats(wt.path)
    local last_commit = get_last_commit_time(wt.path)
    local time_str = time_ago(last_commit)

    table.insert(entries, {
      path = wt.path,
      branch = wt.branch,
      head = wt.head,
      session_name = session_name,
      has_session = has_session,
      is_current = is_current,
      diff_stats = diff_stats,
      time_ago = time_str,
      last_commit = last_commit,
    })
  end

  -- Sort by most recent commit
  table.sort(entries, function(a, b)
    return a.last_commit > b.last_commit
  end)

  local picker_opts = vim.tbl_deep_extend("force", config.options.telescope or {}, opts)

  pickers
    .new(picker_opts, {
      prompt_title = "Worktrees ( = current, 󰆍 = session)",
      finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
          -- Build diff display string
          local diff_str = ""
          if entry.diff_stats.is_base then
            diff_str = "(base)"
          elseif entry.diff_stats.uncommitted then
            local parts = {}
            if entry.diff_stats.insertions > 0 then
              table.insert(parts, string.format("+%d", entry.diff_stats.insertions))
            end
            if entry.diff_stats.deletions > 0 then
              table.insert(parts, string.format("-%d", entry.diff_stats.deletions))
            end
            diff_str = string.format("%s (uncommitted)", table.concat(parts, " "))
          elseif entry.diff_stats.insertions > 0 or entry.diff_stats.deletions > 0 then
            local parts = {}
            if entry.diff_stats.insertions > 0 then
              table.insert(parts, string.format("+%d", entry.diff_stats.insertions))
            end
            if entry.diff_stats.deletions > 0 then
              table.insert(parts, string.format("-%d", entry.diff_stats.deletions))
            end

            -- Add colored squares
            local total = entry.diff_stats.insertions + entry.diff_stats.deletions
            local insert_ratio = total > 0 and (entry.diff_stats.insertions / total) or 0
            local num_green = math.floor(insert_ratio * 5)
            local squares = string.rep("█", num_green) .. string.rep("█", 5 - num_green)

            diff_str = string.format("%s %s", table.concat(parts, " "), squares)
          end

          local status = ""
          if entry.is_current then
            status = status .. " "
          end
          if entry.has_session then
            status = status .. " 󰆍"
          end

          -- Build simple display string
          local display_str = string.format(
            "%-25s  %-30s  %-12s  %s",
            entry.branch,
            diff_str,
            entry.time_ago,
            status
          )

          return {
            value = entry,
            display = display_str,
            ordinal = entry.branch .. " " .. entry.path,
            path = entry.path,
          }
        end,
      }),
      sorter = conf.generic_sorter(picker_opts),
      previewer = previewers.new_termopen_previewer({
        get_command = function(entry)
          -- Show git diff stat + actual diff
          local base_branch = "main"
          local check_main = vim.fn.system(string.format(
            "git -C '%s' rev-parse --verify main 2>/dev/null",
            entry.value.path
          ))
          if vim.v.shell_error ~= 0 then
            base_branch = "master"
          end

          return {
            "sh",
            "-c",
            string.format(
              "cd '%s' && echo '=== Diff Summary ===' && git diff --stat %s...HEAD && echo '' && echo '=== Changes ===' && git diff %s...HEAD",
              entry.value.path,
              base_branch,
              base_branch
            ),
          }
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
