describe('reload', function()
  local reload

  before_each(function()
    package.loaded['preview.reload'] = nil
    reload = require('preview.reload')
  end)

  after_each(function()
    reload.stop()
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
