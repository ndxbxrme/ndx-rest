(function() {
  'use strict';
  var async;

  async = require('async');

  module.exports = function(ndx) {
    ndx.rest = {};
    return setImmediate(function() {
      var auth, deleteFn, i, len, ref, restSockets, results, selectFn, table, tableName, type, upsertFn;
      if (ndx.socket && ndx.database) {
        restSockets = [];
        ndx.socket.on('connection', function(socket) {
          return socket.on('rest', function(data) {
            socket.rest = true;
            return restSockets.push(socket);
          });
        });
        ndx.socket.on('disconnect', function(socket) {
          if (socket.rest) {
            return restSockets.splice(restSockets.indexOf(socket), 1);
          }
        });
        ndx.database.on('update', function(args) {
          return async.each(restSockets, function(restSocket, callback) {
            restSocket.emit('update', {
              table: args.table
            });
            return callback();
          });
        });
        ndx.database.on('insert', function(args) {
          return async.each(restSockets, function(restSocket, callback) {
            restSocket.emit('insert', {
              table: args.table
            });
            return callback();
          });
        });
        ndx.database.on('delete', function(args) {
          return async.each(restSockets, function(restSocket, callback) {
            restSocket.emit('delete', {
              table: args.table
            });
            return callback();
          });
        });
      }
      ndx.app.get('/rest/endpoints', function(req, res, next) {
        var endpoint, endpoints, i, len;
        endpoints = ndx.rest.tables || ndx.settings.REST_TABLES || ndx.settings.TABLES;
        if (endpoints && endpoints.length && Object.prototype.toString.call(endpoints[0]) === '[object Array]') {
          for (i = 0, len = endpoints.length; i < len; i++) {
            endpoint = endpoints[i];
            endpoint = endpoint[0];
          }
        }
        return res.json({
          autoId: ndx.settings.AUTO_ID,
          endpoints: endpoints
        });
      });
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
        selectFn = function(tableName) {
          return function(req, res, next) {
            var where;
            if (ndx.permissions && !ndx.permissions.check('select', ndx.user)) {
              return next('Not permitted');
            }
            if (req.params && req.params.id) {
              where = {};
              where[ndx.settings.AUTO_ID] = req.params.id;
              return ndx.database.select(tableName, {
                where: where
              }, function(items) {
                if (items && items.length) {
                  return res.json(items[0]);
                } else {
                  return next('Nothing found');
                }
              });
            } else {
              return ndx.database.select(tableName, req.body, function(items) {
                return res.json({
                  total: ndx.database.count(tableName, req.body.where),
                  page: req.body.page || 1,
                  pageSize: req.body.pageSize || 0,
                  items: items
                });
              });
            }
          };
        };
        upsertFn = function(tableName) {
          return function(req, res, next) {
            var op, where;
            op = req.params.id ? 'update' : 'insert';
            if (ndx.permissions && !ndx.permissions.check(op, ndx.user)) {
              return next('Not permitted');
            }
            where = {};
            if (req.params.id) {
              where[ndx.settings.AUTO_ID] = req.params.id;
            }
            ndx.database.upsert(tableName, req.body, where);
            return res.end('OK');
          };
        };
        deleteFn = function(tableName) {
          return function(req, res, next) {
            if (ndx.permissions && !ndx.permissions.check('delete', ndx.user)) {
              return next('Not permitted');
            }
            if (req.params.id) {
              ndx.database["delete"](tableName, req.params.id);
            }
            return res.end('OK');
          };
        };
        ndx.app.get(["/api/" + tableName, "/api/" + tableName + "/:id"], ndx.authenticate(auth), selectFn(tableName));
        ndx.app.post("/api/" + tableName + "/search", ndx.authenticate(auth), selectFn(tableName));
        ndx.app.post(["/api/" + tableName, "/api/" + tableName + "/:id"], ndx.authenticate(auth), upsertFn(tableName));
        ndx.app.put(["/api/" + tableName, "/api/" + tableName + "/:id"], ndx.authenticate(auth), upsertFn(tableName));
        results.push(ndx.app["delete"]("/api/" + tableName + "/:id", ndx.authenticate(auth), deleteFn(tableName)));
      }
      return results;
    });
  };

}).call(this);

//# sourceMappingURL=index.js.map
