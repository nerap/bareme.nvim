# bareme.nvim Keybindings

## Quick Reference

### Main Keybindings

| Key | Command | Description |
|-----|---------|-------------|
| `<C-b>` | `:WorktreeSwitch` | Quick switch between worktrees (Telescope) |
| `<leader>ww` | `:WorktreeSwitch` | Switch worktrees |
| `<leader>wa` | `:WorktreeCreate` | Add/Create new worktree |
| `<leader>wd` | `:WorktreeDelete` | Delete a worktree |
| `<leader>wl` | `:WorktreeList` | List all worktrees |
| `<leader>wc` | `:WorktreeCleanup` | Cleanup orphaned worktrees |
| `<leader>wp` | `:WorktreePrune` | Prune worktrees |

### Comparison with tmux-sessionizer

| Key | Scope | Tool | Use Case |
|-----|-------|------|----------|
| `<C-f>` | ALL projects | tmux-sessionizer | Switch between different repos |
| `<C-b>` | Current repo | bareme.nvim | Switch branches within same repo |

**Example workflow:**
- `<C-f>` → Jump from `bareme.nvim` to `dotfiles` to `my-app`
- `<C-b>` → Switch from `bareme.nvim/main` to `bareme.nvim/feature-test`

## Command Details

### `<leader>wa` - Create Worktree

Create a new worktree with a new branch:

```vim
<leader>wa
" Enter branch name when prompted
" Example: feature-auth

" Or provide branch name directly:
:WorktreeCreate feature-auth
```

**What it does:**
1. Creates a new branch
2. Creates worktree at `<bare-repo>/<branch-name>`
3. Asks if you want to switch to it
4. Creates tmux session `<repo>_<branch>`

### `<leader>ww` or `<C-b>` - Switch Worktree

Open Telescope picker to switch between worktrees:

```vim
<leader>ww
" or
<C-b>
```

**Features:**
- Shows all worktrees with branch names
- Shows session status (󰆍 = has active tmux session)
- Preview shows directory contents
- Press `Enter` to switch (changes dir + switches tmux session)

### `<leader>wd` - Delete Worktree

Delete a worktree and its tmux session:

```vim
<leader>wd
" Telescope picker appears - select worktree to delete
" Confirm deletion
```

**What it does:**
1. Shows picker to select worktree
2. Asks for confirmation
3. Deletes the worktree
4. Kills the associated tmux session

### `<leader>wl` - List Worktrees

View all worktrees with their status:

```vim
<leader>wl
```

**Status indicators:**
-  = Current worktree (where you are now)
- 󰆍 = Has active tmux session

**Preview:** Shows `git status` for each worktree

### `<leader>wc` - Cleanup Orphaned Worktrees

Clean up worktrees whose remote branches were deleted:

```vim
<leader>wc
```

**Use case:** After running `git fetch --prune`, use this to clean up local worktrees for deleted remote branches.

**What it does:**
1. Finds worktrees with deleted branches
2. Shows list and asks for confirmation
3. Deletes each orphaned worktree
4. Kills associated tmux sessions

### `<leader>wp` - Prune Worktrees

Same as cleanup, plus runs `git worktree prune`:

```vim
<leader>wp
```

**What it does:**
1. Runs cleanup (above)
2. Runs `git worktree prune` to clean up administrative files

## Typical Workflows

### Workflow 1: Start New Feature

```vim
" 1. Create new feature branch
<leader>wa
" Enter: feature-auth

" 2. Switch to it (when prompted)
" Press: y

" 3. Start coding!
```

### Workflow 2: Switch Between Features

```vim
" Quick switch with Ctrl-B
<C-b>
" Select: feature-auth
" Press: Enter

" Neovim changes directory
" Tmux switches to bareme_nvim_feature-auth session
```

### Workflow 3: Clean Up Merged Features

```bash
# On main branch, pull changes
git fetch --prune
```

```vim
" In Neovim, cleanup orphaned worktrees
<leader>wc

" Confirms and shows:
" - feature-auth (branch deleted)
" - feature-old (branch deleted)

" Press 'y' to delete them
```

### Workflow 4: Review All Features

```vim
" List all worktrees with status
<leader>wl

" See which features:
" - Have active sessions (󰆍)
" - Are current ()
" - Preview shows git status
```

## Mnemonic

All worktree commands start with `<leader>w`:

- `w` + `w` = **W**orktree s**W**itch
- `w` + `a` = **W**orktree **A**dd
- `w` + `d` = **W**orktree **D**elete
- `w` + `l` = **W**orktree **L**ist
- `w` + `c` = **W**orktree **C**leanup
- `w` + `p` = **W**orktree **P**rune

Easy to remember!

## Customization

To customize keybindings, edit `/Users/nerap/config/nvim/lua/plugins/bareme.lua`:

```lua
-- Change Ctrl-B to something else
vim.keymap.set("n", "<C-w>", "<cmd>WorktreeSwitch<cr>", { desc = "Switch worktree" })

-- Change leader prefix from 'w' to 'g' (git)
vim.keymap.set("n", "<leader>gs", "<cmd>WorktreeSwitch<cr>", { desc = "Git worktree switch" })
```
