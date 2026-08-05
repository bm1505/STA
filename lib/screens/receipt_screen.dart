import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:screenshot/screenshot.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// Use relative imports for consistency and to avoid package resolution issues
import '../providers/auth_provider.dart';
import '../services/localization_service.dart';
import '../utils/theme.dart';

class ReceiptScreen extends StatefulWidget {
  final Map<String, dynamic> tripData;

  const ReceiptScreen({super.key, required this.tripData});

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();
  bool _isSaving = false;

  double _calculateDistanceFallback() {
    try {
      var p = widget.tripData['pickup'];
      var d = widget.tripData['dropoff'];

      if (p is String && p.startsWith('{')) p = json.decode(p);
      if (d is String && d.startsWith('{')) d = json.decode(d);

      if (p is Map && d is Map) {
        double dist = Geolocator.distanceBetween(
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
          (d['lat'] as num).toDouble(),
          (d['lng'] as num).toDouble(),
        );
        return (dist / 1000) * 1.2;
      }
    } catch (e) {
      debugPrint("Error calculating fallback distance: $e");
    }
    return 0.0;
  }

  Future<void> _saveReceipt() async {
    setState(() => _isSaving = true);
    try {
      if (await Permission.storage.request().isGranted || await Permission.photos.request().isGranted) {
        final Uint8List? imageBytes = await _screenshotController.capture();
        if (imageBytes != null) {
          final result = await ImageGallerySaverPlus.saveImage(
            imageBytes,
            quality: 100,
            name: "STA_Receipt_${widget.tripData['id'] ?? DateTime.now().millisecondsSinceEpoch}",
          );
          if (result != null && result['isSuccess'] == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Risiti imehifadhiwa kwenye Gallery!"), backgroundColor: Colors.green),
              );
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Ruhusa ya kuhifadhi imekataliwa."), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      debugPrint("Save Receipt Error: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatAddress(dynamic data) {
    if (data == null) return "Unknown Location";
    if (data is String) return data;
    if (data is Map) {
      return data['name'] ?? data['address'] ?? data['text'] ?? "Unknown Location";
    }
    return "Unknown Location";
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final lang = auth.language;

    DateTime dt;
    var ts = widget.tripData['timestamp'];
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is String) {
      dt = DateTime.parse(ts);
    } else {
      dt = DateTime.now();
    }
    String formattedDate = DateFormat('MMMM dd, yyyy').format(dt);
    String formattedTime = DateFormat('hh:mm a').format(dt);

    double fare = (widget.tripData['fare'] as num?)?.toDouble() ?? 0.0;
    double distance = (widget.tripData['distance'] as num?)?.toDouble() ?? 0.0;

    if (distance <= 0.01) {
      distance = _calculateDistanceFallback();
    }

    String pickupAddr = widget.tripData['pickupAddress'] ?? _formatAddress(widget.tripData['pickup']);
    String dropoffAddr = widget.tripData['dropoffAddress'] ?? _formatAddress(widget.tripData['dropoff']);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          LocalizationService.translate('trip_summary', lang).toUpperCase(),
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          if (!_isSaving)
            IconButton(
              icon: Icon(Icons.save_alt, color: AppTheme.primaryGold),
              onPressed: _saveReceipt,
            )
          else
            const Padding(
              padding: EdgeInsets.all(12.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryGold)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            Screenshot(
              controller: _screenshotController,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primaryGold,
                            AppTheme.primaryGold.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(30),
                          topRight: Radius.circular(30),
                        ),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.check_circle_outline, color: Colors.black, size: 50),
                          const SizedBox(height: 10),
                          Text(
                            "TZS ${NumberFormat('#,###').format(fare)}",
                            style: GoogleFonts.poppins(
                              color: Colors.black,
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            LocalizationService.translate('trip_completed', lang).toUpperCase(),
                            style: GoogleFonts.poppins(
                              color: Colors.black.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(25),
                      child: Column(
                        children: [
                          _buildDarkRow("DATE", formattedDate),
                          _buildDarkRow("TIME", formattedTime),
                          if (widget.tripData['isGuestRide'] == true)
                            _buildDarkRow("PASSENGER", widget.tripData['guestName'] ?? LocalizationService.translate('guest', lang)),
                          _buildDarkRow("TRIP ID", widget.tripData['id']?.toString().toUpperCase() ?? "STA-REF"),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(color: Colors.white10),
                          ),
                          _buildLocationEntry(Icons.circle, Colors.green, "Pickup", pickupAddr),
                          const SizedBox(height: 20),
                          _buildLocationEntry(Icons.location_on, Colors.red, "Dropoff", dropoffAddr),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Divider(color: Colors.white10),
                          ),
                          Row(
                            children: [
                              Expanded(child: _buildStatItem("DISTANCE", "${distance.toStringAsFixed(1)} KM")),
                              Container(width: 1, height: 40, color: Colors.white10),
                              Expanded(child: _buildStatItem("VEHICLE", (widget.tripData['vehicleType'] ?? "CAR").toString().toUpperCase())),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Image.asset('assets/rider_icon.png', height: 40, width: 40),
                          const SizedBox(height: 5),
                          Text("STA RIDE - SMART TRANSPORT", 
                            style: GoogleFonts.poppins(color: Colors.white24, fontSize: 8, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                onPressed: _saveReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.download),
                    const SizedBox(width: 10),
                    Text(
                      "SAVE TO GALLERY",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildLocationEntry(IconData icon, Color color, String label, String address) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold)),
              Text(address, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: AppTheme.primaryGold, fontSize: 18, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
