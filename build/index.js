(function() {
  'use strict';
  module.exports = function(ndx) {
    ndx.rest = {};
    return setImmediate(function() {
      var auth, deleteFn, i, len, ref, results, selectFn, table, tableName, type, upsertFn;
      ref = ndx.rest.tables || ndx.settings.REST_TABLES || ndx.settings.TABLES;
      results = [];
      for (i = 0, len = ref.length; i < len; i++) {
        table = ref[i];
        type = Object.prototype.toString.call(table);
        tableName = '';
        auth = null;
        if (type === '[object String]') {
          tableName = table;
        } else if (type === '[object Array]') {
          tableName = table[0];
          auth = table[1];
        }
        selectFn = function(req, res, next) {
          var items, where;
          if (ndx.permissions && !ndx.permissions.check('select', req.user)) {
            return next('Not permitted');
          }
          if (req.params && req.params.id) {
            where = {};
            where[ndx.settings.AUTO_ID] = req.params.id;
            items = ndx.database.select(tableName, where);
            if (items && items.length) {
              return res.json(items[0]);
            } else {
              return res.end('Nothing found');
            }
          } else {
            return res.json({
              total: ndx.database.count(tableName, req.body.where),
              page: req.body.page || 1,
              pageSize: req.body.pageSize || 0,
              items: ndx.database.select(tableName, req.body.where, req.body.page, req.body.pageSize, req.body.sort, req.body.sortDir)
            });
          }
        };
        upsertFn = function(req, res, next) {
          var op;
          op = req.params.id ? 'update' : 'insert';
          if (ndx.permissions && !ndx.permissions.check(op, req.user)) {
            return next('Not permitted');
          }
          if (req.params.id) {
            req.body[ndx.settings.AUTO_ID] = req.params.id;
          }
          ndx.database.upsert(tableName, req.body);
          return res.end('OK');
        };
        deleteFn = function(req, res, next) {
          if (ndx.permissions && !ndx.permissions.check('delete', req.user)) {
            return next('Not permitted');
          }
          if (req.params.id) {
            return ndx.database["delete"](tableName, req.params.id);
          }
        };
        ndx.app.get(["/api/" + tableName, "/api/" + tableName + "/:id"], ndx.authenticate(auth), selectFn);
        ndx.app.post("/api/" + tableName + "/search", ndx.authenticate(auth), selectFn);
        ndx.app.post(["/api/" + tableName, "/api/" + tableName + "/:id"], ndx.authenticate(auth), upsertFn);
        ndx.app.put(["/api/" + tableName, "/api/" + tableName + "/:id"], ndx.authenticate(auth), upsertFn);
        results.push(ndx.app["delete"]("/api/" + tableName + "/:id", ndx.authenticate(auth), deleteFn));
      }
      return results;
    });
  };

}).call(this);

//# sourceMappingURL=index.js.map
