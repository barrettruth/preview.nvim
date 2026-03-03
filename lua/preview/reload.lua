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

function M.start(port)
  if server_handle then
    return
  end
  local server = vim.uv.new_tcp()
  server:bind('127.0.0.1', port or 0)
  local sockname = server:getsockname()
  if sockname then
    actual_port = sockname.port
  end
  server:listen(128, function(err)
    if err then
      return
    end
    local client = vim.uv.new_tcp()
    server:accept(client)
    local buf = ''
    client:read_start(function(read_err, data)
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
  end)
  server_handle = server
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
