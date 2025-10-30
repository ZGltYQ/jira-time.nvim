# jira-time.nvim

A Neovim plugin for logging time to Jira tasks directly from your editor. Track time spent on issues and automatically sync with Jira using the Atlassian API.

## Features

- ⏱️ **Built-in Timer**: Track time spent on tasks with a running timer
- 🔄 **Git Integration**: Automatically detect Jira issue key from git branch names
- 🔐 **OAuth 2.0 Authentication**: Secure authentication with Atlassian
- 📊 **Statusline Integration**: Display current issue and timer in lualine or custom statuslines
- 💾 **Persistent State**: Timer state survives Neovim restarts
- 🎯 **Smart Issue Selection**: Auto-detect from branch or select from your assigned issues
- 📝 **View Worklogs**: See all logged time for any issue

## Requirements

- Neovim >= 0.8.0
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) (required)
- [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) (optional, for statusline integration)
- Git (for branch detection)
- Atlassian Jira account with OAuth 2.0 app credentials

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'ZGltYQ/jira-time.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('jira-time').setup({
      oauth = {
        client_id = 'your-oauth-client-id',
        client_secret = 'your-oauth-client-secret',
      },
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'ZGltYQ/jira-time.nvim',
  requires = { 'nvim-lua/plenary.nvim' },
  config = function()
    require('jira-time').setup({
      oauth = {
        client_id = 'your-oauth-client-id',
        client_secret = 'your-oauth-client-secret',
      },
    })
  end,
}
```

## Setting up Atlassian OAuth 2.0

1. Go to [Atlassian Developer Console](https://developer.atlassian.com/console/myapps/)
2. Click **Create** → **OAuth 2.0 integration**
3. Fill in the app details:
   - **App name**: Choose any name (e.g., "Neovim Jira Timer")
   - Click **Create**
4. In the app settings:
   - Click **Permissions** → **Add** → **Jira API**
   - Add **Callback URL**: `http://localhost:8080/callback`
   - Add required **Scopes**:
     - `read:jira-work` - Read Jira issues and worklogs
     - `write:jira-work` - Create and update worklogs
     - `read:jira-user` - Read user information
     - `offline_access` - Refresh tokens
5. Click **Settings** and copy your **Client ID** and **Client Secret**
6. Add them to your Neovim configuration (see Configuration section below)

## Configuration

Full configuration example:

```lua
require('jira-time').setup({
  -- Required: OAuth 2.0 credentials from Atlassian Developer Console
  oauth = {
    client_id = 'your-oauth-client-id',
    client_secret = 'your-oauth-client-secret',
    -- Optional: Defaults shown below
    redirect_uri = 'http://localhost:8080/callback',
    scopes = {
      'read:jira-work',
      'write:jira-work',
      'read:jira-user',
      'offline_access',
    },
  },

  -- Timer configuration
  timer = {
    auto_save_interval = 60, -- Save timer state every 60 seconds
    format = '%H:%M:%S', -- Time format
    auto_start_on_branch_change = false,
  },

  -- Statusline configuration
  statusline = {
    enabled = true,
    mode = 'standalone', -- 'standalone', 'lualine', or 'custom'
    position = 'right', -- Position: 'left', 'center', or 'right' (standalone mode only)
    format = '[%s] ⏱ %s', -- Format: [ISSUE-KEY] ⏱ HH:MM:SS
    show_when_inactive = false, -- Show even when timer is paused
  },

  -- Git branch patterns to extract Jira issue keys
  branch_patterns = {
    '([A-Z]+%-[0-9]+)', -- PROJ-123 anywhere
    'feature/([A-Z]+%-[0-9]+)', -- feature/PROJ-123-description
    'bugfix/([A-Z]+%-[0-9]+)', -- bugfix/PROJ-123-description
    'hotfix/([A-Z]+%-[0-9]+)', -- hotfix/PROJ-123-description
  },

  -- UI configuration
  ui = {
    border = 'rounded',
    confirm_before_logging = true,
  },

  -- Keymaps configuration
  keymaps = {
    enabled = true, -- Enable default keymaps
    prefix = '<leader>j', -- Prefix for all jira-time keymaps
    start = 's', -- <leader>js - Start timer
    stop = 'x', -- <leader>jx - Stop timer
    log = 'l', -- <leader>jl - Log time
    select = 'i', -- <leader>ji - Select issue
    view = 'v', -- <leader>jv - View worklogs
    status = 't', -- <leader>jt - Show status
  },
})
```

## Keymaps

Default keymaps are automatically configured with the prefix `<leader>j`:

| Keymap | Command | Description |
|--------|---------|-------------|
| `<leader>js` | `:JiraTimeStart` | Start timer (auto-detect from branch or select issue) |
| `<leader>jx` | `:JiraTimeStop` | Stop the running timer |
| `<leader>jl` | `:JiraTimeLog` | Log time to Jira |
| `<leader>ji` | `:JiraTimeSelect` | Select a different issue |
| `<leader>jv` | `:JiraTimeView` | View worklogs for current issue |
| `<leader>jt` | `:JiraTimeStatus` | Show plugin status |

### Customizing Keymaps

You can customize or disable keymaps in your configuration:

```lua
require('jira-time').setup({
  keymaps = {
    enabled = true, -- Set to false to disable all keymaps
    prefix = '<leader>j', -- Change the prefix
    start = 's', -- Change individual keys
    stop = 'x',
    log = 'l',
    select = 'i',
    view = 'v',
    status = 't',
  },
})
```

To disable a specific keymap, set it to `false`:

```lua
require('jira-time').setup({
  keymaps = {
    start = false, -- Disable <leader>js
    -- Other keymaps remain enabled
  },
})
```

## Usage

### Authentication

First, authenticate with Jira:

```vim
:JiraAuth
```

This will:
1. Open your browser for OAuth authentication
2. Ask you to authorize the app in Atlassian
3. Automatically redirect to `http://localhost:8080/callback`
4. Automatically discover your Jira Cloud ID
5. Save your authentication tokens for future use

Note: Your Jira site URL (e.g., `yourcompany.atlassian.net`) is automatically discovered during authentication - no manual configuration needed!

### Commands

#### `:JiraTimeStart [issue-key]`

Start the timer for a Jira issue.

- If `issue-key` is provided, starts timer for that issue
- If no argument, tries to detect issue from current git branch
- If detection fails, shows a list of your assigned issues to select from

```vim
:JiraTimeStart              " Auto-detect from branch or select
:JiraTimeStart PROJ-123     " Start timer for specific issue
```

#### `:JiraTimeStop`

Stop the running timer.

```vim
:JiraTimeStop
```

#### `:JiraTimeLog [duration]`

Log tracked time to Jira.

- If `duration` is provided, logs that amount
- If no argument, logs the current timer's elapsed time
- Prompts for an optional comment/description

```vim
:JiraTimeLog          " Log current timer elapsed time
:JiraTimeLog 2h 30m   " Log specific duration
:JiraTimeLog 150m     " Log 150 minutes
:JiraTimeLog 1h       " Log 1 hour
```

Duration formats:
- `2h 30m` - 2 hours and 30 minutes
- `150m` - 150 minutes
- `1h` - 1 hour
- `45m` - 45 minutes
- `150` - 150 minutes (default unit)

#### `:JiraTimeView [issue-key]`

View worklogs for an issue.

- If `issue-key` is provided, shows worklogs for that issue
- If no argument, shows worklogs for current timer issue

```vim
:JiraTimeView           " View worklogs for current issue
:JiraTimeView PROJ-123  " View worklogs for specific issue
```

#### `:JiraTimeSelect`

Manually select a Jira issue from your assigned issues.

```vim
:JiraTimeSelect
```

#### `:JiraTimeStatus`

Show plugin status (useful for debugging).

```vim
:JiraTimeStatus
```

## Statusline Integration

The plugin displays a **live timer** at the bottom of Neovim showing:
- Current Jira issue key (e.g., `PROJ-123`)
- Elapsed time (e.g., `01:23:45`)
- Running/paused indicator (⏱/⏸)

Example: `⏱ [PROJ-123] ⏱ 01:23:45`

### Standalone Mode (Default - Works Everywhere!)

**No configuration needed!** The timer automatically appears in your statusline when you start tracking:

```lua
require('jira-time').setup({
  oauth = {
    client_id = 'your-oauth-client-id',
    client_secret = 'your-oauth-client-secret',
  },
  -- Statusline is enabled by default in standalone mode
})
```

The timer will automatically show at the **bottom-right** of Neovim when you run `:JiraTimeStart`.

**Customize the position:**

```lua
require('jira-time').setup({
  statusline = {
    enabled = true,
    mode = 'standalone', -- Default mode
    position = 'right', -- 'left', 'center', or 'right'
    format = '[%s] ⏱ %s', -- [ISSUE-KEY] ⏱ HH:MM:SS
    show_when_inactive = false, -- Show even when timer is paused
  },
})
```

### Lualine Integration

If you use lualine, switch to lualine mode:

```lua
require('jira-time').setup({
  statusline = {
    mode = 'lualine',
  },
})

-- Then add to your lualine config:
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

### Heirline / AstroNvim Integration

For AstroNvim or custom heirline setups, create `~/.config/nvim/lua/plugins/heirline.lua`:

```lua
-- First, configure jira-time to use custom mode
require('jira-time').setup({
  statusline = {
    mode = 'custom',
  },
})
```

Then add the heirline integration:

```lua
-- ~/.config/nvim/lua/plugins/heirline.lua
return {
  "rebelot/heirline.nvim",
  opts = function(_, opts)
    local status = require("astroui.status")

    -- Create jira-time component
    local jira_component = status.component.builder({
      {
        provider = function()
          local ok, jira = pcall(require, 'jira-time.statusline')
          if ok then
            local jira_status = jira.get_status()
            if jira_status ~= '' then
              return ' ' .. jira_status .. ' '
            end
          end
          return ""
        end,
        hl = status.hl.get_attributes("git_branch", true),
        on_click = {
          callback = function()
            vim.cmd("JiraTimeStatus")
          end,
          name = "jira_time_click",
        },
      },
    })

    -- Insert component into statusline
    table.insert(opts.statusline, 9, jira_component)

    return opts
  end,
}
```

### Other Custom Statusline Plugins

For other statusline plugins (feline, galaxyline, etc.):

```lua
require('jira-time').setup({
  statusline = {
    mode = 'custom', -- Disable automatic integration
  },
})

-- Then use in your statusline config:
local jira_status = require('jira-time.statusline').get_component()
statusline = statusline .. jira_status()
```

## Workflow Example

1. **Start working on a task:**
   ```bash
   git checkout -b feature/PROJ-123-add-new-feature
   ```

2. **Start timer in Neovim:**
   ```vim
   :JiraTimeStart  " Automatically detects PROJ-123 from branch
   ```

3. **Work on your code** (timer runs in background, visible in statusline)

4. **Stop timer when taking a break:**
   ```vim
   :JiraTimeStop
   ```

5. **Resume timer:**
   ```vim
   :JiraTimeStart  " Resumes with saved time
   ```

6. **Log time to Jira when done:**
   ```vim
   :JiraTimeLog  " Logs accumulated time with optional comment
   ```

## Git Branch Naming

The plugin can automatically extract Jira issue keys from your git branch names. Common patterns supported by default:

- `PROJ-123`
- `feature/PROJ-123-description`
- `bugfix/PROJ-123-description`
- `hotfix/PROJ-123-description`

You can customize patterns in the configuration.

## Troubleshooting

### "Not authenticated" error

Run `:JiraAuth` to authenticate with Jira.

### "Failed to fetch issues" error

Check your OAuth configuration and ensure the scopes include `read:jira-work`.

### Timer not persisting across sessions

Check that the data directory is writable:
```vim
:echo stdpath('data') .. '/jira-time'
```

### Issue not detected from branch

- Verify your branch name contains a Jira issue key
- Check the `branch_patterns` configuration
- Use `:JiraTimeStart PROJ-123` to manually specify the issue

## Data Storage

Plugin data is stored in:
- **Auth tokens:** `~/.local/share/nvim/jira-time/auth.json`
- **Timer state:** `~/.local/share/nvim/jira-time/timer.json`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Credits

Built with:
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) for HTTP requests
- Atlassian Jira REST API
- OAuth 2.0 (3LO) authentication

## Related Projects

- [Funk66/jira.nvim](https://github.com/Funk66/jira.nvim)
- [kid-icarus/jira.nvim](https://github.com/kid-icarus/jira.nvim)
- [vipul-sharma20/nvim-jira](https://github.com/vipul-sharma20/nvim-jira)
