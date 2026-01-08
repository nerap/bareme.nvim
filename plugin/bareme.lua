-- Command definitions for bareme.nvim

-- Don't load plugin twice
if vim.g.loaded_bareme then
  return
end
vim.g.loaded_bareme = 1

local bareme = require("bareme")

-- Command to create a new worktree with a new branch
vim.api.nvim_create_user_command("WorktreeCreate", function(opts)
  bareme.create_worktree(opts.args, true)
end, {
  nargs = "?",
  desc = "Create a new worktree with a new branch",
})

-- Command to create a worktree from an existing branch
vim.api.nvim_create_user_command("WorktreeCreateFrom", function(opts)
  bareme.create_worktree(opts.args, false)
end, {
  nargs = "?",
  desc = "Create a worktree from an existing branch",
})

-- Command to switch between worktrees
vim.api.nvim_create_user_command("WorktreeSwitch", function()
  bareme.switch_worktree()
end, {
  desc = "Switch to a different worktree",
})

-- Command to delete a worktree
vim.api.nvim_create_user_command("WorktreeDelete", function(opts)
  bareme.delete_worktree(opts.args)
end, {
  nargs = "?",
  desc = "Delete a worktree",
})

-- Command to list all worktrees
vim.api.nvim_create_user_command("WorktreeList", function()
  bareme.list_worktrees()
end, {
  desc = "List all worktrees with session status",
})

-- Command to cleanup orphaned worktrees (deleted remote branches)
vim.api.nvim_create_user_command("WorktreeCleanup", function()
  bareme.cleanup_orphaned()
end, {
  desc = "Cleanup worktrees for deleted remote branches",
})

-- Command to prune worktrees (cleanup + git worktree prune)
vim.api.nvim_create_user_command("WorktreePrune", function()
  bareme.prune()
end, {
  desc = "Prune worktrees and cleanup deleted branches",
})

-- Trash management commands
vim.api.nvim_create_user_command("WorktreeRecover", function()
  bareme.recover_worktree()
end, {
  desc = "Recover a worktree from trash",
})

vim.api.nvim_create_user_command("WorktreeEmptyTrash", function()
  bareme.empty_trash()
end, {
  desc = "Permanently delete all trashed worktrees",
})

vim.api.nvim_create_user_command("WorktreeTrashStatus", function()
  bareme.trash_status()
end, {
  desc = "Show trash status (count and size)",
})

-- Environment and project commands
vim.api.nvim_create_user_command("WorktreeInitEnv", function()
  bareme.init_env_template()
end, {
  desc = "Create default .env.template in bare repo root",
})

vim.api.nvim_create_user_command("WorktreePorts", function()
  bareme.show_ports()
end, {
  desc = "Show port allocations for all worktrees",
})

-- Docker commands
vim.api.nvim_create_user_command("WorktreeDockerRestart", function()
  bareme.docker_restart()
end, {
  desc = "Restart Docker services in current worktree",
})

vim.api.nvim_create_user_command("WorktreeDockerStatus", function()
  bareme.docker_status()
end, {
  desc = "Show Docker services status",
})

vim.api.nvim_create_user_command("WorktreeDockerLogs", function(opts)
  local args = vim.split(opts.args, " ")
  local service = args[1]
  local lines = tonumber(args[2]) or 100
  bareme.docker_logs(service, lines)
end, {
  nargs = "*",
  desc = "Show Docker logs (usage: WorktreeDockerLogs [service] [lines])",
})

-- Observability commands
vim.api.nvim_create_user_command("WorktreeHealth", function()
  bareme.show_health()
end, {
  desc = "Show worktree health summary",
})

vim.api.nvim_create_user_command("BaremeLog", function(opts)
  local lines = tonumber(opts.args) or 100
  bareme.show_log(lines)
end, {
  nargs = "?",
  desc = "Show bareme event log (usage: BaremeLog [lines])",
})

vim.api.nvim_create_user_command("ClaudeStats", function()
  bareme.show_claude_stats()
end, {
  desc = "Show Claude Code session statistics",
})

vim.api.nvim_create_user_command("BaremeMonitor", function()
  bareme.show_monitor()
end, {
  desc = "Show real-time monitoring dashboard",
})

vim.api.nvim_create_user_command("ClaudeInstallHooks", function()
  bareme.install_claude_hooks()
end, {
  desc = "Install Claude Code hooks in all existing worktrees",
})

vim.api.nvim_create_user_command("BaremeCleanupPorts", function()
  bareme.cleanup_orphaned_ports()
end, {
  desc = "Clean up orphaned port allocations",
})

-- Default keymaps
-- Quick access to dashboard
vim.keymap.set("n", "<C-s>", function()
  bareme.show_monitor()
end, { desc = "Open Bareme Dashboard" })

-- Leader keymaps for other actions
vim.keymap.set("n", "<leader>ws", function()
  bareme.switch_worktree()
end, { desc = "Switch Worktree" })

vim.keymap.set("n", "<leader>wc", function()
  bareme.create_worktree()
end, { desc = "Create Worktree" })

vim.keymap.set("n", "<leader>wd", function()
  bareme.delete_worktree()
end, { desc = "Delete Worktree" })

-- Start Claude monitoring on plugin load
local claude_monitor = require("bareme.claude_monitor")
claude_monitor.start_watching()

-- Load reload utility for development
require("bareme.reload")

-- Load debug utility for development
require("bareme.debug")
