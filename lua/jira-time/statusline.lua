-- Statusline integration module for lualine and other statuslines
local M = {}

-- Standalone mode autocmd group
local standalone_group = nil

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

-- Setup standalone statusline mode
function M.setup_standalone()
  local config = require('jira-time.config').get()

  if not config.statusline.enabled then
    return
  end

  -- Create autocmd group
  if standalone_group then
    vim.api.nvim_del_augroup_by_id(standalone_group)
  end
  standalone_group = vim.api.nvim_create_augroup('JiraTimeStatusline', { clear = true })

  -- Build statusline with jira-time component
  local function build_statusline()
    local jira_status = M.get_status()
    if jira_status == '' then
      return vim.o.statusline -- Return current statusline if no jira status
    end

    local position = config.statusline.position or 'right'

    if position == 'left' then
      return jira_status .. ' %= %f %m %= %l:%c '
    elseif position == 'center' then
      return '%f %m %= ' .. jira_status .. ' %= %l:%c '
    else -- right
      return '%f %m %= %l:%c  ' .. jira_status
    end
  end

  -- Set up autocmd to update statusline
  vim.api.nvim_create_autocmd({ 'VimEnter', 'BufEnter', 'WinEnter' }, {
    group = standalone_group,
    callback = function()
      vim.opt.statusline = build_statusline()
    end,
    desc = 'Update jira-time statusline',
  })

  -- Initial setup
  vim.opt.statusline = build_statusline()
end

-- Disable standalone mode
function M.disable_standalone()
  if standalone_group then
    vim.api.nvim_del_augroup_by_id(standalone_group)
    standalone_group = nil
  end
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
