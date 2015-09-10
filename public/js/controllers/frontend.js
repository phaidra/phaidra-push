var app = angular.module('frontendApp', ['ngRoute', 'actionControllers' ,'ngAnimate', 'ngSanitize', 'mm.foundation', 'ajoslin.promise-tracker', 'pasvaz.bindonce', 'frontendService', 'dataService']);

app.factory('pT', function (promiseTracker) {
  return promiseTracker();
});

app.run(function($rootScope, pT) {
    $rootScope.spinnerOpts = {
      lines: 8 // The number of lines to draw
    , length: 0 // The length of each line
    , width: 14 // The line thickness
    , radius: 15 // The radius of the inner circle
    , scale: 0.75 // Scales overall size of the spinner
    , corners: 1 // Corner roundness (0..1)
    , color: '#fff' // #rgb or #rrggbb or array of colors
    , opacity: 0 // Opacity of the lines
    , rotate: 0 // The rotation offset
    , direction: 1 // 1: clockwise, -1: counterclockwise
    , speed: 1 // Rounds per second
    , trail: 42 // Afterglow percentage
    , fps: 20 // Frames per second when using setTimeout() as a fallback for CSS
    , zIndex: 2e9 // The z-index (defaults to 2000000000)    
    , top: '50%' // Top position relative to parent
    , left: '50%' // Left position relative to parent
    , shadow: false // Whether to render a shadow
    , hwaccel: true // Whether to use hardware acceleration
    , position: 'relative' // Element positioning
  }

  $rootScope.spinner = new Spinner($rootScope.spinnerOpts);

  // we will use this to track running ajax requests to show spinner
  //$scope.pt = promiseTracker.register('main');
  $rootScope.$watch(pT.active, function (isActive) {
    if(isActive){
      $rootScope.spinner.spin(jQuery('#spin').get(0));
    }else{
      $rootScope.spinner.stop();
    }
  });

})

app.config(['$routeProvider',
  function($routeProvider) {
    $routeProvider.
      when('/delete/:pid', {
        templateUrl: 'partials/delete.html',
        controller: 'DeleteCtrl'
      }).
      when('/delete_selection/', {
        templateUrl: 'partials/delete_selection.html',
        controller: 'DeleteCtrl'
      }).
      when('/push/:pid', {
        templateUrl: 'partials/push.html',
        controller: 'PushCtrl'
      }).
      when('/push/', {
        templateUrl: 'partials/push.html',
        controller: 'PushCtrl'
      }).
      otherwise({              
        templateUrl: 'partials/list.html',
        controller: 'ListCtrl'
      });
  }]
);

var actionControllers = angular.module('actionControllers', []);

actionControllers.controller('DeleteCtrl', function($scope, $routeParams, DataService, FrontendService, pT) {

    $scope.pid = $routeParams.pid;
    $scope.agreed = false;
    $scope.alerts = [];
    $scope.success = false;
    $scope.progress_message = '';

    $scope.initdata = '';
    $scope.phaidratemp_baseurl = '';

    $scope.init = function () {
      $scope.initdata = DataService.getInitData();
      $scope.phaidratemp_baseurl = $scope.initdata.phaidratemp_baseurl;
    };

    $scope.getSelection = function(){
      return FrontendService.getSelection();
    };

    $scope.closeAlert = function(index) {
      $scope.alerts.splice(index, 1);
    };
  
    $scope.startDelete = function(pids) {
    
      var stop = false;
      for (var i = 0; i < pids.length; i++) {
        if(stop){
          break;
        }
        $scope.progress_message = "Deleting object " + pids[i];        
        var promise = FrontendService.deleteObject(pids[i]);
        pT.addPromise(promise);
        promise.then(
          function(response) {
            //$scope.alerts = response.data.alerts;  
            FrontendService.removeFromSelection(pids[i]);  
            $scope.success = true;
          }
          ,function(response) {          
            if(response.data){
              if(response.data.alerts){
                $scope.alerts = response.data.alerts;
                stop = true;
              }
            }
          }
        );
      }
      $scope.progress_message = '';
    };

    $scope.init();
});

actionControllers.controller('PushCtrl', ['$scope', '$routeParams',
  function($scope, $routeParams) {
    $scope.pid = $routeParams.pid;
  }]
);

actionControllers.controller('ListCtrl', function($rootScope, $scope, $window, $modal, $log, FrontendService, DataService, pT) {
  
  $scope.alerts = {
    "phaidra-temp": [],
    "phaidra": []
  };

  $scope.initdata = '';
  $scope.current_user = '';

  $scope.objects = {
    "phaidra-temp": [],
    "phaidra": []
  };

  $scope.paging = {
    "phaidra-temp": {
      "query": '',
      "totalItems": 0,
      "currentPage": 1,
      "maxSize": 10,
      "from": 1,
      "limit": 10,
      "sort": 'fgs.createdDate,STRING',
      "reverse": 0
    },
    "phaidra": {
      "query": '',
      "totalItems": 0,
      "currentPage": 1,
      "maxSize": 10,
      "from": 1,
      "limit": 10,
      "sort": 'fgs.createdDate,STRING',
      "reverse": 0
    }
  };
  
  $rootScope.baseurls = {
    'phaidra-temp': '',
    'phaidra': ''
  }

  $scope.init = function () {

    $scope.baseurl = $('head base').attr('href');
    $scope.initdata = DataService.getInitData();
    $scope.current_user = $scope.initdata.current_user;
    $scope.baseurls['phaidra-temp'] = $scope.initdata.phaidratemp_baseurl;
    $scope.baseurls['phaidra'] = $scope.initdata.phaidra_baseurl;    
    if(!($scope.current_user)){
      $scope.signin_open();
    }else{
      $scope.search('phaidra-temp');
      $scope.search('phaidra');
    }
  };

  $scope.isSelected = function(pid){
    return FrontendService.isSelected(pid);
  }

  $scope.toggleSelected = function(pid){
    FrontendService.toggleSelected(pid);  
  }

  $scope.getSelection = function(){
    return FrontendService.getSelection();
  };

  $scope.resetSelection = function(){
    return FrontendService.setSelection([]);
  };

  $scope.selectAll = function(){

    var paging = {
      "query": $scope.paging['phaidra-temp'].query,
      "totalItems": 0,
      "currentPage": 1,
      "maxSize": 10,
      "from": 1,
      "limit": 0,
      "sort": 'PIDNum,INT',
      "reverse": 0,
      "fields": ['PID']
    }

    var promise = FrontendService.search('phaidra-temp', paging);      
    pT.addPromise(promise);
    promise.then(
      function(response) { 
        $scope.alerts['phaidra-temp'] = response.data.alerts;     
        var a = [];
        for (var i = 0; i < response.data.objects.length; i++) {
            a.push(response.data.objects[i].PID);
        }
        FrontendService.setSelection(a);
      }        
      ,function(response) {
          if(response.data){
            if(response.data.alerts){
              $scope.alerts['phaidra-temp'] = response.data.alerts;
            }
          }
      }
    );

    
  };

  $scope.closeAlert = function(index, instance) {
    $scope.alerts[instance].splice(index, 1);
  };

  $scope.signin_open = function () {
    var modalInstance = $modal.open({
      templateUrl: $('head base').attr('href')+'partials/modals/loginform.html',
      controller: SigninModalCtrl
    });
  };

  $scope.setPage = function (instance, page) {
      
    if(page == 1){
      $scope.paging[instance].from = 1;
    }else{        
      $scope.paging[instance].from = (page-1)*$scope.paging[instance].limit+1;
    }

    $scope.search(instance);    
    $scope.currentPage = page;
  };

  $scope.setSort = function(instance, sort){
    $scope.paging[instance].sort = sort;
    if($scope.paging[instance].reverse == 0){
      $scope.paging[instance].reverse = 1;
    }else{
      $scope.paging[instance].reverse = 0;
    }
    $scope.search(instance);
  }

  $scope.querySearch = function(instance){
    $scope.paging[instance].sort = "uw.general.title,SCORE";
    $scope.search(instance);
  }

  $scope.search = function(instance) {

    var promise = FrontendService.search(instance, $scope.paging[instance]);      
    pT.addPromise(promise);
    promise.then(
      function(response) { 
        $scope.alerts[instance] = response.data.alerts;        
        $scope.objects[instance] = response.data.objects;        
        $scope.paging[instance].totalItems = response.data.hits;      
      }        
      ,function(response) {
          if(response.data){
            if(response.data.alerts){
              $scope.alerts[instance] = response.data.alerts;
            }
          }
      }
    );
  };

  $scope.searchHitEnter = function(keyEvent, instance) {
    if (keyEvent.which === 13){
      $scope.querySearch(instance);
    }
  };

  $scope.setLang = function(langKey) {
    $translate.use(langKey);
  };

});

var SigninModalCtrl = function ($scope, $modalInstance, FrontendService, pT) {

  $scope.user = {username: '', password: ''};
  $scope.alerts = [];

  $scope.baseurl = $('head base').attr('href');

  $scope.closeAlert = function(index) {
      $scope.alerts.splice(index, 1);
    };

    $scope.hitEnterSignin = function(evt){
      if(angular.equals(evt.keyCode,13)
          && !(angular.equals($scope.user.username,null) || angular.equals($scope.user.username,''))
          && !(angular.equals($scope.user.password,null) || angular.equals($scope.user.password,''))
          )
      $scope.signin();
    };

  $scope.signin = function () {

    $scope.form_disabled = true;

    var promise = FrontendService.signin($scope.user.username, $scope.user.password);
      pT.addPromise(promise);
      promise.then(
        function(response) {
          $scope.alerts = response.data.alerts;
          $modalInstance.close();
          var red = $('#signin').attr('data-redirect');
          if(red){
            window.location = red;
          }else{
            window.location = $scope.baseurl;
          }
        }
        ,function(response) {
            $scope.alerts = response.data.alerts;
          }
        );
    return;

  };

  $scope.cancel = function () {
    $modalInstance.dismiss('cancel');
  };
};

String.prototype.capitalizeFirstLetter = function() {
    return this.charAt(0).toUpperCase() + this.slice(1);
}