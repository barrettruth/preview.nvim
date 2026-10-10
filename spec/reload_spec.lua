describe('reload', function()
  local reload

  before_each(function()
    package.loaded['preview.reload'] = nil
    reload = require('preview.reload')
  end)

  after_each(function()
    reload.stop()
  end)

  describe('start', function()
    local new_tcp, server, client, connection, failure, allocations

    before_each(function()
      new_tcp = vim.uv.new_tcp
      failure, connection, allocations = nil, nil, 0
      server = {
        closed = 0,
        bind = function()
          if failure == 'bind' then
            return nil, 'bind failed'
          end
          return 0
        end,
        getsockname = function()
          if failure == 'getsockname' then
            return nil, 'getsockname failed'
          end
          return { port = 12345 }
        end,
        listen = function(_, _, callback)
          if failure == 'listen' then
            return nil, 'listen failed'
          end
          connection = callback
          return 0
        end,
        accept = function()
          if failure == 'accept' then
            return nil, 'accept failed'
          end
          return 0
        end,
        close = function(self)
          self.closed = self.closed + 1
        end,
      }
      client = {
        closed = 0,
        read_start = function()
          if failure == 'read_start' then
            return nil, 'read_start failed'
          end
          return 0
        end,
        is_closing = function(self)
          return self.closed > 0
        end,
        close = function(self)
          self.closed = self.closed + 1
        end,
      }
      vim.uv.new_tcp = function()
        allocations = allocations + 1
        if failure == 'allocation' or (failure == 'client' and allocations > 1) then
          return nil, 'allocation failed'
        end
        return allocations == 1 and server or client
      end
    end)

    after_each(function()
      reload.stop()
      vim.uv.new_tcp = new_tcp
    end)

    it('returns an allocation error and permits another start', function()
      failure = 'allocation'
      local ok, err = reload.start()
      assert.is_false(ok)
      assert.are.equal('allocation failed', err)
      failure, allocations = nil, 0
      assert.is_true(reload.start())
    end)

    for _, operation in ipairs({ 'bind', 'getsockname', 'listen' }) do
      it('closes the server after ' .. operation .. ' fails', function()
        failure = operation
        local ok, err = reload.start()
        assert.is_false(ok)
        assert.are.equal(operation .. ' failed', err)
        assert.are.equal(1, server.closed)
        failure, allocations = nil, 0
        assert.is_true(reload.start())
      end)
    end

    it('does not allocate another server when already started', function()
      assert.is_true(reload.start())
      assert.is_true(reload.start())
      assert.are.equal(1, allocations)
    end)

    it('ignores listen callback errors without allocating a client', function()
      assert.is_true(reload.start())
      connection('connection failed')
      assert.are.equal(1, allocations)
    end)

    it('handles client allocation failure without closing the server', function()
      assert.is_true(reload.start())
      failure = 'client'
      assert.has_no.errors(function()
        connection(nil)
      end)
      assert.are.equal(0, server.closed)
    end)

    for _, operation in ipairs({ 'accept', 'read_start' }) do
      it('closes the client after ' .. operation .. ' fails', function()
        assert.is_true(reload.start())
        failure = operation
        connection(nil)
        assert.are.equal(1, client.closed)
        assert.are.equal(0, server.closed)
      end)
    end
  end)

  it('starts and stops a real TCP server', function()
    assert.is_true(reload.start())
    reload.stop()
    assert.is_true(reload.start())
  end)

  describe('inject', function()
    it('injects script before </body>', function()
      local path = os.tmpname()
      local f = assert(io.open(path, 'w'))
      f:write('<html><body><p>hello</p></body></html>')
      f:close()

      reload.inject(path)

      local fr = assert(io.open(path, 'r'))
      local content = fr:read('*a')
      fr:close()
      os.remove(path)

      assert.is_truthy(content:find('EventSource', 1, true))
      local script_pos = content:find('EventSource', 1, true)
      local body_pos = content:find('</body>', 1, true)
      assert.is_truthy(body_pos)
      assert.is_true(script_pos < body_pos)
    end)

    it('appends script when no </body>', function()
      local path = os.tmpname()
      local f = assert(io.open(path, 'w'))
      f:write('<html><p>hello</p></html>')
      f:close()

      reload.inject(path)

      local fr = assert(io.open(path, 'r'))
      local content = fr:read('*a')
      fr:close()
      os.remove(path)

      assert.is_truthy(content:find('EventSource', 1, true))
    end)
  end)

  describe('broadcast', function()
    it('does not error with no clients', function()
      assert.has_no.errors(function()
        reload.broadcast()
      end)
    end)
  end)
end)
