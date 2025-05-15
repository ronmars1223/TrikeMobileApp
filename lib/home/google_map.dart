import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:animate_do/animate_do.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:url_launcher/url_launcher.dart';

enum TransportMode { car, motorcycle, walking }

class GoogleMapWidget extends StatefulWidget {
  const GoogleMapWidget({Key? key}) : super(key: key);

  @override
  GoogleMapWidgetState createState() => GoogleMapWidgetState();
}

class GoogleMapWidgetState extends State<GoogleMapWidget>
    with SingleTickerProviderStateMixin {
  // Controllers
  GoogleMapController? _controller;
  final Completer<GoogleMapController> _mapController = Completer();
  late AnimationController _animationController;

  // Map settings
  MapType _currentMapType = MapType.hybrid;
  bool _isMapLoading = true;
  bool _isMapTypeSelectorVisible = false;
  bool _isTripInfoVisible = true;
  bool _trafficEnabled = true; // Always true for traffic
  double _trafficMultiplier = 1.0;
  String _nightStyle = '''[
    {"elementType": "geometry", "stylers": [{"color": "#242f3e"}]},
    {"elementType": "labels.text.fill", "stylers": [{"color": "#746855"}]},
    {"elementType": "labels.text.stroke", "stylers": [{"color": "#242f3e"}]},
    {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#17263c"}]}
  ]''';

  // Location tracking
  StreamSubscription<Position>? _locationSubscription;
  Position? _currentPosition;
  bool _isFollowingUser = true;
  static const LatLng _initialPosition = LatLng(8.0000, 124.0000);
  static const LatLng _defaultUserLocation = LatLng(8.4542, 124.6319);

  // Route and navigation
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  String? _destination;
  String? _pickup;
  LatLng? _destinationCoords;
  LatLng? _pickupCoords;
  double? _distance;
  List<LatLng> _routePoints = [];
  double _routeDistance = 0;
  String _routeDuration = "";
  bool _isLoadingDirections = false;
  String _routeType = "Fastest Route";
  TransportMode _selectedTransportMode = TransportMode.car;
  List<Map<String, String>> _emergencyContacts = [];
  bool _hasNotifiedEmergencyContacts = false;
  bool _hasArrivedAtDestination = false;
  double _arrivalThresholdDistance = 0.5;

  // Countdown timer
  Timer? _countdownTimer;
  String _countdownText = "";
  DateTime? _estimatedArrivalTime;

  // API key
  final String _apiKey = "AIzaSyCZxuhUy8SfuNsPDQ7J2F1VQy9eUAfqVKI";

  @override
  void initState() {
    super.initState();

    // Enable hybrid composition for Google Maps
    final GoogleMapsFlutterPlatform mapsImplementation =
        GoogleMapsFlutterPlatform.instance;
    if (mapsImplementation is GoogleMapsFlutterAndroid) {
      mapsImplementation.useAndroidViewSurface = true;
    }

    // Always enable traffic
    _trafficEnabled = true;

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    );

    Future.delayed(Duration(milliseconds: 100), () {
      _startLocationTracking();
      _initializeTrafficConditions();
      _fetchEmergencyContacts();
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _animationController.dispose();
    _locationSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _initializeTrafficConditions() {
    final hour = DateTime.now().hour;
    if (hour >= 7 && hour <= 9) {
      _trafficMultiplier = 1.5; // Morning rush
    } else if (hour >= 16 && hour <= 19) {
      _trafficMultiplier = 1.7; // Evening rush
    } else if (hour >= 23 || hour <= 5) {
      _trafficMultiplier = 0.8; // Late night
    } else {
      _trafficMultiplier = 1.2; // Normal daytime
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      // First check for permissions as in the original code
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }
      }

      // Get the current user from Firebase Auth
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print('No user logged in, cannot access location');
        return;
      }

      // Reference to the database location
      final DatabaseReference databaseRef = FirebaseDatabase.instance.ref();
      final String userId = currentUser.uid;

      // Set up a listener for the user's location in Firebase
      databaseRef.child('users/$userId/current_location').onValue.listen((
        event,
      ) {
        if (!mounted) return;

        final data = event.snapshot.value as Map<dynamic, dynamic>?;
        if (data != null) {
          setState(() {
            // Create a Position object from the Firebase data with all required parameters
            _currentPosition = Position(
              latitude: data['latitude'] ?? 0.0,
              longitude: data['longitude'] ?? 0.0,
              timestamp: DateTime.fromMillisecondsSinceEpoch(
                (data['timestamp'] as int?) ?? 0,
              ),
              accuracy: data['accuracy'] ?? 0.0,
              altitude: 0.0,
              heading: 0.0,
              speed: data['speed'] ?? 0.0,
              speedAccuracy: 0.0,
              altitudeAccuracy: 0.0,
              headingAccuracy: 0.0,
              floor: null,
              isMocked: false,
            );

            // Update pickup coordinates if needed
            if (_pickup == null || _pickup!.contains("Current Location")) {
              _pickupCoords = LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              );
              if (_destinationCoords != null) {
                _distance = _calculateDistance(
                  _pickupCoords!,
                  _destinationCoords!,
                );
              }
            }

            // Check if user has arrived at destination
            if (_destinationCoords != null && !_hasArrivedAtDestination) {
              double distanceToDestination = _calculateDistance(
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                _destinationCoords!,
              );

              // If within threshold distance (50 meters = 0.05 km), mark as arrived
              if (distanceToDestination <= _arrivalThresholdDistance) {
                _hasArrivedAtDestination = true;
                _countdownTimer?.cancel();
                _countdownText = "Arrived";

                // Show arrived notification
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('You have arrived at your destination!'),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 5),
                  ),
                );

                // Auto-reload route information
                _reloadRouteOnArrival();
              }
            }
          });

          // Move the map to follow user if needed
          if (_isFollowingUser) {
            _animateToCurrentLocation(zoom: 17.0);
          }
        }
      });

      // Get the initial position
      final snapshot =
          await databaseRef.child('users/$userId/current_location').get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<dynamic, dynamic>;

        _currentPosition = Position(
          latitude: data['latitude'] ?? 0.0,
          longitude: data['longitude'] ?? 0.0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            (data['timestamp'] as int?) ?? 0,
          ),
          accuracy: data['accuracy'] ?? 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: data['speed'] ?? 0.0,
          speedAccuracy: 0.0,
          altitudeAccuracy: 0.0, // Added missing parameter
          headingAccuracy: 0.0, // Added missing parameter
          floor: null, // Added missing parameter
          isMocked: false, // Added missing parameter
        );

        if (mounted) {
          setState(() {
            _pickupCoords = LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            );
          });
        }
      }

      // We don't need the locationSubscription from the original code
      // since we're using Firebase as our location source
      _locationSubscription = null;
    } catch (e) {
      print('Error starting location tracking: $e');
    }
  }

  void _reloadRouteOnArrival() {
    // Cancel any existing timers
    _countdownTimer?.cancel();

    // Reset the arrival state after a short delay (to allow notification to be seen)
    Future.delayed(Duration(seconds: 5), () {
      if (!mounted) return;

      // Only perform auto-reload if we're still on the same destination
      if (_hasArrivedAtDestination && _destinationCoords != null) {
        setState(() {
          // Mark that we've completed this destination
          _hasArrivedAtDestination = true;
          _countdownText = "Arrived";

          // Update the UI to reflect arrival
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: PolylineId('arrival_route'),
              points: [
                LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                _destinationCoords!,
              ],
              color: Colors.green,
              width: 6,
            ),
          );

          // Show the destination mark more prominently
          _markers.clear();
          _markers.add(
            Marker(
              markerId: MarkerId('destination'),
              position: _destinationCoords!,
              infoWindow: InfoWindow(
                title: 'Destination',
                snippet: _destination,
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          );

          // Show current location marker
          _markers.add(
            Marker(
              markerId: MarkerId('current_location'),
              position: LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              ),
              infoWindow: InfoWindow(title: 'Current Location'),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueBlue,
              ),
            ),
          );
        });

        // Center the map to show both the user and destination
        _zoomToShowBothLocations(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          _destinationCoords!,
        );
      }
    });
  }

  // Modify the _updateCurrentLocation method to check if user has arrived
  Future<void> _animateToCurrentLocation({double zoom = 14.0}) async {
    try {
      final controller = await _mapController.future;
      if (controller != null && _currentPosition != null && mounted) {
        controller.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
              ),
              zoom: zoom,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error animating to current location: $e');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    if (!mounted) return;
    _controller = controller;
    if (!_mapController.isCompleted) {
      _mapController.complete(controller);
    }
    setState(() => _isMapLoading = false);
    if (_currentPosition != null) {
      _animateToCurrentLocation();
    }
  }

  void _onMapInteraction() => setState(() => _isFollowingUser = false);

  // Calculate distance between two points (in kilometers)
  double _calculateDistance(LatLng start, LatLng end) {
    const R = 6371.0; // Earth radius in kilometers
    final lat1 = start.latitude * (math.pi / 180);
    final lat2 = end.latitude * (math.pi / 180);
    final dLat = (end.latitude - start.latitude) * (math.pi / 180);
    final dLon = (end.longitude - start.longitude) * (math.pi / 180);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  String _formatDistance(double distanceKm) {
    return distanceKm < 1
        ? '${(distanceKm * 1000).toStringAsFixed(0)} m'
        : '${distanceKm.toStringAsFixed(1)} km';
  }

  void _toggleTripInfoVisibility() =>
      setState(() => _isTripInfoVisible = !_isTripInfoVisible);

  void _toggleMapTypeSelector() => setState(() {
    _isMapTypeSelectorVisible = !_isMapTypeSelectorVisible;
    _isMapTypeSelectorVisible
        ? _animationController.forward()
        : _animationController.reverse();
  });

  void _changeMapType(MapType type) async {
    setState(() {
      _currentMapType = type;
      _isMapTypeSelectorVisible = false;
      _animationController.reverse();
    });

    final controller = await _mapController.future;
    if (type == MapType.hybrid || type == MapType.terrain) {
      controller.setMapStyle(null);
    }
  }

  void _applyNightMode() async {
    final controller = await _mapController.future;
    controller.setMapStyle(_nightStyle);
    setState(() {
      _currentMapType = MapType.normal;
      _isMapTypeSelectorVisible = false;
      _animationController.reverse();
    });
  }

  Future<void> _goToMyLocation() async {
    setState(() => _isFollowingUser = true);
    await _animateToCurrentLocation();
  }

  // Countdown Timer Methods
  void _startCountdown(Duration duration) {
    _countdownTimer?.cancel();
    _estimatedArrivalTime = DateTime.now().add(duration);
    _updateCountdownText();
    _countdownTimer = Timer.periodic(
      Duration(seconds: 1),
      (_) => _updateCountdownText(),
    );
  }

  void _updateCountdownText() {
    if (_estimatedArrivalTime == null || !mounted) return;

    // If we've arrived at destination, always show "Arrived" state
    if (_hasArrivedAtDestination) {
      setState(() => _countdownText = "Arrived");
      return;
    }

    final now = DateTime.now();
    final difference = _estimatedArrivalTime!.difference(now);

    // If time is up but we haven't arrived
    if (difference.isNegative) {
      setState(() => _countdownText = "Time's up!");

      // Send notification immediately when time is up and not arrived yet
      // BUT ONLY IF we haven't sent it already
      if (!_hasNotifiedEmergencyContacts) {
        print("⚠️ TIME'S UP! Sending emergency notifications now...");
        _notifyEmergencyContacts();

        // Cancel the timer to prevent further checks
        _countdownTimer?.cancel();
      }
      return;
    }

    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;
    final seconds = difference.inSeconds % 60;

    setState(() {
      if (hours > 0) {
        _countdownText = "${hours}h ${minutes}m ${seconds}s";
      } else if (minutes > 0) {
        _countdownText = "${minutes}m ${seconds}s";
      } else {
        _countdownText = "${seconds}s";
      }
    });
  }

  Future<Map<String, dynamic>?> fetchUserInfo() async {
    print("🔄 Fetching complete user info");

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print("❌ No user logged in - Cannot fetch user info");
      return null;
    }

    try {
      final db = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
      );

      final userRef = db.ref('users').child(currentUser.uid);
      final snapshot = await userRef.get().timeout(Duration(seconds: 5));

      if (snapshot.exists) {
        final raw = snapshot.value;
        if (raw is Map) {
          final userData = Map<String, dynamic>.from(raw);
          print("✅ User data fetched: $userData");
          return userData;
        }
      }
    } catch (e) {
      print("❌ Error during fetchUserInfo: $e");
    }

    return null;
  }

  Future<void> _notifyEmergencyContacts() async {
    print("🔄 STARTING EMERGENCY NOTIFICATION PROCESS");

    // Set a timeout flag to prevent hanging
    bool isTimeoutOccurred = false;
    Timer timeoutTimer = Timer(Duration(seconds: 30), () {
      isTimeoutOccurred = true;
      print("⚠️ SMS sending process timed out");
      setState(() {
        _hasNotifiedEmergencyContacts =
            true; // Mark as notified to prevent retries
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Emergency notification process timed out. Please try again.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    });

    // Fetch emergency contacts first with a shorter timeout
    List<Map<String, String>> contacts = [];
    try {
      print("🔄 Fetching emergency contacts");

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("❌ No user logged in - Cannot fetch contacts");
        timeoutTimer.cancel();
        throw Exception("No user logged in");
      }

      // Directly fetch contacts with shorter timeout
      final url = Uri.parse(
        'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/emergency_contacts/${currentUser.uid}.json',
      );

      final response = await http.get(url).timeout(Duration(seconds: 5));

      print("🔍 Contacts API Response status: ${response.statusCode}");

      if (response.statusCode == 200 &&
          response.body != 'null' &&
          response.body.isNotEmpty) {
        try {
          final Map<String, dynamic> contactsMap =
              json.decode(response.body) as Map<String, dynamic>;

          contactsMap.forEach((key, value) {
            final name = value['name']?.toString() ?? '';
            final phone = value['phone']?.toString() ?? '';

            if (name.isNotEmpty && phone.isNotEmpty) {
              String cleanedPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
              contacts.add({'name': name, 'phone': cleanedPhone});
              print("📱 Loaded contact: $name ($cleanedPhone)");
            }
          });
        } catch (e) {
          print("⚠️ Error parsing contacts JSON: $e");
        }
      }

      if (contacts.isEmpty) {
        print("⚠️ No contacts found in database, will try fallback fetch");

        // Try fallback approach by querying the general contacts location
        final fallbackUrl = Uri.parse(
          'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/emergency_contacts.json',
        );

        final fallbackResponse = await http
            .get(fallbackUrl)
            .timeout(Duration(seconds: 5));

        if (fallbackResponse.statusCode == 200 &&
            fallbackResponse.body != 'null' &&
            fallbackResponse.body.isNotEmpty) {
          try {
            final Map<String, dynamic> rootData =
                json.decode(fallbackResponse.body) as Map<String, dynamic>;

            rootData.forEach((groupKey, groupValue) {
              if (groupValue is Map<String, dynamic>) {
                groupValue.forEach((contactKey, contactValue) {
                  if (contactValue is Map<String, dynamic>) {
                    if (contactValue.containsKey('uid') &&
                        contactValue['uid'] == currentUser.uid &&
                        contactValue.containsKey('name') &&
                        contactValue.containsKey('phone')) {
                      final name = contactValue['name']?.toString() ?? '';
                      final phone = contactValue['phone']?.toString() ?? '';

                      if (name.isNotEmpty && phone.isNotEmpty) {
                        String cleanedPhone = phone.replaceAll(
                          RegExp(r'[^\d+]'),
                          '',
                        );
                        contacts.add({'name': name, 'phone': cleanedPhone});
                        print(
                          "📱 Loaded fallback contact: $name ($cleanedPhone)",
                        );
                      }
                    }
                  }
                });
              }
            });
          } catch (e) {
            print("⚠️ Error parsing fallback contacts JSON: $e");
          }
        }
      }
    } catch (e) {
      print("❌ Error fetching emergency contacts: $e");
    }

    // If no contacts were found, we can't continue
    if (contacts.isEmpty) {
      print("❌ NO EMERGENCY CONTACTS FOUND - Cannot send notifications");
      timeoutTimer.cancel();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No emergency contacts found to notify'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    print("✅ Found ${contacts.length} emergency contacts");

    if (_hasNotifiedEmergencyContacts) {
      print("ℹ️ Emergency contacts already notified - skipping");
      timeoutTimer.cancel();
      return;
    }

    try {
      // Default values
      String fullName = 'Trike User';
      Position? userPosition =
          _currentPosition; // Default to the current tracking position

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null) {
        // Use our new function to fetch all user information at once
        try {
          print("🔄 Fetching user information using fetchUserInfo()");
          final userInfo = await fetchUserInfo();

          if (userInfo != null) {
            final firstName = userInfo['firstName']?.toString() ?? '';
            final lastName = userInfo['lastName']?.toString() ?? '';

            if (firstName.isNotEmpty || lastName.isNotEmpty) {
              fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
              print("📝 Using fetched user name: $fullName");
            }

            if (userInfo.containsKey('current_location')) {
              try {
                final locationData =
                    userInfo['current_location'] as Map<dynamic, dynamic>;
                final latitude = locationData['latitude']?.toDouble();
                final longitude = locationData['longitude']?.toDouble();

                if (latitude != null && longitude != null) {
                  userPosition = Position(
                    latitude: latitude,
                    longitude: longitude,
                    timestamp: DateTime.now(),
                    accuracy: 0,
                    altitude: 0,
                    heading: 0,
                    speed: 0,
                    speedAccuracy: 0,
                    altitudeAccuracy: 0,
                    headingAccuracy: 0,
                    floor: null,
                    isMocked: false,
                  );
                  print(
                    "📍 Using location from database: $latitude, $longitude",
                  );
                }
              } catch (e) {
                print("⚠️ Error parsing location data: $e");
              }
            }
          }
        } catch (e) {
          print("⚠️ fetchUserInfo failed: $e - will try fallbacks");

          // Fallback to direct database query with a tight timeout
          try {
            final userSnapshot = await FirebaseDatabase.instance
                .ref()
                .child('users/${currentUser.uid}')
                .get()
                .timeout(Duration(seconds: 2));

            if (userSnapshot.exists) {
              final userData = userSnapshot.value as Map<dynamic, dynamic>;
              final firstName = userData['firstName']?.toString() ?? '';
              final lastName = userData['lastName']?.toString() ?? '';

              if (firstName.isNotEmpty || lastName.isNotEmpty) {
                fullName = '${firstName.trim()} ${lastName.trim()}'.trim();
                print("📝 Using fallback database user name: $fullName");
              }
            }
          } catch (e) {
            print("⚠️ Could not fetch user info: $e - using default name");
          }
        }

        // Last fallback options if we still don't have a name
        if (fullName == 'Trike User') {
          if (currentUser.displayName != null &&
              currentUser.displayName!.isNotEmpty) {
            fullName = currentUser.displayName!;
            print("📝 Using Firebase Auth display name: $fullName");
          } else if (currentUser.email != null) {
            String emailName = currentUser.email!.split('@')[0];
            // Capitalize first letter of email name
            if (emailName.isNotEmpty) {
              emailName = emailName[0].toUpperCase() + emailName.substring(1);
              fullName = emailName;
              print("📝 Using Firebase Auth email name: $fullName");
            }
          }
        }
      }

      // Check if the operation has timed out
      if (isTimeoutOccurred) return;

      // Get location directly from current position variable
      String locationText = 'Location unavailable';
      if (userPosition != null) {
        final lat = userPosition.latitude;
        final lng = userPosition.longitude;
        locationText = 'https://maps.google.com/maps?q=$lat,$lng';
      }

      final destinationText = _destination ?? 'their destination';
      final message =
          '$fullName has not arrived at $destinationText. Current location: $locationText';

      print("📝 Prepared message: $message");

      // Flag to track if at least one message was sent successfully
      bool atLeastOneMessageSent = false;

      // Process each contact
      for (final contact in contacts) {
        // Check for timeout before sending each message
        if (isTimeoutOccurred) return;

        final phoneNumber = contact['phone'] ?? '';
        final contactName = contact['name'] ?? 'Contact';

        // Basic phone number validation
        if (phoneNumber.isEmpty || phoneNumber.length < 10) {
          print("⚠️ Invalid phone number for contact: $contactName");
          continue;
        }

        print("📞 Sending to $contactName ($phoneNumber)");

        try {
          // Format the phone number properly
          String formattedPhone = _formatPhoneNumber(phoneNumber);

          if (formattedPhone.isEmpty) {
            print("Invalid phone format for $contactName: $phoneNumber");
            continue;
          }

          // Send the SMS
          var response = await _sendSingleSms(formattedPhone, message);

          if (response['success']) {
            print("✅ SMS sent successfully to $contactName ($formattedPhone)");
            atLeastOneMessageSent = true;
          } else {
            print("❌ Failed to send SMS to $contactName: ${response['error']}");
          }
        } catch (e) {
          print("❌ Exception while sending SMS to $contactName: $e");
        }

        // Small delay between sending messages
        await Future.delayed(Duration(milliseconds: 500));
      }

      // Cancel the timeout timer as we've completed the process
      timeoutTimer.cancel();

      setState(() {
        _hasNotifiedEmergencyContacts = true;
      });

      print("✅ EMERGENCY NOTIFICATION PROCESS COMPLETED");

      if (atLeastOneMessageSent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency contacts have been notified'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      } else {
        throw Exception("No messages were sent successfully");
      }
    } catch (e) {
      print("❌ ERROR DURING EMERGENCY NOTIFICATION: $e");
      print("❌ Stack trace: ${StackTrace.current}");

      // Cancel the timeout timer
      timeoutTimer.cancel();

      setState(() {
        _hasNotifiedEmergencyContacts =
            true; // Mark as completed to avoid infinite retries
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to send emergency notifications. Please try again or call for help.',
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  /// Format phone number according to Semaphore guidelines
  String _formatPhoneNumber(String phone) {
    // Strip any non-numeric characters
    phone = phone.replaceAll(RegExp(r'\D'), '');

    // If empty after stripping, return empty
    if (phone.isEmpty) {
      return '';
    }

    // Check if it's a Philippine number and format correctly
    if (phone.startsWith("0")) {
      // Convert 09XXXXXXXXX to 639XXXXXXXXX (without + symbol)
      phone = "63" + phone.substring(1);
    } else if (phone.startsWith("9") && phone.length == 10) {
      // Convert 9XXXXXXXXX to 639XXXXXXXXX
      phone = "63" + phone;
    } else if (phone.startsWith("+63")) {
      // Remove the + symbol
      phone = phone.substring(1);
    } else if (phone.startsWith("63") && phone.length >= 12) {
      // Already in correct format
    } else if (phone.length == 11 && phone.startsWith("0")) {
      // Convert 09XXXXXXXXX to 639XXXXXXXXX
      phone = "63" + phone.substring(1);
    } else {
      // If it doesn't match any known pattern, try to make a best guess
      if (phone.length == 10) {
        // Assume it's a 10-digit number missing the country code
        phone = "63" + phone;
      } else if (phone.length == 11 && !phone.startsWith("0")) {
        // Some other 11-digit format
        phone = "63" + phone.substring(phone.length - 10);
      }
    }

    // Validate that it seems like a proper phone number format
    if ((phone.startsWith("63") && phone.length >= 12) ||
        (!phone.startsWith("63") && phone.length >= 10)) {
      return phone;
    }

    return '';
  }

  /// Send a single SMS using the Semaphore API
  Future<Map<String, dynamic>> _sendSingleSms(
    String phoneNumber,
    String message,
  ) async {
    try {
      print("Sending SMS to: $phoneNumber");

      // Semaphore SMS API credentials
      const String apiKey = "ebced0ed69d67b826ef466fda6bd533b";
      const String senderName = "Trike";
      const String apiUrl = "https://semaphore.co/api/v4/messages";

      // Create form data
      var formData = {
        'apikey': apiKey,
        'number': phoneNumber,
        'message': message,
        'sendername': senderName,
      };

      // Make the HTTP POST request with a shorter timeout
      final response = await http
          .post(Uri.parse(apiUrl), body: formData)
          .timeout(Duration(seconds: 8));

      print("SMS API Response code: ${response.statusCode}");
      print("SMS API Response body: ${response.body}");

      if (response.statusCode == 200) {
        try {
          List<dynamic> responseList = json.decode(response.body);
          if (responseList.isNotEmpty) {
            var msgResponse = responseList[0];
            if (msgResponse is Map<String, dynamic>) {
              String status = msgResponse['status'] ?? 'unknown';
              if (status.toLowerCase() == 'pending' ||
                  status.toLowerCase() == 'success') {
                return {'success': true};
              } else {
                return {
                  'success': false,
                  'error': 'Message status: ${status.toLowerCase()}',
                };
              }
            }
          }
          // If we can't determine status from response, assume success
          return {'success': true};
        } catch (e) {
          print("Error parsing API response: $e");
          // If response is 200 but parsing fails, assume success
          return {'success': true};
        }
      } else {
        return {
          'success': false,
          'error': 'HTTP Error ${response.statusCode}: ${response.body}',
        };
      }
    } catch (e) {
      print("Exception sending SMS: $e");
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> _fetchEmergencyContacts() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        print("⚠️ No user logged in");
        return false;
      }

      final url = Uri.parse(
        'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/emergency_contacts/${currentUser.uid}.json',
      );

      // Add timeout to the HTTP request
      final response = await http
          .get(url)
          .timeout(
            Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException("Fetching contacts timed out");
            },
          );

      print("🔍 Contacts API Response status: ${response.statusCode}");
      print(
        "🔍 Contacts API Response body: ${response.body.substring(0, math.min(100, response.body.length))}...",
      );

      if (response.statusCode != 200) {
        print("⚠️ Error fetching contacts: HTTP ${response.statusCode}");
        return false;
      }

      if (response.body == 'null' || response.body.isEmpty) {
        print("⚠️ No contacts found in database");
        return false;
      }

      try {
        final Map<String, dynamic> contactsMap =
            json.decode(response.body) as Map<String, dynamic>;

        final List<Map<String, String>> loadedContacts = [];

        contactsMap.forEach((key, value) {
          final name = value['name']?.toString() ?? '';
          final phone = value['phone']?.toString() ?? '';

          if (name.isNotEmpty && phone.isNotEmpty) {
            // Basic phone number cleaning
            String cleanedPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');

            // Add the contact with cleaned phone number
            loadedContacts.add({'name': name, 'phone': cleanedPhone});
            print("📱 Loaded contact: $name ($cleanedPhone)");
          } else {
            print("⚠️ Skipping invalid contact: name=$name, phone=$phone");
          }
        });

        setState(() {
          _emergencyContacts = loadedContacts;
        });

        print("📱 Loaded ${loadedContacts.length} contacts");
        return loadedContacts.isNotEmpty;
      } catch (e) {
        print("❌ Error parsing contacts JSON: $e");
        print(
          "🔍 JSON data: ${response.body.substring(0, math.min(100, response.body.length))}...",
        );
        return false;
      }
    } catch (e) {
      print("❌ Error fetching emergency contacts: $e");
      return false;
    }
  }

  // Parse duration string from Google API
  Duration _parseDurationText(String durationText) {
    int hours = 0;
    int minutes = 0;

    final hourRegex = RegExp(r'(\d+)\s*hour');
    final hourMatch = hourRegex.firstMatch(durationText);
    if (hourMatch != null && hourMatch.groupCount >= 1) {
      hours = int.tryParse(hourMatch.group(1) ?? '0') ?? 0;
    }

    final minRegex = RegExp(r'(\d+)\s*min');
    final minMatch = minRegex.firstMatch(durationText);
    if (minMatch != null && minMatch.groupCount >= 1) {
      minutes = int.tryParse(minMatch.group(1) ?? '0') ?? 0;
    }

    return Duration(hours: hours, minutes: minutes);
  }

  void _resetCountdown() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Reset Arrival Time'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Reset to original estimate'),
                onTap: () {
                  Navigator.pop(context);
                  final duration = _parseDurationText(_routeDuration);
                  _startCountdown(duration);
                },
              ),
              Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
              ListTile(
                leading: Icon(Icons.add_circle_outline),
                title: Text('Add 5 minutes'),
                onTap: () {
                  Navigator.pop(context);
                  if (_estimatedArrivalTime != null) {
                    _estimatedArrivalTime = _estimatedArrivalTime!.add(
                      Duration(minutes: 5),
                    );
                    _updateCountdownText();
                  }
                },
              ),
              ListTile(
                leading: Icon(Icons.remove_circle_outline),
                title: Text('Subtract 5 minutes'),
                onTap: () {
                  Navigator.pop(context);
                  if (_estimatedArrivalTime != null) {
                    _estimatedArrivalTime = _estimatedArrivalTime!.subtract(
                      Duration(minutes: 5),
                    );
                    _updateCountdownText();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        );
      },
    );
  }

  String _formatArrivalTime(DateTime arrivalTime) {
    final hour =
        arrivalTime.hour > 12
            ? arrivalTime.hour - 12
            : (arrivalTime.hour == 0 ? 12 : arrivalTime.hour);
    final minute = arrivalTime.minute.toString().padLeft(2, '0');
    final period = arrivalTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  void setDestinationWithCoords(
    String destination,
    LatLng destinationCoords,
    String pickup,
    LatLng pickupCoords,
  ) async {
    if (!mounted) return;

    setState(() {
      _destination = destination;
      _destinationCoords = destinationCoords;
      _pickup = pickup;
      _pickupCoords = pickupCoords;
      _distance = _calculateDistance(pickupCoords, destinationCoords);
      _hasArrivedAtDestination = false;
      _hasNotifiedEmergencyContacts = false;

      _markers.clear();
      _markers.add(
        Marker(
          markerId: MarkerId('destination'),
          position: destinationCoords,
          infoWindow: InfoWindow(title: 'Destination', snippet: destination),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );

      _markers.add(
        Marker(
          markerId: MarkerId('pickup'),
          position: pickupCoords,
          infoWindow: InfoWindow(title: 'Pickup', snippet: pickup),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );

      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: PolylineId('route'),
          points: [pickupCoords, destinationCoords],
          color: Colors.blue,
          width: 5,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );
    });

    _zoomToShowBothLocations(pickupCoords, destinationCoords);
    _getDirections(pickupCoords, destinationCoords);
  }

  Future<void> _zoomToShowBothLocations(LatLng from, LatLng to) async {
    try {
      final controller = await _mapController.future;
      if (controller == null) return;

      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          math.min(from.latitude, to.latitude),
          math.min(from.longitude, to.longitude),
        ),
        northeast: LatLng(
          math.max(from.latitude, to.latitude),
          math.max(from.longitude, to.longitude),
        ),
      );

      controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } catch (e) {
      print('Error zooming to locations: $e');
    }
  }

  void setDestination(String destination) async {
    final double lat = 8.0 + (destination.hashCode % 100) / 100.0;
    final double lng = 124.0 + (destination.hashCode % 100) / 100.0;
    final LatLng destinationCoords = LatLng(lat, lng);

    setDestinationWithCoords(
      destination,
      destinationCoords,
      "Current Location",
      _currentPosition != null
          ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
          : _defaultUserLocation,
    );
  }

  void clearDestination() {
    if (!mounted) return;
    setState(() {
      _destination = null;
      _pickup = null;
      _destinationCoords = null;
      _pickupCoords = null;
      _distance = null;
      _markers.clear();
      _polylines.clear();
      _countdownTimer?.cancel();
      _countdownText = "";
      _estimatedArrivalTime = null;
      _hasArrivedAtDestination = false;
      _hasNotifiedEmergencyContacts = false;
    });
  }

  Future<void> _getDirections(LatLng origin, LatLng destination) async {
    return findFastestRoute(origin, destination);
  }

  // Method to find the fastest route
  Future<void> findFastestRoute([
    LatLng? originOverride,
    LatLng? destinationOverride,
  ]) async {
    final origin = originOverride ?? _pickupCoords;
    final destination = destinationOverride ?? _destinationCoords;

    if (origin == null || destination == null || !mounted) return;

    setState(() {
      _isLoadingDirections = true;
      _routeType = "Fastest Route";
    });

    try {
      String travelMode;
      switch (_selectedTransportMode) {
        case TransportMode.car:
          travelMode = "driving";
          break;
        case TransportMode.motorcycle:
          travelMode = "driving"; // API doesn't have motorcycle mode
          break;
        case TransportMode.walking:
          travelMode = "walking";
          break;
        default:
          travelMode = "driving";
      }

      // Modified URL to ensure highway routes with your API key
      final url =
          'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&mode=$travelMode'
          '&alternatives=true'
          '&avoid=ferries|indoor' // Avoid ferries and indoor, but not highways
          '&traffic_model=best_guess'
          '&departure_time=now'
          '&key=$_apiKey'; // Your API key

      print("Directions API URL: $url"); // Debug logging

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print("API Response Status: ${data['status']}"); // Debug logging

        if (data['status'] == 'OK') {
          final routes = data['routes'];
          print("Found ${routes.length} routes"); // Debug logging

          if (routes.isNotEmpty) {
            var fastestDuration = double.infinity;
            var fastestRouteIndex = 0;
            var highwayRouteIndex = -1;

            // Check each route and prioritize highways
            for (int i = 0; i < routes.length; i++) {
              final route = routes[i];
              final summary = route['summary'] ?? '';
              print("Route $i summary: $summary"); // Debug logging

              // Check if summary contains highway keywords
              if (summary.toLowerCase().contains('highway') ||
                  summary.toLowerCase().contains('hwy') ||
                  summary.toLowerCase().contains('expressway') ||
                  summary.toLowerCase().contains('freeway') ||
                  summary.toLowerCase().contains('interstate')) {
                highwayRouteIndex = i;
                print(
                  "Highway route found at index $i: $summary",
                ); // Debug logging
              }

              final legs = route['legs'];
              if (legs.isNotEmpty) {
                final leg = legs[0];
                int durationValue;
                if (_trafficEnabled && leg.containsKey('duration_in_traffic')) {
                  durationValue = leg['duration_in_traffic']['value'];
                } else {
                  durationValue = leg['duration']['value'];
                }

                if (durationValue < fastestDuration) {
                  fastestDuration = durationValue.toDouble();
                  fastestRouteIndex = i;
                }
              }
            }

            // Prefer highway routes if available, otherwise use fastest
            final selectedRouteIndex =
                (highwayRouteIndex != -1)
                    ? highwayRouteIndex
                    : fastestRouteIndex;
            print("Selected route index: $selectedRouteIndex"); // Debug logging

            final route = routes[selectedRouteIndex];
            final summary = route['summary'] ?? '';
            final legs = route['legs'];
            if (legs.isNotEmpty) {
              final leg = legs[0];
              final distance = leg['distance']['value'];
              final duration = leg['duration']['text'];
              String durationInTraffic = duration;

              if (leg.containsKey('duration_in_traffic') && _trafficEnabled) {
                durationInTraffic = leg['duration_in_traffic']['text'];
              }

              // Get the encoded polyline points and decode them
              final points = _decodePolyline(
                route['overview_polyline']['points'],
              );

              if (!mounted) return;

              setState(() {
                _routePoints = points;
                _routeDistance = distance.toDouble();
                _routeDuration = durationInTraffic;
                _distance = _routeDistance / 1000;

                if (summary.isNotEmpty) {
                  _routeType = "Fastest Route via $summary";
                } else {
                  _routeType = "Fastest Route";
                }

                // Update polylines with the route
                _polylines.clear();
                _polylines.add(
                  Polyline(
                    polylineId: PolylineId('route'),
                    points: _routePoints,
                    color: Colors.blue,
                    width: 5,
                  ),
                );
              });

              _startCountdown(_parseDurationText(durationInTraffic));
              _fitBoundsWithMarkers();
            }
          }
        } else {
          print('Directions API error: ${data['status']}');
          _calculateBasicRoute(origin, destination);
        }
      } else {
        print('Failed to get directions: ${response.statusCode}');
        _calculateBasicRoute(origin, destination);
      }
    } catch (e) {
      print('Error finding fastest route: $e');
      _calculateBasicRoute(origin, destination);
    } finally {
      if (mounted) {
        setState(() => _isLoadingDirections = false);
      }
    }
  }

  Future<void> _fitBoundsWithMarkers() async {
    if (_routePoints.isEmpty ||
        _pickupCoords == null ||
        _destinationCoords == null)
      return;

    try {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          _routePoints.map((p) => p.latitude).reduce(math.min),
          _routePoints.map((p) => p.longitude).reduce(math.min),
        ),
        northeast: LatLng(
          _routePoints.map((p) => p.latitude).reduce(math.max),
          _routePoints.map((p) => p.longitude).reduce(math.max),
        ),
      );

      bounds = LatLngBounds(
        southwest: LatLng(
          math.min(
            bounds.southwest.latitude,
            math.min(_pickupCoords!.latitude, _destinationCoords!.latitude),
          ),
          math.min(
            bounds.southwest.longitude,
            math.min(_pickupCoords!.longitude, _destinationCoords!.longitude),
          ),
        ),
        northeast: LatLng(
          math.max(
            bounds.northeast.latitude,
            math.max(_pickupCoords!.latitude, _destinationCoords!.latitude),
          ),
          math.max(
            bounds.northeast.longitude,
            math.max(_pickupCoords!.longitude, _destinationCoords!.longitude),
          ),
        ),
      );

      final controller = await _mapController.future;
      if (controller != null) {
        controller.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
      }
    } catch (e) {
      print('Error fitting bounds with markers: $e');
    }
  }

  void _calculateBasicRoute(LatLng origin, LatLng destination) {
    if (!mounted) return;

    setState(() {
      _routePoints = [origin, destination];
      double straightLineDistance = _calculateDistance(origin, destination);
      double roadFactor = 1.3;
      _routeDistance = straightLineDistance * roadFactor * 1000;
      _distance = _routeDistance / 1000;

      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: PolylineId('route'),
          points: _routePoints,
          color: Colors.blue,
          width: 5,
          patterns: [PatternItem.dash(20), PatternItem.gap(10)],
        ),
      );

      int estimatedMinutes = (_distance! * 60 / 40).round();
      _routeDuration =
          estimatedMinutes < 60
              ? "$estimatedMinutes mins"
              : "${(estimatedMinutes / 60).floor()} hour ${estimatedMinutes % 60} mins";

      _startCountdown(Duration(minutes: estimatedMinutes));
    });
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.blue,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: CircleBorder(),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.all(12),
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildMapTypeOption(String title, IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: Colors.blue.shade600),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Map container with controls
        Expanded(
          child: Stack(
            children: [
              // Google Map
              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: _initialPosition,
                  zoom: 8.0,
                ),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                compassEnabled: true,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                mapType: _currentMapType,
                markers: _markers,
                polylines: _polylines,
                onCameraMove: (_) => _onMapInteraction(),
                onTap: (_) => _onMapInteraction(),
                trafficEnabled: _trafficEnabled,
              ),

              // Loading indicator
              if (_isMapLoading)
                Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),

              // Map control buttons
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildControlButton(
                      icon: Icons.layers,
                      onTap: _toggleMapTypeSelector,
                    ),
                    SizedBox(height: 12),
                    _buildControlButton(
                      icon: Icons.my_location,
                      onTap: _goToMyLocation,
                    ),
                    SizedBox(height: 12),
                    _buildControlButton(
                      icon: Icons.add,
                      onTap: () async {
                        final controller = await _mapController.future;
                        controller.animateCamera(CameraUpdate.zoomIn());
                      },
                    ),
                    SizedBox(height: 12),
                    _buildControlButton(
                      icon: Icons.remove,
                      onTap: () async {
                        final controller = await _mapController.future;
                        controller.animateCamera(CameraUpdate.zoomOut());
                      },
                    ),
                  ],
                ),
              ),

              // Map Type Selector Panel
              if (_isMapTypeSelectorVisible)
                Positioned(
                  right: 16,
                  bottom: 176,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(1, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _animationController,
                        curve: Curves.easeOut,
                      ),
                    ),
                    child: Container(
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMapTypeOption(
                            'Hybrid',
                            Icons.map_outlined,
                            () => _changeMapType(MapType.hybrid),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.grey.shade200,
                          ),
                          _buildMapTypeOption(
                            'Terrain',
                            Icons.terrain,
                            () => _changeMapType(MapType.terrain),
                          ),
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: Colors.grey.shade200,
                          ),
                          _buildMapTypeOption(
                            'Night Mode',
                            Icons.nightlight_round,
                            _applyNightMode,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Trip Information Panel (when destination is set)
        if (_destination != null)
          Container(
            height: _isTripInfoVisible ? null : 48,
            constraints: BoxConstraints(
              maxHeight: _isTripInfoVisible ? 300 : 48,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: Offset(0, -2),
                ),
              ],
            ),
            child: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with toggle button
                  InkWell(
                    onTap: _toggleTripInfoVisibility,
                    child: Container(
                      height: 48,
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Left side - Title when expanded, arrival status or countdown when minimized
                          Row(
                            children: [
                              if (!_isTripInfoVisible &&
                                  _distance != null &&
                                  _distance! <= 0.05)
                                // Show "Arrived" status when within 50m of destination
                                Container(
                                  margin: EdgeInsets.only(right: 10),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.green.shade300,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 14,
                                        color: Colors.green.shade800,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        "Arrived",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (!_isTripInfoVisible &&
                                  _countdownText.isNotEmpty &&
                                  (_distance == null || _distance! > 0.05))
                                // Show countdown only if not arrived and countdown exists
                                Container(
                                  margin: EdgeInsets.only(right: 10),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.orange.shade300,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.timer,
                                        size: 14,
                                        color: Colors.orange.shade800,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        _countdownText,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: Colors.orange.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(
                                _isTripInfoVisible
                                    ? 'Trip Information'
                                    : (_distance != null && _distance! <= 0.05
                                        ? 'Destination Reached'
                                        : (_estimatedArrivalTime != null
                                            ? 'ETA: ${_formatArrivalTime(_estimatedArrivalTime!)}'
                                            : 'Trip Information')),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color:
                                      _distance != null &&
                                              _distance! <= 0.05 &&
                                              !_isTripInfoVisible
                                          ? Colors.green.shade800
                                          : Colors.blue.shade800,
                                ),
                              ),
                            ],
                          ),

                          // Right side - Change button when expanded, arrow icon
                          Row(
                            children: [
                              if (_isTripInfoVisible)
                                TextButton.icon(
                                  onPressed: clearDestination,
                                  icon: Icon(Icons.edit_location_alt, size: 16),
                                  label: Text('CHANGE'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.blue,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                ),
                              SizedBox(width: 8),
                              Icon(
                                _isTripInfoVisible
                                    ? Icons.keyboard_arrow_down
                                    : Icons.keyboard_arrow_up,
                                color: Colors.grey.shade600,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Expanded information (hidden when collapsed)
                  if (_isTripInfoVisible)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // From location
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.my_location,
                                  color: Colors.blue,
                                  size: 16,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'From',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _pickup ?? 'Current Location',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Connecting line
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Container(
                              height: 20,
                              width: 1,
                              color: Colors.grey.shade300,
                            ),
                          ),

                          // To location
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 16,
                                ),
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'To',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _destination!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Route information section
                          SizedBox(height: 16),
                          Container(
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                // Route type badge with overflow handling
                                Container(
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  child: Container(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width -
                                          80,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade700,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.bolt,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                        SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            _routeType,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(height: 10),
                                // Route details - Modified to show only Distance and Duration
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    // Distance
                                    Column(
                                      children: [
                                        Icon(
                                          Icons.route,
                                          color: Colors.blue.shade700,
                                          size: 18,
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          _distance != null
                                              ? _formatDistance(_distance!)
                                              : 'Calculating...',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          'Distance',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Duration with countdown or Arrived status
                                    Column(
                                      children: [
                                        Icon(
                                          _distance != null &&
                                                  _distance! <= 0.05
                                              ? Icons.check_circle
                                              : Icons.access_time,
                                          color:
                                              _distance != null &&
                                                      _distance! <= 0.05
                                                  ? Colors.green.shade700
                                                  : Colors.blue.shade700,
                                          size: 18,
                                        ),
                                        SizedBox(height: 4),
                                        Column(
                                          children: [
                                            Text(
                                              _distance != null &&
                                                      _distance! <= 0.05
                                                  ? "Arrived" // Change the main text to "Arrived" instead of showing duration
                                                  : (_routeDuration.isNotEmpty
                                                      ? _routeDuration
                                                      : 'Calculating...'),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color:
                                                    _distance != null &&
                                                            _distance! <= 0.05
                                                        ? Colors.green.shade700
                                                        : Colors.black,
                                              ),
                                            ),
                                            // Only show countdown if NOT arrived
                                            if (_distance == null ||
                                                _distance! > 0.05)
                                              if (_countdownText.isNotEmpty)
                                                GestureDetector(
                                                  onTap: _resetCountdown,
                                                  child: Container(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors
                                                              .orange
                                                              .shade100,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            4,
                                                          ),
                                                      border: Border.all(
                                                        color:
                                                            Colors
                                                                .orange
                                                                .shade300,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          _countdownText,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 12,
                                                            color:
                                                                Colors
                                                                    .orange
                                                                    .shade800,
                                                          ),
                                                        ),
                                                        SizedBox(width: 2),
                                                        Icon(
                                                          Icons.edit_outlined,
                                                          size: 10,
                                                          color:
                                                              Colors
                                                                  .orange
                                                                  .shade800,
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ),
                                        Text(
                                          _distance != null &&
                                                  _distance! <= 0.05
                                              ? 'Status'
                                              : 'Duration',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    // Traffic icon (always on, not toggleable)
                                    Column(
                                      children: [
                                        Icon(
                                          Icons.traffic,
                                          color: Colors.orange,
                                          size: 18,
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Active',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 16,
                                            color: Colors.orange,
                                          ),
                                        ),
                                        Text(
                                          'Traffic',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        _distance != null && _distance! <= 0.05
                                            ? Colors.green.shade100
                                            : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          _distance != null &&
                                                  _distance! <= 0.05
                                              ? Colors.green.shade300
                                              : Colors.green.shade100,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _distance != null && _distance! <= 0.05
                                            ? Icons.check_circle
                                            : Icons.flag,
                                        color: Colors.green.shade700,
                                        size: 16,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        _distance != null && _distance! <= 0.05
                                            ? 'You have arrived at your destination!'
                                            : _estimatedArrivalTime != null
                                            ? 'ETA: ${_formatArrivalTime(_estimatedArrivalTime!)}'
                                            : 'Calculating arrival time...',
                                        style: TextStyle(
                                          color: Colors.green.shade800,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Only show the loading indicator when directions are loading
                          if (_isLoadingDirections)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.blue.shade100,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.blue,
                                            ),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Finding fastest route...',
                                      style: TextStyle(
                                        color: Colors.blue.shade800,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
