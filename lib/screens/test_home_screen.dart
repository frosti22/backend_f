import 'package:flutter/material.dart';

import 'clinic_directory_screen.dart';
import 'food_water_test_screen.dart';

class TestHomeScreen extends StatelessWidget {
  const TestHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('log.CKD Backend Tests'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TestCard(
            icon: Icons.restaurant_menu,
            title: 'Food and Water Test',
            description:
                'Open the existing food search, food logs, and hydration test screen.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FoodWaterTestScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          _TestCard(
            icon: Icons.local_hospital_outlined,
            title: 'Accredited Clinic Directory',
            description:
                'Select Region → Province/Area → City/Municipality, search the facility list, and tap a facility to expand its MapLibre map pin.',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ClinicDirectoryScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  const _TestCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(child: Icon(icon)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 5),
                    Text(description),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
