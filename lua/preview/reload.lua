local M = {}

local PORT = 5554
local server_handle = nil
local actual_port = nil
local clients = {}

local function make_script(port)
  return '<script>(function(){'
    .. 'var es=new EventSource("http://localhost:'
    .. tostring(port)
    .. '/__live/events");'
    .. 'es.addEventListener("reload",function(){location.reload();});'
    .. '})()</script>'
end

---@param port? integer
---@return boolean, string?
function M.start(port)
  if server_handle then
    return true
  end
  local server, create_err = vim.uv.new_tcp()
  if not server then
    return false, create_err or 'cannot allocate TCP server'
  end
  local bound, bind_err = server:bind('127.0.0.1', port or 0)
  if not bound then
    server:close()
    return false, bind_err
  end
  local sockname, name_err = server:getsockname()
  if not sockname then
    server:close()
    return false, name_err
  end
  local listening, listen_err = server:listen(128, function(err)
    if err then
      return
    end
    local client = vim.uv.new_tcp()
    if not client then
      return
    end
    if not server:accept(client) then
      client:close()
      return
    end
    local buf = ''
    local reading = client:read_start(function(read_err, data)
      if read_err or not data then
        if not client:is_closing() then
          client:close()
        end
        return
      end
      buf = buf .. data
      if buf:find('\r\n\r\n') or buf:find('\n\n') then
        client:read_stop()
        local first_line = buf:match('^([^\r\n]+)')
        if first_line and first_line:find('/__live/events', 1, true) then
          local response = 'HTTP/1.1 200 OK\r\n'
            .. 'Content-Type: text/event-stream\r\n'
            .. 'Cache-Control: no-cache\r\n'
            .. 'Access-Control-Allow-Origin: *\r\n'
            .. '\r\n'
          client:write(response)
          table.insert(clients, client)
        else
          client:close()
        end
      end
    end)
    if not reading and not client:is_closing() then
      client:close()
    end
  end)
  if not listening then
    server:close()
    return false, listen_err
  end
  server_handle = server
  actual_port = sockname.port
  return true
end

function M.stop()
  for _, c in ipairs(clients) do
    if not c:is_closing() then
      c:close()
    end
  end
  clients = {}
  if server_handle then
    server_handle:close()
    server_handle = nil
  end
  actual_port = nil
end

function M.broadcast()
  local event = 'event: reload\ndata: {}\n\n'
  local alive = {}
  for _, c in ipairs(clients) do
    if not c:is_closing() then
      local ok = pcall(function()
        c:write(event)
      end)
      if ok then
        table.insert(alive, c)
      end
    end
  end
  clients = alive
end

function M.inject(path, port)
  port = actual_port or port or PORT
  local f = io.open(path, 'r')
  if not f then
    return
  end
  local content = f:read('*a')
  f:close()
  local script = make_script(port)
  local new_content, n = content:gsub('</body>', script .. '\n</body>', 1)
  if n == 0 then
    new_content = content .. '\n' .. script
  end
  local fw = io.open(path, 'w')
  if not fw then
    return
  end
  fw:write(new_content)
  fw:close()
end

return M
