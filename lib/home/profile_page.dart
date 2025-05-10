// First, add these dependencies to your pubspec.yaml:
// location: ^5.0.3
// permission_handler: ^10.4.0

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as permission;
import 'package:shared_preferences/shared_preferences.dart';
import 'ride_history_page.dart';

class ProfilePage extends StatefulWidget {
  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        "https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/",
  );

  String firstName = "";
  String lastName = "";
  String email = "";
  String mobile = "";
  String fullAddress = "";

  // Location variables
  Location _location = Location();
  bool _locationServiceEnabled = false;
  PermissionStatus? _locationPermissionStatus;
  LocationData? _currentLocation;
  Timer? _locationTimer;
  bool _isTrackingLocation = false;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCachedProfile();
    _fetchUserProfile();
    _initLocationService(); // Initialize location service

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.5, 1, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
  }

  // Initialize location service
  Future<void> _initLocationService() async {
    try {
      // Check if location service is enabled
      _locationServiceEnabled = await _location.serviceEnabled();
      if (!_locationServiceEnabled) {
        _locationServiceEnabled = await _location.requestService();
        if (!_locationServiceEnabled) {
          return;
        }
      }

      // Check location permission
      _locationPermissionStatus = await _location.hasPermission();
      if (_locationPermissionStatus == PermissionStatus.denied) {
        _locationPermissionStatus = await _location.requestPermission();
        if (_locationPermissionStatus != PermissionStatus.granted) {
          return;
        }
      }

      // Configure location settings
      await _location.changeSettings(
        accuracy: LocationAccuracy.high,
        interval: 20000, // 20 seconds in milliseconds
        distanceFilter: 5, // minimum distance (in meters) to trigger updates
      );

      // Start tracking location
      _startLocationTracking();
    } catch (e) {
      print("Error initializing location service: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to initialize location service")),
      );
    }
  }

  // Start tracking location
  void _startLocationTracking() {
    if (_isTrackingLocation) return;

    _isTrackingLocation = true;

    // Get location immediately
    _getCurrentLocation();

    // Set up timer for periodic updates
    _locationTimer = Timer.periodic(Duration(seconds: 20), (timer) {
      _getCurrentLocation();
    });
  }

  // Stop tracking location
  void _stopLocationTracking() {
    _locationTimer?.cancel();
    _isTrackingLocation = false;
  }

  // Get current location and store it
  Future<void> _getCurrentLocation() async {
    try {
      final locationData = await _location.getLocation();
      setState(() {
        _currentLocation = locationData;
      });

      // Store location in Firebase
      await _storeLocationData(locationData);

      print(
        "Location updated: ${locationData.latitude}, ${locationData.longitude}",
      );
    } catch (e) {
      print("Error getting location: $e");
    }
  }

  // Store location data in Firebase
  Future<void> _storeLocationData(LocationData locationData) async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // Create a reference to the user's location history
        final locationRef = _database.ref("users/${user.uid}/location_history");

        // Create a new entry with timestamp
        final newLocationRef = locationRef.push();
        await newLocationRef.set({
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
          'accuracy': locationData.accuracy,
          'speed': locationData.speed,
          'timestamp': ServerValue.timestamp,
        });

        // Update the user's current location
        final userCurrentLocationRef = _database.ref(
          "users/${user.uid}/current_location",
        );
        await userCurrentLocationRef.set({
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
          'accuracy': locationData.accuracy,
          'speed': locationData.speed,
          'timestamp': ServerValue.timestamp,
        });
      }
    } catch (e) {
      print("Error storing location data: $e");
    }
  }

  Future<void> _loadCachedProfile() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      firstName = prefs.getString("firstName") ?? "";
      lastName = prefs.getString("lastName") ?? "";
      email = prefs.getString("email") ?? "";
      mobile = prefs.getString("mobile") ?? "";
      fullAddress = prefs.getString("fullAddress") ?? "";
    });
  }

  Future<void> _fetchUserProfile() async {
    User? user = _auth.currentUser;
    if (user != null) {
      DatabaseReference userRef = _database.ref("users/${user.uid}");
      userRef.once().then((DatabaseEvent event) async {
        var data = event.snapshot.value as Map?;
        if (data != null) {
          setState(() {
            firstName = data["firstName"] ?? "";
            lastName = data["lastName"] ?? "";
            email = user.email ?? "";
            mobile = data["mobile"] ?? "";
            fullAddress = data["full_address"] ?? "";
            _isLoading = false;
          });

          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString("firstName", firstName);
          await prefs.setString("lastName", lastName);
          await prefs.setString("email", email);
          await prefs.setString("mobile", mobile);
          await prefs.setString("fullAddress", fullAddress);
        }
      });
    }
  }

  void _showRideHistory() {
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
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
              child: RideHistoryPage(),
            ),
          ),
    );
  }

  @override
  void dispose() {
    _stopLocationTracking();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildProfileSection() {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Colors.blue.shade300, Colors.blue.shade700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade200.withOpacity(0.5),
                    blurRadius: 15,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.transparent,
                child: Text(
                  "${firstName.isNotEmpty ? firstName[0].toUpperCase() : ''}${lastName.isNotEmpty ? lastName[0].toUpperCase() : ''}",
                  style: TextStyle(
                    fontSize: 48,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              "$firstName $lastName",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 8),
            Text(email, style: TextStyle(fontSize: 16, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileDetails() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 16),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Profile Details',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16),
            _buildDetailRow('First Name', firstName),
            _buildDetailRow('Last Name', lastName),
            _buildDetailRow('Email', email),
            _buildDetailRow('Mobile', mobile),
            _buildAddressRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 16,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressRow() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Address',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              fullAddress.isEmpty ? 'No address provided' : fullAddress,
              style: TextStyle(
                fontSize: 16,
                color: fullAddress.isEmpty ? Colors.grey : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfo() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 16),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Location',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color:
                        _isTrackingLocation
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isTrackingLocation ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color:
                          _isTrackingLocation
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            if (_currentLocation != null) ...[
              _buildLocationDetailRow(
                'Latitude',
                _currentLocation!.latitude?.toStringAsFixed(6) ?? 'N/A',
              ),
              _buildLocationDetailRow(
                'Longitude',
                _currentLocation!.longitude?.toStringAsFixed(6) ?? 'N/A',
              ),
              _buildLocationDetailRow(
                'Accuracy',
                '${_currentLocation!.accuracy?.toStringAsFixed(2) ?? 'N/A'} m',
              ),
              _buildLocationDetailRow(
                'Speed',
                '${_currentLocation!.speed?.toStringAsFixed(2) ?? 'N/A'} m/s',
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _isTrackingLocation
                              ? _stopLocationTracking
                              : _startLocationTracking,
                      icon: Icon(
                        _isTrackingLocation ? Icons.pause : Icons.play_arrow,
                      ),
                      label: Text(
                        _isTrackingLocation
                            ? 'Stop Tracking'
                            : 'Start Tracking',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _isTrackingLocation ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Center(
                child: Column(
                  children: [
                    Icon(Icons.location_off, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text(
                      'Location data not available',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _initLocationService,
                      icon: Icon(Icons.refresh),
                      label: Text('Initialize Location Service'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLocationDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideHistoryButton() {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: GestureDetector(
          onTap: _showRideHistory,
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 16),
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.shade200.withOpacity(0.5),
                  blurRadius: 15,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Ride History",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Track and review your past rides",
                        style: TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body:
          _isLoading
              ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              )
              : SafeArea(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 20),
                      _buildProfileSection(),
                      _buildProfileDetails(),
                      _buildLocationInfo(), // Add the location section
                      _buildRideHistoryButton(),
                    ],
                  ),
                ),
              ),
    );
  }
}
