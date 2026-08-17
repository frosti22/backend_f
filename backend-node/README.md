# log.CKD Node.js Backend

Main modules:

- foods
- food_logs
- nutrition
- lifestyle_logs
- water_logs
- checkup_records
- wearable_records
- facility_directory
- health_data_validation


## Local Philippine LGU and PhilHealth facility directory

This project now works without a facility database.

Data files:

- `data/locations/processed/complete_philippine_lgu_hierarchy.json`
- `data/facilities/processed/philhealth_facilities.json`

The facility file contains 904 PhilHealth-accredited freestanding
dialysis clinics. Pampanga currently contains 34 directory records:

- 33 clinics have user-supplied exact coordinates.
- Lubao Dialysis Center remains without coordinates.
- Facilities without coordinates keep `latitude` and `longitude` as `null`.

This prevents guessed map pins while allowing the Pampanga clinics with
coordinates to appear on the map.

API endpoints:

- `GET /api/locations/regions`
- `GET /api/locations/provinces?region=Region III (Central Luzon)`
- `GET /api/locations/localities?region=Region III (Central Luzon)&province=Pampanga`
- `GET /api/facilities/status`
- `GET /api/facilities?region=Region III (Central Luzon)&province=Pampanga&cityMunicipality=Mabalacat City`
- `GET /api/facilities/216`
- `POST /api/facilities/recommend`

Example recommendation body:

```json
{
  "region": "Region III (Central Luzon)",
  "province": "Pampanga",
  "cityMunicipality": "Mabalacat City",
  "latitude": 15.210000,
  "longitude": 120.580000,
  "limit": 5
}
```

The API returns `isActualNearest: true` only when every clinic in the
candidate set has a verified exact pin. When only some pins are verified,
it returns `isPartialDistanceRanking: true` and does not claim that the
result is the complete nearest-clinic ranking.

Validate the facility JSON with:

```powershell
npm run validate:facilities
```
