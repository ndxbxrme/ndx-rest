'use strict'

async = require 'async'

module.exports = (ndx) ->
  ndx.settings.SOFT_DELETE = ndx.settings.SOFT_DELETE or process.env.SOFT_DELETE
  ndx.rest =
    on: (name, callback) ->
      callbacks[name].push callback
      @
    off: (name, callback) ->
      callbacks[name].splice callbacks[name].indexOf(callback), 1
      @
  callbacks =
    update: []
    insert: []
    delete: []
  asyncCallback = (name, obj, cb) ->
    truth = false
    if callbacks[name] and callbacks[name].length
      async.eachSeries callbacks[name], (cbitem, callback) ->
        if not truth
          cbitem obj, (result) ->
            truth = truth or result
            callback()
        else
          callback()
      , ->
        cb? truth
    else
      cb? true
  setImmediate ->
    endpoints = ndx.rest.tables or ndx.settings.REST_TABLES or ndx.settings.TABLES
    if ndx.socket and ndx.database
      restSockets = []
      ndx.socket.on 'connection', (socket) ->
        socket.on 'rest', (data) ->
          if restSockets.indexOf(socket) is -1
            socket.rest = true
            restSockets.push socket
        socket.on 'user', (data) ->
          socket.user = data
          ndx.auth and ndx.auth.extendUser socket.user
      ndx.socket.on 'disconnect', (socket) ->
        if socket.rest
          restSockets.splice restSockets.indexOf(socket), 1
      ndx.database.on 'update', (args, cb) ->
        if endpoints.indexOf(args.table) isnt -1
          async.each restSockets, (restSocket, callback) ->
            args.user = restSocket.user
            asyncCallback 'update', args
            , (result) ->
              if not result
                return callback()
              restSocket.emit 'update', 
                table: args.table
                id: args.id
              callback()
          cb()
      ndx.database.on 'insert', (args, cb) ->
        if endpoints.indexOf(args.table) isnt -1
          async.each restSockets, (restSocket, callback) ->
            args.user = restSocket.user
            asyncCallback 'insert', args
            , (result) ->
              if not result
                return callback()
              restSocket.emit 'insert', 
                table: args.table
                id: args.id
              callback()
          cb()
      ndx.database.on 'delete', (args, cb) ->
        if endpoints.indexOf(args.table) isnt -1
          async.each restSockets, (restSocket, callback) ->
            args.user = restSocket.user
            asyncCallback 'delete', args
            , (result) ->
              if not result
                return callback()
              restSocket.emit 'delete', 
                table: args.table
                id: args.id
              callback()
          cb()
    
    ndx.app.get '/rest/endpoints', (req, res, next) ->
      if endpoints and endpoints.length and Object.prototype.toString.call(endpoints[0]) is '[object Array]'
        for endpoint in endpoints
          endpoint = endpoint[0]
      res.json 
        autoId: ndx.settings.AUTO_ID
        endpoints: endpoints
    for table in ndx.rest.tables or ndx.settings.REST_TABLES or ndx.settings.TABLES
      type = Object.prototype.toString.call table
      tableName = ''
      auth = null
      if type is '[object String]'
        tableName = table
      else if type is '[object Array]'
        tableName = table[0]
        auth = table[1]
      selectFn = (tableName) ->
        (req, res, next) ->
          if req.params and req.params.id
            where = {}
            if req.params.id.indexOf('{') is 0
              where = JSON.parse req.params.id
            else
              where[ndx.settings.AUTO_ID] = req.params.id
            if ndx.settings.SOFT_DELETE
              where.deleted = null
            ndx.database.select tableName, 
              where: where
            , (items) ->
              if items and items.length
                res.json items[0]
              else
                res.json {}
          else
            req.body.where = req.body.where or {}
            if ndx.settings.SOFT_DELETE and not req.body.where.deleted
              req.body.where.deleted = null
            ndx.database.select tableName, req.body, (items, total) ->
              res.json
                total: total
                page: req.body.page or 1
                pageSize: req.body.pageSize or 0
                items: items
      upsertFn = (tableName) ->
        (req, res, next) ->
          console.log 'upsert', req.params.id
          op = if req.params.id then 'update' else 'insert'
          where = {}
          if req.params.id
            where[ndx.settings.AUTO_ID] = req.params.id
          ndx.database.upsert tableName, req.body, where, (err, r) ->
            res.json(err or r)
      deleteFn = (tableName) ->
        (req, res, next) ->
          if req.params.id
            where = {}
            where[ndx.settings.AUTO_ID] = req.params.id
            if ndx.settings.SOFT_DELETE
              ndx.database.update tableName, 
                deleted:
                  by:ndx.user[ndx.settings.AUTO_ID]
                  at:new Date().valueOf()
              , where
            else
              ndx.database.delete tableName, where
          res.end 'OK'
      ndx.app.get ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), selectFn(tableName)
      ndx.app.post "/api/#{tableName}/search", ndx.authenticate(auth), selectFn(tableName)
      ndx.app.post ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
      ndx.app.put ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
      ndx.app.delete "/api/#{tableName}/:id", ndx.authenticate(auth), deleteFn(tableName)
        
      
        