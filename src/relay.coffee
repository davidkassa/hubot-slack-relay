{EventEmitter} = require 'events'
S = require 'string'
Log            = require 'log'
RemoteSlack = require './remote-slack'

class Relay extends EventEmitter

  constructor: (@localRoom, @remote, @remoteRoom) ->
    @logger         = new Log process.env.SLACK_LOG_LEVEL or 'info'
    if @remote then @remote.on 'remote.error', @RemoteError
    'constructor'

  RemoteError:  (error) =>
    if error.msg is 'invalid channel id'
      @emit 'invalidChannel', @

  toString: () ->
    t = S(@remote.token).padLeft(5)
    token = S(S('*').repeat(5) + S(t.substr(t.length - 5)))
    local = S(@localRoom + ',').padRight(20)
    remote = S(@remoteRoom + ',').padRight(20)
    'local-channel: ' + local + ' remote-channel: ' + remote + ' remote-token: ' + token

  toJSON: () ->
    {'local-channel': @localRoom.toString(), 'remote-channel': @remoteRoom.toString(), 'remote-token': @remote.token.toString()}

  @fromJSON: (o) ->
#    obj = JSON.parse json
    remote = new RemoteSlack(o['remote-token'])
    remote.login()
    new Relay o['local-channel'], remote, o['remote-channel']


module.exports = Relay