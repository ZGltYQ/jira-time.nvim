-- Jira REST API client using plenary.curl
local M = {}

-- Check if plenary is available
local has_plenary, curl = pcall(require, 'plenary.curl')
if not has_plenary then
  vim.notify(
    'jira-time requires plenary.nvim. Please install: nvim-lua/plenary.nvim',
    vim.log.levels.ERROR
  )
end

-- URL encode a string
---@param str string String to encode
---@return string encoded URL encoded string
local function url_encode(str)
  if str == nil then
    return ''
  end
  str = string.gsub(str, '\n', '\r\n')
  str = string.gsub(str, '([^%w%-%.%_%~ ])', function(c)
    return string.format('%%%02X', string.byte(c))
  end)
  str = string.gsub(str, ' ', '+')
  return str
end

-- Make authenticated API request
---@param method string HTTP method (get, post, put, delete)
---@param endpoint string API endpoint path (e.g., /rest/api/3/myself)
---@param data table|nil Request body data
---@param callback function Callback function(response, error)
---@param is_retry boolean|nil Internal flag to prevent infinite recursion
function M.request(method, endpoint, data, callback, is_retry)
  local config = require('jira-time.config').get()
  local auth = require('jira-time.auth')

  -- Get access token and cloud ID
  local token = auth.get_access_token()
  local cloud_id = auth.get_cloud_id()

  if not token or not cloud_id then
    vim.notify('Not authenticated. Run :JiraAuth to authenticate.', vim.log.levels.ERROR)
    if callback then
      callback(nil, 'Not authenticated')
    end
    return
  end

  -- Use Atlassian OAuth API format: https://api.atlassian.com/ex/jira/{cloudId}/rest/api/3/...
  local url = 'https://api.atlassian.com/ex/jira/' .. cloud_id .. endpoint

  -- Prepare headers
  local headers = {
    ['Authorization'] = 'Bearer ' .. token,
    ['Accept'] = 'application/json',
    ['Content-Type'] = 'application/json',
  }

  -- Prepare curl options
  local opts = {
    headers = headers,
    body = data and vim.json.encode(data) or nil,
  }

  -- Debug: Show request URL
  vim.notify('Making API request: ' .. method:upper() .. ' ' .. url, vim.log.levels.DEBUG)

  -- Make request with error handling
  local ok, response = pcall(function()
    if method == 'get' then
      return curl.get(url, opts)
    elseif method == 'post' then
      return curl.post(url, opts)
    elseif method == 'put' then
      return curl.put(url, opts)
    elseif method == 'delete' then
      return curl.delete(url, opts)
    else
      error('Unsupported HTTP method: ' .. method)
    end
  end)

  if not ok then
    local error_msg = 'API request failed: ' .. tostring(response)
    vim.notify(error_msg, vim.log.levels.ERROR)
    if callback then
      callback(nil, error_msg)
    end
    return
  end

  -- Handle response
  if response.status == 200 or response.status == 201 or response.status == 204 then
    local body_data = nil
    if response.body and response.body ~= '' then
      local ok, decoded = pcall(vim.json.decode, response.body)
      if ok then
        body_data = decoded
      else
        vim.notify('Failed to parse JSON response', vim.log.levels.ERROR)
      end
    end

    if callback then
      callback(body_data, nil)
    end
  elseif response.status == 401 then
    -- Token expired, try to refresh (but only once to prevent infinite recursion)
    if is_retry then
      vim.notify('Token refresh failed. Please run :JiraAuth to re-authenticate', vim.log.levels.ERROR)
      if callback then
        callback(nil, 'Authentication failed')
      end
      return
    end

    vim.notify('Access token expired, refreshing...', vim.log.levels.INFO)
    auth.refresh_token(function(success)
      if success then
        vim.notify('Token refreshed successfully, retrying request...', vim.log.levels.INFO)
        -- Retry the request once
        M.request(method, endpoint, data, callback, true)
      else
        vim.notify('Token refresh failed. Please run :JiraAuth to re-authenticate', vim.log.levels.ERROR)
        if callback then
          callback(nil, 'Authentication failed')
        end
      end
    end)
  else
    local error_msg = 'API request failed: ' .. response.status
    if response.body then
      vim.notify('Response body: ' .. response.body, vim.log.levels.DEBUG)
      local ok, error_data = pcall(vim.json.decode, response.body)
      if ok then
        if error_data.errorMessages then
          error_msg = error_msg .. ' - ' .. table.concat(error_data.errorMessages, ', ')
        elseif error_data.message then
          error_msg = error_msg .. ' - ' .. error_data.message
        end
      else
        -- Not JSON, show raw body if small enough
        if #response.body < 200 then
          error_msg = error_msg .. ' - ' .. response.body
        end
      end
    end

    vim.notify(error_msg, vim.log.levels.ERROR)
    if callback then
      callback(nil, error_msg)
    end
  end
end

-- Get current user information
---@param callback function Callback function(user, error)
function M.get_current_user(callback)
  M.request('get', '/rest/api/3/myself', nil, callback)
end

-- Get issue by key
---@param issue_key string Jira issue key
---@param callback function Callback function(issue, error)
function M.get_issue(issue_key, callback)
  M.request('get', '/rest/api/3/issue/' .. issue_key, nil, callback)
end

-- Search issues using JQL
---@param jql string JQL query string
---@param callback function Callback function(results, error)
function M.search_issues(jql, callback)
  local endpoint = '/rest/api/3/search?jql=' .. url_encode(jql)
  M.request('get', endpoint, nil, callback)
end

-- Get issues assigned to current user
---@param callback function Callback function(issues, error)
function M.get_my_issues(callback)
  local jql = 'assignee=currentUser() AND resolution=Unresolved ORDER BY updated DESC'
  M.search_issues(jql, function(response, error)
    if error then
      callback(nil, error)
    else
      callback(response.issues or {}, nil)
    end
  end)
end

-- Log work to an issue
---@param issue_key string Jira issue key
---@param time_seconds number Time in seconds
---@param comment string|nil Optional comment
---@param callback function Callback function(worklog, error)
function M.log_work(issue_key, time_seconds, comment, callback)
  local data = {
    timeSpentSeconds = time_seconds,
    started = os.date('!%Y-%m-%dT%H:%M:%S.000+0000'),
  }

  if comment and comment ~= '' then
    data.comment = {
      type = 'doc',
      version = 1,
      content = {
        {
          type = 'paragraph',
          content = {
            {
              type = 'text',
              text = comment,
            },
          },
        },
      },
    }
  end

  M.request('post', '/rest/api/3/issue/' .. issue_key .. '/worklog', data, callback)
end

-- Get worklogs for an issue
---@param issue_key string Jira issue key
---@param callback function Callback function(worklogs, error)
function M.get_worklogs(issue_key, callback)
  M.request('get', '/rest/api/3/issue/' .. issue_key .. '/worklog', nil, function(response, error)
    if error then
      callback(nil, error)
    else
      callback(response.worklogs or {}, nil)
    end
  end)
end

return M
