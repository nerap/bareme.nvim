# bareme.nvim

A Neovim plugin for seamless git worktree and tmux session management.

## Features

- **Worktree Management**: Create, switch, delete, and list git worktrees
- **Tmux Integration**: Automatically create/switch tmux sessions when working with worktrees
- **Telescope Integration**: Beautiful fuzzy-finder interface for switching between worktrees
- **Session Status**: See which worktrees have active tmux sessions
- **Smart Naming**: Consistent session naming convention: `<repo>_<branch>`

## Requirements

- Neovim >= 0.8.0
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- git with worktree support
- tmux (optional, for session management)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nerap/bareme.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("bareme").setup({
      -- Path to your tmux-sessionizer script
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
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nerap/bareme.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("bareme").setup()
  end
}
```

## Usage

### Commands

#### `:WorktreeCreate [branch-name]`

Create a new worktree with a new branch. If no branch name is provided, you'll be prompted to enter one.

```vim
:WorktreeCreate feature-auth
```

This will:
1. Create a new branch `feature-auth`
2. Create a worktree in `<bare-repo>/feature-auth`
3. Optionally switch to the new worktree
4. Create a tmux session named `<repo>_feature-auth`

#### `:WorktreeCreateFrom [branch-name]`

Create a worktree from an existing branch.

```vim
:WorktreeCreateFrom main
```

#### `:WorktreeSwitch`

Open a Telescope picker to switch between worktrees. Shows:
- Worktree path
- Branch name
- Session status (󰆍 = has active tmux session)

**Features:**
- Preview shows directory contents
- Automatically changes directory and switches tmux session
- Press `<CR>` to switch to selected worktree

#### `:WorktreeDelete [path]`

Delete a worktree. If no path is provided, opens a Telescope picker to select which worktree to delete.

```vim
:WorktreeDelete
```

This will:
1. Show confirmation prompt (if enabled)
2. Delete the worktree
3. Optionally kill the associated tmux session

#### `:WorktreeList`

List all worktrees with their status. Shows:
-  = current worktree
- 󰆍 = has active tmux session

**Features:**
- Preview shows `git status` for each worktree
- Read-only picker for viewing worktree status

### Key Bindings (Suggested)

```lua
vim.keymap.set("n", "<leader>wc", "<cmd>WorktreeCreate<cr>", { desc = "Create worktree" })
vim.keymap.set("n", "<leader>ws", "<cmd>WorktreeSwitch<cr>", { desc = "Switch worktree" })
vim.keymap.set("n", "<leader>wd", "<cmd>WorktreeDelete<cr>", { desc = "Delete worktree" })
vim.keymap.set("n", "<leader>wl", "<cmd>WorktreeList<cr>", { desc = "List worktrees" })
```

## How It Works

### Bare Repository Setup

This plugin works best with bare git repositories using the worktree workflow:

```bash
# Clone as bare repository
git clone --bare git@github.com:user/repo.git repo.git

# Create worktrees
cd repo.git
git worktree add ../main main
git worktree add ../feature-x feature-x
```

Your directory structure will look like:
```
repo.git/           # Bare repository
├── main/           # Worktree for main branch
├── feature-x/      # Worktree for feature-x branch
└── feature-y/      # Worktree for feature-y branch
```

### Tmux Session Management

When you create or switch to a worktree, the plugin:

1. Generates a session name: `<repo-name>_<branch-name>`
   - Example: `myapp_main`, `myapp_feature-auth`
2. Creates a tmux session with vertical split (70/30)
   - Left pane: Neovim
   - Right pane: Claude CLI (auto-resumes if `.claude` directory exists)
3. Switches to the session if you're already in tmux

### Session Naming Convention

- **Worktrees of bare repos**: `<repo-name>_<branch-name>`
  - Example: `bareme_nvim_main`, `bareme_nvim_feature-test`
- **Regular directories**: `<directory-name>`

This ensures no session name collisions between branches of the same project.

## Configuration

### Default Configuration

```lua
{
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
```

## Architecture

```
bareme.nvim/
├── lua/
│   └── bareme/
│       ├── init.lua          # Main entry point, command implementations
│       ├── config.lua         # Configuration management
│       ├── git.lua            # Git worktree utilities
│       ├── tmux.lua           # Tmux session management
│       └── telescope.lua      # Telescope pickers
└── plugin/
    └── bareme.lua             # User command definitions
```

## Complementary Tools

This plugin is designed to work alongside:

- **tmux-sessionizer**: Bash script for creating tmux sessions from directories
- **fzf**: For the tmux-sessionizer picker

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT

## Credits

Inspired by:
- [ThePrimeagen's tmux-sessionizer](https://github.com/ThePrimeagen/.dotfiles/blob/master/bin/.local/scripts/tmux-sessionizer)
- [git-worktree.nvim](https://github.com/ThePrimeagen/git-worktree.nvim)
