'use strict';

var simpleCamExports = {};

simpleCamExports.getPicture = function(successCallback, errorCallback, options) {
   options = options || {};

   var quality = options.quality || 50;
   var targetWidth = options.targetWidth || -1;
   var targetHeight = options.targetHeight || -1;
   var encodingType = options.encodingType || 'jpeg';

   var args = [quality, targetWidth, targetHeight, encodingType];

   cordova.exec(successCallback, errorCallback, 'SimpleCam', 'takePicture', args);
};

module.exports = simpleCamExports;
