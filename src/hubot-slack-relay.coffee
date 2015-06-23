# Description
#   Relay helper command for Hubot
#
# Dependencies:
#   hubot-slack
#
# Commands:
#   relay add <local-channel> <remote-channel> <remote-token> - Adds a relay with a remote channel. *NOTE:* Tokens are private and this should be setup via Direct Messaging.
#   relay remove <local-channel> [<remote-channel>]- Removes a relay with a remote channel.
#   relay list - Lists all existing relays.
#   relay addignore <user> - Do not relay anything this user says, usually a bot.
#   relay removeignore <user> - Resume relaying anything the user says.
#   relay listignore - Lists all ignored users.
#
# Author:
#   davidkassa

S = require 'string'
RemoteSlack = require './remote-slack'
Relay = require './relay'

module.exports = (robot) ->

  BRAIN_KEY = 'hubot-slack-relay.storage'
  relays = []
  ignoreUsers = []

  brainLoaded = () =>
    #load brain data
    robot.logger.info 'Load Brain'
    data = (robot.brain.get BRAIN_KEY) || {}

    relays = for d in data
      relay = Relay.fromJSON d
      relay.on 'invalidChannel', invalidChannelError
      relay

    ignoreUsers = (robot.brain.get BRAIN_KEY + '.ignoreUsers') || []

  invalidChannelError = (relay) =>
    robot.logger.info 'invalidChannelError'
    remoteBot = relay.remote.client.self.name ? 'the remote bot'

    user = { room: relay.localRoom }
    robot.adapter.send user, 'Could not deliver message to  \'' + relay.remoteRoom + '\' because ' + remoteBot + ' is not in the channel.' 

  brainLoaded() #call brainLoaded directly for brains without a load event, such as jobot-brain-file or hubot-scripts/file-brain
  robot.brain.on 'loaded', brainLoaded

  saveBrain = () =>
    robot.logger.info 'Save Brain'

    #store array before saving, due to bad mergeData in brain
    temp = relays

    robot.brain.set BRAIN_KEY, relays
    robot.brain.set BRAIN_KEY + '.ignoreUsers', ignoreUsers
    robot.brain.save()

    #re-assign relays for deep copy after save
    relays = temp

  robot.respond /relay add\s+(\S+)\s+(\S+)\s+(\S+)/i, (res) =>
    robot.logger.info 'relay add ' + res.match[1] + ' ' + res.match[2] + ' ' + res.match[3]

    localRoom = S(res.match[1]).chompLeft('#').s
    remoteRoom = S(res.match[2]).chompLeft('#').s
    remoteToken = S(res.match[3]).chompLeft('#').s

    #check to make sure it doesn't exist
    if process.env.HUBOT_SLACK_TOKEN is remoteToken
      res.send 'This is the local hubot token. Please use the hubot token from the remote server.'
      return

    for relay in relays
      if relay.localRoom is localRoom and relay.remoteRoom is remoteRoom and relay.remote.token is remoteToken
        res.send 'This remote relay already exists.'
        return


    @newResponse = res
    #TODO: validate local room

    #validate token and remote room by connecting
    remote = new RemoteSlack(remoteToken)
    @newRelay = new Relay localRoom, remote, remoteRoom

    remote.on 'remote.connected', newRemoteConnected
    remote.on 'remote.error', newRemoteError

    remote.login()

  newRemoteConnected = (remote) =>
    @newRelay.remote.removeListener('remote.connected',newRemoteConnected)
    @newRelay.remote.removeListener('remote.error',newRemoteError)
    @newRelay.on 'invalidChannel', invalidChannelError

    channel = @newRelay.remote.client.getChannelByName @newRelay.remoteRoom
    remoteBot = @newRelay.remote.client.self.name ? 'the remote bot'

    if channel
      #save to brain and push onto relay
      relays.push @newRelay
      saveBrain()

      if channel.is_member
        @newResponse.send 'Successfully connected to the remote relay and channel \'' + @newRelay.remoteRoom + '\'.'
      else
        @newResponse.send 'Successfully connected to the remote relay but ' + remoteBot + ' needs to be invited to \'' + @newRelay.remoteRoom + '\'.'

    else
      @newResponse.send 'Could not find the channel \'' + @newRelay.remoteRoom + '\' on the remote relay.'


  newRemoteError = (error) =>
    @newRelay.remote.removeListener('remote.connected',newRemoteConnected)
    @newRelay.remote.removeListener('remote.error',newRemoteError)

    t = S(@newRelay.remote.token).padLeft(5)
    @newResponse.send 'Could not connect to remote relay with token \'' + S('*').repeat(t.length - 5) + S(t.substr(t.length - 5)).trim() + '\'.'

  robot.respond /relay addignore\s+(\S+)/i, (res) =>
    robot.logger.info 'relay addignore ' + res.match[1]
    ignoreUsers.push S(res.match[1]).chompLeft('@').s
    saveBrain()
    res.send 'Ignoring user \'' + res.match[1] + '\' when relaying'

  robot.respond /relay remove\s+(\S+)\s*(\S*)\s*(\S*)/i, (res) =>
    robot.logger.info 'relay remove ' + res.match[1] + ' ' + res.match[2] + ' ' + res.match[3]

    localRoom = S(res.match[1]).chompLeft('#').s
    remoteRoom = if res.match[2] then S(res.match[2]).chompLeft('#').s
    remoteToken = if res.match[3] then S(res.match[3]).chompLeft('#').s

    found = false
    if not remoteRoom
      relays = for relay in relays
        #remove if matched
        if relay.localRoom is localRoom
          found = true
          continue
        relay
      if found
        saveBrain()
        res.send 'Removed all remote relays associated with local channel \'' + localRoom + '\''

    else
      if remoteToken
        relays = for relay in relays
          #remove if matched
          t = relay.remote.token
          token = t.substr(t.length - 5)
          if relay.localRoom is localRoom and relay.remoteRoom is remoteRoom and token is remoteToken
            found = true
            continue
          relay
        if found
          saveBrain()
          res.send 'Removed remote relay - local-channel: ' + localRoom + ' remote-channel: ' + remoteRoom + ' remote-token: ' + remoteToken
      else
        matches = []
        potentialRelays = for relay in relays
          if relay.localRoom is localRoom and relay.remoteRoom is remoteRoom
            matches.push relay
            continue
          relay
        #if single, match
        if matches.length is 1
          found = true
          relays = potentialRelays
          saveBrain()
          res.send 'Removed remote relay - local-channel: ' + localRoom + ' remote-channel: ' + remoteRoom
        #if multiple, show list
        else if matches.length > 1
          found = true
          res.send '*There are multiple options for this <local-channel> <remote-channel> combination.*\nPlease include the last 5 digits of the remote token and try again.\n`relay remove <local-channel> <remote-channel> <last 5 of remote-token>`'
          res.send blockList(matches)

    if not found
      res.send 'Could not find any records matching the criteria.'

  robot.respond /relay removeignore\s+(\S+)/i, (res) =>
    robot.logger.info 'relay removeignore ' + res.match[1]
    removeUser = S(res.match[1]).chompLeft('@').s

    ignoreUsers = ignoreUsers.filter (user) -> user isnt removeUser
    saveBrain()
    res.send 'Stopped ignoring user \'' + removeUser + '\''

  robot.respond /relay list$/i, (res) =>
    robot.logger.info 'relay list'
    res.send blockList(relays)

  robot.respond /relay (listignore|ignorelist)$/i, (res) =>
    robot.logger.info 'relay listignore'
    res.send blockList(ignoreUsers)


  blockList = (collection, filter) =>
    if not collection or collection.length is 0 then return '(empty)'
    filter ?= () -> true
    list = '```'
    for item in collection when filter(item)
      list = list + item.toString() + '\n'
    list + '```'

  robot.hear /(.+)/i, (res) =>

    if res.message.user.name in ignoreUsers then return false

    for relay in relays
      if res.message.room isnt relay.localRoom then continue
      user = { room: relay.remoteRoom }
      if not relay.remote.send user, '_' + res.message.user.name + ' said:_ ' + res.match[1]
        invalidChannelError relay

  robot.enter (res) ->
    for relay in relays
      if res.message.room isnt relay.localRoom then continue
      user = { room: relay.remoteRoom }
      if not relay.remote.send user, '_' + res.message.user.name + ' has entered #' + res.message.room + '_'
        invalidChannelError relay
    
  robot.leave (res) ->
    for relay in relays
      if res.message.room isnt relay.localRoom then continue
      user = { room: relay.remoteRoom }
      if not relay.remote.send user, '_' + res.message.user.name + ' has left #' + res.message.room + '_'
        invalidChannelError relay

#  robot.catchAll (res) ->
#    robot.logger.info 'catchAll'
#    robot.emit 'slack-attachment',
#    	channel: 'other-channel'
#    	fallback: res.message
#    	content:
#    		color: "d96b38",
#    		fields: [{
#                    title: "Status Change",
#                    value: "#test"
#                }]

