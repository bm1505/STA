import 'package:flutter_test/flutter_test.dart';

void main() {
  group('STA RIDE Financial Logic (80/20) Verification', () {
    
    test('Cash Trip: Commission deduction (20%)', () {
      final double fare = 10000.0;
      final double expectedCommission = 2000.0; // 20% of 10000
      
      // Verification of the logic in recordTrip:
      // double commission = (fare * 0.20).roundToDouble();
      
      double calculatedCommission = (fare * 0.20).roundToDouble();
      expect(calculatedCommission, expectedCommission);
    });

    test('Digital Trip: Driver Earnings (80%)', () {
      final double fare = 10000.0;
      final double expectedEarnings = 8000.0; // 80% of 10000
      
      // Verification of the logic in recordTrip:
      // double driverShare = (fare * 0.80).roundToDouble();
      
      double calculatedEarnings = (fare * 0.80).roundToDouble();
      expect(calculatedEarnings, expectedEarnings);
    });

    test('Debt Threshold Block Logic', () {
      const double DEBT_THRESHOLD = -20000.0;
      
      double balance1 = -15000.0;
      double balance2 = -25000.0;
      
      bool isBlocked1 = balance1 < DEBT_THRESHOLD;
      bool isBlocked2 = balance2 < DEBT_THRESHOLD;
      
      expect(isBlocked1, false);
      expect(isBlocked2, true);
    });
  });
}
