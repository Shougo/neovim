do
  local proc =
    io.popen([[python3 -c 'import neovim, sys; sys.stdout.write("ok")' 2> /dev/null]])
  if proc:read() ~= 'ok' then
    -- Don't run these tests if python3 is not available
    return
  end
end


local helpers = require('test.functional.helpers')
local eval, command, feed = helpers.eval, helpers.command, helpers.feed
local eq, clear, insert = helpers.eq, helpers.clear, helpers.insert
local expect = helpers.expect


describe('python3 commands and functions', function()
  before_each(function()
    clear()
    command('python3 import vim')
  end)

  describe('feature test', function()
    it('ok', function()
      eq(1, eval('has("python3")'))
    end)
  end)

  describe('python3_execute', function()
    it('ok', function()
      command('python3 vim.vars["set_by_python3"] = [100, 0]')
      eq({100, 0}, eval('g:set_by_python3'))
    end)
  end)

  describe('python3_execute with nested commands', function()
    it('ok', function()
      command([[python3 vim.command('python3 vim.command("python3 vim.command(\'let set_by_nested_python3 = 555\')")')]])
      eq(555, eval('g:set_by_nested_python3'))
    end)
  end)

  describe('python3_execute with range', function()
    it('ok', function()
      insert([[
        line1
        line2
        line3
        line4]])
      feed('ggjvj:python3 vim.vars["range"] = vim.current.range[:]<CR>')
      eq({'line2', 'line3'}, eval('g:range'))
    end)
  end)

  describe('py3file', function()
    it('ok', function()
      local fname = 'py3file.py'
      local F = io.open(fname, 'w')
      F:write('vim.command("let set_by_py3file = 123")')
      F:close()
      command('py3file py3file.py')
      eq(123, eval('g:set_by_py3file'))
      os.remove(fname)
    end)
  end)

  describe('py3do', function()
    it('ok', function()
      -- :pydo3 42 returns None for all lines,
      -- the buffer should not be changed
      command('normal :py3do 42')
      eq(0, eval('&mod'))
      -- insert some text
      insert('abc\ndef\nghi')
      expect([[
        abc
        def
        ghi]])
      -- go to top and select and replace the first two lines
      feed('ggvj:py3do return str(linenr)<CR>')
      expect([[
        1
        2
        ghi]])
    end)
  end)

  describe('py3eval', function()
    it('ok', function()
      eq({1, 2, {['key'] = 'val'}}, eval([[py3eval('[1, 2, {"key": "val"}]')]]))
    end)
  end)
end)
