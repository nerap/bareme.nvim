-- Git worktree utilities
local M = {}

-- Check if current directory is inside a git repository
function M.is_git_repo()
  local result = vim.fn.system("git rev-parse --is-inside-work-tree 2>/dev/null")
  return vim.v.shell_error == 0
end

-- Check if directory is a bare git repository
function M.is_bare_repo(path)
  path = path or vim.fn.getcwd()
  local result = vim.fn.system(string.format("git -C '%s' rev-parse --is-bare-repository 2>/dev/null", path))
  return vim.trim(result) == "true"
end

-- Get the git root directory
function M.get_git_root()
  local result = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

-- Get the bare repository path (if we're in a worktree)
function M.get_bare_repo_path()
  local git_dir = vim.fn.system("git rev-parse --git-common-dir 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  git_dir = vim.trim(git_dir)

  -- If git-common-dir points to a .git directory inside a bare repo
  -- we need to get its parent
  if git_dir:match("%.git$") then
    return git_dir
  end

  -- Check if the parent of git_dir is a bare repo
  local parent = vim.fn.fnamemodify(git_dir, ":h")
  if M.is_bare_repo(parent) then
    return parent
  end

  return git_dir
end

-- Get current branch name
function M.get_current_branch()
  local result = vim.fn.system("git branch --show-current 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

-- Parse git worktree list --porcelain output
function M.list_worktrees()
  local bare_repo = M.get_bare_repo_path()
  if not bare_repo then
    return {}
  end

  local output = vim.fn.system(string.format("git -C '%s' worktree list --porcelain 2>/dev/null", bare_repo))
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local worktrees = {}
  local current = {}

  -- Helper function to save current entry
  local function save_entry()
    if current.path and not current.is_bare then
      table.insert(worktrees, {
        path = current.path,
        branch = current.branch or "detached",
        head = current.head,
      })
    end
  end

  for line in output:gmatch("[^\r\n]+") do
    if line:match("^worktree ") then
      -- Save previous entry before starting new one
      save_entry()
      -- Start new entry
      current = {
        path = line:sub(10), -- Remove "worktree " prefix
      }
    elseif line:match("^HEAD ") then
      current.head = line:sub(6)
    elseif line:match("^branch ") then
      current.branch = line:sub(8):match("refs/heads/(.+)")
    elseif line:match("^bare") then
      current.is_bare = true
    end
  end

  -- Save the last entry
  save_entry()

  return worktrees
end

-- Create a new worktree
function M.create_worktree(branch_name, path)
  local bare_repo = M.get_bare_repo_path()
  if not bare_repo then
    return false, "Not in a git worktree"
  end

  -- If path not specified, create it inside the bare repo directory
  if not path then
    path = string.format("%s/%s", bare_repo, branch_name)
  end

  local cmd = string.format("git -C '%s' worktree add '%s' -b '%s' 2>&1", bare_repo, path, branch_name)
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, output
  end

  return true, path
end

-- Create worktree from existing branch
function M.create_worktree_from_branch(branch_name, path)
  local bare_repo = M.get_bare_repo_path()
  if not bare_repo then
    return false, "Not in a git worktree"
  end

  -- If path not specified, create it inside the bare repo directory
  if not path then
    path = string.format("%s/%s", bare_repo, branch_name)
  end

  local cmd = string.format("git -C '%s' worktree add '%s' '%s' 2>&1", bare_repo, path, branch_name)
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, output
  end

  return true, path
end

-- Delete a worktree
function M.delete_worktree(path)
  local bare_repo = M.get_bare_repo_path()
  if not bare_repo then
    return false, "Not in a git worktree"
  end

  local cmd = string.format("git -C '%s' worktree remove '%s' --force 2>&1", bare_repo, path)
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    return false, output
  end

  return true, "Worktree deleted successfully"
end

-- Get worktree info for current directory
function M.get_current_worktree_info()
  local worktrees = M.list_worktrees()
  local cwd = vim.fn.getcwd()

  for _, wt in ipairs(worktrees) do
    if wt.path == cwd then
      return wt
    end
  end

  return nil
end

return M
