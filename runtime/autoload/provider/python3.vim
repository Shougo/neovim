" The python3 provider uses a python host to emulate an environment for running
" python3-vim plugins(:h python3-vim). See :h nvim-providers for more
" information.
"
" Associating the plugin with the python3 host is the first step because
" plugins will be passed as command-line arguments

if exists('s:loaded_python3_provider') || &compatible
  finish
endif

let s:loaded_python3_provider = 1
let s:plugin_path = expand('<sfile>:p:h').'/script_host.py'

" The python3 provider plugin will run in a separate instance of the python3
" host.
call remote#host#RegisterClone('legacy-python3-provider', 'python3')
call remote#host#RegisterPlugin('legacy-python3-provider', s:plugin_path, [])

" Ensure that we can load the python3 host before bootstrapping
try
  let s:host = remote#host#Require('legacy-python3-provider')
catch
  echomsg v:exception
  finish
endtry

let s:rpcrequest = function('rpcrequest')

function! provider#python3#Call(method, args)
  return call(s:rpcrequest, insert(insert(a:args, 'python3_'.a:method), s:host))
endfunction
