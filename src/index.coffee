'use strict'

module.exports = (ndx) ->
  ndx.rest = {}
  setImmediate ->
    for table in ndx.rest.tables or ndx.settings.REST_TABLES or ndx.settings.TABLES
      type = Object.prototype.toString.call table
      tableName = ''
      auth = null
      if type is '[object String]'
        tableName = table
      else if type is '[object Array]'
        tableName = table[0]
        auth = table[1]
      selectFn = (req, res, next) ->
        if ndx.permissions and not ndx.permissions.check('select', req.user)
          return next('Not permitted')
        if req.params and req.params.id
          where = {}
          where[ndx.settings.AUTO_ID] = req.params.id
          items = ndx.database.select tableName, where
          if items and items.length
            res.json items[0]
          else
            res.end 'Nothing found'
        else
          res.json
            total: ndx.database.count tableName, req.body.where
            page: req.body.page or 1
            pageSize: req.body.pageSize or 0
            items: ndx.database.select tableName, req.body.where, req.body.page, req.body.pageSize, req.body.sort, req.body.sortDir
      upsertFn = (req, res, next) ->
        op = if req.params.id then 'update' else 'insert'
        if ndx.permissions and not ndx.permissions.check(op, req.user)
          return next('Not permitted')
        if req.params.id
          req.body[ndx.settings.AUTO_ID] = req.params.id
        ndx.database.upsert tableName, req.body
        res.end 'OK'
      deleteFn = (req, res, next) ->
        if ndx.permissions and not ndx.permissions.check('delete', req.user)
          return next('Not permitted')
        if req.params.id
          ndx.database.delete tableName, req.params.id
      ndx.app.get ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), selectFn
      ndx.app.post "/api/#{tableName}/search", ndx.authenticate(auth), selectFn
      ndx.app.post ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn
      ndx.app.put ["/api/#{tableName}", "/api/#{tableName}/:id"], ndx.authenticate(auth), upsertFn
      ndx.app.delete "/api/#{tableName}/:id", ndx.authenticate(auth), deleteFn
        
      
        