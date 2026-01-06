# Testing Guide for bareme.nvim

## Setup for Local Testing

### Option 1: Use with local Neovim config

Add to your Neovim config (e.g., `~/.config/nvim/lua/plugins/bareme.lua`):

```lua
return {
  dir = "/Users/nerap/personal/bareme.nvim.git/main",
  dependencies = {
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("bareme").setup({
      tmux_sessionizer = vim.fn.expand("~/.local/scripts/tmux-sessionizer"),
      auto_switch_tmux = true,
      auto_kill_session = true,
      confirm_delete = true,
    })
  end,
}
```

### Option 2: Test in minimal init.lua

Create a minimal test config at `/tmp/test_bareme.lua`:

```lua
-- Minimal init for testing bareme.nvim
vim.opt.runtimepath:append("/Users/nerap/personal/bareme.nvim.git/main")
vim.opt.runtimepath:append("~/.local/share/nvim/lazy/telescope.nvim")
vim.opt.runtimepath:append("~/.local/share/nvim/lazy/plenary.nvim")

require("bareme").setup({
  tmux_sessionizer = vim.fn.expand("~/.local/scripts/tmux-sessionizer"),
  auto_switch_tmux = true,
  auto_kill_session = true,
  confirm_delete = true,
})

-- Add keybindings for testing
vim.keymap.set("n", "<leader>wc", "<cmd>WorktreeCreate<cr>")
vim.keymap.set("n", "<leader>ws", "<cmd>WorktreeSwitch<cr>")
vim.keymap.set("n", "<leader>wd", "<cmd>WorktreeDelete<cr>")
vim.keymap.set("n", "<leader>wl", "<cmd>WorktreeList<cr>")

print("bareme.nvim loaded! Try :WorktreeList")
```

Launch with: `nvim -u /tmp/test_bareme.lua`

## Test Cases

### Test 1: List Worktrees

**Expected state:**
- 2 worktrees: `main` and `feature-test`
- 2 tmux sessions: `bareme_nvim_main` and `bareme_nvim_feature-test`

**Test:**
1. Open Neovim from any bareme worktree
2. Run `:WorktreeList`
3. Should see:
   ```
   /Users/nerap/personal/bareme.nvim.git/main          [main]            󰆍
   /Users/nerap/personal/bareme.nvim.git/feature-test  [feature-test]    󰆍
   ```
4. The  symbol indicates current worktree
5. The 󰆍 symbol indicates active tmux session

**Result:** ✓ / ✗

---

### Test 2: Switch Worktree

**Test:**
1. Open Neovim in the `main` worktree
2. Run `:WorktreeSwitch`
3. Select `feature-test` from the picker
4. Should:
   - Change directory to feature-test worktree
   - Switch to `bareme_nvim_feature-test` tmux session
   - Show notification: "Switched to worktree: /path/to/feature-test [feature-test]"

**Verify:**
```vim
:pwd  " Should show /Users/nerap/personal/bareme.nvim.git/feature-test
```

**Result:** ✓ / ✗

---

### Test 3: Create New Worktree

**Test:**
1. Run `:WorktreeCreate test-branch`
2. Should:
   - Create worktree at `/Users/nerap/personal/bareme.nvim.git/test-branch`
   - Prompt to switch to new worktree
   - If yes, create tmux session `bareme_nvim_test-branch`

**Verify:**
```bash
git -C /Users/nerap/personal/bareme.nvim.git worktree list
# Should show new test-branch worktree

tmux list-sessions | grep bareme
# Should show new bareme_nvim_test-branch session
```

**Result:** ✓ / ✗

---

### Test 4: Create Worktree from Existing Branch

**Setup:**
```bash
# Create a branch without worktree
git -C /Users/nerap/personal/bareme.nvim.git branch staging
```

**Test:**
1. Run `:WorktreeCreateFrom staging`
2. Should create worktree for existing `staging` branch

**Verify:**
```bash
git -C /Users/nerap/personal/bareme.nvim.git worktree list | grep staging
```

**Result:** ✓ / ✗

---

### Test 5: Delete Worktree

**Test:**
1. Run `:WorktreeDelete`
2. Select `test-branch` from picker
3. Confirm deletion
4. Should:
   - Delete the worktree
   - Kill the tmux session `bareme_nvim_test-branch`
   - Show notifications

**Verify:**
```bash
git -C /Users/nerap/personal/bareme.nvim.git worktree list
# Should NOT show test-branch

tmux list-sessions | grep bareme_nvim_test-branch
# Should return nothing
```

**Result:** ✓ / ✗

---

### Test 6: Session Status Indicators

**Test:**
1. Kill one tmux session: `tmux kill-session -t bareme_nvim_feature-test`
2. Run `:WorktreeList`
3. Should show:
   - `main` with 󰆍 (has session)
   - `feature-test` without 󰆍 (no session)

**Result:** ✓ / ✗

---

### Test 7: Telescope Preview

**Test:**
1. Run `:WorktreeSwitch`
2. Navigate through worktrees
3. Preview pane should show `ls -la` output of each worktree

**Test:**
1. Run `:WorktreeList`
2. Navigate through worktrees
3. Preview pane should show `git status` output

**Result:** ✓ / ✗

---

## Error Cases to Test

### E1: Not in a Git Repository

**Test:**
1. Navigate to a non-git directory: `:cd /tmp`
2. Run `:WorktreeCreate test`
3. Should show error: "Not in a git repository"

**Result:** ✓ / ✗

---

### E2: Invalid Branch Name

**Test:**
1. Run `:WorktreeCreate` with empty input
2. Should show error: "Branch name required"

**Result:** ✓ / ✗

---

### E3: Branch Already Exists

**Test:**
1. Run `:WorktreeCreate main`
2. Should show error from git about existing branch

**Result:** ✓ / ✗

---

## Manual Testing Checklist

- [ ] `:WorktreeList` shows all worktrees with correct status
- [ ] `:WorktreeSwitch` opens telescope picker and switches correctly
- [ ] `:WorktreeCreate` creates new worktree and tmux session
- [ ] `:WorktreeCreateFrom` creates worktree from existing branch
- [ ] `:WorktreeDelete` removes worktree and kills session
- [ ] Session naming follows convention: `<repo>_<branch>`
- [ ] Telescope previews work correctly
- [ ] Error messages are clear and helpful
- [ ] Confirmations work as expected
- [ ] Keybindings work if configured

## Integration Testing

### Test with tmux-sessionizer

**Test:**
1. Run tmux-sessionizer from outside tmux
2. Select a bareme worktree
3. Should create session with correct name
4. Run `:WorktreeList` inside Neovim
5. Should show 󰆍 next to the current worktree

---

## Performance Testing

**Test:**
1. Create 10+ worktrees
2. Run `:WorktreeSwitch`
3. Should load picker quickly
4. Navigation should be smooth

---

## Cleanup After Testing

```bash
# Remove test worktrees
git -C /Users/nerap/personal/bareme.nvim.git worktree remove test-branch --force
git -C /Users/nerap/personal/bareme.nvim.git worktree remove staging --force
git -C /Users/nerap/personal/bareme.nvim.git branch -D test-branch staging

# Kill test sessions
tmux kill-session -t bareme_nvim_test-branch 2>/dev/null
tmux kill-session -t bareme_nvim_staging 2>/dev/null
```
