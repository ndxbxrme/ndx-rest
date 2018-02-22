'use strict'

async = require 'async'
objtrans = require 'objtrans'

module.exports = (ndx) ->
  ndx.settings.SOFT_DELETE = ndx.settings.SOFT_DELETE or process.env.SOFT_DELETE
  hasDeleted = (obj) ->
    truth = false
    if typeof(obj) is 'object'
      for key of obj
        if key is 'deleted'
          return true
        else
          if truth = hasDeleted obj[key]
            return true
    truth
  elevateUser = (user) ->
    user.type = 'system'
    user.role = 'system'
    user.roles =
      system: true
  ndx.rest =
    on: (name, callback) ->
      callbacks[name].push callback
      @
    off: (name, callback) ->
      callbacks[name].splice callbacks[name].indexOf(callback), 1
      @
    selectTransform: (user, table, all, transforms) ->
      null
    transforms: {}
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
  transformItem = (item, user, table, all, transform) ->
    transform = transform or ndx.rest.selectTransform(user, table, all, ndx.rest.transforms)
    if transform
      objtrans item, transform
    else
      item
  transformItems = (items, user, table, all) ->
    transform = ndx.rest.selectTransform user, table, all, ndx.rest.transforms
    if transform
      for item in items
        item = transformItem item, user, table, all, transform
    else 
      items
  setImmediate ->
    endpoints = ndx.rest.tables or ndx.settings.REST_TABLES or ndx.settings.TABLES
    if ndx.rest.restrict
      for restrict of ndx.rest.restrict
        switch Object.prototype.toString.call(ndx.rest.restrict[restrict])
          when '[object Boolean]'
            if ndx.rest.restrict[restrict]
              endpoints.splice(endpoints.indexOf(restrict), 1)
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
        restrict: ndx.rest.restrict
        server: if ndx.maintenanceMode then 'maintenance' else undefined
    for table in endpoints
      type = Object.prototype.toString.call table
      tableName = ''
      auth = null
      if type is '[object String]'
        tableName = table
      else if type is '[object Array]'
        tableName = table[0]
        auth = table[1]
      ###
      if ndx.rest.restrict and ndx.rest.restrict[tableName] and Object.prototype.toString.call(ndx.rest.restrict[tableName]) is '[object Boolean]'
        continue
      hasAll = true
      if ndx.rest.restrict and ndx.rest.restrict[tableName] and ndx.rest.restrict[tableName].all
        if ndx.rest.restrict[tableName] isnt 'server'
          hasAll = false
      ###
      selectFn = (tableName, all) ->
        (req, res, next) ->
          ###
          if all and not hasAll
            return res.status(401).end 'Restricted'
          ###
          myuser = JSON.parse JSON.stringify ndx.user
          role = null
          for key of myuser.roles
            if myuser.roles[key]
              role = key
              break
          role = role or 'default'
          restrict = null
          if ndx.rest.restrict
            tableRestrict = ndx.rest.restrict[tableName] or ndx.rest.restrict.default
            if tableRestrict
              restrict = tableRestrict[role] or tableRestrict.default
          if restrict
            if all and restrict.all
              return res.json
                total: 0
                page: 1
                pageSize: 0
                items: []
            
          if req.params and req.params.id
            where = {}
            if req.params.id.indexOf('{') is 0
              where = JSON.parse req.params.id
            else
              where[ndx.settings.AUTO_ID] = req.params.id
            if ndx.settings.SOFT_DELETE and not req.body.showDeleted and not hasDeleted(where)
              where.deleted = null
            if all
              elevateUser ndx.user
            ndx.database.select tableName, 
              where: where
            , (items) ->
              if items and items.length
                res.json transformItem items[0], myuser, tableName, all
              else
                res.json {}
          else
            req.body.where = req.body.where or {}
            if ndx.settings.SOFT_DELETE and not req.body.showDeleted and not hasDeleted(req.body.where)
              req.body.where.deleted = null
            if req.body.all or all
              elevateUser ndx.user
            ndx.database.select tableName, req.body, (items, total) ->
              res.json
                total: total
                page: req.body.page or 1
                pageSize: req.body.pageSize or 0
                items: transformItems items, myuser, tableName, all
      upsertFn = (tableName) ->
        (req, res, next) ->
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
      modifiedFn = (tableName) ->
        (req, res, next) ->
          ndx.database.maxModified tableName, (maxModified) ->
            res.json
              maxModified: maxModified
      makeRoutes = (tableName, auth) ->
        ndx.app.get ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), selectFn(tableName)
        ndx.app.get "/api/#{tableName}/:id/all", ndx.authenticate(auth), selectFn(tableName, true)
        ndx.app.post "/api/#{tableName}/search", ndx.authenticate(auth), selectFn(tableName)
        ndx.app.post "/api/#{tableName}/search/all", ndx.authenticate(auth), selectFn(tableName, true)
        ndx.app.post "/api/#{tableName}/modified", ndx.authenticate(auth), modifiedFn(tableName)
        ndx.app.post ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
        ndx.app.put ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn(tableName)
        ndx.app.delete "/api/#{tableName}/:id", ndx.authenticate(auth), deleteFn(tableName)
      makeRoutes tableName, auth
        
      
        