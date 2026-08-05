# PROJECT PROPOSAL

## 1. Title Page
**Project Title:** A Multi-Platform Smart Transport Management System (STA Ride)  
**Student Name:** BARAKA MBOJE MAHEGA
**Registration Number:**  BCS-01-0038-2022
**Institution:** INSTITUTE OF ACCOUNTANCE ARUSHA (IAA)  
**Date:** May 2026

---

## 2. Introduction / Background
The transportation industry is undergoing a significant digital transformation. With the rise of the "on-demand" economy, mobile applications have become the primary interface for connecting service providers with consumers. **STA Ride** is a comprehensive smart transport management system designed to streamline urban mobility. It integrates three core roles—Rider, Driver, and Administrator—into a single, synchronized ecosystem. By utilizing modern cross-platform frameworks, the project aims to provide a reliable, transparent, and efficient solution for local transport management.

## 3. Problem Statement
Despite the proliferation of transport apps, many regions still face:
*   **Operational Inefficiency:** Difficulty in matching available drivers with passengers in real-time, leading to long wait times.
*   **Lack of Centralized Oversight:** Administrators often lack tools to monitor fleet performance, safety, and trip metrics effectively.
*   **Communication Gaps:** Delays in notifications between riders and drivers during the booking process.
*   **Development Barriers:** Traditionally, developing and maintaining separate apps for different roles is costly.

### 3.1 Research & Innovation Gaps
Most existing ride-hailing platforms in Tanzania (like Bolt or Uber) have the following gaps which **STA Ride** aims to bridge:
1.  **Gender-Specific Safety:** Lack of a dedicated option for female riders to request female drivers for enhanced security, especially at night.
2.  **Language Barriers:** Most apps are English-centric, excluding a large demographic of Swahili speakers.
3.  **Algorithmic Fairness:** Traditional systems often favor the "closest driver," leading to income inequality among drivers.
4.  **Hardware-Level Security:** Lack of local, offline-capable face verification for drivers to prevent account sharing/fraud.
5.  **Emergency Response:** Limited zero-cost emergency features for users without active data bundles.
6.  **Visual Positioning:** Feature to verify and correct pickup locations using visual cues (photos) in areas where GPS signal is weak or inaccurate.

## 4. Objectives
### a) General Objective
To design, develop, and implement a robust cross-platform smart transport management system (STA Ride) that synchronizes riders, drivers, and administrators while addressing safety, inclusivity, and algorithmic fairness gaps.

### b) Specific Objectives
*   To develop a **Rider Application** with a "Women Safe Ride" feature and integrated SOS emergency response.
*   To implement a **Driver Application** featuring on-device Face Verification for identity security.
*   To implement a **Smart Driver Allocation Algorithm** that balances proximity with driver idle time to ensure fair work distribution.
*   To create a **Multilingual Interface** (English & Swahili) to enhance local accessibility.
*   To implement a **Visual Pickup** feature using EXIF metadata and AI to accurately identify rider locations.
*   To create an **Admin Dashboard** for centralized monitoring and financial transparency.

## 5. System Requirements
### 5.1 Functional Requirements
*   **Role-Based Access:** Distinct modules for Riders, Drivers, and Administrators within a single synchronized system, powered by a unified Node.js/Express backend.
*   **Women Safe Ride:** Specialized toggle for female riders to request female drivers for enhanced safety.
*   **Face Verification:** AI-driven facial recognition for drivers to verify identity during login/onboarding using Google ML Kit.
*   **Real-Time Tracking:** Live GPS monitoring of rides using Socket.IO for riders, drivers, and administrators.
*   **Emergency Response (SOS):** Integrated button for instant location sharing and emergency alerts.
*   **Multilingual Support:** Dynamic language switching between English and Swahili.
*   **Visual Pickup:** Option for riders to upload a photo of their surroundings to automatically detect or verify the pickup location using EXIF metadata or AI recognition.
*   **Ride Management:** Comprehensive flow from request, acceptance, navigation, to completion and history logging.

### 5.2 Non-Functional Requirements
*   **Performance:** Low-latency communication with ride request broadcasting and location updates happening in under 2 seconds.
*   **Security:** Robust data encryption for user privacy and secure authentication mechanisms.
*   **Usability:** Minimalist and intuitive UI ("Midnight Gold" theme) designed for high visibility and reduced eye strain.
*   **Scalability:** Modular backend architecture capable of handling an increasing number of concurrent users.
*   **Availability:** High system uptime ensuring real-time services are always accessible.

## 6. Technology Stack
*   **Frontend Framework:** **Flutter (Dart)** - Cross-platform framework for building the mobile and web interfaces.
*   **Backend Environment:** **Node.js & Express.js** - Scalable server-side environment for handling API requests.
*   **Real-Time Engine:** **Socket.IO** - Enables bidirectional event-based communication for live tracking.
*   **Database:** **SQLite (Centralized)** - Relational database for structured data storage and global persistence via a centralized Node.js backend.
*   **Machine Learning:** **Google ML Kit** - Powering the on-device Face Verification and liveness detection.
*   **Maps & Geolocation:** **OpenStreetMap (OSM)** - Integrated as a cost-effective alternative for mapping and routing.

## 7. System Architecture
The project utilizes a **Modular Client-Server Architecture** designed for high performance and maintainability:
*   **Presentation Layer (Mobile Tier):** Three distinct application modules (Rider, Driver, Admin) generated from a single Flutter codebase using **Product Flavors**. This allows for easy maintenance and deployment.
*   **Application Tier (Logic Layer):** A Node.js server that manages business logic, handles ride-matching algorithms, and orchestrates real-time events via Socket.IO.
*   **Data Tier (Database):** A centralized SQLite database management system that stores user profiles, ride history, and system configurations, ensuring data consistency across all client modules.
*   **Communication Layer:** A hybrid approach using **REST APIs** for transactional data (profiles, history) and **WebSockets (Socket.IO)** for real-time synchronization (live tracking, request broadcasting).

## 8. Research Questions
*   How can real-time communication between multiple mobile modules be optimized to minimize latency in ride-hailing?
*   To what extent does a single-codebase architecture (using Flavors) improve the maintainability and deployment speed of multi-role systems?
*   How can open-source mapping solutions (OSM) provide a viable and cost-effective alternative to proprietary mapping APIs in a local context?

## 9. Literature Review
Current research in mobile computing highlights the shift toward frameworks like **Flutter** for rapid, native-quality cross-platform development. Studies on "On-Demand Mobility" emphasize the necessity of low-latency communication protocols, such as WebSockets (Socket.io), for efficient service delivery. Furthermore, "Smart City" initiatives frequently advocate for integrated transport management systems that provide data-driven insights for administrators to improve urban logistics. This project builds on these foundations by implementing a resource-optimized, tri-app solution.

## 10. Methodology
The project follows an **Agile/Iterative Development** methodology:
*   **System Design:** A modular architecture separating the Frontend (Flutter), Backend (Node.js), and Real-time communication layer (Socket.io).
*   **Data Persistence Strategy:** A centralized backend approach using `sqlite3` on the server and `ApiService` on the clients to ensure data integrity and real-time synchronization across all platforms.
*   **Unique Design Philosophy:** Moving away from standard "app clones" by implementing a bespoke "Midnight Gold" interface. This uses high-contrast typography and deep charcoal tones to reduce eye strain and provide a professional, executive-level experience.
*   **Implementation Strategy:** Using **Product Flavors** to maintain one core codebase while generating three distinct APKs (com.sta.ride, com.sta.driver, com.sta.admin).
*   **Technical Realization of Innovations:**
    *   **Gender Filtering:** Implemented via real-time Socket.IO room filtering, where "Women Safe Ride" requests are broadcasted only to sockets identified with `gender: 'female'`.
    *   **Visual Pickup:** Integrated a image-sharing pipeline where riders capture local surroundings, and the file path is synchronized across the backend to the driver's request dialog using `Image.file` for instant recognition.
    *   **Biometric Security:** Leveraged Google ML Kit's Face Detection API for a "Liveness Check" to ensure drivers are physically present during login.
*   **Tools:** VS Code for coding, Git for version control, and Postman for API testing.
*   **Build Optimization:** Implementing memory-capping techniques (Gradle optimizations) to support development and compilation on systems with limited RAM (e.g., 8GB).
*   **Testing:** Incremental testing of the booking flow, ensuring the Rider's request triggers the Driver's notification and is visible on the Admin panel.

## 11. Expected Results / Outcomes
*   A fully functional prototype of the **STA Ride** system including Rider, Driver, and Admin modules.
*   Successful real-time event handling (e.g., Rider booking request appearing instantly on the Driver's screen).
*   A centralized Admin panel capable of viewing live driver locations and trip history.
*   A technical report documenting the flavor-based architecture and the transition to a centralized server-side data model for improved scalability.

## 12. Work Plan / Timeline
| Activity | Duration | Status |
|---|---|---|
| Requirement Analysis & UI/UX Design | 2 Weeks | Completed |
| Backend API Development & Database Setup | 3 Weeks | Completed |
| Rider & Driver App Core Integration | 4 Weeks | Testing |
| Admin Dashboard Development | 2 Weeks | Testing |
| Final Testing & Documentation | 2 Weeks | Completed |

## 13. Budget (Estimated)
| Item | Description | Cost (Estimated) |
|---|---|---|
| Software | Server Hosting & Domain Registration | TZS 250,000 |
| Internet | Research, API testing, & Cloud Deployment | TZS 150,000 |
| Documentation | Printing, Binding, & Stationery | TZS 50,000 |
| Hardware | Maintenance and testing equipment | TZS 100,000 |
| **Total** | | **TZS 550,000** |

## 14. Limitations
*   **Internet Dependency:** The system requires stable internet connectivity for real-time tracking and synchronization.
*   **GPS Precision:** Accuracy is dependent on the hardware quality of the mobile devices and environmental conditions.
*   **Hardware Constraints:** Compiling multiple app flavors simultaneously requires significant RAM; build processes must be carefully managed.

## 15. Conclusion
The **STA Ride** project offers a professional and scalable solution to modern transport management challenges. By integrating innovative features like "Women Safe Ride," "Visual Pickup," and on-device Face Verification, the system significantly enhances user safety and operational efficiency. The use of Flutter's flavor-based architecture ensures that the solution remains maintainable and resource-optimized, making it a viable model for smart urban mobility in Tanzania and beyond.
