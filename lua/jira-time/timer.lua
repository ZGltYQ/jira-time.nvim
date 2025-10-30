-- Time tracking timer module
local M = {}

-- Timer state
M.state = {
  running = false,
  issue_key = nil,
  start_time = nil,
  elapsed_seconds = 0,
  timer_handle = nil,
  auto_save_timer = nil,
}

-- Format seconds as HH:MM:SS or custom format
---@param seconds number Total seconds to format
---@param format string|nil Format string (default from config)
---@return string formatted_time Formatted time string
function M.format_time(seconds, format)
  local config = require('jira-time.config').get()
  format = format or config.timer.format

  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60

  -- Simple format replacement
  local result = format:gsub('%%H', string.format('%02d', hours))
  result = result:gsub('%%M', string.format('%02d', minutes))
  result = result:gsub('%%S', string.format('%02d', secs))

  return result
end

-- Parse time duration from string (e.g., "2h 30m", "150m", "1h")
---@param duration_str string Duration string
---@return number|nil seconds Total seconds or nil if invalid format
function M.parse_duration(duration_str)
  if not duration_str or duration_str == '' then
    return nil
  end

  local total_seconds = 0

  -- Match hours (e.g., "2h")
  local hours = duration_str:match('(%d+)h')
  if hours then
    total_seconds = total_seconds + (tonumber(hours) * 3600)
  end

  -- Match minutes (e.g., "30m")
  local minutes = duration_str:match('(%d+)m')
  if minutes then
    total_seconds = total_seconds + (tonumber(minutes) * 60)
  end

  -- Match seconds (e.g., "45s")
  local seconds = duration_str:match('(%d+)s')
  if seconds then
    total_seconds = total_seconds + tonumber(seconds)
  end

  -- If no units found, try to parse as just minutes
  if total_seconds == 0 then
    local num = tonumber(duration_str)
    if num then
      total_seconds = num * 60 -- Default to minutes
    end
  end

  return total_seconds > 0 and total_seconds or nil
end

-- Save timer state to disk
function M.save_state()
  local storage = require('jira-time.storage')
  local state_data = {
    running = M.state.running,
    issue_key = M.state.issue_key,
    start_time = M.state.start_time,
    elapsed_seconds = M.state.elapsed_seconds,
  }

  storage.save_timer(state_data)
end

-- Load timer state from disk
function M.load_state()
  local storage = require('jira-time.storage')
  local state_data = storage.load_timer()

  if state_data then
    M.state.issue_key = state_data.issue_key
    M.state.elapsed_seconds = state_data.elapsed_seconds or 0

    -- If timer was running when Neovim closed, restore it
    if state_data.running and state_data.start_time then
      -- Calculate elapsed time since last save
      local now = os.time()
      local additional_time = now - state_data.start_time
      M.state.elapsed_seconds = M.state.elapsed_seconds + additional_time

      -- Restart timer
      M.start(M.state.issue_key, M.state.elapsed_seconds)
    end
  end
end

-- Start timer for a Jira issue
---@param issue_key string Jira issue key (e.g., "PROJ-123")
---@param initial_seconds number|nil Initial elapsed seconds (for restoration)
function M.start(issue_key, initial_seconds)
  if M.state.running then
    M.stop()
  end

  M.state.running = true
  M.state.issue_key = issue_key
  M.state.start_time = os.time()
  M.state.elapsed_seconds = initial_seconds or 0

  -- Start 1-second timer
  M.state.timer_handle = vim.loop.new_timer()
  M.state.timer_handle:start(
    1000, -- Start after 1 second
    1000, -- Repeat every 1 second
    vim.schedule_wrap(function()
      M.state.elapsed_seconds = M.state.elapsed_seconds + 1
      -- Redraw statusline to update timer display
      vim.api.nvim_command('redrawstatus')
    end)
  )

  -- Start auto-save timer
  local config = require('jira-time.config').get()
  if config.timer.auto_save_interval > 0 then
    M.state.auto_save_timer = vim.loop.new_timer()
    M.state.auto_save_timer:start(
      config.timer.auto_save_interval * 1000,
      config.timer.auto_save_interval * 1000,
      vim.schedule_wrap(function()
        M.save_state()
      end)
    )
  end

  M.save_state()
  vim.notify('Timer started for ' .. issue_key, vim.log.levels.INFO)
end

-- Stop timer
---@return number elapsed_seconds Total elapsed seconds
function M.stop()
  if not M.state.running then
    return 0
  end

  local elapsed = M.state.elapsed_seconds

  -- Stop timers
  if M.state.timer_handle then
    M.state.timer_handle:stop()
    M.state.timer_handle:close()
    M.state.timer_handle = nil
  end

  if M.state.auto_save_timer then
    M.state.auto_save_timer:stop()
    M.state.auto_save_timer:close()
    M.state.auto_save_timer = nil
  end

  M.state.running = false
  M.save_state()

  vim.notify(
    'Timer stopped: ' .. M.format_time(elapsed) .. ' for ' .. (M.state.issue_key or 'unknown'),
    vim.log.levels.INFO
  )

  return elapsed
end

-- Reset timer without stopping
function M.reset()
  M.state.elapsed_seconds = 0
  M.save_state()
end

-- Get current timer status
---@return table status Timer status information
function M.get_status()
  return {
    running = M.state.running,
    issue_key = M.state.issue_key,
    elapsed_seconds = M.state.elapsed_seconds,
    formatted_time = M.format_time(M.state.elapsed_seconds),
  }
end

-- Check if timer is running
---@return boolean running True if timer is running
function M.is_running()
  return M.state.running
end

-- Get current issue key
---@return string|nil issue_key Current issue key or nil
function M.get_current_issue()
  return M.state.issue_key
end

-- Setup autocommands for saving state on exit
function M.setup_autocmds()
  local group = vim.api.nvim_create_augroup('JiraTimerAutoSave', { clear = true })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      M.save_state()
    end,
    desc = 'Save jira-time timer state before exiting',
  })
end

return M
