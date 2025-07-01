import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 16, 20, 63),
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color.fromARGB(255, 9, 12, 43),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Review Settings'),
          
          // Placeholder settings (not functional yet)
          _buildSettingCard('Maximum cards per session', '20 cards'),
          _buildSettingCard('Show cards due soon', 'Enabled'),
          _buildSettingCard('Review order', 'Due date'),
          
          _buildSectionHeader('Appearance'),
          
          _buildSettingCard('Dark theme', 'Enabled'),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.amber,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingCard(String title, String value) {
    return Card(
      color: Color.fromARGB(255, 33, 36, 97),
      margin: EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}