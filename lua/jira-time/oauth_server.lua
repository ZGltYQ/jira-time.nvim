-- Simple HTTP server for OAuth callback
local M = {}

local uv = vim.loop

-- Create a simple HTTP server to handle OAuth callback
---@param port number Port to listen on
---@param callback function Callback function(code, state)
---@return table server Server handle
function M.start_server(port, callback)
  local server = uv.new_tcp()
  local is_shutdown = false

  server:bind('127.0.0.1', port)
  server:listen(128, function(err)
    if err then
      vim.schedule(function()
        vim.notify('Failed to start OAuth server: ' .. err, vim.log.levels.ERROR)
      end)
      return
    end

    local client = uv.new_tcp()
    server:accept(client)

    client:read_start(function(read_err, chunk)
      if read_err then
        client:close()
        return
      end

      if chunk then
        -- Parse HTTP request
        local code, state = chunk:match('GET /callback%?code=([^&]+)&state=([^%s]+)')

        if code and state then
          -- Send success response
          local response = table.concat({
            'HTTP/1.1 200 OK',
            'Content-Type: text/html',
            'Connection: close',
            '',
            '<!DOCTYPE html>',
            '<html>',
            '<head><title>Authentication Successful</title></head>',
            '<body style="font-family: sans-serif; text-align: center; padding: 50px;">',
            '<h1>✓ Authentication Successful!</h1>',
            '<p>You can close this window and return to Neovim.</p>',
            '</body>',
            '</html>',
          }, '\r\n')

          client:write(response, function()
            client:close()
          end)

          -- Shutdown server and call callback
          if not is_shutdown then
            is_shutdown = true
            vim.schedule(function()
              server:close()
              callback(code, state)
            end)
          end
        else
          -- Send error response
          local response = table.concat({
            'HTTP/1.1 400 Bad Request',
            'Content-Type: text/html',
            'Connection: close',
            '',
            '<!DOCTYPE html>',
            '<html>',
            '<head><title>Authentication Failed</title></head>',
            '<body style="font-family: sans-serif; text-align: center; padding: 50px;">',
            '<h1>✗ Authentication Failed</h1>',
            '<p>Invalid callback parameters. Please try again.</p>',
            '</body>',
            '</html>',
          }, '\r\n')

          client:write(response, function()
            client:close()
          end)
        end
      else
        client:close()
      end
    end)
  end)

  return server
end

return M
