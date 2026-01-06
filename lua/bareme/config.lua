-- Default configuration for bareme.nvim
local M = {}

M.defaults = {
  -- Path to tmux-sessionizer script
  tmux_sessionizer = vim.fn.expand("~/.local/scripts/tmux-sessionizer"),

  -- Automatically switch tmux session after creating/switching worktree
  auto_switch_tmux = true,

  -- Automatically kill tmux session when deleting worktree
  auto_kill_session = true,

  -- Confirmation prompts
  confirm_delete = true,

  -- Telescope picker options
  telescope = {
    layout_strategy = "horizontal",
    layout_config = {
      width = 0.8,
      height = 0.8,
      preview_width = 0.6,
    },
  },
}

M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

-- Initialize with defaults
M.setup()

return M
