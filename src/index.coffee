'use strict'

async = require 'async'

module.exports = (ndx) ->
  ndx.rest = {}
  setImmediate ->
    if ndx.socket and ndx.database
      restSockets = []
      ndx.socket.on 'connection', (socket) ->
        socket.on 'rest', (data) ->
          socket.rest = true
          restSockets.push socket
      ndx.socket.on 'disconnect', (socket) ->
        if socket.rest
          restSockets.splice restSockets.indexOf(socket), 1
      ndx.database.on 'update', (args) ->
        async.each restSockets, (restSocket, callback) ->
          restSocket.emit 'update', table:args.table
          callback()
      ndx.database.on 'insert', (args) ->
        async.each restSockets, (restSocket, callback) ->
          restSocket.emit 'insert', table:args.table
          callback()
      ndx.database.on 'delete', (args) ->
        async.each restSockets, (restSocket, callback) ->
          restSocket.emit 'delete', table:args.table
          callback()
    
    ndx.app.get '/rest/endpoints', (req, res, next) ->
      endpoints = ndx.rest.tables or ndx.settings.REST_TABLES or ndx.settings.TABLES
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
          if ndx.permissions and not ndx.permissions.check('select', req.user)
            return next('Not permitted')
          if req.params and req.params.id
            where = {}
            where[ndx.settings.AUTO_ID] = req.params.id
            ndx.database.select tableName, 
              where: where
            , (items) ->
              if items and items.length
                res.json items[0]
              else
                res.end 'Nothing found'
          else
            ndx.database.select tableName, req.body, (items) ->
              res.json
                total: ndx.database.count tableName, req.body.where
                page: req.body.page or 1
                pageSize: req.body.pageSize or 0
                items: items
      upsertFn = (tableName) ->
        (req, res, next) ->
          op = if req.params.id then 'update' else 'insert'
          if ndx.permissions and not ndx.permissions.check(op, req.user)
            return next('Not permitted')
          where = {}
          if req.params.id
            where[ndx.settings.AUTO_ID] = req.params.id
          ndx.database.upsert tableName, req.body, where
          res.end 'OK'
      deleteFn = (tableName) ->
        (req, res, next) ->
          if ndx.permissions and not ndx.permissions.check('delete', req.user)
            return next('Not permitted')
          if req.params.id
            ndx.database.delete tableName, req.params.id
          res.end 'OK'
      ndx.app.get ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), selectFn(tableName)
      ndx.app.post "/api/#{tableName}/search", ndx.authenticate(auth), selectFn(tableName)
      ndx.app.post ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
      ndx.app.put ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
      ndx.app.delete "/api/#{tableName}/:id", ndx.authenticate(auth), deleteFn(tableName)
        
      
        