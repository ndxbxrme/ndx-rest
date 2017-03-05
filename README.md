# ndx-rest
### automatically generates a REST API from your [ndx-framework](https://github.com/ndxbxrme/ndx-framework) database
install with  
`npm install --save ndx-rest`  
by default all routes require a logged-in user integrates into [ndx-permissions](https://github.com/ndxbxrme/ndx-permissions) and [ndx-user-roles](https://github.com/ndxbxrme/ndx-user-roles) to further enhance security  
## what it does  
ndx-rest generates these routes for each table in your database  

|method |route |description |
|-------|------|------------|
| GET | `/api/TABLE_NAME` | returns a list of items |
| GET | `/api/TABLE_NAME/ID` | returns the item for that ID |
| POST | `/api/TABLE_NAME/search` | returns a list of matching items, eg `{where:{_id:'we233rsert'},page:1,pageSize:10,sort:'name',sortDir:'DESC'}` |
| POST/PUT | `/api/TABLE_NAME` | inserts an item into the database |
| POST/PUT | `/api/TABLE_NAME/ID` | updates and item in the database |
| DELETE | `/api/TABLE_NAME/ID` | deletes an item from the database |
