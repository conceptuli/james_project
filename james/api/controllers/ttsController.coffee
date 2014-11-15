# TtsController
#
# @description :: Server-side logic for managing tts
# @help        :: See http://links.sailsjs.org/docs/controllers

module.exports =


  # `ttsController.create()`

  create: (req, res) ->
    request = require 'request'
    phrase = req.query.phrase
    querystring = require 'querystring'
    http = require 'http'
    console.log phrase

    extractValues = require 'extract-values'
    formData =
      MyLanguages: 'sonid9'
      MySelectedVoice: 'Graham'
      MyTextForTTS: "#{phrase}"
      SendToVaaS: ''

    options =
      headers:
        'content-type':'Content-type: application/x-www-form-urlencoded\r\n'

    module.exports = linkholder = []
    request.post
      url: 'http://www.acapela-group.com/demo-tts/DemoHTML5Form_V2.php'
      headers: options.headers
      form: formData
      , (error, response, body) ->
        body = extractValues JSON.stringify(response), "var myPhpVar = '{link}\';"
        linkholder.push body
        console.log linkholder
        res.send body
















###
    cb = (error, response, body) ->
      response = []
      if error
        console.log error
      else
      await extractValues JSON.stringify(body), "var myPhpVar = '{link}\';", defer link
      response = link
      cb JSON.stringify response###


