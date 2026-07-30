# Food and Water Test App

This project now includes a Flutter test screen connected to the existing Node.js backend.

## Included test functions

- Food autocomplete while typing
- Food names shown without USDA/Filipino source labels
- Breakfast, lunch, dinner, snack, and other meal categories
- Quantity-based nutrition preview
- Add searched food to a meal
- Manual food and nutrient entry
- Manual water entry with quick-add buttons
- Food and water record lists with delete buttons
- Session nutrition and water totals

`backend-node/data/filipino_foods/aliases.json` and `recipes.json` remain valid empty arrays (`[]`).

## Run the backend

Open a terminal in `backend-node`:

```powershell
npm.cmd install
npm.cmd run dev
```

Keep this terminal running.

## Run Flutter

Open another terminal in the project root:

```powershell
flutter pub get
flutter run
```

## Backend address

Use the network/settings icon in the app toolbar to change the backend URL.

- Windows desktop or iOS simulator: `http://localhost:3000`
- Android Studio emulator: `http://10.0.2.2:3000`
- Physical phone: `http://YOUR_COMPUTER_LAN_IP:3000`

For a physical phone, both devices must be on the same Wi-Fi network and Windows Firewall must allow Node.js.

## Temporary storage

Food and water records are stored in memory for testing. They disappear when the Node.js backend restarts. The USDA processed food JSON datasets remain available.
