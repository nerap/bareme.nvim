-- Environment file generation from templates
local M = {}

-- Load shared secrets from encrypted file (using SOPS)
local function load_shared_secrets(bare_repo_path)
  local enc_file = bare_repo_path .. "/.env.shared.enc"

  if vim.fn.filereadable(enc_file) == 0 then
    return {}
  end

  -- Try to decrypt with SOPS
  local cmd = string.format("sops -d '%s' 2>/dev/null", enc_file)
  local output = vim.fn.system(cmd)

  if vim.v.shell_error ~= 0 then
    vim.notify("Warning: Could not decrypt .env.shared.enc (SOPS not installed or key missing)", vim.log.levels.WARN)
    return {}
  end

  -- Parse the decrypted content as env vars
  local secrets = {}
  for line in output:gmatch("[^\r\n]+") do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key and value then
      secrets[vim.trim(key)] = vim.trim(value)
    end
  end

  return secrets
end

-- Generate .env file from template
function M.generate_env(bare_repo_path, worktree_path, branch_name, ports, package_manager)
  local template_file = bare_repo_path .. "/.env.template"
  local output_file = worktree_path .. "/.env"

  -- Check if template exists
  if vim.fn.filereadable(template_file) == 0 then
    return false, "No .env.template found"
  end

  -- Read template
  local file = io.open(template_file, "r")
  if not file then
    return false, "Failed to read .env.template"
  end

  local template = file:read("*all")
  file:close()

  -- Get project name
  local project_name = vim.fn.fnamemodify(bare_repo_path, ":t"):gsub("%.git$", "")

  -- Sanitize branch name for use in variables (replace special chars with underscores)
  local safe_branch = branch_name:gsub("[^%w-]", "_")

  -- Load shared secrets
  local secrets = load_shared_secrets(bare_repo_path)

  -- Build variables map
  local variables = {
    PROJECT_NAME = project_name,
    BRANCH_NAME = safe_branch,
    WORKTREE_PATH = worktree_path,
    PACKAGE_MANAGER = package_manager or "npm",
  }

  -- Add port variables
  if ports then
    for service, port in pairs(ports) do
      local var_name = service:upper() .. "_PORT"
      variables[var_name] = tostring(port)
    end
  end

  -- Add shared secrets
  for key, value in pairs(secrets) do
    variables[key] = value
  end

  -- Replace ${VAR} and $VAR patterns
  local output = template

  -- Replace ${VAR} format (preferred)
  output = output:gsub("%${([%w_]+)}", function(var)
    return variables[var] or ""
  end)

  -- Replace $VAR format (without braces)
  output = output:gsub("%$([%w_]+)", function(var)
    -- Don't replace if it was already part of ${VAR}
    return variables[var] or ("$" .. var)
  end)

  -- Write output file
  local out_file = io.open(output_file, "w")
  if not out_file then
    return false, "Failed to write .env file"
  end

  out_file:write(output)
  out_file:close()

  return true, output_file
end

-- Create default .env.template
function M.create_default_template(bare_repo_path)
  local template_file = bare_repo_path .. "/.env.template"

  -- Check if already exists
  if vim.fn.filereadable(template_file) == 1 then
    return false, "Template already exists"
  end

  local default_template = [[# Environment Template for ${PROJECT_NAME}
# This file is used to generate .env for each worktree
# Variables are automatically injected by bareme.nvim

# Auto-injected variables:
# - PROJECT_NAME: Name of the project
# - BRANCH_NAME: Current branch (sanitized)
# - WORKTREE_PATH: Path to the worktree
# - PACKAGE_MANAGER: Detected package manager (npm, bun, pnpm, etc.)
# - APP_PORT, API_PORT, DB_PORT, etc.: Allocated ports

# Application
NODE_ENV=development
PORT=${APP_PORT}

# API
API_URL=http://localhost:${API_PORT}

# Database
DATABASE_URL=postgresql://user:password@localhost:${DB_PORT}/db_${BRANCH_NAME}

# Redis
REDIS_URL=redis://localhost:${REDIS_PORT}

# Add your custom variables below
# SECRET_KEY=  # Add to .env.shared.enc for shared secrets
]]

  local file = io.open(template_file, "w")
  if not file then
    return false, "Failed to create template"
  end

  file:write(default_template)
  file:close()

  return true, template_file
end

-- Validate template (check for undefined variables)
function M.validate_template(template_path)
  local file = io.open(template_path, "r")
  if not file then
    return false, "Cannot read template"
  end

  local content = file:read("*all")
  file:close()

  local issues = {}
  local known_vars = {
    "PROJECT_NAME",
    "BRANCH_NAME",
    "WORKTREE_PATH",
    "PACKAGE_MANAGER",
    "APP_PORT",
    "API_PORT",
    "DB_PORT",
    "REDIS_PORT",
    "MONGODB_PORT",
    "POSTGRES_PORT",
  }

  -- Find all ${VAR} references
  for var in content:gmatch("%${([%w_]+)}") do
    local is_known = false
    for _, known in ipairs(known_vars) do
      if var == known then
        is_known = true
        break
      end
    end

    if not is_known then
      table.insert(issues, string.format("Unknown variable: ${%s}", var))
    end
  end

  return #issues == 0, issues
end

-- Update existing .env with new variables
function M.update_env(worktree_path, new_vars)
  local env_file = worktree_path .. "/.env"

  if vim.fn.filereadable(env_file) == 0 then
    return false, ".env file not found"
  end

  -- Read existing content
  local file = io.open(env_file, "r")
  if not file then
    return false, "Failed to read .env"
  end

  local lines = {}
  local existing_vars = {}

  for line in file:lines() do
    table.insert(lines, line)
    local key = line:match("^([^=]+)=")
    if key then
      existing_vars[vim.trim(key)] = true
    end
  end
  file:close()

  -- Add new variables that don't exist
  local added = {}
  for key, value in pairs(new_vars) do
    if not existing_vars[key] then
      table.insert(lines, string.format("%s=%s", key, value))
      table.insert(added, key)
    end
  end

  if #added == 0 then
    return true, "No new variables to add"
  end

  -- Write updated content
  file = io.open(env_file, "w")
  if not file then
    return false, "Failed to write .env"
  end

  for _, line in ipairs(lines) do
    file:write(line .. "\n")
  end
  file:close()

  return true, string.format("Added %d variable(s): %s", #added, table.concat(added, ", "))
end

return M
