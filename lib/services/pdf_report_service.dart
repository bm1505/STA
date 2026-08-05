import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfReportService {
  static Future<void> generateCollegeReport() async {
    final pdf = pw.Document();

    // Font definitions (Times New Roman equivalents in PDF)
    final font = pw.Font.times();
    final fontBold = pw.Font.timesBold();
    final fontItalic = pw.Font.timesItalic();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(
          base: font,
          bold: fontBold,
          italic: fontItalic,
        ),
        build: (pw.Context context) {
          return [
            // --- COVER PAGE ---
            pw.Center(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.max,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.SizedBox(height: 50),
                  pw.Text("STA RIDE: A SMART TRANSPORT MANAGEMENT SYSTEM",
                      style: pw.TextStyle(font: fontBold, fontSize: 24),
                      textAlign: pw.TextAlign.center),
                  pw.SizedBox(height: 120),
                  pw.Text("FINAL PROJECT REPORT",
                      style: pw.TextStyle(font: fontBold, fontSize: 18)),
                  pw.SizedBox(height: 200),
                  pw.Text("PREPARED BY: [YOUR NAME]",
                      style: pw.TextStyle(font: fontBold, fontSize: 14)),
                  pw.Text("REGISTRATION NUMBER: [YOUR REG NO]",
                      style: pw.TextStyle(font: fontBold, fontSize: 14)),
                  pw.SizedBox(height: 50),
                  pw.Text("SUPERVISOR: [SUPERVISOR NAME]",
                      style: pw.TextStyle(font: fontBold, fontSize: 14)),
                  pw.SizedBox(height: 100),
                  pw.Text("DATE: JUNE 2026",
                      style: pw.TextStyle(font: fontBold, fontSize: 14)),
                ],
              ),
            ),
            pw.NewPage(),

            // --- CHAPTER ONE ---
            _heading1("CHAPTER ONE: INTRODUCTION"),
            _heading2("1.4 General Objective"),
            _bodyText("The general objective of this project was to design and develop a multi-platform smart transportation management system that enables efficient ride-hailing services through real-time communication, GPS tracking, secure user management, and centralized administrative control to improve transportation services."),
            
            _heading2("1.5 Specific Objectives"),
            _bullet("To design and develop a secure user authentication system for Riders, Drivers, Administrators, IT Officers, and Customer Support staff."),
            _bullet("To develop a ride request and management module that allows passengers to request, monitor, and complete transportation services efficiently."),
            _bullet("To implement a real-time GPS tracking system that enables passengers and administrators to monitor driver locations during active trips."),
            _bullet("To develop a driver management module for driver registration, document verification, vehicle information management, and trip history."),
            _bullet("To implement a centralized administrative dashboard for managing users, monitoring active rides, generating reports, and configuring system settings."),
            _bullet("To integrate notification services that provide instant communication between passengers, drivers, and administrators."),
            _bullet("To implement a fare calculation mechanism based on travel distance and predefined pricing policies."),
            _bullet("To develop an in-app messaging system that facilitates communication between riders and drivers during active trips."),
            _bullet("To evaluate the performance, usability, reliability, and security of the developed transportation management system through comprehensive system testing."),

            _heading2("1.6 Scope of the Project"),
            _bodyText("This project focused on the design and implementation of a smart transportation management system known as STA RIDE. The system was developed to support transportation service management through multiple user roles operating within a single integrated platform."),
            
            _heading3("Rider Module"),
            _bullet("Register and log into the system."),
            _bullet("Update personal profile information."),
            _bullet("Request transportation services and view nearby available drivers."),
            _bullet("Track drivers in real time and view estimated fare."),
            _bullet("Chat with drivers, cancel ride requests, and view trip history."),

            _heading3("Driver Module"),
            _bullet("Register driver accounts and upload driving license/vehicle documents."),
            _bullet("Accept or reject ride requests and navigate to passenger locations."),
            _bullet("Update online/offline availability and monitor earnings."),

            _heading3("Administrator Module"),
            _bullet("Verifying driver documents and monitoring ongoing trips."),
            _bullet("Managing fare settings, system users, and reports."),

            _heading2("1.7 Significance of the Project"),
            _bodyText("The implementation of the STA RIDE system provides significant benefits to Passengers (safety & tracking), Drivers (job opportunities & organization), and Transport Companies (operational efficiency). It serves as a valuable reference for future researchers in mobile application development."),

            _heading2("1.8 Limitations of the Project"),
            _bullet("Depends on internet connectivity and GPS accuracy varies by device/weather."),
            _bullet("Mobile money integration was not implemented within this scope."),

            _heading2("1.9 Conclusion"),
            _bodyText("This chapter established the need for a comprehensive transportation management system capable of improving services through modern mobile and cloud technologies like Firebase."),

            pw.NewPage(),

            // --- CHAPTER TWO ---
            _heading1("CHAPTER TWO: MAIN BODY"),
            _heading2("2.1 Methodology"),
            _heading3("2.1.2 Software Development Methodology"),
            _bodyText("The development of the STA RIDE system adopted the Agile Scrum Methodology. This iterative approach emphasized continuous planning, development, testing, and improvement throughout the project lifecycle."),
            
            _heading3("2.1.3 Development Tools"),
            _bodyText("Frontend: Flutter (Dart)\nBackend: Firebase (Auth, Cloud Firestore, Storage, Messaging)\nMaps: Google Maps API\nIDE: Android Studio & VS Code"),

            _heading2("2.2 Requirements Specification"),
            _bodyText("Functional requirements cover Rider, Driver, and Admin functionalities. Non-functional requirements focus on Performance, Reliability, Security (Encrypted authentication), and Scalability."),

            _heading2("2.4 System Design"),
            _bodyText("STA RIDE follows a client-server architecture using Firebase for real-time synchronization. Major collections in Firestore include Users, Drivers, Ride Requests, and Notifications."),

            _heading2("2.6 System Testing"),
            _bodyText("Comprehensive testing was conducted, including Unit Testing, Integration Testing, and User Acceptance Testing (UAT). All modules passed successfully with positive user experience."),

            pw.NewPage(),

            // --- CHAPTER THREE ---
            _heading1("CHAPTER THREE: CONCLUSION AND RECOMMENDATIONS"),
            _heading2("3.2 Conclusion"),
            _bodyText("The STA RIDE project successfully achieved its objectives by developing a modern multi-platform system. Firebase cloud services ensured secure data storage and reliable real-time communication."),

            _heading2("3.6 Recommendations"),
            _bullet("Online Payment Integration (M-Pesa, Tigo Pesa)."),
            _bullet("Route Optimization using intelligent algorithms."),
            _bullet("Multi-Language Support (English and Kiswahili)."),

            pw.NewPage(),

            // --- REFERENCES ---
            _heading1("REFERENCES (Harvard Style)"),
            _bodyText("Bass, L., Clements, P. & Kazman, R., 2021. Software Architecture in Practice. 4th ed. Boston: Addison-Wesley."),
            _bodyText("Firebase, 2024. Cloud Firestore Documentation. Available at: https://firebase.google.com/docs/firestore."),
            _bodyText("Google Developers, 2024. Flutter Documentation. Available at: https://docs.flutter.dev."),
            _bodyText("Sommerville, I., 2020. Software Engineering. 10th ed. London: Pearson Education."),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // --- Helper Methods for Formatting ---
  static pw.Widget _heading1(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _heading2(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 15, bottom: 5),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _heading3(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    );
  }

  static pw.Widget _bodyText(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 12), textAlign: pw.TextAlign.justify),
    );
  }

  static pw.Widget _bullet(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 15, bottom: 3),
      child: pw.Bullet(text: text, style: const pw.TextStyle(fontSize: 12), textAlign: pw.TextAlign.justify),
    );
  }
}
