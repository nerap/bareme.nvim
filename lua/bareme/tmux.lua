-- Tmux session management utilities
local M = {}

-- Check if running inside tmux
function M.is_inside_tmux()
  return vim.env.TMUX ~= nil
end

-- Check if tmux is running
function M.is_tmux_running()
  local result = vim.fn.system("pgrep tmux 2>/dev/null")
  return vim.v.shell_error == 0
end

-- Get tmux session name for a worktree path
function M.get_session_name_for_path(path, branch)
  -- Check if parent directory is a bare repo
  local parent = vim.fn.fnamemodify(path, ":h")
  local is_bare = vim.fn.system(string.format("git -C '%s' rev-parse --is-bare-repository 2>/dev/null", parent))

  if vim.trim(is_bare) == "true" then
    -- This is a worktree of a bare repo
    local repo_name = vim.fn.fnamemodify(parent, ":t"):gsub("%.git$", ""):gsub("%.", "_")
    if branch then
      return string.format("%s_%s", repo_name, branch)
    else
      return string.format("%s_%s", repo_name, vim.fn.fnamemodify(path, ":t"):gsub("%.", "_"))
    end
  else
    -- Regular directory
    return vim.fn.fnamemodify(path, ":t"):gsub("%.", "_")
  end
end

-- Check if a tmux session exists
function M.session_exists(session_name)
  local cmd = string.format("tmux has-session -t='%s' 2>/dev/null", session_name)
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

-- Get current tmux session name
function M.get_current_session()
  if not M.is_inside_tmux() then
    return nil
  end
  local result = vim.fn.system("tmux display-message -p '#S'")
  return vim.trim(result)
end

-- Switch to a tmux session (or create and switch)
function M.switch_to_session(session_name, path)
  if not M.is_tmux_running() then
    return false, "Tmux is not running"
  end

  -- Create session if it doesn't exist
  if not M.session_exists(session_name) then
    local success, err = M.create_session(session_name, path)
    if not success then
      return false, err
    end
  end

  -- Switch to session
  if M.is_inside_tmux() then
    local cmd = string.format("tmux switch-client -t '%s'", session_name)
    vim.fn.system(cmd)
  else
    local cmd = string.format("tmux attach-session -t '%s'", session_name)
    vim.fn.system(cmd)
  end

  return vim.v.shell_error == 0, "Switched to session: " .. session_name
end

-- Create a new tmux session with 2 windows (terminal+claude, nvim)
function M.create_session(session_name, path)
  if M.session_exists(session_name) then
    return true, "Session already exists"
  end

  -- Create new session detached with first window (terminal)
  local cmd = string.format("tmux new-session -ds '%s' -c '%s'", session_name, path)
  vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, "Failed to create tmux session"
  end

  -- Window 1: Split for Claude in right pane (70/30)
  cmd = string.format("tmux split-window -t '%s:1' -h -p 30 -c '%s' 'claude --continue || claude'", session_name, path)
  vim.fn.system(cmd)

  -- Create window 2 with nvim
  cmd = string.format("tmux new-window -t '%s:2' -c '%s'", session_name, path)
  vim.fn.system(cmd)

  cmd = string.format("tmux send-keys -t '%s:2' 'nvim .' C-m", session_name)
  vim.fn.system(cmd)

  -- Focus on window 2 (nvim)
  cmd = string.format("tmux select-window -t '%s:2'", session_name)
  vim.fn.system(cmd)

  return true, "Created session: " .. session_name
end

-- Kill a tmux session
function M.kill_session(session_name)
  if not M.session_exists(session_name) then
    return true, "Session does not exist"
  end

  local cmd = string.format("tmux kill-session -t '%s' 2>&1", session_name)
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, output
  end

  return true, "Killed session: " .. session_name
end

-- List all tmux sessions
function M.list_sessions()
  if not M.is_tmux_running() then
    return {}
  end

  local output = vim.fn.system("tmux list-sessions -F '#{session_name}' 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local sessions = {}
  for line in output:gmatch("[^\r\n]+") do
    table.insert(sessions, vim.trim(line))
  end

  return sessions
end

-- Call tmux-sessionizer script
function M.call_sessionizer(path)
  local config = require("bareme.config")
  local script = config.options.tmux_sessionizer

  if vim.fn.executable(script) ~= 1 then
    return false, "tmux-sessionizer script not found or not executable: " .. script
  end

  local cmd = string.format("'%s' '%s'", script, path)
  vim.fn.system(cmd)

  return vim.v.shell_error == 0, "Called tmux-sessionizer"
end

return M
