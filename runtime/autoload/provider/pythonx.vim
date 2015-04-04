" The Python provider helper
if exists('s:loaded_pythonx_provider')
  finish
endif

let s:loaded_pythonx_provider = 1

function! provider#pythonx#Detect(ver) abort
  let host_var = (a:ver == 2) ?
        \ 'g:python_host_prog' : 'g:python3_host_prog'
  if exists(host_var)
    " Disable auto detection
    return s:check_interpreter({host_var}, a:ver) ? {host_var} : ''
  endif

  for prog in ['python'.a:ver, 'python']
    if s:check_version(prog, a:ver) && !s:check_interpreter(prog, a:ver)
      return prog
    endif
  endfor

  " No python interpreter
  return ''
endfunction

function! s:check_version(prog, ver) abort
  let get_version =
        \ ' -c "import sys; sys.stdout.write(str(sys.version_info[0]) + '.
        \ '\".\" + str(sys.version_info[1]))"'
  let supported = (a:ver == 2) ?
        \ ['2.6', '2.7'] : ['3.3', '3.4', '3.5']
  return index(supported, system(a:prog . get_version)) >= 0
endfunction

function! s:check_interpreter(prog, ver) abort
  if !executable(a:prog)
    return 1
  endif

  " Load neovim module check
  call system(a:prog . ' -c ' .
        \ (a:ver == 2 ?
        \   '''import pkgutil; exit(pkgutil.get_loader("neovim") is None)''':
        \   '''import importlib; exit(importlib.find_loader("neovim") is None)''')
        \ )
  return v:shell_error
endfunction

