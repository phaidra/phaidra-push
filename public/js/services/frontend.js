angular.module('frontendService', ['Base64'])
.factory('FrontendService', function($http, Base64) {

  var selection = [];  
  var config = {};

  return {

    signin: function(username, password) {

      return $http({
        method  : 'GET',
          url     : $('head base').attr('href') + 'signin',
          headers: {'Authorization': 'Basic ' + Base64.encode(username + ':' + password)}
        });
      },

    deleteObject: function(pid) {

      return $http({
        method  : 'DELETE',
        url     : $('head base').attr('href') + 'delete/' + pid
      });
    },

    requestPush: function(objects) {

      return $http({
        method  : 'POST',
        url     : $('head base').attr('href') + 'push',
        data    : angular.toJson(objects),
        headers : {'Content-Type': 'application/json'}
      });
    },
          
    search: function(instance, paging){

      var params = {
          instance: instance, 
          q: paging.query, 
          from: paging.from, 
          limit: paging.limit, 
          sort: paging.sort, 
          reverse: paging.reverse          
      };

      if(paging['fields']){
        params['fields'] = paging['fields'];
      }

      return $http({
        method  : 'GET',
        url     : $('head base').attr('href') + 'objects',
        params  : params
      });         
    },

    setSelection: function(sel) {
      selection = sel;
    },

    getSelection: function() {
      return selection;
    },
    
    getSelectionPID: function() {
        
       var selectionPID = [];
       for (var i = 0; i < selection.length; i++) {
               selectionPID.push(selection[i].PID);
       }
       return selectionPID;
    },
    

    isSelected: function(o) {
      return this.getSelectedIdx(o) > -1;      
    },

    getSelectedIdx: function(o){
      for (var i = 0; i < selection.length; i++) {
        if(selection[i].PID == o.PID){
          return i;
        }
      }
      return -1;
    },

    toggleSelected: function(o) {
      var idx = this.getSelectedIdx(o);
      if(idx >= 0){
        selection.splice(idx, 1);
      }else{
        selection.push(o);
      }
    },

    addToSelection: function(o) {
      selection.push(o);
    },

    removeFromSelection: function(o) {  
      selection.splice(this.getSelectedIdx(o), 1);
    },

    setConfig: function(cfg){
      config = cfg;
    },

    getConfig: function(){
      return config;
    },

  }
});
