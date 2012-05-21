ServerError = require './ServerError'
isBrowser = typeof window isnt 'undefined'
eio = require (if isBrowser then 'node_modules/engine.io-client/lib/engine.io-client' else 'engine.io-client')

class Vein
  constructor: (@options={}) ->
    if isBrowser
      @options.host ?= window.location.hostname
      @options.port ?= (if window.location.port.length > 0 then parseInt window.location.port else 80)
      @options.secure ?= (window.location.protocol is 'https:')
    @options.path ?= '/vein'
    @options.forceBust ?= true
    @options.debug ?= false
    @socket = new eio.Socket @options
    @socket.on 'open', @handleOpen
    @socket.on 'error', @handleError
    @socket.on 'message', @handleMessage
    @socket.on 'close', @handleClose
    return

  connected: false
  services: null
  cookies: {}
  _ready: []
  _close: []
  callbacks: {}
  subscribe: {}

  cookie: (key, val, expires) =>
    if typeof window isnt 'undefined' # browser
      all = ->
        out = {}
        for cookie in document.cookie.split ";"
          pair = cookie.split "="
          out[pair[0]] = pair[1]
        return out
      set = (key, val, expires) ->
        sExpires = ""
        sExpires = "; max-age=#{expires}" if typeof expires is 'number'
        sExpires = "; expires=#{expires}" if typeof expires is 'string'
        sExpires = "; expires=#{expires.toGMTString()}" if expires.toGMTString if typeof expires is 'object'
        document.cookie = "#{escape(key)}=#{escape(val)}#{sExpires}"
        return
      remove = (key) ->
        document.cookie = "#{escape(key)}=; expires=Thu, 01-Jan-1970 00:00:01 GMT; path=/"
        return
    else # node
      all = => @cookies
      set = (key, val, expires) =>
        @cookies[key] = val
        return
      remove = (key) =>
        delete @cookies[key]
        return
    return all() unless key
    return remove key if key and val is null
    return all()[key] if key and not val
    return set key, val, expires if key and val

  disconnect: -> @socket.close()
  ready: (cb) ->
    @_ready.push cb unless @connected
    cb @services if @connected
    return

  close: (cb) -> 
    @_close.push cb if @connected
    cb() unless @connected
    return

  # Event handlers
  handleOpen: =>
    @getSender('list') (services) =>
      for service in services
        @[service] = @getSender service
        @subscribe[service] = @getSubscriber service
      @services = services
      @connected = true
      cb services for cb in @_ready
      @_ready = []
    return

  handleError: (args...) =>
    console.log "Error:", args
    return

  handleMessage: (msg) =>
    console.log 'IN:', msg if @options.debug
    {id, service, args, error, cookies} = JSON.parse msg
    args = [args] unless Array.isArray args
    throw new ServerError error if error?
    @addCookies cookies if cookies?
    if id? and @callbacks[id]
      @callbacks[id] args...
    else if service? and @subscribe[service]
      fn args... for fn in @subscribe[service].listeners
    return

  handleClose: (args...) =>
    @connected = false
    cb args... for cb in @_close
    @_close = []
    return

  # Utilities
  addCookies: (cookies) =>
    existing = @cookie()
    @cookie key, val for key, val of cookies when existing[key] isnt val
    return

  getSubscriber: (service) => 
    sub = (cb) =>
      @subscribe[service].listeners.push cb
      return
    sub.listeners = []
    return sub

  getSender: (service) =>
    (args..., cb) =>
      id = @getId()
      @callbacks[id] = cb
      msg = JSON.stringify id: id, service: service, args: args, cookies: @cookie()
      console.log 'OUT:', msg if @options.debug
      @socket.send msg
      return

  getId: ->
    rand = -> (((1 + Math.random()) * 0x10000000) | 0).toString 16
    rand()+rand()+rand()

if typeof define is 'function'
  define -> Vein

window.Vein = Vein if isBrowser
module.exports = Vein