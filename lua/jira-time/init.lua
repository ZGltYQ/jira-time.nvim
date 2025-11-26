-- Main module for jira-time plugin
local M = {}

-- Plugin modules
M.config = require('jira-time.config')
M.auth = require('jira-time.auth')
M.api = require('jira-time.api')
M.git = require('jira-time.git')
M.timer = require('jira-time.timer')
M.ui = require('jira-time.ui')
M.storage = require('jira-time.storage')
M.statusline = require('jira-time.statusline')
M.autotrack = require('jira-time.autotrack')

-- Setup keymaps
local function setup_keymaps()
  local config = M.config.get()

  if not config.keymaps.enabled then
    return
  end

  local prefix = config.keymaps.prefix
  local maps = config.keymaps

  -- Helper to create keymap with description
  local function map(key, cmd, desc)
    if key then
      vim.keymap.set('n', prefix .. key, cmd, { desc = 'Jira: ' .. desc, silent = true })
    end
  end

  -- Setup keymaps
  map(maps.start, '<cmd>JiraTimeStart<cr>', 'Start timer')
  map(maps.stop, '<cmd>JiraTimeStop<cr>', 'Stop timer')
  map(maps.log, '<cmd>JiraTimeLog<cr>', 'Log time')
  map(maps.select, '<cmd>JiraTimeSelect<cr>', 'Select issue')
  map(maps.view, '<cmd>JiraTimeView<cr>', 'View worklogs')
  map(maps.status, '<cmd>JiraTimeStatus<cr>', 'Show status')

  -- Create which-key group if available
  local ok, wk = pcall(require, 'which-key')
  if ok then
    wk.register({
      [prefix] = { name = 'Jira Time' }
    })
  end
end

-- Validate tokens on startup and refresh if needed
function M.validate_tokens_on_startup()
  vim.schedule(function()
    local auth_data = M.storage.load_auth()

    -- No auth data, nothing to validate
    if not auth_data or not auth_data.access_token then
      return
    end

    local current_time = os.time()

    -- Check if access token is expired
    if auth_data.expires_at and current_time >= auth_data.expires_at then
      vim.notify('Access token expired, refreshing...', vim.log.levels.INFO)
      M.auth.refresh_token(function(success)
        if success then
          vim.notify('Token refreshed successfully on startup', vim.log.levels.INFO)
        else
          vim.notify('Failed to refresh token. Run :JiraAuth to re-authenticate', vim.log.levels.WARN)
        end
      end)
      return
    end

    -- Check if refresh token is getting old (> 80 days)
    if auth_data.refresh_token_issued_at then
      local days_old = (current_time - auth_data.refresh_token_issued_at) / 86400
      if days_old > 80 then
        vim.notify(
          string.format(
            'Jira OAuth refresh token is %d days old. Re-authentication may be needed soon.',
            math.floor(days_old)
          ),
          vim.log.levels.WARN
        )
      end
    end
  end)
end

-- Background token refresh timer
local token_refresh_timer = nil

-- Setup background token refresh timer
function M.setup_token_refresh_timer()
  -- Stop existing timer if any
  if token_refresh_timer then
    token_refresh_timer:stop()
    token_refresh_timer:close()
  end

  -- Get config values
  local config = M.config.get()
  local token_config = config.token_refresh

  -- Check if proactive refresh is enabled
  if not token_config.proactive then
    return
  end

  -- Convert interval to milliseconds
  local refresh_interval_ms = token_config.background_interval * 1000

  -- Create a new timer
  token_refresh_timer = vim.uv.new_timer()

  -- Start timer with repeat
  token_refresh_timer:start(refresh_interval_ms, refresh_interval_ms, vim.schedule_wrap(function()
    -- Check if authenticated
    if not M.auth.is_authenticated() then
      return
    end

    -- Check if token needs refresh
    local storage = M.storage
    local auth_data = storage.load_auth()

    if not auth_data or not auth_data.refresh_token then
      return
    end

    -- Calculate if refresh is needed
    local current_time = os.time()

    local needs_refresh = false

    -- Check 1: Access token expires soon
    if auth_data.expires_at and (auth_data.expires_at - current_time) < token_config.refresh_before_expiry then
      needs_refresh = true
    end

    -- Check 2: Last refresh was too long ago
    if auth_data.last_refresh_at then
      local days_since_refresh = (current_time - auth_data.last_refresh_at) / 86400
      if days_since_refresh > token_config.max_refresh_age_days then
        needs_refresh = true
      end
    end

    -- Trigger refresh if needed
    if needs_refresh then
      vim.notify('Background token refresh triggered', vim.log.levels.DEBUG)
      M.auth.refresh_token(function(success)
        if success then
          vim.notify('Background token refresh successful', vim.log.levels.DEBUG)
        else
          vim.notify('Background token refresh failed', vim.log.levels.WARN)
        end
      end)
    end
  end))
end

-- Setup function called by user
---@param opts table User configuration options
function M.setup(opts)
  -- Setup configuration
  M.config.setup(opts)

  -- Load timer state from previous session
  M.timer.load_state()

  -- Setup timer auto-save autocmds
  M.timer.setup_autocmds()

  -- Setup standalone statusline if enabled
  local config = M.config.get()
  if config.statusline.enabled and config.statusline.mode == 'standalone' then
    M.statusline.setup_standalone()
  end

  -- Setup keymaps
  setup_keymaps()

  -- Setup automatic time tracking (branch detection, auto-log on exit)
  M.autotrack.setup_autocmds()

  -- Validate and refresh tokens on startup
  M.validate_tokens_on_startup()

  -- Setup background token refresh timer
  M.setup_token_refresh_timer()

  return M
end

-- Start timer for an issue (with auto-detection from branch)
---@param issue_key string|nil Optional issue key, auto-detected if nil
function M.start_timer(issue_key)
  if issue_key then
    M.timer.start(issue_key)
    return
  end

  -- Try to auto-detect from branch
  local detected_key = M.git.get_issue_from_current_branch()

  if detected_key then
    -- Validate issue exists in Jira
    M.api.get_issue(detected_key, function(issue, error)
      if error then
        M.ui.error('Issue ' .. detected_key .. ' not found in Jira')
        -- Fallback to manual selection
        M.select_and_start_timer()
      else
        M.timer.start(detected_key)
      end
    end)
  else
    -- No issue detected from branch, show selection
    M.select_and_start_timer()
  end
end

-- Select issue from list and start timer
function M.select_and_start_timer()
  M.api.get_my_issues(function(issues, error)
    if error then
      M.ui.error('Failed to fetch issues: ' .. error)
      return
    end

    if #issues == 0 then
      M.ui.warn('No issues found. You can manually enter an issue key.')
      M.ui.prompt_issue_key(function(key)
        M.timer.start(key)
      end)
      return
    end

    M.ui.select_issue(issues, function(issue)
      M.timer.start(issue.key)
    end)
  end)
end

-- Stop timer
function M.stop_timer()
  M.timer.stop()
end

-- Log time to Jira
---@param issue_key string|nil Issue key (uses current timer issue if nil)
---@param duration_str string|nil Duration string (uses timer elapsed if nil)
function M.log_time(issue_key, duration_str)
  local current_issue = issue_key or M.timer.get_current_issue()

  if not current_issue then
    M.ui.error('No issue selected. Start a timer or specify an issue key.')
    return
  end

  -- Parse duration
  local duration_seconds
  if duration_str then
    duration_seconds = M.timer.parse_duration(duration_str)
    if not duration_seconds then
      M.ui.error('Invalid duration format. Use: 2h 30m, 150m, etc.')
      return
    end
  else
    -- Use timer elapsed time
    local status = M.timer.get_status()
    if status.elapsed_seconds == 0 then
      M.ui.error('No time tracked. Specify a duration or start the timer.')
      return
    end
    duration_seconds = status.elapsed_seconds
  end

  -- Prompt for comment
  M.ui.prompt_worklog_comment(function(comment)
    -- Log to Jira
    M.api.log_work(current_issue, duration_seconds, comment, function(worklog, error)
      if error then
        M.ui.notify_time_logged(current_issue, duration_seconds, false)
        M.ui.error('Failed to log work: ' .. error)
      else
        M.ui.notify_time_logged(current_issue, duration_seconds, true)

        -- Reset timer if it was used
        if not duration_str and M.timer.is_running() then
          M.timer.reset()
        end
      end
    end)
  end)
end

-- View worklogs for an issue
---@param issue_key string|nil Issue key (uses current timer issue if nil)
function M.view_worklogs(issue_key)
  local target_issue = issue_key or M.timer.get_current_issue()

  if not target_issue then
    M.ui.error('No issue selected. Specify an issue key.')
    return
  end

  M.api.get_worklogs(target_issue, function(worklogs, error)
    if error then
      M.ui.error('Failed to fetch worklogs: ' .. error)
      return
    end

    M.ui.display_worklogs(target_issue, worklogs)
  end)
end

-- Select a different issue
function M.select_issue()
  M.select_and_start_timer()
end

-- Authenticate with Jira
function M.authenticate()
  M.auth.authenticate()
end

-- Get current status (for debugging or custom statuslines)
---@return table status Current plugin status
function M.get_status()
  return {
    timer = M.timer.get_status(),
    authenticated = M.auth.is_authenticated(),
    git_branch = M.git.get_current_branch(),
    git_issue = M.git.get_issue_from_current_branch(),
  }
end

return M
