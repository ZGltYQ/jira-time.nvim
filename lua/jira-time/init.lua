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

-- Setup function called by user
---@param opts table User configuration options
function M.setup(opts)
  -- Setup configuration
  M.config.setup(opts)

  -- Load timer state from previous session
  M.timer.load_state()

  -- Setup timer auto-save autocmds
  M.timer.setup_autocmds()

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
