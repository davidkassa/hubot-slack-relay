{EventEmitter} = require 'events'
SlackClient    = require 'slack-client'
Log            = require 'log'

class RemoteSlack extends EventEmitter
  @MAX_MESSAGE_LENGTH: 4000
  @MIN_MESSAGE_LENGTH: 1

  constructor: (token) ->
    @logger         = new Log process.env.SLACK_LOG_LEVEL or 'info'
    @token = token

    options =
      token: @token
      autoReconnect: false
      autoMark: true

    @client = new SlackClient options.token, options.autoReconnect, options.autoMark

    @client.on 'error', @.error
    @client.on 'loggedIn', @.loggedIn
    @client.on 'open', @.open


  login: =>
    @client.login()


  error: (error) =>
    return @logger.warning "Received rate limiting error #{JSON.stringify error}" if error.code == -1

    @logger.error "Received error #{JSON.stringify error}"

    @emit "remote.error", error

  loggedIn: (self, team) =>
    @logger.info "Logged in as #{self.name} of #{team.name}, but not yet connected"

  open: =>
    @logger.info 'Slack client now connected'

    @emit "remote.connected", @

  send: (envelope, messages...) ->

    if not @client.connected or not @client.authenticated then @client.reconnect()

    channel = @client.getChannelGroupOrDMByName envelope.room
    if not channel and @client.getUserByName(envelope.room)
      user_id = @client.getUserByName(envelope.room).id
      @client.openDM user_id, =>
        this.send envelope, messages...
      return

    if not channel.is_member then return false

    for msg in messages
      continue if msg.length < RemoteSlack.MIN_MESSAGE_LENGTH

      @logger.debug "Sending to #{envelope.room}: #{msg}"

      if msg.length <= RemoteSlack.MAX_MESSAGE_LENGTH
        channel.send msg

      # If message is greater than MAX_MESSAGE_LENGTH, split it into multiple messages
      else
        submessages = []

        while msg.length > 0
          if msg.length <= RemoteSlack.MAX_MESSAGE_LENGTH
            submessages.push msg
            msg = ''

          else
            # Split message at last line break, if it exists
            maxSizeChunk = msg.substring(0, RemoteSlack.MAX_MESSAGE_LENGTH)

            lastLineBreak = maxSizeChunk.lastIndexOf('\n')
            lastWordBreak = maxSizeChunk.match(/\W\w+$/)?.index

            breakIndex = if lastLineBreak > -1
              lastLineBreak
            else if lastWordBreak
              lastWordBreak
            else
              RemoteSlack.MAX_MESSAGE_LENGTH

            submessages.push msg.substring(0, breakIndex)

            # Skip char if split on line or word break
            breakIndex++ if breakIndex isnt RemoteSlack.MAX_MESSAGE_LENGTH

            msg = msg.substring(breakIndex, msg.length)

        channel.send m for m in submessages

module.exports = RemoteSlack