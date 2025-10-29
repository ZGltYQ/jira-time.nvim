-- Git integration module for branch detection and Jira issue extraction
local M = {}

-- Check if current directory is a git repository
---@return boolean is_git_repo True if in a git repository
function M.is_git_repo()
  vim.fn.system('git rev-parse --is-inside-work-tree 2>/dev/null')
  return vim.v.shell_error == 0
end

-- Get current git branch name
---@return string|nil branch_name Current branch name or nil if not in a git repo
function M.get_current_branch()
  if not M.is_git_repo() then
    return nil
  end

  local branch = vim.fn.system('git rev-parse --abbrev-ref HEAD 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error == 0 and branch ~= '' then
    return branch
  end

  return nil
end

-- Extract Jira issue key from branch name using configured patterns
---@param branch_name string Branch name to parse
---@return string|nil issue_key Extracted Jira issue key or nil if not found
function M.extract_issue_key(branch_name)
  if not branch_name then
    return nil
  end

  local config = require('jira-time.config').get()

  -- Try each configured pattern
  for _, pattern in ipairs(config.branch_patterns) do
    local issue_key = branch_name:match(pattern)
    if issue_key then
      return issue_key:upper() -- Jira keys are uppercase
    end
  end

  return nil
end

-- Get Jira issue key from current branch
---@return string|nil issue_key Jira issue key from current branch or nil if not found
function M.get_issue_from_current_branch()
  local branch = M.get_current_branch()
  if not branch then
    return nil
  end

  return M.extract_issue_key(branch)
end

-- Get git root directory
---@return string|nil git_root Git repository root path or nil if not in a git repo
function M.get_git_root()
  if not M.is_git_repo() then
    return nil
  end

  local git_root = vim.fn.system('git rev-parse --show-toplevel 2>/dev/null'):gsub('\n', '')
  if vim.v.shell_error == 0 and git_root ~= '' then
    return git_root
  end

  return nil
end

-- Get list of modified files in git
---@return table files List of modified files
function M.get_modified_files()
  if not M.is_git_repo() then
    return {}
  end

  local output = vim.fn.system('git status --porcelain 2>/dev/null')
  if vim.v.shell_error ~= 0 then
    return {}
  end

  local files = {}
  for line in output:gmatch('[^\r\n]+') do
    -- Parse git status output (format: "XY filename")
    local status, file = line:match('^(..)%s+(.+)$')
    if file then
      table.insert(files, {
        status = status,
        file = file,
      })
    end
  end

  return files
end

-- Check if there are uncommitted changes
---@return boolean has_changes True if there are uncommitted changes
function M.has_uncommitted_changes()
  local files = M.get_modified_files()
  return #files > 0
end

return M
