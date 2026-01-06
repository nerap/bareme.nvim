# bareme.nvim Quick Start

## Setup Complete!

### What You Have

**Plugin Location:**
- Development: `/Users/nerap/personal/bareme.nvim.git/main`
- Config: `/Users/nerap/config/nvim/lua/plugins/bareme.lua`

**Keybindings:**
- `<C-f>` - tmux-sessionizer (switch between ALL projects)
- `<C-b>` - WorktreeSwitch (switch between worktrees in CURRENT repo)

### Available Commands

```vim
:WorktreeCreate [branch]       " Create new worktree with new branch
:WorktreeCreateFrom [branch]   " Create worktree from existing branch
:WorktreeSwitch                " Telescope picker to switch worktrees
:WorktreeDelete [path]         " Delete worktree (with picker if no path)
:WorktreeList                  " View all worktrees with status
:BaremeReload                  " Reload plugin (for development)
```

### Quick Test

1. **Restart Neovim** or reload config:
   ```vim
   :source $MYVIMRC
   ```

2. **Test the plugin:**
   ```vim
   :WorktreeList
   ```
   You should see:
   - `/Users/nerap/personal/bareme.nvim.git/main [main]  󰆍`
   - `/Users/nerap/personal/bareme.nvim.git/feature-test [feature-test]  󰆍`

3. **Try switching worktrees:**
   ```
   Press Ctrl-B
   ```
   Select a worktree and press Enter

### Status Indicators

-  = Current worktree
- 󰆍 = Has active tmux session

### Development Workflow

**When you make changes to the plugin:**

1. Edit file in `/Users/nerap/personal/bareme.nvim.git/main/`
2. Save the file (`:w`)
3. Reload: `:BaremeReload`
4. Test your changes immediately!

**Alternative:**
- Use `<leader><leader>` (your existing remap) to reload entire config

### Typical Usage

**Scenario 1: Create a new feature branch**
```vim
:WorktreeCreate feature-auth
" Press 'y' to switch to new worktree
" Creates: /Users/nerap/personal/bareme.nvim.git/feature-auth
" Session: bareme_nvim_feature-auth
```

**Scenario 2: Switch between features**
```
Press Ctrl-B
" Telescope picker appears
" Select worktree with arrow keys
" Press Enter to switch
```

**Scenario 3: Clean up old feature**
```vim
:WorktreeDelete
" Telescope picker appears
" Select worktree to delete
" Confirm deletion
" Tmux session automatically killed
```

**Scenario 4: Check status of all worktrees**
```vim
:WorktreeList
" See which worktrees exist
" See which have active tmux sessions
" Preview shows git status for each
```

### Comparison: Ctrl-F vs Ctrl-B

| Key | Command | Scope | Use Case |
|-----|---------|-------|----------|
| `<C-f>` | tmux-sessionizer | ALL projects | "I want to work on a different project" |
| `<C-b>` | WorktreeSwitch | Current repo | "I want to switch branches in THIS project" |

**Example:**
- `<C-f>`: Jump from `bareme.nvim` to `dotfiles` to `my-app`
- `<C-b>`: Switch from `bareme.nvim/main` to `bareme.nvim/feature-test`

### Troubleshooting

**Plugin not loading?**
```vim
:Lazy sync
:source $MYVIMRC
```

**Commands not available?**
```vim
:BaremeReload
" or restart Neovim
```

**Telescope not showing preview?**
```vim
" Check telescope is installed:
:Telescope
```

**Worktrees not showing?**
```vim
" Make sure you're in a git worktree:
:!git worktree list
```

### Next Steps

1. ✅ Plugin installed and configured
2. ✅ Test with existing worktrees (`main`, `feature-test`)
3. 🔄 Create a test worktree: `:WorktreeCreate test-feature`
4. 🔄 Switch between worktrees with `Ctrl-B`
5. 🔄 Delete test worktree: `:WorktreeDelete`
6. 🚀 Use in your daily workflow!

### Links

- Full docs: See [README.md](./README.md)
- Testing guide: See [TESTING.md](./TESTING.md)
- Your config: `/Users/nerap/config/nvim/lua/plugins/bareme.lua`
- Plugin code: `/Users/nerap/personal/bareme.nvim.git/main/`

---

**You're all set! Press `Ctrl-B` to try it out!**
