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
---@param endpoint string API endpoint path
---@param data table|nil Request body data
---@param callback function Callback function(response, error)
function M.request(method, endpoint, data, callback)
  local config = require('jira-time.config').get()
  local auth = require('jira-time.auth')

  -- Get access token
  local token = auth.get_access_token()
  if not token then
    vim.notify('Not authenticated. Run :JiraAuth to authenticate.', vim.log.levels.ERROR)
    if callback then
      callback(nil, 'Not authenticated')
    end
    return
  end

  local url = config.jira_url .. endpoint

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

  -- Make request
  local response
  if method == 'get' then
    response = curl.get(url, opts)
  elseif method == 'post' then
    response = curl.post(url, opts)
  elseif method == 'put' then
    response = curl.put(url, opts)
  elseif method == 'delete' then
    response = curl.delete(url, opts)
  else
    vim.notify('Unsupported HTTP method: ' .. method, vim.log.levels.ERROR)
    if callback then
      callback(nil, 'Unsupported HTTP method')
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
    -- Token expired, try to refresh
    auth.refresh_token(function(success)
      if success then
        -- Retry the request
        M.request(method, endpoint, data, callback)
      else
        vim.notify('Authentication failed. Please run :JiraAuth', vim.log.levels.ERROR)
        if callback then
          callback(nil, 'Authentication failed')
        end
      end
    end)
  else
    local error_msg = 'API request failed: ' .. response.status
    if response.body then
      local ok, error_data = pcall(vim.json.decode, response.body)
      if ok and error_data.errorMessages then
        error_msg = error_msg .. ' - ' .. table.concat(error_data.errorMessages, ', ')
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
