-- Automatic time tracking module
-- Handles auto-start on branch change, auto-log on branch switch and exit
local M = {}

-- Constants
local DEBOUNCE_MS = 100
local EXIT_TIMEOUT_MS = 5000

-- Module state
M.autocmd_group = nil
M.debounce_timer = nil
M.debounce_generation = 0 -- Generation counter to prevent stale callback execution
M.pending_auto_start = false -- Prevent overlapping auto-start attempts

-- Helper function to maybe auto-start on new branch
---@param new_branch string|nil New branch name
---@param config table Configuration object
local function maybe_auto_start_for_branch(new_branch, config)
  if config.timer.auto_start_on_branch_change and new_branch then
    M.auto_start_for_branch(new_branch)
  end
end

-- Check if branch has changed and handle accordingly
---@return boolean changed True if branch changed
function M.check_branch_change()
  local git = require('jira-time.git')
  local timer = require('jira-time.timer')
  local config = require('jira-time.config').get()

  local current_branch = git.get_current_branch()
  local last_branch = timer.get_last_known_branch()

  -- Handle nil cases explicitly (not in git repo or left git repo)
  if current_branch == nil and last_branch == nil then
    return false
  end

  -- No change
  if current_branch == last_branch then
    return false
  end

  -- Update tracked branch
  timer.set_last_known_branch(current_branch)
  timer.save_state()

  -- If we left a git repo (current_branch is nil), just update state
  if current_branch == nil then
    return true
  end

  -- Handle old branch (log time if running)
  if timer.is_running() and config.timer.auto_log_on_branch_change then
    M.prompt_log_on_branch_change(last_branch, current_branch)
    return true
  end

  -- Handle new branch (auto-start if enabled and timer not running)
  if not timer.is_running() then
    maybe_auto_start_for_branch(current_branch, config)
  end

  return true
end

-- Prompt user to log time when switching branches
---@param old_branch string|nil Previous branch
---@param new_branch string|nil New branch
function M.prompt_log_on_branch_change(old_branch, new_branch)
  local timer = require('jira-time.timer')
  local ui = require('jira-time.ui')
  local config = require('jira-time.config').get()

  -- Prevent duplicate prompts
  if timer.state.pending_log_prompt then
    return
  end

  -- Check minimum threshold
  if not timer.is_above_minimum_threshold() then
    -- Below threshold - just clear silently
    timer.clear_for_branch_switch()
    -- Auto-start on new branch if enabled
    maybe_auto_start_for_branch(new_branch, config)
    return
  end

  timer.state.pending_log_prompt = true

  local issue_key = timer.get_current_issue()
  local elapsed = timer.state.elapsed_seconds
  local formatted_time = timer.format_time(elapsed)

  local message = string.format('Log %s to %s before switching branches?', formatted_time, issue_key)

  -- Wrap callback in pcall to ensure pending_log_prompt is always reset
  ui.confirm(message, function(confirmed)
    local ok, err = pcall(function()
      if confirmed then
        M.log_time_quick(issue_key, elapsed, function(success)
          timer.clear_for_branch_switch()
          maybe_auto_start_for_branch(new_branch, config)
        end)
      else
        -- User declined - clear timer anyway
        timer.clear_for_branch_switch()
        maybe_auto_start_for_branch(new_branch, config)
      end
    end)

    -- Always reset flag, even on error
    timer.state.pending_log_prompt = false

    if not ok then
      vim.notify('Error in branch switch handler: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end)
end

-- Auto-start timer for a branch with Jira issue
---@param branch string|nil Branch name
function M.auto_start_for_branch(branch)
  if not branch then
    return
  end

  local timer = require('jira-time.timer')

  -- Prevent overlapping auto-start attempts
  if M.pending_auto_start then
    return
  end

  -- Don't auto-start if timer is already running
  if timer.is_running() then
    return
  end

  local git = require('jira-time.git')
  local api = require('jira-time.api')
  local ui = require('jira-time.ui')

  local issue_key = git.extract_issue_key(branch)
  if not issue_key then
    return
  end

  M.pending_auto_start = true

  -- Validate issue exists before starting
  api.get_issue(issue_key, function(issue, error)
    M.pending_auto_start = false

    if error then
      -- Issue doesn't exist or can't be accessed - don't auto-start
      return
    end

    -- Double-check timer isn't running (could have changed during async call)
    if timer.is_running() then
      return
    end

    timer.start(issue_key)
    ui.info('Auto-started timer for ' .. issue_key)
  end)
end

-- Log time quickly without comment prompt
---@param issue_key string Jira issue key
---@param seconds number Time in seconds
---@param callback function|nil Callback(success)
function M.log_time_quick(issue_key, seconds, callback)
  local api = require('jira-time.api')
  local ui = require('jira-time.ui')

  -- No comment for auto-logging
  local comment = ''

  api.log_work(issue_key, seconds, comment, function(worklog, error)
    local success = error == nil
    ui.notify_time_logged(issue_key, seconds, success)
    if callback then
      callback(success)
    end
  end)
end

-- Handle VimLeavePre - prompt to log before exit
-- Uses synchronous vim.fn.confirm for VimLeavePre compatibility
function M.handle_vim_leave()
  local timer = require('jira-time.timer')
  local ui = require('jira-time.ui')
  local config = require('jira-time.config').get()

  -- Always save state first
  timer.save_state()

  if not config.timer.auto_log_on_exit then
    return
  end

  if not timer.is_running() then
    return
  end

  if timer.state.exit_log_in_progress then
    return
  end

  if not timer.is_above_minimum_threshold() then
    return
  end

  timer.state.exit_log_in_progress = true

  local issue_key = timer.get_current_issue()
  local elapsed = timer.state.elapsed_seconds
  local formatted_time = timer.format_time(elapsed)

  local message = string.format('Log %s to %s before exiting?', formatted_time, issue_key)

  -- Use ui.confirm_sync for synchronous confirmation during VimLeavePre
  if ui.confirm_sync(message) then
    M.log_time_sync(issue_key, elapsed)
  end

  timer.state.exit_log_in_progress = false
end

-- Synchronous time logging for VimLeavePre
-- Uses plenary.curl in blocking mode
---@param issue_key string Jira issue key
---@param seconds number Time in seconds
function M.log_time_sync(issue_key, seconds)
  local auth = require('jira-time.auth')
  local timer = require('jira-time.timer')

  local has_curl, curl = pcall(require, 'plenary.curl')
  if not has_curl then
    vim.notify('Cannot log time: plenary.curl not available', vim.log.levels.WARN)
    return
  end

  local token = auth.get_access_token()
  local cloud_id = auth.get_cloud_id()

  if not token then
    vim.notify('Cannot log time: access token expired or missing. Run :JiraAuth to re-authenticate.', vim.log.levels.WARN)
    return
  end

  if not cloud_id then
    vim.notify('Cannot log time: not authenticated. Run :JiraAuth to authenticate.', vim.log.levels.WARN)
    return
  end

  local url = 'https://api.atlassian.com/ex/jira/' .. cloud_id .. '/rest/api/3/issue/' .. issue_key .. '/worklog'

  local data = {
    timeSpentSeconds = seconds,
    started = os.date('!%Y-%m-%dT%H:%M:%S.000+0000'),
  }

  local response = curl.post(url, {
    headers = {
      ['Authorization'] = 'Bearer ' .. token,
      ['Accept'] = 'application/json',
      ['Content-Type'] = 'application/json',
    },
    body = vim.json.encode(data),
    timeout = EXIT_TIMEOUT_MS,
  })

  if response.status == 200 or response.status == 201 then
    vim.notify('Logged ' .. timer.format_time(seconds) .. ' to ' .. issue_key, vim.log.levels.INFO)
  elseif response.status == 401 then
    vim.notify('Failed to log time: access token expired. Run :JiraAuth to re-authenticate.', vim.log.levels.WARN)
  else
    vim.notify('Failed to log time on exit (HTTP ' .. response.status .. ')', vim.log.levels.WARN)
  end
end

-- Setup autocmds for branch change detection
function M.setup_autocmds()
  local config = require('jira-time.config').get()
  local git = require('jira-time.git')
  local timer = require('jira-time.timer')

  -- Clean up existing group
  if M.autocmd_group then
    vim.api.nvim_del_augroup_by_id(M.autocmd_group)
  end

  M.autocmd_group = vim.api.nvim_create_augroup('JiraTimeAutoTrack', { clear = true })

  -- Initialize last known branch if not set
  if not timer.get_last_known_branch() then
    local current_branch = git.get_current_branch()
    timer.set_last_known_branch(current_branch)

    -- Auto-start on initial load if enabled and on a branch with issue key
    if config.timer.auto_start_on_branch_change and not timer.is_running() and current_branch then
      -- Defer to allow vim to fully initialize
      vim.defer_fn(function()
        M.auto_start_for_branch(current_branch)
      end, 500)
    end
  end

  -- Branch change detection events
  if config.timer.auto_start_on_branch_change or config.timer.auto_log_on_branch_change then
    local events = config.timer.branch_check_events or { 'FocusGained', 'BufEnter' }

    vim.api.nvim_create_autocmd(events, {
      group = M.autocmd_group,
      callback = function()
        -- Increment generation to invalidate any pending callbacks
        M.debounce_generation = M.debounce_generation + 1
        local current_generation = M.debounce_generation

        -- Clean up existing timer
        if M.debounce_timer then
          M.debounce_timer:stop()
          M.debounce_timer:close()
          M.debounce_timer = nil
        end

        -- Create new debounce timer
        M.debounce_timer = vim.loop.new_timer()
        M.debounce_timer:start(
          DEBOUNCE_MS,
          0,
          vim.schedule_wrap(function()
            -- Only execute if this is still the current generation
            if current_generation ~= M.debounce_generation then
              return
            end

            M.check_branch_change()

            -- Clean up timer
            if M.debounce_timer then
              M.debounce_timer:stop()
              M.debounce_timer:close()
              M.debounce_timer = nil
            end
          end)
        )
      end,
      desc = 'Check for git branch changes',
    })
  end

  -- VimLeavePre for exit logging
  if config.timer.auto_log_on_exit then
    vim.api.nvim_create_autocmd('VimLeavePre', {
      group = M.autocmd_group,
      callback = function()
        M.handle_vim_leave()
      end,
      desc = 'Prompt to log time before exiting Neovim',
    })
  end
end

-- Disable all auto-tracking
function M.disable()
  if M.debounce_timer then
    M.debounce_timer:stop()
    M.debounce_timer:close()
    M.debounce_timer = nil
  end
  if M.autocmd_group then
    vim.api.nvim_del_augroup_by_id(M.autocmd_group)
    M.autocmd_group = nil
  end
end

return M
