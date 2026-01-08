# Bareme Observability System

Complete monitoring, logging, and debugging system for bareme.nvim.

## Overview

The observability system provides real-time insights into your worktree workflow, including:
- Port allocations and conflicts
- Docker container status
- Claude Code session activity
- Worktree health and performance
- Event history and debugging

---

## Commands

### Health & Monitoring

```vim
:checkhealth bareme          " Comprehensive health check (Neovim native)
:WorktreeHealth             " Quick health summary
:BaremeMonitor              " Real-time dashboard (auto-refresh every 5s)
```

### Event Logging

```vim
:BaremeLog [lines]          " View event log (default: 100 lines)
:ClaudeStats                " View Claude Code session statistics
```

### Maintenance

```vim
:ClaudeInstallHooks         " Install Claude hooks in existing worktrees
:BaremeCleanupPorts         " Clean up orphaned port allocations
```

### Existing Commands

All existing worktree commands now include full logging and event tracking:
- `:WorktreeCreate`, `:WorktreeDelete`, `:WorktreeSwitch`
- `:WorktreePorts`, `:WorktreeDockerStatus`, etc.

---

## Real-Time Monitor Dashboard

**Command**: `:BaremeMonitor`

### Features:
- **Auto-refresh** every 5 seconds
- **Live stats** for worktrees, ports, Docker, Claude
- **Health indicators** showing issues/warnings
- **Recent events** timeline
- **Interactive** keybindings

### Keybindings:
```
r - Manual refresh
h - Open full health check (:checkhealth bareme)
q - Quit
<Esc> - Quit
? - Show help
```

### What It Shows:

```
┌─ Bareme Monitor ────────────────────────────────────────┐
│                   Bareme Monitor                        │
│               Auto-refresh: 5s                          │
│                                                         │
│ 📊 Overview                                             │
│   Status: ✓ Healthy                                    │
│   Worktrees: 5                                         │
│   Ports: 15 allocated                                  │
│   Docker: 10/12 running                                │
│   Trash: 2 (1.2GB)                                     │
│                                                         │
│ 🌳 Worktrees                                            │
│   │    │ Branch      │ Size │ Activity   │            │
│   ├────┼─────────────┼──────┼────────────┤            │
│   │ 🟢 │ main        │ 45MB │ 5m ago     │            │
│   │ 🔔 │ feature-a   │ 52MB │ 2h ago     │            │
│   │ 💤 │ feature-b   │ 48MB │ 1d ago     │            │
│                                                         │
│ 🔔 Claude Notifications                                 │
│   [feature-a] needs input (2h ago)                     │
│                                                         │
│ 🔌 Port Status                                          │
│   APP: 5 port(s)                                       │
│   DB: 5 port(s)                                        │
│   REDIS: 3 port(s)                                     │
│                                                         │
│ 📋 Recent Events                                        │
│   [20:15:32] WORKTREE SWITCHED [main]                  │
│   [20:14:10] DOCKER STARTED [feature-a] (3.2s)         │
│   [20:13:45] PORT ALLOCATED app:3001 for feature-a     │
│                                                         │
│          Press [r]efresh [h]ealth [q]uit               │
└─────────────────────────────────────────────────────────┘
```

---

## Health Checks

**Command**: `:checkhealth bareme`

### What's Checked:

#### 1. **Port Allocations**
- Conflicts (port allocated but in use by another process)
- Orphaned ports (allocated but worktree deleted)
- Service usage statistics

#### 2. **Docker**
- Daemon availability
- Container status (running/stopped)
- Orphaned containers (worktree deleted but container remains)
- Resource usage warnings (CPU/memory)

#### 3. **Worktrees**
- Total count and disk usage
- Broken `.git` references
- Last activity per worktree

#### 4. **Environment Configuration**
- `.env.template` existence
- Missing `.env` files in worktrees
- Undefined variables

#### 5. **Trash**
- Size and item count
- Old items approaching auto-purge (30 days)

#### 6. **Logging**
- Log file size
- Rotation status

#### 7. **Claude Code Integration**
- Active sessions
- Sessions needing input
- Hook installation status

### Example Output:

```
bareme: require("bareme.health").check()

Worktrees ~
• OK Total worktrees: 5
• OK Disk usage: 245 MB
• OK All worktrees have valid .git references

Port Allocations ~
• OK Total ports allocated: 15
• OK No port conflicts
• OK No orphaned ports
• INFO  APP: 5 port(s) allocated
• INFO  DB: 5 port(s) allocated

Docker ~
• OK Docker available
• INFO Containers: 10 running, 2 stopped
• OK No orphaned containers

Claude Code Integration ~
• OK Claude sessions: 3 active
• WARNING 1 session(s) need input
  - Check with :ClaudeStats
```

---

## Event Logging

### Viewing Logs

**Command**: `:BaremeLog [lines]`

Shows recent events in a new buffer. Default: 50 lines.

### Event Types Tracked:

- `WORKTREE_CREATED` - New worktree created
- `WORKTREE_DELETED` - Worktree moved to trash
- `WORKTREE_SWITCHED` - Switched to different worktree
- `WORKTREE_RECOVERED` - Recovered from trash
- `PORT_ALLOCATED` - Port assigned to service
- `PORT_RELEASED` - Port freed
- `PORT_CONFLICT` - Port conflict detected
- `DOCKER_STARTED` - Docker services started
- `DOCKER_STOPPED` - Docker services stopped
- `DOCKER_FAILED` - Docker failed to start
- `ENV_GENERATED` - `.env` file generated
- `CLAUDE_MESSAGE` - Claude message sent/received
- `CLAUDE_NEEDS_INPUT` - Claude waiting for input
- `BUFFER_CLEANUP` - Buffers cleaned on switch

### Event Format:

```
[timestamp] EVENT_TYPE [worktree] details
```

### Example Log:

```
Recent Events (last 50):

[20:15:32] WORKTREE SWITCHED [main]
[20:14:10] DOCKER STARTED [feature-a] (3.2s)
[20:13:45] PORT ALLOCATED [feature-a] app:3001
[20:13:45] PORT ALLOCATED [feature-a] db:5433
[20:13:44] WORKTREE CREATED [feature-a]
[20:10:22] CLAUDE NEEDS INPUT [main]
[20:05:18] BUFFER CLEANUP [feature-b] (12 buffers)
```

### Log Files

Events are stored in two locations:

1. **Events** (JSONL): `~/.local/state/bareme/events.jsonl`
   - Structured event data
   - Machine-readable format
   - Used by monitor dashboard

2. **Logs** (Text): `~/.local/state/bareme/bareme.log`
   - Human-readable format
   - Includes DEBUG/INFO/WARN/ERROR levels
   - Auto-rotates at 10MB (keeps 5 backups)

---

## Claude Code Integration

### Session Detection

Bareme detects Claude Code sessions in **two ways**:

1. **Process Detection** (automatic) - Scans for running `claude` processes and matches them to worktrees
2. **Hook Events** (optional) - Provides detailed message counts and timing via hooks

### Automatic Hook Installation

Claude Code hooks are **automatically installed** when you create a worktree.

For **existing worktrees**, run: `:ClaudeInstallHooks`

Hooks are created at: `.claude/hooks/` in each worktree

### What Hooks Do:

1. **`on-message.sh`** - Tracks Claude messages
2. **`on-await-input.sh`** - Notifies when Claude needs input

### Event Flow:

```
Claude needs input
    ↓
Hook writes to: ~/.local/state/bareme/claude_events.jsonl
    ↓
File watcher detects change
    ↓
Bareme emits CLAUDE_NEEDS_INPUT event
    ↓
Shows notification: "[feature-a] Claude needs input"
    ↓
Appears in :BaremeMonitor and :ClaudeStats
```

### Viewing Claude Stats

**Command**: `:ClaudeStats`

Shows:
- Active sessions
- Sessions needing input
- Message counts
- Last activity

### Example Output:

```
Claude Code Sessions

🔔 1 session(s) need input:
  [feature-a] 2h ago

Sessions:
  🟢 [main] 23 messages, 5m ago
  🔔 [feature-a] 45 messages, 2h ago
  ⏸ [feature-b] 12 messages, 1d ago
```

---

## Statusline Integration

Show Claude notifications in your statusline!

### For Lualine:

```lua
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
```

### For Custom Statusline:

```lua
function MyStatusline()
  local bareme = require('bareme.statusline')
  local claude = bareme.get_claude_statusline()

  if claude ~= '' then
    return '%f ' .. claude .. ' %= %l:%c'
  else
    return '%f %= %l:%c'
  end
end

vim.o.statusline = '%!v:lua.MyStatusline()'
```

### Available Functions:

```lua
local statusline = require('bareme.statusline')

statusline.get_current_branch()       -- Current worktree branch
statusline.get_claude_status()        -- Claude status object
statusline.get_claude_icon()          -- Icon (🔔/🟢/⏸)
statusline.get_claude_statusline()    -- Formatted string
statusline.has_notifications()        -- Boolean
statusline.get_notification_count()   -- Number
statusline.get_notifications_statusline()  -- "🔔 N notifications"
```

---

## Performance Metrics

All operations are timed and logged:

- **Worktree creation**: Total time from start to finish
- **Docker startup**: Time to start all services
- **Worktree switching**: Buffer cleanup + directory change time
- **Port allocation**: Time to find and allocate ports

View metrics in logs:
```
[INFO] [docker] Services started in 3.24s
[INFO] [ports] Allocated 5 port(s) in 0.15s
```

---

## Troubleshooting

### Common Issues:

#### "No Claude sessions showing" or "No Claude events detected"
- **Process detection works automatically** - no hooks required!
- If you see Claude running but it's not detected, reload Neovim
- For **detailed stats** (message counts), install hooks: `:ClaudeInstallHooks`
- Check hook installation: `ls .claude/hooks/` in worktree

#### "Port conflict detected" or "Orphaned port allocations"
- **Clean up orphaned ports**: `:BaremeCleanupPorts`
- Check which process is using the port:
  ```bash
  lsof -i :PORT_NUMBER
  ```
- Manually release a specific port:
  `:lua require('bareme.ports').release_ports('project', 'branch')`

#### "Docker services failed to start"
- Check logs: `:WorktreeDockerLogs`
- Verify ports are available
- Check `:BaremeLog` for error details

#### "Monitor not refreshing"
- Press `r` to manually refresh
- Check if timer is still running (should auto-refresh every 5s)
- Close and reopen: `:BaremeMonitor`

### Debug Mode:

Enable debug logging:

```lua
require('bareme.logger').setup({
  level = require('bareme.logger').LEVELS.DEBUG
})
```

Then check: `~/.local/state/bareme/bareme.log`

---

## API

### For Plugin Developers:

```lua
local events = require('bareme.events')
local logger = require('bareme.logger')
local health = require('bareme.health')

-- Subscribe to events
events.on(events.TYPES.WORKTREE_SWITCHED, function(event)
  print("Switched to:", event.data.worktree)
end)

-- Emit custom events
events.emit(events.TYPES.CLAUDE_MESSAGE, {
  worktree = "main",
  type = "assistant",
  count = 5,
})

-- Log messages
logger.info("mymodule", "Operation completed", { duration = 1.5 })
logger.warn("mymodule", "Resource usage high")
logger.error("mymodule", "Operation failed", { error = "timeout" })

-- Get health summary
local summary = health.get_summary()
if not summary.healthy then
  print("Issues:", table.concat(summary.issues, ", "))
end
```

---

## Configuration

### Log Level:

```lua
require('bareme').setup({
  log_level = 'INFO',  -- DEBUG, INFO, WARN, ERROR
})
```

### Monitor Refresh Rate:

Edit `lua/bareme/ui/monitor.lua`:
```lua
refresh_interval = 3000,  -- 3 seconds instead of 5
```

### Auto-install Claude Hooks:

Enabled by default. To disable, comment out in `lua/bareme/init.lua`:
```lua
-- claude_monitor.install_hooks(worktree_path, branch_name)
```

---

## Summary

**✅ Available Now:**
- `:checkhealth bareme` - Comprehensive health checks
- `:WorktreeHealth` - Quick summary
- `:BaremeMonitor` - Real-time dashboard (auto-refreshing)
- `:BaremeLog [lines]` - Event history
- `:ClaudeStats` - Claude session tracking
- `:ClaudeInstallHooks` - Install hooks in existing worktrees
- `:BaremeCleanupPorts` - Clean orphaned port allocations
- Automatic logging of all operations
- Claude hook auto-installation
- **Automatic Claude process detection** (no hooks required!)
- Statusline integration

**🎯 What You Get:**
- Full visibility into port allocations
- Real-time Docker monitoring
- **Automatic Claude Code session detection**
- Optional detailed tracking via hooks
- Performance metrics
- Debug capabilities
- Event history
- Easy maintenance commands

Enjoy your supercharged observability! 🚀
