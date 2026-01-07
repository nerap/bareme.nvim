-- Project detection and configuration management
local M = {}

-- Detect package manager from lockfiles
function M.detect_package_manager(worktree_path)
  local lockfiles = {
    { file = "bun.lockb", manager = "bun" },
    { file = "pnpm-lock.yaml", manager = "pnpm" },
    { file = "yarn.lock", manager = "yarn" },
    { file = "package-lock.json", manager = "npm" },
    { file = "Pipfile.lock", manager = "pip" },
    { file = "poetry.lock", manager = "poetry" },
    { file = "requirements.txt", manager = "pip" },
    { file = "Cargo.lock", manager = "cargo" },
    { file = "go.mod", manager = "go" },
    { file = "composer.lock", manager = "composer" },
  }

  for _, lock in ipairs(lockfiles) do
    if vim.fn.filereadable(worktree_path .. "/" .. lock.file) == 1 then
      return lock.manager
    end
  end

  -- Default fallback
  if vim.fn.filereadable(worktree_path .. "/package.json") == 1 then
    return "npm"
  end

  return "unknown"
end

-- Check if worktree has docker-compose file
function M.has_docker_compose(worktree_path)
  local compose_files = {
    "docker-compose.yml",
    "docker-compose.yaml",
    "compose.yml",
    "compose.yaml",
  }

  for _, file in ipairs(compose_files) do
    if vim.fn.filereadable(worktree_path .. "/" .. file) == 1 then
      return true, file
    end
  end

  return false
end

-- Check if bare repo has .env.template
function M.has_env_template(bare_repo_path)
  return vim.fn.filereadable(bare_repo_path .. "/.env.template") == 1
end

-- Detect project from bare repo
function M.detect_project(bare_repo_path)
  -- Get project name from path
  local project_name = vim.fn.fnamemodify(bare_repo_path, ":t"):gsub("%.git$", "")

  -- Try to load .bareme.json config
  local config_file = bare_repo_path .. "/.bareme.json"
  local config = {}

  if vim.fn.filereadable(config_file) == 1 then
    local file = io.open(config_file, "r")
    if file then
      local content = file:read("*all")
      file:close()

      local ok, data = pcall(vim.fn.json_decode, content)
      if ok then
        config = data
        -- Override project name if specified in config
        if config.name then
          project_name = config.name
        end
      end
    end
  end

  return {
    name = project_name,
    bare_repo = bare_repo_path,
    config = config,
  }
end

-- Get hooks from config
function M.get_hooks(config)
  return config.hooks or {}
end

-- Run a hook command
function M.run_hook(hook_name, worktree_path, config)
  local hooks = M.get_hooks(config)
  local hook_cmd = hooks[hook_name]

  if not hook_cmd then
    return true, nil -- No hook defined, not an error
  end

  -- Execute hook in worktree directory
  local cmd = string.format("cd '%s' && %s 2>&1", worktree_path, hook_cmd)
  local output = vim.fn.system(cmd)
  local success = vim.v.shell_error == 0

  return success, output
end

-- Create default .bareme.json config
function M.create_default_config(bare_repo_path)
  local config_file = bare_repo_path .. "/.bareme.json"

  -- Check if already exists
  if vim.fn.filereadable(config_file) == 1 then
    return false, "Config file already exists"
  end

  local default_config = {
    name = vim.fn.fnamemodify(bare_repo_path, ":t"):gsub("%.git$", ""),
    ports = {
      app = { start = 3000, ["end"] = 3099 },
      api = { start = 4000, ["end"] = 4099 },
      db = { start = 5432, ["end"] = 5532 },
    },
    hooks = {
      onCreate = "echo 'Worktree created!'",
      onDelete = "echo 'Worktree deleted!'",
    },
  }

  local content = vim.fn.json_encode(default_config)
  local file = io.open(config_file, "w")
  if not file then
    return false, "Failed to create config file"
  end

  file:write(content)
  file:close()

  return true, config_file
end

-- Get project info for display
function M.get_info(bare_repo_path, worktree_path)
  local project = M.detect_project(bare_repo_path)
  local package_manager = M.detect_package_manager(worktree_path)
  local has_compose, compose_file = M.has_docker_compose(worktree_path)
  local has_template = M.has_env_template(bare_repo_path)

  return {
    name = project.name,
    package_manager = package_manager,
    has_docker = has_compose,
    docker_file = compose_file,
    has_env_template = has_template,
    config = project.config,
  }
end

-- Validate project structure
function M.validate(bare_repo_path, worktree_path)
  local issues = {}

  -- Check if .env.template exists but .env is missing in worktree
  if M.has_env_template(bare_repo_path) then
    if vim.fn.filereadable(worktree_path .. "/.env") == 0 then
      table.insert(issues, ".env file missing (run :WorktreeInitEnv)")
    end
  end

  -- Check if docker-compose exists but docker is not installed
  local has_compose = M.has_docker_compose(worktree_path)
  if has_compose then
    local docker_check = vim.fn.system("command -v docker 2>/dev/null")
    if vim.trim(docker_check) == "" then
      table.insert(issues, "docker-compose.yml found but Docker is not installed")
    end
  end

  return issues
end

return M
