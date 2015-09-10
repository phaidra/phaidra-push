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
        method  : 'GET',
        url     : $('head base').attr('href') + 'delete/' + pid
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

    isSelected: function(pid) {
      return selection.indexOf(pid) > -1;
    },

    toggleSelected: function(pid) {
      var idx = selection.indexOf(pid);
      if(idx >= 0){
        selection.splice(idx, 1);
      }else{
        selection.push(pid);
      }
    },

    addToSelection: function(pid) {
      selection.push(pid);
    },

    removeFromSelection: function(pid) {  
      selection.splice(selection.indexOf(pid), 1);
    },

    setConfig: function(cfg){
      config = cfg;
    },

    getConfig: function(){
      return config;
    },


/*
    getObjects: function(temp) {

         return $http({
             method  : 'GET',
             url     : $('head base').attr('href') + 'objects',            
             params  : { temp: temp ? 1 : 0 }
         });
    },
*/
  }
});
