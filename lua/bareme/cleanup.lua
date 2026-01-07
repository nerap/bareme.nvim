-- Cleanup utilities for orphaned worktrees
local M = {}

local git = require("bareme.git")
local tmux = require("bareme.tmux")

-- Get list of branches (local and remote)
local function get_branches()
  local output = vim.fn.system("git branch -a 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local branches = {}
  for line in output:gmatch("[^\r\n]+") do
    -- Remove leading spaces, asterisk, and "remotes/origin/"
    local branch = line:gsub("^%s*%*?%s*", ""):gsub("^remotes/origin/", "")
    -- Skip HEAD pointer
    if not branch:match("HEAD ->") then
      branches[branch] = true
    end
  end

  return branches
end

-- Find worktrees with deleted branches
function M.find_orphaned_worktrees()
  local worktrees = git.list_worktrees()
  local branches = get_branches()
  local orphaned = {}

  for _, wt in ipairs(worktrees) do
    -- Skip detached HEAD worktrees
    if wt.branch ~= "detached" then
      -- Check if branch still exists
      if not branches[wt.branch] then
        table.insert(orphaned, wt)
      end
    end
  end

  return orphaned
end

-- Clean up orphaned worktrees
function M.cleanup_orphaned_worktrees()
  -- First, fetch from remote to get latest branch info
  vim.notify("Fetching from remote...", vim.log.levels.INFO)
  local fetch_output = vim.fn.system("git fetch --prune 2>&1")
  if vim.v.shell_error ~= 0 then
    vim.notify("Warning: Failed to fetch from remote: " .. fetch_output, vim.log.levels.WARN)
  end

  local orphaned = M.find_orphaned_worktrees()

  if #orphaned == 0 then
    vim.notify("No orphaned worktrees found", vim.log.levels.INFO)
    return
  end

  -- Show what will be cleaned up
  local msg = string.format("Found %d orphaned worktree(s):\n", #orphaned)
  for _, wt in ipairs(orphaned) do
    msg = msg .. string.format("  - %s [%s]\n", wt.path, wt.branch)
  end
  msg = msg .. "\nClean up these worktrees?"

  local choice = vim.fn.confirm(msg, "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end

  -- Clean up each orphaned worktree
  local cleaned = 0
  local failed = 0
  local sessions_killed = 0

  for _, wt in ipairs(orphaned) do
    -- Get session name before deleting
    local session_name = tmux.get_session_name_for_path(wt.path, wt.branch)

    -- Delete worktree
    local success, err = git.delete_worktree(wt.path)
    if success then
      cleaned = cleaned + 1

      -- Kill tmux session if it exists
      if tmux.session_exists(session_name) then
        tmux.kill_session(session_name)
        sessions_killed = sessions_killed + 1
      end
    else
      failed = failed + 1
      vim.notify(string.format("Failed to delete %s: %s", wt.path, err), vim.log.levels.ERROR)
    end
  end

  -- Single summary notification
  local summary = string.format("Cleanup complete: %d worktree(s) deleted", cleaned)
  if sessions_killed > 0 then
    summary = summary .. string.format(", %d session(s) killed", sessions_killed)
  end
  if failed > 0 then
    summary = summary .. string.format(", %d failed", failed)
  end
  vim.notify(summary, vim.log.levels.INFO)
end

-- Prune worktrees (cleanup orphaned + run git worktree prune)
function M.prune_worktrees()
  -- First, cleanup orphaned worktrees
  M.cleanup_orphaned_worktrees()

  -- Then run git worktree prune
  local bare_repo = git.get_bare_repo_path()
  if not bare_repo then
    vim.notify("Not in a git worktree", vim.log.levels.ERROR)
    return
  end

  local output = vim.fn.system(string.format("git -C '%s' worktree prune -v 2>&1", bare_repo))
  if vim.v.shell_error == 0 then
    vim.notify("Git worktree prune complete", vim.log.levels.INFO)
  else
    vim.notify("Git worktree prune failed: " .. output, vim.log.levels.ERROR)
  end
end

return M
