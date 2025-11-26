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

-- Command: Logout / Clear authentication
-- Usage: :JiraLogout
vim.api.nvim_create_user_command('JiraLogout', function()
  get_plugin().auth.logout()
  vim.notify('Logged out. Run :JiraAuth to authenticate again.', vim.log.levels.INFO)
end, {
  nargs = 0,
  desc = 'Clear Jira authentication (logout)',
})

-- Command: Show token information
-- Usage: :JiraTokenInfo
vim.api.nvim_create_user_command('JiraTokenInfo', function()
  local token_info = get_plugin().auth.get_token_info()

  if not token_info then
    print('=== Jira OAuth Token Info ===')
    print('Status: Not authenticated')
    print('\nRun :JiraAuth to authenticate')
    return
  end

  print('=== Jira OAuth Token Info ===')
  print(string.format('Authenticated: %s', tostring(token_info.authenticated)))
  print(string.format('Has Refresh Token: %s', tostring(token_info.has_refresh_token)))

  if token_info.cloud_id then
    print(string.format('Cloud ID: %s', token_info.cloud_id))
  end

  if token_info.access_token_expires_at then
    local expires_in_min = math.floor(token_info.access_token_expires_in_seconds / 60)
    print(string.format('\nAccess Token:'))
    print(string.format('  Expires at: %s', os.date('%Y-%m-%d %H:%M:%S', token_info.access_token_expires_at)))
    print(string.format('  Expires in: %d minutes', expires_in_min))
    print(string.format('  Expired: %s', tostring(token_info.access_token_expired)))
  end

  if token_info.refresh_token_age_days then
    local days_remaining = 90 - token_info.refresh_token_age_days
    print(string.format('\nRefresh Token:'))
    print(string.format('  Age: %d days', token_info.refresh_token_age_days))
    print(string.format('  Issued: %s', os.date('%Y-%m-%d %H:%M:%S', token_info.refresh_token_issued_at)))
    print(string.format('  Est. days until re-auth needed: ~%d days', math.max(0, days_remaining)))

    if token_info.refresh_token_age_days > 80 then
      print('  ⚠ WARNING: Refresh token is old, re-authentication may be needed soon')
    end
  end

  if token_info.last_refresh_at then
    local days_ago = math.floor(token_info.days_since_last_refresh)
    print(string.format('\nLast Refresh:'))
    print(string.format('  Time: %s', os.date('%Y-%m-%d %H:%M:%S', token_info.last_refresh_at)))
    print(string.format('  Days ago: %d', days_ago))
  end

  if token_info.last_error then
    print(string.format('\nLast Error:'))
    print(string.format('  Status: %s', token_info.last_error.status))
    if token_info.last_error.error then
      print(string.format('  Error: %s', token_info.last_error.error))
    end
    print(string.format('  Time: %s', os.date('%Y-%m-%d %H:%M:%S', token_info.last_error.timestamp)))
  end

  print(string.format('\nToken Schema Version: %d', token_info.token_version))
end, {
  nargs = 0,
  desc = 'Show OAuth token information and diagnostics',
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

-- Command: Debug authentication (development)
-- Usage: :JiraTimeDebug
vim.api.nvim_create_user_command('JiraTimeDebug', function()
  require('jira-time.debug').test_auth()
end, {
  nargs = 0,
  desc = 'Debug authentication and API calls',
})
