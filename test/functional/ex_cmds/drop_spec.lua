local n = require('test.functional.testnvim')()
local Screen = require('test.functional.ui.screen')

local command = n.command
local clear, feed, feed_command = n.clear, n.feed, n.feed_command
local exec = n.exec

describe(':drop', function()
  local screen

  before_each(function()
    clear()
    screen = Screen.new(35, 10)
    screen:set_default_attr_ids({
      [0] = { bold = true, foreground = Screen.colors.Blue },
      [1] = { bold = true, reverse = true },
      [2] = { reverse = true },
      [3] = { bold = true },
    })
    command('set nohidden laststatus=2 shortmess-=F')
  end)

  it('works like :e when called with only one window open', function()
    feed_command('drop tmp1.vim')
    screen:expect([[
      ^                                   |
      {0:~                                  }|*7
      {1:tmp1.vim                           }|
      "tmp1.vim" [New]                   |
    ]])
  end)

  it('switches to an open window showing the buffer', function()
    feed_command('edit tmp1')
    feed_command('vsplit')
    feed_command('edit tmp2')
    feed_command('drop tmp1')
    screen:expect([[
                    │^                    |
      {0:~             }│{0:~                   }|*7
      {2:tmp2           }{1:tmp1                }|
      "tmp1" [New]                       |
    ]])
  end)

  it("splits off a new window when a buffer can't be abandoned", function()
    feed_command('edit tmp1')
    feed_command('vsplit')
    feed_command('edit tmp2')
    feed('iABC<esc>')
    feed_command('drop tmp3')
    screen:expect([[
      ^                    │              |
      {0:~                   }│{0:~             }|*3
      {1:tmp3                }│{0:~             }|
      ABC                 │{0:~             }|
      {0:~                   }│{0:~             }|*2
      {2:tmp2 [+]             tmp1          }|
      "tmp3" [New]                       |
    ]])
  end)

  -- oldtest: Test_drop_modified_file()
  it('does not cause E37 with modified same file', function()
    exec([[
      edit Xdrop_modified.txt
      call setline(1, 'The quick brown fox jumped over the lazy dogs')
    ]])
    feed_command('drop Xdrop_modified.txt')
    screen:expect([[
      ^The quick brown fox jumped over the|
       lazy dogs                         |
      {0:~                                  }|*6
      {1:Xdrop_modified.txt [+]             }|
      :drop Xdrop_modified.txt           |
    ]])
  end)

  it('jumps to line number when passed +line', function()
    exec([[
      edit Xdrop_line.txt
      call append(0, "I just miss doing art. Don't you?")
      call append(1, "It is not so hard as we have supposed.")
      call append(2, "We are propelled by disaster. We are moving swiftly.")
    ]])
    feed_command('drop +2 Xdrop_line.txt')
    screen:expect([[
      I just miss doing art. Don't you?  |
      ^It is not so hard as we have suppos|
      ed.                                |
      We are propelled by disaster. We ar|
      e moving swiftly.                  |
                                         |
      {0:~                                  }|*2
      {1:Xdrop_line.txt [+]                 }|
      :drop +2 Xdrop_line.txt            |
    ]])
  end)
end)
