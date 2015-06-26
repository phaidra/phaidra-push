var app = angular.module('frontendApp', ['ngAnimate', 'ngSanitize', 'mm.foundation', 'ajoslin.promise-tracker', 'pasvaz.bindonce', 'frontendService']);


app.controller('FrontendCtrl', function($scope, $window, $modal, $log, FrontendService, promiseTracker) {

  // we will use this to track running ajax requests to show spinner
  $scope.loadingTracker = promiseTracker.register('loadingTrackerFrontend');

  $scope.alerts = [];

  $scope.initdata = '';
  $scope.current_user = '';

  $scope.acnumbers = [];
  $scope.inputacnumbers = [];

  $scope.allselected = false;

  $scope.init = function (initdata) {
    $scope.initdata = angular.fromJson(initdata);
    $scope.current_user = $scope.initdata.current_user;
    $scope.baseurl = $('head base').attr('href');
    if($scope.initdata.load_bags){
      $scope.getACNumbers();
    }
  };

  $scope.closeAlert = function(index) {
    $scope.alerts.splice(index, 1);
  };



  $scope.signin_open = function () {

      var modalInstance = $modal.open({
            templateUrl: $('head base').attr('href')+'views/modals/loginform.html',
            controller: SigninModalCtrl
      });

  };

  $scope.selectAll = function () {
    if($scope.allselected){
      for (var i = 0; i < $scope.acnumbers.length; i++) {
        $scope.acnumbers[i].selected = false;
      }
    }else{
      for (var i = 0; i < $scope.acnumbers.length; i++) {
	$scope.acnumbers[i].selected = true;
      }	
    }
  }

  $scope.mapping_alerts_open = function (ac) {

      var modalInstance = $modal.open({
            templateUrl: $('head base').attr('href')+'views/modals/mapping_alerts.html',
            controller: AlertsModalCtrl,
            resolve: {
              mapping_alerts: function(){
               return ac.mapping_alerts;
              }
            }
      });
  };

    $scope.addACNumbers = function(){
        var promise = FrontendService.addACNumbers($scope.inputacnumbers);
        $scope.loadingTracker.addPromise(promise);
        promise.then(
          function(response) {
            $scope.form_disabled = false;
            $scope.alerts = response.data.alerts;
            $scope.inputacnumbers = [];
            $scope.getACNumbers();
            // we use bindonce so we have to do a full refresh
            $window.location.reload();
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

    $scope.getACNumbers = function(){
        var promise = FrontendService.getACNumbers();
        $scope.loadingTracker.addPromise(promise);
        promise.then(
          function(response) {
            $scope.form_disabled = false;
            $scope.alerts = response.data.alerts;
            $scope.acnumbers = response.data.acnumbers;
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

    $scope.fetchMetadataSelected = function(){
        var sel = [];
	for (var i = 0; i < $scope.acnumbers.length; i++) {
	  if($scope.acnumbers[i].selected == true){
	    sel.push($scope.acnumbers[i].ac_number);
          }
        }
        $scope.fetchMetadata(sel);
    }


    $scope.fetchMetadata = function(acnumbers){
        var promise = FrontendService.fetchMetadata(acnumbers);
        $scope.loadingTracker.addPromise(promise);
        promise.then(
          function(response) {
            $scope.form_disabled = false;
            $scope.alerts = response.data.alerts;
            $scope.getACNumbers();
            $window.location.reload();
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

    $scope.createBagSelected = function(){
      var sel = [];
      for (var i = 0; i < $scope.acnumbers.length; i++) {
        if($scope.acnumbers[i].selected == true){
	   sel.push($scope.acnumbers[i].ac_number);
        }
      }
	$scope.createBag(sel);
    }

    $scope.createBag = function(acnumbers){
        var promise = FrontendService.createBag(acnumbers);
        $scope.loadingTracker.addPromise(promise);
        promise.then(
          function(response) {
            $scope.form_disabled = false;
            $scope.alerts = response.data.alerts;
            $scope.getACNumbers();
            $window.location.reload();
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

    $scope.has_errors = function(ac){
      if(ac.mapping_alerts){
        for (var i = 0; i < ac.mapping_alerts.length; i++) {
          if(ac.mapping_alerts[i].type == 'danger'){
            return true;
          }
        }
      }
      return false;
    }

    $scope.has_warnings = function(ac){
      if(ac.mapping_alerts){
        for (var i = 0; i < ac.mapping_alerts.length; i++) {
          if(ac.mapping_alerts[i].type == 'warning'){
            return true;
          }
        }
      }
      return false;
    }
});

var AlertsModalCtrl = function ($scope, $modalInstance, FrontendService, promiseTracker, mapping_alerts) {

  $scope.mapping_alerts = mapping_alerts;

  $scope.baseurl = $('head base').attr('href');

  // we will use this to track running ajax requests to show spinner
  $scope.loadingTracker = promiseTracker('loadingTrackerFrontend');

  $scope.closeAlert = function(index) {
      $scope.alerts.splice(index, 1);
  };

  $scope.ok = function () {
    $modalInstance.dismiss('ok');
  };
};


var SigninModalCtrl = function ($scope, $modalInstance, FrontendService, promiseTracker) {

  $scope.user = {username: '', password: ''};
  $scope.alerts = [];

  $scope.baseurl = $('head base').attr('href');

  // we will use this to track running ajax requests to show spinner
  $scope.loadingTracker = promiseTracker('loadingTrackerFrontend');

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
      $scope.loadingTracker.addPromise(promise);
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
