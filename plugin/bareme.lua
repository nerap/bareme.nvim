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

-- Load reload utility for development
require("bareme.reload")

-- Load debug utility for development
require("bareme.debug")
