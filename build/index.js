(function() {
  'use strict';
  var async;

  async = require('async');

  module.exports = function(ndx) {
    var asyncCallback, callbacks;
    ndx.settings.SOFT_DELETE = ndx.settings.SOFT_DELETE || process.env.SOFT_DELETE;
    ndx.rest = {
      on: function(name, callback) {
        callbacks[name].push(callback);
        return this;
      },
      off: function(name, callback) {
        callbacks[name].splice(callbacks[name].indexOf(callback), 1);
        return this;
      }
    };
    callbacks = {
      update: [],
      insert: [],
      "delete": []
    };
    asyncCallback = function(name, obj, cb) {
      var truth;
      truth = false;
      if (callbacks[name] && callbacks[name].length) {
        return async.eachSeries(callbacks[name], function(cbitem, callback) {
          if (!truth) {
            return cbitem(obj, function(result) {
              truth = truth || result;
              return callback();
            });
          } else {
            return callback();
          }
        }, function() {
          return typeof cb === "function" ? cb(truth) : void 0;
        });
      } else {
        return typeof cb === "function" ? cb(true) : void 0;
      }
    };
    return setImmediate(function() {
      var auth, deleteFn, endpoints, i, len, ref, restSockets, results, selectFn, table, tableName, type, upsertFn;
      endpoints = ndx.rest.tables || ndx.settings.REST_TABLES || ndx.settings.TABLES;
      if (ndx.socket && ndx.database) {
        restSockets = [];
        ndx.socket.on('connection', function(socket) {
          socket.on('rest', function(data) {
            if (restSockets.indexOf(socket) === -1) {
              socket.rest = true;
              return restSockets.push(socket);
            }
          });
          return socket.on('user', function(data) {
            socket.user = data;
            return ndx.auth && ndx.auth.extendUser(socket.user);
          });
        });
        ndx.socket.on('disconnect', function(socket) {
          if (socket.rest) {
            return restSockets.splice(restSockets.indexOf(socket), 1);
          }
        });
        ndx.database.on('update', function(args, cb) {
          if (endpoints.indexOf(args.table) !== -1) {
            async.each(restSockets, function(restSocket, callback) {
              args.user = restSocket.user;
              return asyncCallback('update', args, function(result) {
                if (!result) {
                  return callback();
                }
                restSocket.emit('update', {
                  table: args.table,
                  id: args.id
                });
                return callback();
              });
            });
            return cb();
          }
        });
        ndx.database.on('insert', function(args, cb) {
          if (endpoints.indexOf(args.table) !== -1) {
            async.each(restSockets, function(restSocket, callback) {
              args.user = restSocket.user;
              return asyncCallback('insert', args, function(result) {
                if (!result) {
                  return callback();
                }
                restSocket.emit('insert', {
                  table: args.table,
                  id: args.id
                });
                return callback();
              });
            });
            return cb();
          }
        });
        ndx.database.on('delete', function(args, cb) {
          if (endpoints.indexOf(args.table) !== -1) {
            async.each(restSockets, function(restSocket, callback) {
              args.user = restSocket.user;
              return asyncCallback('delete', args, function(result) {
                if (!result) {
                  return callback();
                }
                restSocket.emit('delete', {
                  table: args.table,
                  id: args.id
                });
                return callback();
              });
            });
            return cb();
          }
        });
      }
      ndx.app.get('/rest/endpoints', function(req, res, next) {
        var endpoint, i, len;
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
            if (req.params && req.params.id) {
              where = {};
              if (req.params.id.indexOf('{') === 0) {
                where = JSON.parse(req.params.id);
              } else {
                where[ndx.settings.AUTO_ID] = req.params.id;
              }
              if (ndx.settings.SOFT_DELETE) {
                where.deleted = null;
              }
              return ndx.database.select(tableName, {
                where: where
              }, function(items) {
                if (items && items.length) {
                  return res.json(items[0]);
                } else {
                  return res.json({});
                }
              });
            } else {
              req.body.where = req.body.where || {};
              if (ndx.settings.SOFT_DELETE) {
                req.body.where.deleted = null;
              }
              return ndx.database.select(tableName, req.body, function(items, total) {
                return res.json({
                  total: total,
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
            var where;
            if (req.params.id) {
              where = {};
              where[ndx.settings.AUTO_ID] = req.params.id;
              if (ndx.settings.SOFT_DELETE) {
                ndx.database.update(tableName, {
                  deleted: true
                }, where);
              } else {
                ndx.database["delete"](tableName, where);
              }
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
