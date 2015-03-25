let s:hosts = {}
let s:plugin_patterns = {
      \ 'python': '*.py',
      \ 'python3': '*.py',
      \ }
let s:remote_plugins_manifest = fnamemodify($MYVIMRC, ':p:h')
      \.'/.'.fnamemodify($MYVIMRC, ':t').'-rplugin~'


" Register a host by associating it with a factory(funcref)
function! remote#host#Register(name, factory)
  let s:hosts[a:name] = {'factory': a:factory, 'channel': 0, 'initialized': 0}
  if type(a:factory) == type(1) && a:factory
    " Passed a channel directly
    let s:hosts[a:name].channel = a:factory
  endif
endfunction


" Register a clone to an existing host. The new host will use the same factory
" as `source`, but it will run as a different process. This can be used by
" plugins that should run isolated from other plugins created for the same host
" type
function! remote#host#RegisterClone(name, orig_name)
  if !has_key(s:hosts, a:orig_name)
    throw 'No host named "'.a:orig_name.'" is registered'
  endif
  let Factory = s:hosts[a:orig_name].factory
  let s:hosts[a:name] = {
        \ 'factory': Factory,
        \ 'channel': 0,
        \ 'initialized': 0,
        \ 'orig_name': a:orig_name
        \ }
endfunction


" Get a host channel, bootstrapping it if necessary
function! remote#host#Require(name)
  if !has_key(s:hosts, a:name)
    throw 'No host named "'.a:name.'" is registered'
  endif
  let host = s:hosts[a:name]
  if !host.channel && !host.initialized
    let host.channel = call(host.factory, [a:name])
    let host.initialized = 1
  endif
  return host.channel
endfunction


function! remote#host#IsRunning(name)
  if !has_key(s:hosts, a:name)
    throw 'No host named "'.a:name.'" is registered'
  endif
  return s:hosts[a:name].channel != 0
endfunction


" Example of registering a Python plugin with two commands(one async), one
" autocmd(async) and one function(sync):
"
" let s:plugin_path = expand('<sfile>:p:h').'/nvim_plugin.py'
" call remote#host#RegisterPlugin('python', s:plugin_path, [
"   \ {'type': 'command', 'name': 'PyCmd', 'sync': 1, 'opts': {}},
"   \ {'type': 'command', 'name': 'PyAsyncCmd', 'sync': 0, 'opts': {'eval': 'cursor()'}},
"   \ {'type': 'autocmd', 'name': 'BufEnter', 'sync': 0, 'opts': {'eval': 'expand("<afile>")'}},
"   \ {'type': 'function', 'name': 'PyFunc', 'sync': 1, 'opts': {}}
"   \ ])
"
" The third item in a declaration is a boolean: non zero means the command,
" autocommand or function will be executed synchronously with rpcrequest.
function! remote#host#RegisterPlugin(host, path, specs)
  let plugins = s:PluginsForHost(a:host)

  for plugin in plugins
    if plugin.path == a:path
      throw 'Plugin "'.a:path.'" is already registered'
    endif
  endfor

  if remote#host#IsRunning(a:host)
    " For now we won't allow registration of plugins when the host is already
    " running.
    throw 'Host "'.a:host.'" is already running'
  endif

  for spec in a:specs
    let type = spec.type
    let name = spec.name
    let sync = spec.sync
    let opts = spec.opts
    let rpc_method = a:path
    if type == 'command'
      let rpc_method .= ':command:'.name
      call remote#define#CommandOnHost(a:host, rpc_method, sync, name, opts)
    elseif type == 'autocmd'
      " Since multiple handlers can be attached to the same autocmd event by a
      " single plugin, we need a way to uniquely identify the rpc method to
      " call.  The solution is to append the autocmd pattern to the method
      " name(This still has a limit: one handler per event/pattern combo, but
      " there's no need to allow plugins define multiple handlers in that case)
      let rpc_method .= ':autocmd:'.name.':'.get(opts, 'pattern', '*')
      call remote#define#AutocmdOnHost(a:host, rpc_method, sync, name, opts)
    elseif type == 'function'
      let rpc_method .= ':function:'.name
      call remote#define#FunctionOnHost(a:host, rpc_method, sync, name, opts)
    else
      echoerr 'Invalid declaration type: '.type
    endif
  endfor

  call add(plugins, {'path': a:path, 'specs': a:specs})
endfunction


function! remote#host#LoadRemotePlugins()
  if filereadable(s:remote_plugins_manifest)
    exe 'source '.s:remote_plugins_manifest
  endif
endfunction


function! s:RegistrationCommands(host)
  " Register a temporary host clone for discovering specs
  let host_id = a:host.'-registration-clone'
  call remote#host#RegisterClone(host_id, a:host)
  let pattern = s:plugin_patterns[a:host]
  let paths = globpath(&rtp, 'rplugin/'.a:host.'/'.pattern, 0, 1)
  if len(paths) < 1
    echom "Could not find any plugins when attempting to register plugin "
          \ ."commands. See :he remote-plugin"
    return []
  endif
  for path in paths
    call remote#host#RegisterPlugin(host_id, path, [])
  endfor
  let channel = remote#host#Require(host_id)
  let lines = []
  for path in paths
    let specs = rpcrequest(channel, 'specs', path)
    if type(specs) != type([])
      " host didn't return a spec list, indicates a failure while loading a
      " plugin
      continue
    endif
    call add(lines, "call remote#host#RegisterPlugin('".a:host
          \ ."', '".path."', [")
    for spec in specs
      call add(lines, "      \\ ".string(spec).",")
    endfor
    call add(lines, "     \\ ])")
  endfor
  " Delete the temporary host clone
  call rpcstop(s:hosts[host_id].channel)
  call remove(s:hosts, host_id)
  call remove(s:plugins_for_host, host_id)
  return lines
endfunction


function! s:UpdateRemotePlugins()
  let commands = []
  let hosts = keys(s:hosts)
  for host in hosts
    if has_key(s:plugin_patterns, host)
      let commands = commands
            \ + ['" '.host.' plugins']
            \ + s:RegistrationCommands(host)
            \ + ['', '']
    endif
  endfor
  call writefile(commands, s:remote_plugins_manifest)
endfunction


command! UpdateRemotePlugins call s:UpdateRemotePlugins()


let s:plugins_for_host = {}
function! s:PluginsForHost(host)
  if !has_key(s:plugins_for_host, a:host)
    let s:plugins_for_host[a:host] = []
  end
  return s:plugins_for_host[a:host]
endfunction


" Registration of standard hosts

" Python/Python3 {{{
function! s:RequirePythonHost(name)
  let ver_name = get(s:hosts[a:name], 'orig_name', a:name)
  let ver = (ver_name ==# 'python') ? 2 : 3

  " Python host arguments
  let args = ['-c', 'import neovim; neovim.start_host()']

  " Collect registered Python plugins into args
  let python_plugins = s:PluginsForHost(a:name)
  for plugin in python_plugins
    call add(args, plugin.path)
  endfor

  let host_var = (ver == 2) ?
        \ 'python_host_prog' : 'python3_host_prog'

  " Try loading a Python host using `python_host_prog` or `python2/3`
  let python_host_prog = get(g:, host_var, 'python' .ver)
  try
    let channel_id = rpcstart(python_host_prog, args)
    if rpcrequest(channel_id, 'poll') == 'ok'
      return channel_id
    endif
  catch
  endtry

  " Failed, try a little harder to find the correct interpreter or 
  " report a friendly error to user
  let get_version =
        \ ' -c "import sys; sys.stdout.write(str(sys.version_info[0]) + '.
        \ '\".\" + str(sys.version_info[1]))"'

  let supported = (ver == 2) ?
        \ ['2.6', '2.7'] : ['3.3', '3.4', '3.5']

  " To load the Python/Python3 host a Python/Python3 executable must be
  " available
  if has_key(g:, host_var)
        \ && executable(g:[host_var])
        \ && index(supported, system(g:[host_var].get_version)) >= 0
    let python_host_prog = g:[host_var]
  elseif executable('python')
        \ && index(supported, system('python'.get_version)) >= 0
    let python_host_prog = 'python'
  elseif ver == 3 && executable('python3')
        \ && index(supported, system('python3'.get_version)) >= 0
    " In some distros, python2 is the default python command
    let python_host_prog = 'python3'
  elseif ver == 2 && executable('python2')
        \ && index(supported, system('python2'.get_version)) >= 0
    " In some distros, python3 is the default python command
    let python_host_prog = 'python2'
  else
    throw printf('No Python%d interpreter found in your $PATH.' .
      \ " Try setting 'let g:%s=/path/to/python' in your '.nvimrc'" .
      \ " or see ':help nvim-python'.", ver, host_var)
  endif

  " Make sure we pick correct Python version on path.
  let python_host_prog = exepath(python_host_prog)

  " Execute Python, import neovim and print a string. If import_result doesn't
  " matches the printed string, the user is missing the neovim module
  let import_result = system(python_host_prog .
        \ ' -c "import neovim, sys; sys.stdout.write(\"ok\")"')
  if import_result != 'ok'
    throw 'No neovim module found for ' .
          \ systemlist(python_host_prog . ' --version')[0] . '.' .
          \ " See ':help nvim-python'."
  endif

  try
    let channel_id = rpcstart(python_host_prog, args)
    if rpcrequest(channel_id, 'poll') == 'ok'
      return channel_id
    endif
  catch
  endtry
  throw 'Failed to load python host. You can try to see what happened ' .
    \ 'by starting Neovim with $NVIM_PYTHON_PYTHON_LOG and opening '.
    \ 'the generated log file. Also, the host stderr will be available '.
    \ 'in Neovim log, so it may contain useful information.'
endfunction

call remote#host#Register('python', function('s:RequirePythonHost'))
call remote#host#Register('python3', function('s:RequirePythonHost'))
" }}}
