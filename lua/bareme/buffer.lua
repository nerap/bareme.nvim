-- Buffer management utilities for worktrees
local M = {}

-- Close all buffers that are not in the current worktree
function M.cleanup_foreign_buffers()
  local cwd = vim.fn.getcwd()
  local buffers_to_delete = {}

  -- Find all buffers that are outside current worktree
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    -- Check all buffers, even if not loaded (catches hidden terminals)
    local bufname = vim.api.nvim_buf_get_name(bufnr)

    if bufname ~= "" then
      -- Check terminal buffers (lazygit, etc.)
      if bufname:match("^term://") then
        -- Close all terminal buffers - they're tied to specific worktrees
        -- This includes lazygit, shell terminals, etc.
        table.insert(buffers_to_delete, bufnr)
      elseif vim.api.nvim_buf_is_loaded(bufnr) then
        -- Regular file buffers - check if they're in current worktree
        local buf_path = vim.fn.fnamemodify(bufname, ":p")
        local cwd_normalized = vim.fn.fnamemodify(cwd, ":p")

        -- If buffer is not under current directory, mark for deletion
        if not buf_path:match("^" .. vim.pesc(cwd_normalized)) then
          table.insert(buffers_to_delete, bufnr)
        end
      end
    end
  end

  -- Delete foreign buffers
  local deleted_count = 0
  for _, bufnr in ipairs(buffers_to_delete) do
    local bufname = vim.api.nvim_buf_get_name(bufnr)

    -- Terminal buffers (lazygit, etc.) should always be force-wiped (wipeout removes from buffer list entirely)
    if bufname:match("^term://") then
      -- Use bwipeout instead of bdelete to completely remove terminal buffers
      if pcall(vim.cmd, string.format("bwipeout! %d", bufnr)) then
        deleted_count = deleted_count + 1
      end
    else
      -- Regular file buffers - only delete if not modified
      local is_modified = pcall(function()
        return vim.api.nvim_buf_get_option(bufnr, "modified")
      end) and vim.api.nvim_buf_get_option(bufnr, "modified")

      if not is_modified then
        if pcall(vim.api.nvim_buf_delete, bufnr, { force = true }) then
          deleted_count = deleted_count + 1
        end
      end
    end
  end

  return deleted_count
end

-- Get count of buffers from other worktrees
function M.count_foreign_buffers()
  local cwd = vim.fn.getcwd()
  local count = 0

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local bufname = vim.api.nvim_buf_get_name(bufnr)

      if bufname ~= "" and not bufname:match("^term://") then
        local buf_path = vim.fn.fnamemodify(bufname, ":p")
        local cwd_normalized = vim.fn.fnamemodify(cwd, ":p")

        if not buf_path:match("^" .. vim.pesc(cwd_normalized)) then
          count = count + 1
        end
      end
    end
  end

  return count
end

-- Open a sensible default file in the new worktree
function M.open_default_file()
  -- Try to open common entry points in order of preference
  local candidates = {
    "README.md",
    "init.lua",
    "main.lua",
    "src/main.lua",
    "lib/init.lua",
    "."
  }

  for _, file in ipairs(candidates) do
    local path = vim.fn.expand(file)
    if vim.fn.filereadable(path) == 1 or vim.fn.isdirectory(path) == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
      return true
    end
  end

  -- Fallback: open current directory
  vim.cmd("edit .")
  return false
end

return M
