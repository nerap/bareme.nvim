-- Reusable UI components for bareme.nvim
local M = {}

-- Create a centered floating window
function M.create_float(opts)
  opts = opts or {}

  local width = opts.width or math.floor(vim.o.columns * 0.8)
  local height = opts.height or math.floor(vim.o.lines * 0.8)

  -- Calculate position
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", opts.filetype or "bareme")

  -- Window options
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = opts.border or "rounded",
    title = opts.title or "",
    title_pos = "center",
  }

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set window options
  vim.api.nvim_win_set_option(win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)

  return {
    buf = buf,
    win = win,
    width = width,
    height = height,
  }
end

-- Format time ago
function M.time_ago(timestamp)
  if not timestamp or timestamp == 0 then
    return "never"
  end

  local diff = os.time() - timestamp

  if diff < 60 then
    return string.format("%ds ago", diff)
  elseif diff < 3600 then
    return string.format("%dm ago", math.floor(diff / 60))
  elseif diff < 86400 then
    return string.format("%dh ago", math.floor(diff / 3600))
  else
    return string.format("%dd ago", math.floor(diff / 86400))
  end
end

-- Format bytes to human readable
function M.format_bytes(bytes)
  if bytes < 1024 then
    return string.format("%dB", bytes)
  elseif bytes < 1024 * 1024 then
    return string.format("%.1fKB", bytes / 1024)
  elseif bytes < 1024 * 1024 * 1024 then
    return string.format("%.1fMB", bytes / 1024 / 1024)
  else
    return string.format("%.1fGB", bytes / 1024 / 1024 / 1024)
  end
end

-- Pad string to width
function M.pad(str, width, align)
  align = align or "left"
  local len = vim.fn.strdisplaywidth(str)

  if len >= width then
    return str:sub(1, width)
  end

  local padding = string.rep(" ", width - len)

  if align == "right" then
    return padding .. str
  elseif align == "center" then
    local left_pad = math.floor((width - len) / 2)
    local right_pad = width - len - left_pad
    return string.rep(" ", left_pad) .. str .. string.rep(" ", right_pad)
  else
    return str .. padding
  end
end

-- Create a table
function M.create_table(headers, rows, opts)
  opts = opts or {}
  local col_widths = {}

  -- Calculate column widths
  for i, header in ipairs(headers) do
    col_widths[i] = vim.fn.strdisplaywidth(header)
  end

  for _, row in ipairs(rows) do
    for i, cell in ipairs(row) do
      local width = vim.fn.strdisplaywidth(tostring(cell))
      if width > col_widths[i] then
        col_widths[i] = width
      end
    end
  end

  -- Add padding
  for i = 1, #col_widths do
    col_widths[i] = col_widths[i] + 2
  end

  local lines = {}

  -- Header
  local header_line = "│"
  for i, header in ipairs(headers) do
    header_line = header_line .. " " .. M.pad(header, col_widths[i] - 2) .. " │"
  end
  table.insert(lines, header_line)

  -- Separator
  local sep = "├"
  for i = 1, #headers do
    sep = sep .. string.rep("─", col_widths[i]) .. "┼"
  end
  sep = sep:sub(1, -2) .. "┤"
  table.insert(lines, sep)

  -- Rows
  for _, row in ipairs(rows) do
    local row_line = "│"
    for i, cell in ipairs(row) do
      row_line = row_line .. " " .. M.pad(tostring(cell), col_widths[i] - 2) .. " │"
    end
    table.insert(lines, row_line)
  end

  return lines
end

-- Create a progress bar
function M.progress_bar(value, max, width)
  width = width or 20
  local filled = math.floor((value / max) * width)
  local empty = width - filled

  return string.format("[%s%s] %d/%d", string.rep("█", filled), string.rep("░", empty), value, max)
end

-- Create a box around text
function M.box(lines, title)
  local width = 0
  for _, line in ipairs(lines) do
    local len = vim.fn.strdisplaywidth(line)
    if len > width then
      width = len
    end
  end

  local result = {}

  -- Top border
  if title then
    local title_line = "┌─ " .. title .. " "
    local remaining = width - vim.fn.strdisplaywidth(title) - 3
    title_line = title_line .. string.rep("─", math.max(0, remaining)) .. "┐"
    table.insert(result, title_line)
  else
    table.insert(result, "┌" .. string.rep("─", width + 2) .. "┐")
  end

  -- Content
  for _, line in ipairs(lines) do
    table.insert(result, "│ " .. M.pad(line, width) .. " │")
  end

  -- Bottom border
  table.insert(result, "└" .. string.rep("─", width + 2) .. "┘")

  return result
end

-- Status icons
M.icons = {
  success = "✓",
  error = "✗",
  warning = "⚠",
  info = "ℹ",
  loading = "◴",
  active = "●",
  inactive = "○",
  claude_active = "🟢",
  claude_idle = "💤",
  claude_needs_input = "🔔",
  claude_paused = "⏸",
  docker = "🐳",
  port = "🔌",
  worktree = "🌳",
  trash = "🗑",
}

return M
