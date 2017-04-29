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
            truth = truth and result
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
          socket.user = ndx.user
          socket.rest = true
          restSockets.push socket
      ndx.socket.on 'disconnect', (socket) ->
        if socket.rest
          restSockets.splice restSockets.indexOf(socket), 1
      ndx.database.on 'update', (args, cb) ->
        if endpoints.indexOf(args.table) isnt -1
          async.each restSockets, (restSocket, callback) ->
            asyncCallback 'update',
              args: args
              user: restSocket.user
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
            asyncCallback 'insert',
              args: args
              user: restSocket.user
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
            asyncCallback 'delete',
              args: args
              user: restSocket.user
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
          if ndx.permissions and not ndx.permissions.check('select', ndx.user)
            return next('Not permitted')
          if req.params and req.params.id
            where = {}
            if ndx.settings.SOFT_DELETE
              where.deleted = null
            where[ndx.settings.AUTO_ID] = req.params.id
            ndx.database.select tableName, 
              where: where
            , (items) ->
              if items and items.length
                res.json items[0]
              else
                next 'Nothing found'
          else
            req.body.where = req.body.where or {}
            if ndx.settings.SOFT_DELETE
              req.body.where.deleted = null
            ndx.database.select tableName, req.body, (items, total) ->
              res.json
                total: total
                page: req.body.page or 1
                pageSize: req.body.pageSize or 0
                items: items
      upsertFn = (tableName) ->
        (req, res, next) ->
          op = if req.params.id then 'update' else 'insert'
          if ndx.permissions and not ndx.permissions.check(op, ndx.user)
            return next('Not permitted')
          where = {}
          if req.params.id
            where[ndx.settings.AUTO_ID] = req.params.id
          ndx.database.upsert tableName, req.body, where
          res.end 'OK'
      deleteFn = (tableName) ->
        (req, res, next) ->
          if ndx.permissions and not ndx.permissions.check('delete', ndx.user)
            return next('Not permitted')
          if req.params.id
            where = {}
            where[ndx.settings.AUTO_ID] = req.params.id
            if ndx.settings.SOFT_DELETE
              ndx.database.update tableName, deleted:true, where
            else
              ndx.database.delete tableName, where
          res.end 'OK'
      ndx.app.get ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), selectFn(tableName)
      ndx.app.post "/api/#{tableName}/search", ndx.authenticate(auth), selectFn(tableName)
      ndx.app.post ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
      ndx.app.put ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
      ndx.app.delete "/api/#{tableName}/:id", ndx.authenticate(auth), deleteFn(tableName)
        
      
        