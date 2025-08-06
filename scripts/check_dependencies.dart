import 'dart:io';
import 'package:flutter/foundation.dart';

/// Utility script to check project dependencies and provide insights
void main() async {
  // Check if pubspec.yaml exists
  final pubspecFile = File('pubspec.yaml');
  if (!await pubspecFile.exists()) {
    debugPrint('Error: pubspec.yaml not found!');
    return;
  }
  
  // Read and parse pubspec.yaml
  final pubspecContent = await pubspecFile.readAsString();
  final lines = pubspecContent.split('\n');
  
  debugPrint('📦 Dependencies Analysis:');
  bool inDependencies = false;
  bool inDevDependencies = false;
  
  for (final line in lines) {
    if (line.trim() == 'dependencies:') {
      inDependencies = true;
      inDevDependencies = false;
      debugPrint('\n  Production Dependencies:');
      continue;
    }
    
    if (line.trim() == 'dev_dependencies:') {
      inDependencies = false;
      inDevDependencies = true;
      debugPrint('\n  Development Dependencies:');
      continue;
    }
    
    if (line.trim().startsWith('-') && (inDependencies || inDevDependencies)) {
      final dep = line.trim().substring(1).trim();
      final icon = inDependencies ? '📱' : '🛠️';
      debugPrint('    $icon $dep');
    }
  }
  
  // Check for common Flutter project files
  debugPrint('\n📁 Project Structure Check:');
  final importantFiles = [
    'lib/main.dart',
    'lib/screens/',
    'lib/widgets/',
    'lib/helpers/',
    'assets/',
    'test/',
  ];
  
  for (final file in importantFiles) {
    final exists = await Directory(file).exists() || await File(file).exists();
    final icon = exists ? '✅' : '❌';
    debugPrint('  $icon $file');
  }
  
  // Check for database files
  debugPrint('\n🗄️ Database Files:');
  final dbFiles = [
    'assets/jmdict_fts5.db',
  ];
  
  for (final file in dbFiles) {
    final exists = await File(file).exists();
    final icon = exists ? '✅' : '❌';
    final size = exists ? ' (${(await File(file).length() / 1024 / 1024).toStringAsFixed(1)} MB)' : '';
    debugPrint('  $icon $file$size');
  }
  
  debugPrint('\n✨ Analysis Complete!');
  debugPrint('\n💡 Tips:');
  debugPrint('  - Run "flutter pub get" to install dependencies');
  debugPrint('  - Run "flutter analyze" to check for code issues');
  debugPrint('  - Run "flutter test" to run unit tests');
}