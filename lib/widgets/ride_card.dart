import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RideCard extends StatelessWidget {
  final String pickup;
  final String dropoff;
  final double fare;
  final String time;
  final VoidCallback onTap;
  
  const RideCard({
    super.key,
    required this.pickup,
    required this.dropoff,
    required this.fare,
    required this.time,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_car, color: Colors.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.circle, size: 8, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickup,
                          style: GoogleFonts.poppins(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Container(
                      height: 20,
                      width: 2,
                      color: Colors.grey.shade300,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 12, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dropoff,
                          style: GoogleFonts.poppins(fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'TZS ${fare.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}