-- Trash/recovery system for worktrees (soft delete)
local M = {}

local git = require("bareme.git")
local tmux = require("bareme.tmux")

-- Get trash directory path
local function get_trash_dir()
  local home = os.getenv("HOME")
  return home .. "/.local/share/bareme/trash"
end

-- Ensure trash directory exists
local function ensure_trash_dir()
  local trash_dir = get_trash_dir()
  vim.fn.mkdir(trash_dir, "p")
  return trash_dir
end

-- Generate trash folder name
local function get_trash_folder_name(branch_name)
  local timestamp = os.date("%Y%m%d_%H%M%S")
  local safe_branch = branch_name:gsub("[^%w-]", "_")
  return string.format("%s_%s", safe_branch, timestamp)
end

-- Save metadata for recovery
local function save_metadata(trash_path, metadata)
  local meta_file = trash_path .. "/bareme_metadata.json"
  local content = vim.fn.json_encode(metadata)

  local file = io.open(meta_file, "w")
  if file then
    file:write(content)
    file:close()
    return true
  end
  return false
end

-- Load metadata from trash
local function load_metadata(trash_path)
  local meta_file = trash_path .. "/bareme_metadata.json"
  local file = io.open(meta_file, "r")
  if not file then
    return nil
  end

  local content = file:read("*all")
  file:close()

  local ok, metadata = pcall(vim.fn.json_decode, content)
  if ok then
    return metadata
  end
  return nil
end

-- Get size of directory in MB
local function get_dir_size(path)
  local output = vim.fn.system(string.format("du -sm '%s' 2>/dev/null | cut -f1", path))
  return tonumber(vim.trim(output)) or 0
end

-- List all trashed worktrees
function M.list_trashed()
  local trash_dir = get_trash_dir()
  if vim.fn.isdirectory(trash_dir) == 0 then
    return {}
  end

  local entries = vim.fn.readdir(trash_dir)
  local trashed = {}

  for _, entry in ipairs(entries) do
    local trash_path = trash_dir .. "/" .. entry
    if vim.fn.isdirectory(trash_path) == 1 then
      local metadata = load_metadata(trash_path)
      if metadata then
        metadata.trash_path = trash_path
        metadata.trash_name = entry
        metadata.size_mb = get_dir_size(trash_path)
        table.insert(trashed, metadata)
      end
    end
  end

  -- Sort by deletion time (newest first)
  table.sort(trashed, function(a, b)
    return a.deleted_at > b.deleted_at
  end)

  return trashed
end

-- Soft delete a worktree (move to trash)
function M.soft_delete(worktree_path, branch_name, skip_confirm)
  -- Safety checks
  local cwd = vim.fn.getcwd()
  if worktree_path == cwd then
    return false, "Cannot delete currently active worktree. Switch to another worktree first."
  end

  -- Prevent deleting main/master without explicit confirmation
  if (branch_name == "main" or branch_name == "master") and not skip_confirm then
    local choice = vim.fn.confirm(
      string.format("Delete base branch '%s'? This is usually not recommended.", branch_name),
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return false, "Deletion cancelled"
    end
  end

  -- Get worktree info for preview
  local last_commit = vim.fn.system(string.format(
    "git -C '%s' log -1 --format='%%h %%s' 2>/dev/null",
    worktree_path
  ))
  last_commit = vim.trim(last_commit)

  local files_count = vim.fn.system(string.format(
    "find '%s' -type f | wc -l",
    worktree_path
  ))
  files_count = vim.trim(files_count)

  -- Show confirmation with preview
  if not skip_confirm then
    local msg = string.format(
      "Delete worktree?\n\nBranch: %s\nPath: %s\nLast commit: %s\nFiles: %s\n\nThis will move to trash (recoverable for 30 days)",
      branch_name,
      worktree_path,
      last_commit,
      files_count
    )

    local choice = vim.fn.confirm(msg, "&Delete\n&Cancel", 2)
    if choice ~= 1 then
      return false, "Deletion cancelled"
    end
  end

  -- Ensure trash directory exists
  local trash_dir = ensure_trash_dir()
  local trash_folder = get_trash_folder_name(branch_name)
  local trash_path = trash_dir .. "/" .. trash_folder

  -- Create metadata
  local bare_repo = git.get_bare_repo_path()
  local metadata = {
    original_path = worktree_path,
    branch_name = branch_name,
    bare_repo = bare_repo,
    deleted_at = os.time(),
    last_commit = last_commit,
    files_count = tonumber(files_count) or 0,
  }

  -- Kill tmux session if it exists
  local session_name = tmux.get_session_name_for_path(worktree_path, branch_name)
  if tmux.session_exists(session_name) then
    tmux.kill_session(session_name)
  end

  -- Move worktree to trash
  local move_cmd = string.format("mv '%s' '%s' 2>&1", worktree_path, trash_path)
  local output = vim.fn.system(move_cmd)
  if vim.v.shell_error ~= 0 then
    return false, "Failed to move to trash: " .. output
  end

  -- Save metadata
  if not save_metadata(trash_path, metadata) then
    return false, "Failed to save metadata"
  end

  -- Remove from git worktree list
  local prune_cmd = string.format("git -C '%s' worktree prune 2>&1", bare_repo)
  vim.fn.system(prune_cmd)

  return true, string.format("Moved to trash: %s (recoverable)", branch_name)
end

-- Recover a worktree from trash
function M.recover(trash_path)
  local metadata = load_metadata(trash_path)
  if not metadata then
    return false, "Invalid trash entry (missing metadata)"
  end

  local original_path = metadata.original_path
  local branch_name = metadata.branch_name
  local bare_repo = metadata.bare_repo

  -- Check if original path already exists
  if vim.fn.isdirectory(original_path) == 1 then
    return false, string.format("Path already exists: %s", original_path)
  end

  -- Move back to original location
  local move_cmd = string.format("mv '%s' '%s' 2>&1", trash_path, original_path)
  local output = vim.fn.system(move_cmd)
  if vim.v.shell_error ~= 0 then
    return false, "Failed to recover: " .. output
  end

  -- Find the gitdir name in the bare repo's worktrees folder
  -- Git uses branch name (sanitized) as the gitdir name, not the folder name
  local gitdir = nil
  local worktrees_dir = bare_repo .. "/worktrees"

  -- Check if worktree gitdir already exists for this branch
  local branch_gitdir = worktrees_dir .. "/" .. branch_name
  if vim.fn.isdirectory(branch_gitdir) == 1 then
    gitdir = branch_gitdir
  else
    -- Try sanitized branch name (slashes become dashes, etc.)
    local sanitized = branch_name:gsub("/", "-"):gsub("[^%w%-_]", "_")
    local sanitized_gitdir = worktrees_dir .. "/" .. sanitized
    if vim.fn.isdirectory(sanitized_gitdir) == 1 then
      gitdir = sanitized_gitdir
    else
      -- List all gitdirs and try to find the right one by reading the gitdir file
      local entries = vim.fn.readdir(worktrees_dir)
      for _, entry in ipairs(entries) do
        local gitdir_file = worktrees_dir .. "/" .. entry .. "/gitdir"
        if vim.fn.filereadable(gitdir_file) == 1 then
          local f = io.open(gitdir_file, "r")
          if f then
            local content = f:read("*all")
            f:close()
            -- Check if this gitdir points to our original path
            if content:match(vim.pesc(original_path)) then
              gitdir = worktrees_dir .. "/" .. entry
              break
            end
          end
        end
      end
    end
  end

  -- If no gitdir found, recreate the worktree using git
  if not gitdir then
    -- Remove the recovered directory
    vim.fn.system(string.format("rm -rf '%s'", original_path))

    -- Recreate worktree using git
    local create_cmd = string.format("git -C '%s' worktree add '%s' '%s' 2>&1", bare_repo, original_path, branch_name)
    output = vim.fn.system(create_cmd)
    if vim.v.shell_error ~= 0 then
      return false, "Failed to recreate worktree: " .. output
    end

    return true, string.format("Recovered by recreating: [%s] to %s", branch_name, original_path)
  end

  -- Update the .git file to point to the correct gitdir
  local git_file = original_path .. "/.git"
  local file = io.open(git_file, "w")
  if not file then
    -- Rollback: move back to trash
    vim.fn.system(string.format("mv '%s' '%s'", original_path, trash_path))
    return false, "Failed to update .git file"
  end
  file:write(string.format("gitdir: %s\n", gitdir))
  file:close()

  -- Update the gitdir/gitdir file to point back to the worktree
  local gitdir_file = gitdir .. "/gitdir"
  file = io.open(gitdir_file, "w")
  if file then
    file:write(original_path .. "/.git\n")
    file:close()
  end

  -- Run git worktree repair to ensure everything is synchronized
  local repair_cmd = string.format("git -C '%s' worktree repair 2>&1", bare_repo)
  output = vim.fn.system(repair_cmd)
  -- Don't fail if repair has warnings, as long as the .git file is correct

  return true, string.format("Recovered: [%s] to %s", branch_name, original_path)
end

-- Permanently delete from trash
function M.permanent_delete(trash_path)
  local metadata = load_metadata(trash_path)
  if not metadata then
    return false, "Invalid trash entry"
  end

  local choice = vim.fn.confirm(
    string.format("PERMANENTLY delete '%s'?\nThis cannot be undone!", metadata.branch_name),
    "&Delete Forever\n&Cancel",
    2
  )

  if choice ~= 1 then
    return false, "Cancelled"
  end

  -- Permanently delete
  local rm_cmd = string.format("rm -rf '%s' 2>&1", trash_path)
  local output = vim.fn.system(rm_cmd)
  if vim.v.shell_error ~= 0 then
    return false, "Failed to delete: " .. output
  end

  return true, "Permanently deleted"
end

-- Empty entire trash
function M.empty_trash(skip_confirm)
  local trashed = M.list_trashed()
  if #trashed == 0 then
    return false, "Trash is already empty"
  end

  if not skip_confirm then
    local choice = vim.fn.confirm(
      string.format("PERMANENTLY delete ALL %d trashed worktree(s)?\nThis cannot be undone!", #trashed),
      "&Delete All\n&Cancel",
      2
    )

    if choice ~= 1 then
      return false, "Cancelled"
    end
  end

  local trash_dir = get_trash_dir()
  local rm_cmd = string.format("rm -rf '%s'/* 2>&1", trash_dir)
  local output = vim.fn.system(rm_cmd)
  if vim.v.shell_error ~= 0 then
    return false, "Failed to empty trash: " .. output
  end

  return true, string.format("Emptied trash (%d worktree(s) deleted)", #trashed)
end

-- Auto-purge old trash (older than days)
function M.auto_purge(days)
  days = days or 30
  local threshold = os.time() - (days * 24 * 60 * 60)
  local trashed = M.list_trashed()
  local purged_count = 0

  for _, entry in ipairs(trashed) do
    if entry.deleted_at < threshold then
      local rm_cmd = string.format("rm -rf '%s' 2>&1", entry.trash_path)
      local output = vim.fn.system(rm_cmd)
      if vim.v.shell_error == 0 then
        purged_count = purged_count + 1
      end
    end
  end

  if purged_count > 0 then
    return true, string.format("Auto-purged %d old worktree(s)", purged_count)
  end

  return true, "No old worktrees to purge"
end

-- Get trash status (count and size)
function M.get_status()
  local trashed = M.list_trashed()
  local total_size = 0

  for _, entry in ipairs(trashed) do
    total_size = total_size + entry.size_mb
  end

  return {
    count = #trashed,
    size_mb = total_size,
    entries = trashed,
  }
end

return M
