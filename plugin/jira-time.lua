-- Auto-loaded plugin commands for jira-time
-- This file is automatically sourced by Neovim

-- Prevent loading twice
if vim.g.loaded_jira_time then
  return
end
vim.g.loaded_jira_time = 1

-- Lazy load the plugin
local function get_plugin()
  return require('jira-time')
end

-- Command: Start timer
-- Usage: :JiraTimeStart [issue-key]
vim.api.nvim_create_user_command('JiraTimeStart', function(opts)
  local issue_key = opts.args ~= '' and opts.args or nil
  get_plugin().start_timer(issue_key)
end, {
  nargs = '?',
  desc = 'Start Jira time tracker (auto-detects from branch or prompts)',
})

-- Command: Stop timer
-- Usage: :JiraTimeStop
vim.api.nvim_create_user_command('JiraTimeStop', function()
  get_plugin().stop_timer()
end, {
  nargs = 0,
  desc = 'Stop Jira time tracker',
})

-- Command: Log time to Jira
-- Usage: :JiraTimeLog [duration]
-- Examples: :JiraTimeLog 2h 30m
--           :JiraTimeLog 150m
--           :JiraTimeLog (uses current timer)
vim.api.nvim_create_user_command('JiraTimeLog', function(opts)
  local duration = opts.args ~= '' and opts.args or nil
  get_plugin().log_time(nil, duration)
end, {
  nargs = '?',
  desc = 'Log tracked time to Jira issue',
})

-- Command: View worklogs
-- Usage: :JiraTimeView [issue-key]
vim.api.nvim_create_user_command('JiraTimeView', function(opts)
  local issue_key = opts.args ~= '' and opts.args or nil
  get_plugin().view_worklogs(issue_key)
end, {
  nargs = '?',
  desc = 'View worklogs for current or specified issue',
})

-- Command: Select issue
-- Usage: :JiraTimeSelect
vim.api.nvim_create_user_command('JiraTimeSelect', function()
  get_plugin().select_issue()
end, {
  nargs = 0,
  desc = 'Manually select a Jira issue',
})

-- Command: Authenticate with Jira
-- Usage: :JiraAuth
vim.api.nvim_create_user_command('JiraAuth', function()
  get_plugin().authenticate()
end, {
  nargs = 0,
  desc = 'Authenticate with Jira using OAuth 2.0',
})

-- Command: Show status (debug)
-- Usage: :JiraTimeStatus
vim.api.nvim_create_user_command('JiraTimeStatus', function()
  local status = get_plugin().get_status()
  print('=== Jira Time Status ===')
  print('Authenticated: ' .. tostring(status.authenticated))
  print('Git Branch: ' .. (status.git_branch or 'N/A'))
  print('Detected Issue: ' .. (status.git_issue or 'N/A'))
  print('Timer Running: ' .. tostring(status.timer.running))
  print('Current Issue: ' .. (status.timer.issue_key or 'N/A'))
  print('Elapsed Time: ' .. status.timer.formatted_time)
end, {
  nargs = 0,
  desc = 'Show jira-time plugin status',
})
