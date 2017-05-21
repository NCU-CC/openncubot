module.exports = (robot) ->
  fs = require "fs"

  get_config = (fileName, callback) ->
    fs.readFile fileName, "utf8", (err, data) ->
      jsonData = JSON.parse data
      callback jsonData

  authentication = () ->
    get_config "config.json", (config) ->
      postData = "grant_type=refresh_token&refresh_token=#{config.refresh_token}&client_id=#{config.client_id}&client_secret=#{config.client_secret}&redirect_uri=#{config.redirect_uri}"
      robot.http(config.oauth_path).header("Content-Type", "application/x-www-form-urlencoded").post("#{postData}") (err, apiRes, body) ->
        jsonData = JSON.parse body
        obj = {
          "slack_token" : process.env.HUBOT_SLACK_TOKEN,
          "oauth_path" : "#{config.oauth_path}",
          "door_path" : "#{config.door_path}",
          "client_id" : "#{config.client_id}",
          "client_secret" : "#{config.client_secret}",
          "access_token" : "#{jsonData.access_token}",
          "refresh_token" : "#{jsonData.refresh_token}",
          "redirect_uri" : "#{config.redirect_uri}"
        }
        json = JSON.stringify obj
        fs.writeFile "config.json", json, "utf8"
        setTimeout authentication, 3600000

  get_channel_info = (channel_name, is_private, slack_token, callback) ->
    if is_private
      robot.http("https://slack.com/api/groups.list?token=#{slack_token}").get() (err, res, body) ->
        jsonData = JSON.parse body
        groupArr = jsonData.groups
        for group in groupArr
          if group.name is channel_name
            callback group.id
    else
      robot.http("https://slack.com/api/channels.list?token=#{slack_token}").get() (err, res, body) ->
        jsonData = JSON.parse body
        channelArr = jsonData.channels
        for channel in channelArr
          if channel.name is channel_name
            callback channel.id

  get_entity_name = (door_ip, door_path, api_token, callback) ->
    robot.http(door_path).header('Authorization', "Bearer #{api_token}").get() (err, res, body) ->
      jsonData = JSON.parse body
      entities = jsonData.content
      for entity in entities
        if entity.ip is door_ip
          found = true
          callback entity.name
      if not found
        callback ""


  authentication()

  robot.router.post '/log/api', (req, res) ->
    application = req.body.application
    message = req.body.message

    if message is undefined
      res.send 404
    else
      get_config "log_config.json", (log_config) ->
        get_config "config.json", (config) ->
          switch application
            when "door_api"
              channel = log_config.door_api.channel
              is_private = log_config.door_api.is_private

          if channel isnt undefined
            get_channel_info channel, is_private, config.slack_token, (channel_id) ->
              robot.messageRoom channel_id, message
              res.send "send to channel #{channel} OK"

  robot.router.post '/log/entity', (req, res) ->
    status = req.body.status
    code = req.body.code
    ip = req.connection.remoteAddress

    if status is undefined
      res.send 404
    else
      get_config "log_config.json", (log_config) ->
        get_config "config.json", (config) ->
          get_entity_name ip, config.door_path, config.access_token, (entity_name) ->
            if entity_name is ""
              message = "#{ip} is not an entity, but use entity log API"
            else
              if status is "204"
                message = "Open entity #{entity_name} successfully with code #{code}"
              else if status is "404"
                message = "Fail to open entity #{entity_name} with code #{code}"
              else if status is "500"
                message = "Error in #{entity_name} or API Service with code #{code}"
              else
                message = "Get invalid status on #{entity_name} or API Service with code #{code}"
            channel = log_config.door_guard.channel
            get_channel_info channel, log_config.door_guard.is_private, config.slack_token, (channel_id) ->
              robot.messageRoom channel_id, message
              res.send "send to channel #{channel} OK"
