import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/ride_provider.dart';
import '../models/ride.dart';
import '../widgets/profile_image_widget.dart';

class DriverAcceptScreen extends StatelessWidget {
  const DriverAcceptScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rideProvider = Provider.of<RideProvider>(context);
    final bool isFound =
        rideProvider.currentRide?.status == RideStatus.accepted;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Text(isFound ? 'DRIVER EN ROUTE' : 'FINDING EXECUTIVE DRIVER',
            style: GoogleFonts.poppins(
                fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isFound) ...[
                // Premium Pulse Animation (Simulated)
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      height: 140,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.1)),
                      ),
                    ),
                    Icon(Icons.directions_car_rounded,
                        size: 40, color: Theme.of(context).primaryColor),
                  ],
                ),
                const SizedBox(height: 40),
                Text(
                  'Sourcing the finest driver for you',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  'A moment of patience while we coordinate...',
                  style: GoogleFonts.poppins(
                      color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ] else
                _buildDriverInfo(context, rideProvider),

              const SizedBox(height: 60),

              // Cancel Button - Subtle
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'CANCEL REQUEST',
                  style: GoogleFonts.poppins(
                      color: Colors.redAccent.withValues(alpha: 0.7),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDriverInfo(BuildContext context, RideProvider rideProvider) {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20)
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              ProfileImageWidget(
                imageUrl: rideProvider.driverInfo?.profileImageUrl,
                name: rideProvider.driverInfo?.name,
                radius: 45,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: Colors.greenAccent, shape: BoxShape.circle),
                  child: const Icon(Icons.check, size: 16, color: Colors.black),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'E X E C U T I V E   F O U N D',
            style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
                letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          Text(
            rideProvider.driverInfo?.name ?? 'Professional Driver',
            style: GoogleFonts.poppins(
                fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '${rideProvider.driverInfo?.carModel ?? 'Luxury Vehicle'} • TZS ${rideProvider.driverInfo?.carPlate ?? 'STA 001'}',
            style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 25),
          const Divider(color: Colors.white10),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionIcon(
                  Icons.call, "Call", Theme.of(context).primaryColor),
              _buildActionIcon(
                  Icons.chat_bubble, "Message", Theme.of(context).primaryColor),
              _buildActionIcon(Icons.star, "4.9", Colors.orangeAccent),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildActionIcon(IconData icon, String label, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(label,
            style: GoogleFonts.poppins(fontSize: 10, color: Colors.white70)),
      ],
    );
  }
}
