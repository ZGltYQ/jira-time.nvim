-- Statusline integration module for lualine and other statuslines
local M = {}

-- Get statusline component string
---@return string status Formatted status string for statusline
function M.get_status()
  local timer = require('jira-time.timer')
  local config = require('jira-time.config').get()

  local status = timer.get_status()

  -- If timer is not running and config says not to show when inactive
  if not status.running and not config.statusline.show_when_inactive then
    return ''
  end

  -- If no issue is selected
  if not status.issue_key then
    return ''
  end

  -- Format the status line
  local formatted = string.format(
    config.statusline.format,
    status.issue_key,
    status.formatted_time
  )

  -- Add running indicator
  if status.running then
    formatted = '⏱ ' .. formatted
  else
    formatted = '⏸ ' .. formatted
  end

  return formatted
end

-- Lualine component
---@return table component Lualine component
function M.lualine_component()
  return {
    function()
      return M.get_status()
    end,
    cond = function()
      local timer = require('jira-time.timer')
      local config = require('jira-time.config').get()
      local status = timer.get_status()

      -- Show if timer is running OR if show_when_inactive is true and there's an issue
      return status.running or (config.statusline.show_when_inactive and status.issue_key ~= nil)
    end,
  }
end

-- Get component for generic statuslines (returns a function)
---@return function component Function that returns status string
function M.get_component()
  return function()
    return M.get_status()
  end
end

return M
