-- Worktree visibility management (hide/show worktrees)
local M = {}

local logger = require("bareme.logger")

-- In-memory cache
local visibility_cache = nil

-- Get visibility state file path
local function get_visibility_file()
  local dir = vim.fn.expand("~/.local/state/bareme")
  vim.fn.mkdir(dir, "p")
  return dir .. "/visibility.json"
end

-- Load visibility state from disk
function M.load_visibility()
  -- Return cached if available
  if visibility_cache then
    return visibility_cache
  end

  local file_path = get_visibility_file()

  -- Check if file exists
  if vim.fn.filereadable(file_path) == 0 then
    -- Initialize with defaults
    visibility_cache = {
      ["*"] = {
        main = true, -- Hide "main" by default
      }
    }
    M.save_visibility(visibility_cache)
    return visibility_cache
  end

  -- Read and parse JSON
  local file = io.open(file_path, "r")
  if not file then
    logger.error("visibility", "Failed to open visibility file")
    visibility_cache = {}
    return visibility_cache
  end

  local content = file:read("*all")
  file:close()

  if content == "" then
    visibility_cache = {}
    return visibility_cache
  end

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok then
    logger.error("visibility", "Failed to parse visibility JSON: " .. tostring(data))
    visibility_cache = {}
    return visibility_cache
  end

  visibility_cache = data
  return visibility_cache
end

-- Save visibility state to disk
function M.save_visibility(state)
  local file_path = get_visibility_file()

  local ok, json = pcall(vim.fn.json_encode, state)
  if not ok then
    logger.error("visibility", "Failed to encode visibility JSON: " .. tostring(json))
    return false
  end

  local file = io.open(file_path, "w")
  if not file then
    logger.error("visibility", "Failed to open visibility file for writing")
    return false
  end

  file:write(json)
  file:close()

  -- Update cache
  visibility_cache = state
  logger.info("visibility", "Saved visibility state")
  return true
end

-- Get project name from bare repo path
local function get_project_name(bare_repo)
  if not bare_repo then
    return "*" -- Global fallback
  end
  return vim.fn.fnamemodify(bare_repo, ":t:r")
end

-- Check if worktree is hidden
function M.is_hidden(project_name, branch_name)
  local state = M.load_visibility()

  -- Check project-specific first
  if state[project_name] and state[project_name][branch_name] then
    return true
  end

  -- Check global defaults (*)
  if state["*"] and state["*"][branch_name] then
    return true
  end

  return false
end

-- Hide a worktree
function M.hide_worktree(project_name, branch_name)
  local state = M.load_visibility()

  -- Ensure project exists in state
  if not state[project_name] then
    state[project_name] = {}
  end

  -- Mark as hidden
  state[project_name][branch_name] = true

  -- Save to disk
  M.save_visibility(state)
  logger.info("visibility", string.format("Hidden worktree: %s/%s", project_name, branch_name))
end

-- Show a worktree (remove from hidden list)
function M.show_worktree(project_name, branch_name)
  local state = M.load_visibility()

  -- Remove from project-specific
  if state[project_name] then
    state[project_name][branch_name] = nil

    -- Clean up empty project
    if vim.tbl_isempty(state[project_name]) then
      state[project_name] = nil
    end
  end

  -- Remove from global defaults
  if state["*"] then
    state["*"][branch_name] = nil
  end

  -- Save to disk
  M.save_visibility(state)
  logger.info("visibility", string.format("Shown worktree: %s/%s", project_name, branch_name))
end

-- Toggle visibility of a worktree
function M.toggle_visibility(project_name, branch_name)
  if M.is_hidden(project_name, branch_name) then
    M.show_worktree(project_name, branch_name)
    return false -- Now visible
  else
    M.hide_worktree(project_name, branch_name)
    return true -- Now hidden
  end
end

-- Get all hidden worktrees for a project
function M.get_hidden_branches(project_name)
  local state = M.load_visibility()
  local hidden = {}

  -- Add project-specific hidden
  if state[project_name] then
    for branch, is_hidden in pairs(state[project_name]) do
      if is_hidden then
        table.insert(hidden, branch)
      end
    end
  end

  -- Add global defaults
  if state["*"] then
    for branch, is_hidden in pairs(state["*"]) do
      if is_hidden then
        table.insert(hidden, branch)
      end
    end
  end

  return hidden
end

-- Clear cache (useful for testing or manual refresh)
function M.clear_cache()
  visibility_cache = nil
end

-- Helper to get project name from bare repo
function M.get_project_name_from_repo(bare_repo)
  return get_project_name(bare_repo)
end

return M
