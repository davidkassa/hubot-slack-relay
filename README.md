
# Hubot Slack Relay

A script to relay messages from a local channel to a remote channel on a separate slack server without an account. This script is designed
specifically for use with Hubot and the Slack adapter.

## Features

* Multiple local channels can relay to multiple remote channels
* No need for additional bots
* Accounts not required on each slack server

## Installation

`npm install hubot-slack-relay`

Then add `"hubot-slack-relay"` to `external-scripts.json`

## Commands

### Adding Relays

Adds a relay from the local channel to the remote channel. The remote token will be the same token as the remote HUBOT\_SLACK_TOKEN.

*NOTE:* Tokens are private and this should be setup via Direct Messaging.

`hubot relay add <local-channel> <remote-channel> <remote-token>`

### Remove Relays

Removes relays from the local channel specified. All remote channels can be removed or single remote channels can be removed one by one.

`hubot relay remove <local-channel> [<remote-channel>]`

### List Relays

Show all existing local server to remote server relay mappings and a partial token listing in case of duplicates.

`hubot relay list`

## Configuration

If you're using the [hubot-auth](https://github.com/hubot-scripts/hubot-auth/) script, you can get the user IDs required for the `HUBOT_AUTH_ADMIN` setting by calling the [users.list API method](https://api.slack.com/methods/users.list/test).

Users can be part of the admin group or a custom group named `relay` can be created.
