" The Python provider uses a Python host to emulate an environment for running
" python-vim plugins. See ":help nvim-provider" for more information.
"
" Associating the plugin with the Python host is the first step because plugins
" will be passed as command-line arguments

if exists('g:loaded_python_provider')
  finish
endif

let g:loaded_python_provider = 1

let s:prog = provider#pythonx#Detect(2)
if s:prog == ''
  finish
endif

let s:plugin_path = expand('<sfile>:p:h').'/script_host.py'

" The Python provider plugin will run in a separate instance of the Python
" host.
call remote#host#RegisterClone('legacy-python-provider', 'python')
call remote#host#RegisterPlugin('legacy-python-provider', s:plugin_path, [])

function! provider#python#Prog()
  return s:prog
endfunction

function! provider#python#Call(method, args)
  if !exists('s:host')
    " Ensure that we can load the Python host before bootstrapping
    try
      let s:host = remote#host#Require('legacy-python-provider')
    catch
      echomsg v:exception
      return
    endtry

    let s:rpcrequest = function('rpcrequest')
  endif
  return call(s:rpcrequest, insert(insert(a:args, 'python_'.a:method), s:host))
endfunction
