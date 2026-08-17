const express = require('express');
const locationController = require(
  './location.controller',
);

const router = express.Router();

router.get(
  '/status',
  locationController.getStatus,
);

router.get(
  '/regions',
  locationController.getRegions,
);

router.get(
  '/provinces',
  locationController.getProvinces,
);

router.get(
  '/localities',
  locationController.getLocalities,
);

module.exports = router;
