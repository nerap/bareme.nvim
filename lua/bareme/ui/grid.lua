-- Grid layout system for card-based dashboard
local M = {}

-- Calculate number of columns based on terminal width and card width
function M.calculate_columns(term_width, card_width)
  -- Always display 3 cards per row
  return 3
end

-- Combine two lines horizontally with spacing
local function combine_horizontal(line1, line2, spacing)
  spacing = spacing or 2
  return line1 .. string.rep(" ", spacing) .. line2
end

-- Layout cards in a grid
-- Returns array of rendered lines
function M.layout_cards(cards, columns)
  if #cards == 0 then
    return { "No worktrees to display" }
  end

  columns = columns or 2
  local output = {}
  local row_start = 1

  while row_start <= #cards do
    -- Get cards for this row
    local row_cards = {}
    for i = 0, columns - 1 do
      local idx = row_start + i
      if idx <= #cards then
        table.insert(row_cards, cards[idx])
      end
    end

    -- All cards have fixed height, so just use the first card's height
    local card_height = row_cards[1].height

    -- Combine cards horizontally line by line
    for line_idx = 1, card_height do
      local combined_line = ""

      for card_idx, card in ipairs(row_cards) do
        if card_idx == 1 then
          combined_line = card.lines[line_idx]
        else
          combined_line = combine_horizontal(combined_line, card.lines[line_idx], 2)
        end
      end

      table.insert(output, combined_line)
    end

    -- Add spacing between rows
    if row_start + columns <= #cards then
      table.insert(output, "")
    end

    row_start = row_start + columns
  end

  return output
end

-- Navigate grid with hjkl
-- Returns new selected index
function M.navigate(current_idx, direction, total_cards, columns)
  local row = math.floor((current_idx - 1) / columns)
  local col = (current_idx - 1) % columns
  local total_rows = math.ceil(total_cards / columns)

  if direction == "h" then
    -- Move left
    if col > 0 then
      return current_idx - 1
    end
  elseif direction == "l" then
    -- Move right
    if col < columns - 1 and current_idx < total_cards then
      return current_idx + 1
    end
  elseif direction == "k" then
    -- Move up
    if row > 0 then
      local new_idx = current_idx - columns
      if new_idx >= 1 then
        return new_idx
      end
    end
  elseif direction == "j" then
    -- Move down
    if row < total_rows - 1 then
      local new_idx = current_idx + columns
      if new_idx <= total_cards then
        return new_idx
      end
    end
  end

  return current_idx
end

-- Convert flat index to (row, col) position
function M.index_to_position(idx, columns)
  local row = math.floor((idx - 1) / columns)
  local col = (idx - 1) % columns
  return row, col
end

-- Convert (row, col) position to flat index
function M.position_to_index(row, col, columns)
  return row * columns + col + 1
end

return M
