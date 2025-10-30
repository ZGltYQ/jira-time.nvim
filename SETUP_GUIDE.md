# Quick Setup Guide for jira-time.nvim

This guide will help you get started with jira-time.nvim in 5 steps.

## Step 1: Install Dependencies

Install plenary.nvim if you haven't already:

```lua
-- lazy.nvim
{ 'nvim-lua/plenary.nvim' }

-- packer.nvim
use { 'nvim-lua/plenary.nvim' }
```

## Step 2: Create OAuth 2.0 App in Atlassian

1. Visit [Atlassian Developer Console](https://developer.atlassian.com/console/myapps/)
2. Click "Create" → "OAuth 2.0 integration"
3. Fill in app details:
   - **App name**: Neovim Jira Time Tracker
   - **Redirect URL**: `http://localhost:8080/callback`
4. Click "Permissions" → "Add" → "Jira API"
5. Configure OAuth 2.0 (3LO) and add scopes:
   - `read:jira-work`
   - `write:jira-work`
   - `read:jira-user`
   - `offline_access`
6. Save and copy your **Client ID** and **Client Secret**

## Step 3: Install the Plugin

Add to your Neovim config:

```lua
{
  'ZGltYQ/jira-time.nvim',
  dependencies = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('jira-time').setup({
      jira_url = 'https://YOUR-COMPANY.atlassian.net', -- Replace with your Jira URL
      oauth = {
        client_id = 'YOUR_CLIENT_ID',         -- Replace with your Client ID
        client_secret = 'YOUR_CLIENT_SECRET', -- Replace with your Client Secret
      },
    })
  end,
}
```

## Step 4: Authenticate

After installation, authenticate with Jira:

```vim
:JiraAuth
```

This will:
1. Open your browser
2. Ask you to authorize the app
3. Redirect to a callback URL with an authorization code
4. Prompt you to paste the code in Neovim

Copy the code from the URL (everything after `code=`) and paste it when prompted.

## Step 5: Start Tracking Time!

### Option A: Auto-detect from Git Branch

If your branch is named like `feature/PROJ-123-add-feature`:

```vim
:JiraTimeStart
```

This will automatically detect `PROJ-123` and start the timer.

### Option B: Manual Selection

```vim
:JiraTimeStart
```

If no issue is detected, you'll see a list of your assigned issues to choose from.

### Option C: Specify Issue

```vim
:JiraTimeStart PROJ-123
```

### Log Your Time

When done working:

```vim
:JiraTimeLog
```

This will prompt you for an optional comment and log the tracked time to Jira.

## Optional: Add to Statusline

If using lualine, add to your config:

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      require('jira-time.statusline').lualine_component(),
      'encoding',
      'fileformat',
      'filetype',
    },
  },
})
```

## Troubleshooting

### OAuth Authorization Code

The redirect URL will look like:
```
http://localhost:8080/callback?code=VERY_LONG_CODE&state=...
```

Copy only the `VERY_LONG_CODE` part (everything between `code=` and `&state`).

### Can't Open Browser

If the browser doesn't open automatically, copy the URL from the notification and open it manually.

### Invalid Client Error

- Double-check your Client ID and Client Secret
- Ensure the redirect URI in your config matches exactly what's in the Atlassian console
- Verify you've added all required scopes

### No Issues Found

- Make sure you have issues assigned to you in Jira
- Try manually entering an issue key: `:JiraTimeStart PROJ-123`

## Example Workflow

```bash
# 1. Create a branch with Jira issue key
git checkout -b feature/PROJ-123-implement-feature

# 2. In Neovim, start timer
:JiraTimeStart  # Auto-detects PROJ-123

# 3. Work on your code...
# Timer runs in background, visible in statusline: [PROJ-123] ⏱ 01:23:45

# 4. Take a break
:JiraTimeStop

# 5. Resume later
:JiraTimeStart  # Continues from where you left off

# 6. Done working, log to Jira
:JiraTimeLog    # Logs 1h 23m 45s to PROJ-123
```

## Next Steps

- Read the full README.md for advanced configuration
- Set up custom branch patterns for your team's naming conventions
- Configure keyboard shortcuts for common commands
- Explore the `:JiraTimeView` command to see logged worklogs

## Need Help?

- Check `:JiraTimeStatus` for current plugin state
- Review logs in `~/.local/share/nvim/jira-time/`
- Open an issue on GitHub

Happy time tracking! ⏱️
