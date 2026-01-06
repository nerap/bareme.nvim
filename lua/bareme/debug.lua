-- Debug utilities for bareme.nvim
local M = {}

function M.check_current_state()
  print("=== Current State ===")
  print("CWD: " .. vim.fn.getcwd())
  print("CWD exists: " .. tostring(vim.fn.isdirectory(vim.fn.getcwd()) == 1))

  local is_repo = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null")
  print("Is git repo (shell): " .. vim.trim(is_repo))
  print("Shell error: " .. vim.v.shell_error)

  local bare_repo_cmd = vim.fn.system("git rev-parse --git-common-dir 2>/dev/null")
  print("Git common dir: " .. vim.trim(bare_repo_cmd))

  local git = require("bareme.git")
  print("is_git_repo(): " .. tostring(git.is_git_repo()))
  print("get_bare_repo_path(): " .. tostring(git.get_bare_repo_path()))

  local worktrees = git.list_worktrees()
  print("Worktrees found: " .. #worktrees)
  print("=== End State ===")
end

function M.test_git_detection()
  local git = require("bareme.git")

  print("=== Git Detection Debug ===")

  -- Test 1: Is git repo?
  local is_repo = git.is_git_repo()
  print("Is git repo: " .. tostring(is_repo))

  -- Test 2: Get bare repo path
  local bare_repo = git.get_bare_repo_path()
  print("Bare repo path: " .. tostring(bare_repo))

  -- Test 3: Is bare repo?
  if bare_repo then
    local is_bare = git.is_bare_repo(bare_repo)
    print("Is bare repo: " .. tostring(is_bare))
  end

  -- Test 4: Raw git output
  if bare_repo then
    print("\n--- Raw git worktree list ---")
    local output = vim.fn.system(string.format("git -C '%s' worktree list --porcelain 2>/dev/null", bare_repo))
    print("Shell error: " .. vim.v.shell_error)
    print("Output length: " .. #output)
    print("Output:")
    print(output)
    print("--- End raw output ---\n")

    -- Parse line by line
    print("--- Parsing lines ---")
    local line_num = 0
    for line in output:gmatch("[^\r\n]+") do
      line_num = line_num + 1
      print(string.format("[%d] '%s'", line_num, line))
    end
    print("--- End parsing ---\n")
  end

  -- Test 5: List worktrees
  local worktrees = git.list_worktrees()
  print("Number of worktrees: " .. #worktrees)

  for i, wt in ipairs(worktrees) do
    print(string.format("  [%d] %s [%s]", i, wt.path, wt.branch))
  end

  print("=== End Debug ===")

  return worktrees
end

function M.test_tmux()
  local tmux = require("bareme.tmux")

  print("=== Tmux Debug ===")
  print("Inside tmux: " .. tostring(tmux.is_inside_tmux()))
  print("Tmux running: " .. tostring(tmux.is_tmux_running()))

  local sessions = tmux.list_sessions()
  print("Sessions: " .. #sessions)
  for i, session in ipairs(sessions) do
    print("  [" .. i .. "] " .. session)
  end

  print("=== End Debug ===")
end

-- Create commands
vim.api.nvim_create_user_command("BaremeDebug", function()
  M.test_git_detection()
  M.test_tmux()
end, {
  desc = "Debug bareme.nvim git and tmux detection",
})

vim.api.nvim_create_user_command("BaremeState", function()
  M.check_current_state()
end, {
  desc = "Check current state after operations",
})

return M
