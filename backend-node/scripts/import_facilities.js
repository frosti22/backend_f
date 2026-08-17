const fs = require('fs');
const path = require('path');

const DEFAULT_INPUT = path.join(
  __dirname,
  '..',
  'data',
  'facilities',
  'processed',
  'philhealth_facilities.json',
);

const inputPath = process.argv[2]
  ? path.resolve(process.argv[2])
  : DEFAULT_INPUT;

const outputPath = process.argv[3]
  ? path.resolve(process.argv[3])
  : DEFAULT_INPUT;

if (!fs.existsSync(inputPath)) {
  console.error(
    `Facility JSON was not found: ${inputPath}`,
  );
  process.exit(1);
}

let parsed;

try {
  parsed = JSON.parse(
    fs.readFileSync(inputPath, 'utf8'),
  );
} catch (error) {
  console.error(
    `Invalid facility JSON: ${error.message}`,
  );
  process.exit(1);
}

if (!Array.isArray(parsed.facilities)) {
  console.error(
    'Facility JSON must contain a facilities array.',
  );
  process.exit(1);
}

const facilityNumbers = new Set();
const errors = [];

for (const facility of parsed.facilities) {
  const number = Number(
    facility.facilityNumber,
  );

  if (!Number.isInteger(number)) {
    errors.push(
      `Invalid facilityNumber for ${facility.name}`,
    );
    continue;
  }

  if (facilityNumbers.has(number)) {
    errors.push(
      `Duplicate facilityNumber: ${number}`,
    );
  }

  facilityNumbers.add(number);

  if (!facility.name) {
    errors.push(
      `Facility ${number} has no name.`,
    );
  }

  if (!facility.region) {
    errors.push(
      `Facility ${number} has no region.`,
    );
  }

  if (!facility.cityMunicipality) {
    errors.push(
      `Facility ${number} has no cityMunicipality.`,
    );
  }

  const hasLatitude =
    facility.latitude !== null &&
    facility.latitude !== undefined;

  const hasLongitude =
    facility.longitude !== null &&
    facility.longitude !== undefined;

  if (hasLatitude !== hasLongitude) {
    errors.push(
      `Facility ${number} must have both latitude and longitude or neither.`,
    );
  }

  if (
    facility.exactClinicLocationVerified === true &&
    (!hasLatitude || !hasLongitude)
  ) {
    errors.push(
      `Verified facility ${number} is missing coordinates.`,
    );
  }
}

if (errors.length > 0) {
  console.error(
    `Facility validation failed with ${errors.length} error(s):`,
  );

  for (const error of errors.slice(0, 50)) {
    console.error(`- ${error}`);
  }

  process.exit(1);
}

fs.mkdirSync(
  path.dirname(outputPath),
  { recursive: true },
);

fs.writeFileSync(
  outputPath,
  `${JSON.stringify(parsed, null, 2)}\n`,
  'utf8',
);

const verifiedCount =
  parsed.facilities.filter(
    (facility) =>
      facility.exactClinicLocationVerified === true,
  ).length;

console.log(
  `Validated ${parsed.facilities.length} facilities.`,
);
console.log(
  `Verified exact clinic coordinates: ${verifiedCount}.`,
);
console.log(
  `Saved facility data to: ${outputPath}`,
);
