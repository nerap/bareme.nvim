-- Utility to reload the plugin during development
local M = {}

-- Reload bareme.nvim modules
function M.reload_bareme()
  -- Clear all bareme modules from package.loaded
  for module_name, _ in pairs(package.loaded) do
    if module_name:match("^bareme") then
      package.loaded[module_name] = nil
    end
  end

  -- Clear user commands
  pcall(vim.api.nvim_del_user_command, "WorktreeCreate")
  pcall(vim.api.nvim_del_user_command, "WorktreeCreateFrom")
  pcall(vim.api.nvim_del_user_command, "WorktreeSwitch")
  pcall(vim.api.nvim_del_user_command, "WorktreeDelete")
  pcall(vim.api.nvim_del_user_command, "WorktreeList")

  -- Reset loaded flag
  vim.g.loaded_bareme = nil

  -- Reload plugin
  vim.cmd("runtime! plugin/bareme.lua")

  vim.notify("bareme.nvim reloaded!", vim.log.levels.INFO)
end

-- Create command for easy reloading
vim.api.nvim_create_user_command("BaremeReload", M.reload_bareme, {
  desc = "Reload bareme.nvim plugin",
})

return M
