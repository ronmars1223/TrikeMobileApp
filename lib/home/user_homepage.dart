import '../home/Location_input.dart';
import '../home/qr_scanner.dart';
import '../home/emergency_contact.dart'; // Add this import
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../Authentication/login_screen.dart';
import 'bottom_navbar.dart';
import 'emergency_page.dart';
import 'google_map.dart';
import 'profile_page.dart';
import 'LocationsPageSaved.dart'; // Import the new page

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        "https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/",
  );

  String firstName = "";
  String lastName = "";
  int _selectedIndex = 0; // Tracks selected bottom navigation item

  // For map destination marker
  String? _pickupLocation;
  String? _destinationLocation;
  LatLng? _pickupCoordinates;
  LatLng? _destinationCoordinates;
  final GlobalKey<GoogleMapWidgetState> _mapKey =
      GlobalKey<GoogleMapWidgetState>();

  // Animation controller for ride button pulse
  late AnimationController _rideButtonAnimationController;

  // QR Scanner state management
  bool _showingQRScanner = false;
  Map<String, dynamic>? _selectedDriver;

  @override
  void initState() {
    super.initState();
    _fetchUserData();

    // Initialize animation controller
    _rideButtonAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    );

    // Add a listener to the animation controller
    _rideButtonAnimationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _rideButtonAnimationController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _rideButtonAnimationController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    User? user = _auth.currentUser;
    if (user != null) {
      DatabaseReference userRef = _database.ref("users/${user.uid}");
      userRef.once().then((DatabaseEvent event) {
        var data = event.snapshot.value as Map?;
        if (data != null) {
          setState(() {
            firstName = data["firstName"] ?? "";
            lastName = data["lastName"] ?? "";
          });
        }
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == 0) {
      // Navigate to LocationsPageSaved when Locations tab is pressed
      _showLocationsModal();
    } else if (index == 1) {
      // Navigate to EmergencyContactsPage when Emergency tab is pressed
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => EmergencyContactsPage()),
      );
    } else if (index == 2) {
      _showProfileModal();
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  // New method to show Locations page as a modal
  void _showLocationsModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.9,
            child: SlideInUp(
              duration: Duration(milliseconds: 400),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: LocationsPageSaved(),
              ),
            ),
          ),
    );
  }

  Future<void> _logout() async {
    await _auth.signOut();
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => LoginPage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
  }

  // Keep this method for compatibility, but it's not used directly anymore
  void _showEmergencyDialog() async {
    // Use the improved EmergencyDialog.showEnhanced method instead of showWithLocationSharing
    final alertSent = await EmergencyDialog.showEnhanced(context);

    // If the alert was sent, record it in the database
    if (alertSent) {
      User? user = _auth.currentUser;
      if (user != null) {
        try {
          DatabaseReference emergencyRef = _database.ref(
            "users/${user.uid}/emergency_alerts",
          );
          DatabaseReference newAlertRef = emergencyRef.push();
          await newAlertRef.set({
            // No more 'type' field since we're not selecting specific emergency types
            'timestamp': ServerValue.timestamp,
            'status': 'sent',
            'user_name': '$firstName $lastName',
            // Add user location if available
            'location':
                _pickupCoordinates != null
                    ? {
                      'lat': _pickupCoordinates!.latitude,
                      'lng': _pickupCoordinates!.longitude,
                    }
                    : null,
          });

          // Log the emergency alert
          print("Emergency alert recorded in database");
        } catch (e) {
          print("Error saving emergency alert: $e");
        }
      }
    }
  }

  void _showProfileModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.9,
            child: SlideInUp(
              duration: Duration(milliseconds: 400),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: ProfilePage(),
              ),
            ),
          ),
    );
  }

  Future<void> _saveRideToHistory(
    String pickup,
    String destination,
    LatLng? pickupCoords,
    LatLng? destCoords,
  ) async {
    User? user = _auth.currentUser;
    if (user != null) {
      // Create a new ride entry
      Map<String, dynamic> rideData = {
        'pickup': pickup,
        'destination': destination,
        'timestamp': ServerValue.timestamp, // Current server timestamp
        'status': 'confirmed',
      };

      // Add coordinates if available
      if (pickupCoords != null) {
        rideData['pickup_lat'] = pickupCoords.latitude;
        rideData['pickup_lng'] = pickupCoords.longitude;
      }

      if (destCoords != null) {
        rideData['destination_lat'] = destCoords.latitude;
        rideData['destination_lng'] = destCoords.longitude;
      }

      // Add driver information if available
      if (_selectedDriver != null) {
        rideData['driverId'] = _selectedDriver!['tricycleId'] ?? '';
        rideData['driverName'] =
            '${_selectedDriver!['firstName'] ?? ''} ${_selectedDriver!['lastName'] ?? ''}';
        rideData['driverLicense'] = _selectedDriver!['licenseCode'] ?? '';
      }

      try {
        // Reference to the user's ride history
        DatabaseReference rideHistoryRef = _database.ref(
          "users/${user.uid}/ride_history",
        );

        // Generate a unique key for this ride
        DatabaseReference newRideRef = rideHistoryRef.push();

        // Save the ride data
        await newRideRef.set(rideData);

        // Also save to general ride_history for analytics
        DatabaseReference generalRideHistoryRef = _database.ref("ride_history");
        DatabaseReference generalRideRef = generalRideHistoryRef.push();
        await generalRideRef.set({
          ...rideData,
          'userId': user.uid, // Add user ID to general history
        });

        print("Ride history saved successfully!");
      } catch (e) {
        print("Error saving ride history: $e");
      }
    }
  }

  // New method to handle location confirmation and save ride history
  void _handleLocationConfirmed(
    String pickup,
    String destination,
    LatLng? pickupCoords,
    LatLng? destCoords,
  ) async {
    setState(() {
      _pickupLocation = pickup;
      _destinationLocation = destination;
      _pickupCoordinates = pickupCoords;
      _destinationCoordinates = destCoords;
    });

    // Update map with destination marker
    if (_mapKey.currentState != null) {
      _mapKey.currentState!.setDestinationWithCoords(
        destination,
        _destinationCoordinates ?? LatLng(0, 0), // Fallback coordinates if null
        pickup,
        _pickupCoordinates ?? LatLng(0, 0), // Fallback coordinates if null
      );
    }

    // Save the ride to history
    await _saveRideToHistory(pickup, destination, pickupCoords, destCoords);

    // Navigate back to map
    Navigator.pop(context);

    // Show success message with driver info and route info
    final snackBar = SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Ride to $destination confirmed!",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: Colors.blue.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: EdgeInsets.all(15),
      padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      duration: Duration(seconds: 3),
      action: SnackBarAction(
        label: 'CANCEL',
        textColor: Colors.white,
        onPressed: () {
          // Clear destination
          setState(() {
            _destinationLocation = null;
            _destinationCoordinates = null;
            _selectedDriver = null;
          });
          if (_mapKey.currentState != null) {
            _mapKey.currentState!.clearDestination();
          }
        },
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _handleDriverScanned(Map<String, dynamic> driverData) {
    setState(() {
      _selectedDriver = driverData;
    });

    // Close the QR scanner page
    Navigator.pop(context);

    // Show the location input modal with driver info
    _showLocationInputModalWithDriver();
  }

  void _showLocationInputModalWithDriver() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              children: [
                // Driver info bar at the top
                if (_selectedDriver != null)
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(25),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Driver: ${_selectedDriver!['firstName']} ${_selectedDriver!['lastName']}',
                                style: TextStyle(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'ID: ${_selectedDriver!['tricycleId']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          icon: Icon(Icons.qr_code_scanner),
                          label: Text('Re-scan'),
                          onPressed: () {
                            // Close the location input modal
                            Navigator.pop(context);
                            // Open QR scanner again
                            _showQRScannerModal();
                          },
                        ),
                      ],
                    ),
                  ),

                // Location input takes the rest of the space
                Expanded(
                  child: LocationInputPage(
                    onLocationConfirmed: _handleLocationConfirmed,
                    driverData: _selectedDriver, // Pass the driver data here
                  ),
                ),
              ],
            ),
          ),
    );
  }

  void _showQRScannerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder:
          (context) => FractionallySizedBox(
            heightFactor: 0.9,
            child: QRScannerPage(onDriverScanned: _handleDriverScanned),
          ),
    );
  }

  void _showLocationInputModal() {
    // Play animation for button feedback
    _rideButtonAnimationController.forward();

    // Reset selected driver to ensure QR scanner always shows first
    setState(() {
      _selectedDriver = null;
    });

    // Always show QR scanner first
    _showQRScannerModal();
  }

  @override
  Widget build(BuildContext context) {
    // Update AppBar title based on the selected tab
    String appBarTitle = "Welcome${firstName.isNotEmpty ? ', $firstName' : ''}";
    Color appBarColor = Colors.blue;

    // Update the color based on selected tab
    if (_selectedIndex == 0) {
      appBarTitle = "Welcome${firstName.isNotEmpty ? ', $firstName' : ''}";
      appBarColor = Colors.blue;
    } else if (_selectedIndex == 1) {
      appBarTitle = "Emergency";
      appBarColor = Colors.redAccent;
    }

    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60),
        child: Container(
          decoration: BoxDecoration(color: appBarColor),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FadeIn(
                    duration: Duration(milliseconds: 600),
                    child: Text(
                      appBarTitle,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  ZoomIn(
                    duration: Duration(milliseconds: 500),
                    child: IconButton(
                      icon: Icon(Icons.logout, color: Colors.white),
                      onPressed: _logout,
                      tooltip: 'Logout',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          GoogleMapWidget(key: _mapKey), // Pass the key to access the state
        ],
      ),

      // Display destination info if available
      bottomNavigationBar: BottomNavbar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        onRideButtonPressed: _showLocationInputModal,
        onAlertButtonPressed: _handleAlertButtonPress,
      ),
    );
  }

  // Updated to use the new EmergencyDialog class
  void _handleAlertButtonPress() async {
    // Use the improved EmergencyDialog.showEnhanced method
    final alertSent = await EmergencyDialog.showEnhanced(context);

    // If the alert was sent, record it in the database
    if (alertSent) {
      User? user = _auth.currentUser;
      if (user != null) {
        try {
          DatabaseReference emergencyRef = _database.ref(
            "users/${user.uid}/emergency_alerts",
          );
          DatabaseReference newAlertRef = emergencyRef.push();

          // The current timestamp
          final now = DateTime.now();
          final String formattedDate = DateFormat(
            'yyyy-MM-dd_HH-mm-ss',
          ).format(now);

          await newAlertRef.set({
            'timestamp': ServerValue.timestamp,
            'status': 'sent',
            'user_name': '$firstName $lastName',
            // Add location data if available
            'location':
                _pickupCoordinates != null
                    ? {
                      'lat': _pickupCoordinates!.latitude,
                      'lng': _pickupCoordinates!.longitude,
                    }
                    : null,
            // Add reference to expected audio file
            'audio_file': 'emergency_audio_$formattedDate.m4a',
          });

          // Audio recording is handled automatically by the EmergencyDialog
        } catch (e) {
          print("Error saving emergency alert: $e");
        }
      }
    }
  }
}
