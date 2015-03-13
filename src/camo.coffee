path = require 'path'
fs = require 'fs'
utilLib = require 'util'
request = require 'request'

util = require './util'
redisStore = require './store'

camo = (options = {}) ->

  _options = utilLib._extend
    tmpDir: path.join __dirname, '../tmp'   # Save files to the tmp directory, this will also be the nginx alias property
    expire: 86400000                        # Save the file for the expire milliseconds
    urlPrefix: '/camo'                      # The url prefix in nginx location block
    getUrl: (req) -> req.query.url          # Get url param by your way
  , options

  # Initialize mime store
  store = _options.store or redisStore(require('redis').createClient())(_options)

  {tmpDir, expire, urlPrefix} = _options

  _camo = (req, res, next) ->

    url = _options.getUrl(req)

    return next(new Error('invalid url')) unless /^(http|https):\/\//.test url

    basePath = "#{Math.floor(Date.now() / expire)}"
    _tmpDir = path.join tmpDir, basePath

    fs.mkdirSync _tmpDir unless fs.existsSync _tmpDir

    baseName = "#{util.md5(url)}#{path.extname(url)}"
    filePath = path.join _tmpDir, baseName
    redirectPath = path.join urlPrefix, basePath, baseName

    fs.exists filePath, (exists) ->
      if exists
        store.getMime baseName, (err, mime) ->
          res.set 'Content-Type', mime if mime
          res.set 'X-Accel-Redirect', redirectPath
          res.end()
      else
        file = fs.createWriteStream filePath
        mime = null

        _errHandler = (err) ->
          file.close()
          fs.unlink filePath
          next err

        request.get url

        .on 'response', (_res) ->

          if _res.statusCode is 200

            if _res.headers?['content-type']
              mime = _res.headers['content-type']
              store.setMime baseName, mime, ->

            file.on 'finish', ->
              file.close()
              res.set 'Content-Type', mime if mime
              res.set 'X-Accel-Redirect', redirectPath
              res.end()
            _res.pipe file

          else _errHandler(new Error('request failed'))

        .on 'error', _errHandler

camo.util = util
camo.redisStore = redisStore

module.exports = camo
