-- UI interaction module using vim.ui.select and vim.ui.input
local M = {}

-- Select a Jira issue from a list
---@param issues table List of Jira issues
---@param callback function Callback function(selected_issue)
function M.select_issue(issues, callback)
  if not issues or #issues == 0 then
    vim.notify('No issues available', vim.log.levels.WARN)
    return
  end

  -- Format issues for display
  local formatted_items = {}
  for _, issue in ipairs(issues) do
    local display = string.format(
      '%s - %s (%s)',
      issue.key,
      issue.fields.summary:sub(1, 60),
      issue.fields.status.name
    )
    table.insert(formatted_items, display)
  end

  vim.ui.select(formatted_items, {
    prompt = 'Select a Jira issue:',
    format_item = function(item)
      return item
    end,
  }, function(_, idx)
    if idx then
      callback(issues[idx])
    end
  end)
end

-- Prompt for worklog comment
---@param callback function Callback function(comment)
function M.prompt_worklog_comment(callback)
  vim.ui.input({
    prompt = 'Worklog comment (optional): ',
    default = '',
  }, function(input)
    callback(input or '')
  end)
end

-- Prompt for time duration
---@param default_duration string|nil Default duration
---@param callback function Callback function(duration_str)
function M.prompt_duration(default_duration, callback)
  vim.ui.input({
    prompt = 'Time duration (e.g., 2h 30m, 150m): ',
    default = default_duration or '',
  }, function(input)
    if input and input ~= '' then
      callback(input)
    end
  end)
end

-- Prompt for manual issue key entry
---@param callback function Callback function(issue_key)
function M.prompt_issue_key(callback)
  vim.ui.input({
    prompt = 'Enter Jira issue key (e.g., PROJ-123): ',
  }, function(input)
    if input and input ~= '' then
      callback(input:upper())
    end
  end)
end

-- Confirm action
---@param message string Confirmation message
---@param callback function Callback function(confirmed)
function M.confirm(message, callback)
  vim.ui.select({ 'Yes', 'No' }, {
    prompt = message,
  }, function(choice)
    callback(choice == 'Yes')
  end)
end

-- Synchronous confirmation using vim.fn.confirm
-- Use this for VimLeavePre where async callbacks don't work
---@param message string Confirmation message
---@return boolean confirmed True if user confirmed
function M.confirm_sync(message)
  local choice = vim.fn.confirm(message, '&Yes\n&No', 2)
  return choice == 1
end

-- Show notification with formatted time and issue
---@param issue_key string Jira issue key
---@param duration_seconds number Duration in seconds
---@param success boolean Whether operation was successful
function M.notify_time_logged(issue_key, duration_seconds, success)
  local timer = require('jira-time.timer')
  local formatted_time = timer.format_time(duration_seconds)

  if success then
    vim.notify(
      string.format('✓ Logged %s to %s', formatted_time, issue_key),
      vim.log.levels.INFO
    )
  else
    vim.notify(
      string.format('✗ Failed to log %s to %s', formatted_time, issue_key),
      vim.log.levels.ERROR
    )
  end
end

-- Display worklog entries in a buffer
---@param issue_key string Jira issue key
---@param worklogs table List of worklog entries
function M.display_worklogs(issue_key, worklogs)
  if not worklogs or #worklogs == 0 then
    vim.notify('No worklogs found for ' .. issue_key, vim.log.levels.INFO)
    return
  end

  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'

  -- Format worklog entries
  local lines = { '# Worklogs for ' .. issue_key, '' }

  for _, worklog in ipairs(worklogs) do
    -- Defensive nil check for author field
    local author = (worklog.author and (worklog.author.displayName or worklog.author.emailAddress)) or 'Unknown'
    local time_spent = worklog.timeSpent or 'Unknown'
    local started = worklog.started or 'Unknown'
    local comment = worklog.comment or 'No comment'

    table.insert(lines, '## ' .. started)
    table.insert(lines, '- **Author:** ' .. author)
    table.insert(lines, '- **Time Spent:** ' .. time_spent)
    table.insert(lines, '- **Comment:** ' .. comment)
    table.insert(lines, '')
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Open in a split window
  vim.cmd('vsplit')
  vim.api.nvim_win_set_buf(0, buf)
  vim.bo[buf].modifiable = false
end

-- Show error message
---@param message string Error message
function M.error(message)
  vim.notify(message, vim.log.levels.ERROR)
end

-- Show info message
---@param message string Info message
function M.info(message)
  vim.notify(message, vim.log.levels.INFO)
end

-- Show warning message
---@param message string Warning message
function M.warn(message)
  vim.notify(message, vim.log.levels.WARN)
end

return M
