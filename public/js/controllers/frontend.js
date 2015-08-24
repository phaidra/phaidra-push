var app = angular.module('frontendApp', ['ngRoute', 'actionControllers' ,'ngAnimate', 'ngSanitize', 'mm.foundation', 'ajoslin.promise-tracker', 'pasvaz.bindonce', 'frontendService', 'dataService']);

app.config(['$routeProvider',
  function($routeProvider) {
    $routeProvider.
      when('/delete/:pid', {
        templateUrl: 'partials/delete.html',
        controller: 'DeleteCtrl'
      }).
      when('/push/:pid', {
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

actionControllers.controller('DeleteCtrl', ['$scope', '$routeParams', function($scope, $routeParams, FrontendService) {

    $scope.pid = $routeParams.pid;

    $scope.agreed = false;
  
    $scope.startDelete = function () {
      alert('huda');
    };

}]);

actionControllers.controller('PushCtrl', ['$scope', '$routeParams',
  function($scope, $routeParams) {
    $scope.pid = $routeParams.pid;
  }]
);

actionControllers.controller('ListCtrl', function($scope, $window, $modal, $log, FrontendService, DataService, promiseTracker) {

  // we will use this to track running ajax requests to show spinner
  //$scope.loadingTracker = promiseTracker.register('loadingTrackerFrontend');

  $scope.alerts = [];

  $scope.initdata = '';
  $scope.current_user = '';

  $scope.temp_objects = [];
  $scope.prod_objects = [];

  $scope.selection = [];  

  $scope.init = function () {

    $scope.baseurl = $('head base').attr('href');
    var initdata = DataService.getInitData();
    $scope.initdata = angular.fromJson(initdata);    
    $scope.current_user = $scope.initdata.current_user;
    $scope.phaidratemp_baseurl = $scope.initdata.phaidratemp_baseurl;
    $scope.phaidra_baseurl = $scope.initdata.phaidra_baseurl;
    if(!($scope.current_user)){
      $scope.signin_open();
    }else{
      $scope.getObjects(true);
      $scope.getObjects(false);
    }
  };

  $scope.closeAlert = function(index) {
    $scope.alerts.splice(index, 1);
  };

  $scope.signin_open = function () {
    var modalInstance = $modal.open({
      templateUrl: $('head base').attr('href')+'partials/modals/loginform.html',
      controller: SigninModalCtrl
    });
  };

  $scope.selectAll = function () {
    if($scope.allselected){
      for (var i = 0; i < $scope.temp_objects.length; i++) {
        $scope.temp_objects[i].selected = false;
      }
    }else{
      for (var i = 0; i < $scope.temp_objects.length; i++) {
        $scope.temp_objects[i].selected = true;
      }	
    }
  }

  $scope.getObjects = function(temp){
    var promise = FrontendService.getObjects(temp);
    //$scope.loadingTracker.addPromise(promise);
    promise.then(
      function(response) {
        $scope.form_disabled = false;
        $scope.alerts = response.data.alerts;
        if(temp){
          $scope.temp_objects = response.data.objects;
        }else{
          $scope.prod_objects = response.data.objects;
        }
      }
      ,function(response) {
        $scope.form_disabled = false;
        if(response.data){
          if(response.data.alerts){
            $scope.alerts = response.data.alerts;
          }
        }
      }
    );
  };


  $scope.setLang = function(langKey) {
    $translate.use(langKey);
  };

});

var SigninModalCtrl = function ($scope, $modalInstance, FrontendService, promiseTracker) {

  $scope.user = {username: '', password: ''};
  $scope.alerts = [];

  $scope.baseurl = $('head base').attr('href');

  // we will use this to track running ajax requests to show spinner
  //$scope.loadingTracker = promiseTracker('loadingTrackerFrontend');

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
      //$scope.loadingTracker.addPromise(promise);
      promise.then(
        function(response) {
          $scope.form_disabled = false;
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
          $scope.form_disabled = false;
          $scope.alerts = response.data.alerts;
            }
        );
    return;

  };

  $scope.cancel = function () {
    $modalInstance.dismiss('cancel');
  };
};
