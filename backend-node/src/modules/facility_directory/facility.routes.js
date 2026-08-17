const express = require('express');
const facilityController = require(
  './facility.controller',
);

const router = express.Router();

router.get(
  '/status',
  facilityController.getStatus,
);

router.get(
  '/',
  facilityController.listFacilities,
);

router.post(
  '/recommend',
  facilityController.recommendFacilities,
);

router.post(
  '/match',
  facilityController.recommendFacilities,
);

router.get(
  '/:facilityNumber',
  facilityController.getFacility,
);

module.exports = router;
