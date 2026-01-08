-- Card component for worktree visualization
local M = {}

local components = require("bareme.ui.components")

-- Card state icons
local ICONS = {
  active = "🟢",
  needs_input = "🔔",
  idle = "💤",
  no_claude = "⚙",
  docker_running = "✓",
  docker_stopped = "✗",
  docker_partial = "💤",
}

-- Determine card state based on worktree data
local function calculate_card_state(wt_data)
  local claude_status = wt_data.claude_status

  if claude_status and claude_status.status == "needs_input" then
    return "needs_input", ICONS.needs_input
  elseif claude_status and claude_status.status == "active" then
    return "active", ICONS.active
  elseif claude_status and (claude_status.status == "paused" or claude_status.status == "idle") then
    return "idle", ICONS.idle
  else
    return "no_claude", ICONS.no_claude
  end
end

-- Format Claude status section
local function format_claude_section(claude_status)
  if not claude_status then
    return { "Claude: Not detected" }
  end

  local lines = {}
  local status_text = "Unknown"

  if claude_status.status == "active" then
    status_text = "Active"
  elseif claude_status.status == "needs_input" then
    status_text = "Needs Input ⚠"
  elseif claude_status.status == "paused" then
    status_text = "Paused"
  elseif claude_status.status == "idle" then
    status_text = "Idle"
  end

  table.insert(lines, "Claude: " .. status_text)

  -- Add message count if available
  if claude_status.message_count and claude_status.message_count > 0 then
    local age_str = "now"
    if claude_status.last_activity and claude_status.last_activity > 0 then
      local age_min = math.floor((os.time() - claude_status.last_activity) / 60)
      if age_min < 1 then
        age_str = "now"
      elseif age_min < 60 then
        age_str = string.format("%dm ago", age_min)
      else
        age_str = string.format("%dh ago", math.floor(age_min / 60))
      end
    end
    table.insert(lines, string.format("Messages: %d (%s)", claude_status.message_count, age_str))
  elseif claude_status.detected == "process" then
    table.insert(lines, "Status: Running")
  elseif claude_status.last_activity and claude_status.last_activity > 0 then
    local age_str = components.time_ago(claude_status.last_activity)
    table.insert(lines, "Last: " .. age_str)
  end

  return lines
end

-- Format ports section
local function format_ports_section(ports, max_display)
  max_display = max_display or 3

  if not ports or vim.tbl_isempty(ports) then
    return { "Ports: None" }
  end

  local lines = { "Ports:" }
  local count = 0

  for service, port in pairs(ports) do
    if count >= max_display then
      local remaining = vim.tbl_count(ports) - max_display
      table.insert(lines, string.format("  ... +%d more", remaining))
      break
    end
    table.insert(lines, string.format("  • %s:%d", service, port))
    count = count + 1
  end

  return lines
end

-- Format Docker section
local function format_docker_section(docker_info)
  if not docker_info or not docker_info.available then
    return { "Docker: Not available" }
  end

  local running = 0
  local total = 0

  if docker_info.containers then
    for _, container in ipairs(docker_info.containers) do
      total = total + 1
      if container.is_running then
        running = running + 1
      end
    end
  end

  local icon = ICONS.docker_stopped
  if running == total and total > 0 then
    icon = ICONS.docker_running
  elseif running > 0 then
    icon = ICONS.docker_partial
  end

  return { string.format("Docker: %s %d/%d running", icon, running, total) }
end

-- Format footer with size and activity
local function format_footer(wt_data)
  local activity_str = "unknown"
  if wt_data.last_activity and wt_data.last_activity > 0 then
    activity_str = components.time_ago(wt_data.last_activity)
  end

  -- Don't show size (too slow to calculate)
  return string.format("Last activity: %s", activity_str)
end

-- Render a single card
-- Returns: { lines = {...}, width = N, height = N }
function M.render_card(wt_data, card_width, is_selected, is_current)
  card_width = card_width or 31
  local card_height = 12 -- Fixed height for all cards
  local state, icon = calculate_card_state(wt_data)

  local lines = {}
  local border_char = is_selected and "═" or "─"
  local corner_tl = is_selected and "╔" or "┌"
  local corner_tr = is_selected and "╗" or "┐"
  local corner_bl = is_selected and "╚" or "└"
  local corner_br = is_selected and "╝" or "┘"
  local vertical = is_selected and "║" or "│"

  -- Top border (line 1)
  table.insert(lines, corner_tl .. string.rep(border_char, card_width - 2) .. corner_tr)

  -- Header: icon + branch name (line 2)
  local header = string.format("%s %s", icon, wt_data.branch)
  if is_current then
    header = header .. " [current]"
  end
  local header_line = vertical ..
      " " .. header .. string.rep(" ", card_width - 4 - vim.fn.strwidth(header)) .. " " .. vertical
  table.insert(lines, header_line)

  -- Empty line (line 3)
  table.insert(lines, vertical .. string.rep(" ", card_width - 2) .. vertical)

  -- Claude section (lines 4-5 or 4-6, always take exactly 3 lines)
  local claude_lines = format_claude_section(wt_data.claude_status)
  for i = 1, 3 do
    local line = claude_lines[i] or ""
    local padded = line .. string.rep(" ", card_width - 4 - vim.fn.strwidth(line))
    table.insert(lines, vertical .. " " .. padded .. " " .. vertical)
  end

  -- Empty line (line 7)
  table.insert(lines, vertical .. string.rep(" ", card_width - 2) .. vertical)

  -- Footer (line 8)
  local footer = format_footer(wt_data)
  local footer_padded = footer .. string.rep(" ", card_width - 4 - vim.fn.strwidth(footer))
  table.insert(lines, vertical .. " " .. footer_padded .. " " .. vertical)

  -- Empty line (line 9)
  table.insert(lines, vertical .. string.rep(" ", card_width - 2) .. vertical)

  -- Fill remaining lines to reach card_height - 1 (for bottom border)
  while #lines < card_height - 1 do
    table.insert(lines, vertical .. string.rep(" ", card_width - 2) .. vertical)
  end

  -- Bottom border (line 12)
  table.insert(lines, corner_bl .. string.rep(border_char, card_width - 2) .. corner_br)

  -- Ensure all lines have consistent display width (fix emoji padding issues)
  for i, line in ipairs(lines) do
    local actual_width = vim.fn.strwidth(line)
    if actual_width < card_width then
      -- Pad to correct width
      lines[i] = line .. string.rep(" ", card_width - actual_width)
    elseif actual_width > card_width then
      -- Truncate if too long (shouldn't happen but safety check)
      lines[i] = line:sub(1, card_width)
    end
  end

  return {
    lines = lines,
    width = card_width,
    height = card_height,
    branch = wt_data.branch,
    state = state,
  }
end

return M
