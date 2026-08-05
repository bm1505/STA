import 'package:flutter/material.dart';

// Hili faili linatumiwa na Android/iOS wakati wa compile time
Widget buildWebImage({
  required String url,
  double radius = 0,
  BoxFit fit = BoxFit.cover,
  Widget? placeholder,
}) {
  // Tunarudisha placeholder au indicator endapo picha haipo
  return placeholder ?? const Center(child: CircularProgressIndicator());
}
