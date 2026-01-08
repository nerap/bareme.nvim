-- Statusline integration for bareme.nvim
-- Example: Show Claude notifications in your statusline
local M = {}

local claude_monitor = require("bareme.claude_monitor")
local git = require("bareme.git")

-- Get current worktree branch
function M.get_current_branch()
  if not git.is_git_repo() then
    return nil
  end

  local bare_repo = git.get_bare_repo_path()
  if not bare_repo then
    return nil
  end

  local cwd = vim.fn.getcwd()
  local worktrees = git.list_worktrees()

  for _, wt in ipairs(worktrees) do
    if wt.path == cwd then
      return wt.branch
    end
  end

  return nil
end

-- Get Claude status for current worktree
function M.get_claude_status()
  local branch = M.get_current_branch()
  if not branch then
    return nil
  end

  local stats = claude_monitor.get_session_stats()
  return stats[branch]
end

-- Get Claude status icon
function M.get_claude_icon()
  local status = M.get_claude_status()
  if not status then
    return ""
  end

  if status.status == "needs_input" then
    return "🔔"
  elseif status.status == "active" then
    return "🟢"
  elseif status.status == "paused" then
    return "⏸"
  else
    return ""
  end
end

-- Get formatted Claude status for statusline
function M.get_claude_statusline()
  local icon = M.get_claude_icon()
  if icon == "" then
    return ""
  end

  local status = M.get_claude_status()
  if not status then
    return ""
  end

  if status.status == "needs_input" then
    return string.format("%s Claude needs input", icon)
  elseif status.status == "active" then
    return string.format("%s Claude active", icon)
  else
    return ""
  end
end

-- Check if there are pending notifications in any worktree
function M.has_notifications()
  local notifications = claude_monitor.get_pending_notifications()
  return #notifications > 0
end

-- Get notification count
function M.get_notification_count()
  local notifications = claude_monitor.get_pending_notifications()
  return #notifications
end

-- Get notification summary for statusline
function M.get_notifications_statusline()
  local count = M.get_notification_count()
  if count == 0 then
    return ""
  end

  return string.format("🔔 %d Claude notification(s)", count)
end

--[[
INTEGRATION EXAMPLES:

-- For lualine:
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        return require('bareme.statusline').get_claude_statusline()
      end,
      'encoding',
      'fileformat',
      'filetype'
    }
  }
})

-- For custom statusline:
function MyStatusline()
  local bareme = require('bareme.statusline')
  local parts = {
    '%f',  -- filename
    bareme.get_claude_statusline(),
    '%=',  -- right align
    '%l:%c',  -- line:column
  }
  return table.concat(parts, ' ')
end

vim.o.statusline = '%!v:lua.MyStatusline()'

-- For showing notifications count:
function MyStatusline()
  local bareme = require('bareme.statusline')
  local notifications = bareme.get_notifications_statusline()

  if notifications ~= '' then
    return '%f ' .. notifications .. ' %= %l:%c'
  else
    return '%f %= %l:%c'
  end
end
]]

return M
