import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'dart:async';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:math' as math;

// Import the separated classes
import 'local_prediction.dart';
import 'location_search.dart';
import 'suggestion_widget.dart';

class LocationInputPage extends StatefulWidget {
  final Function(String, String, LatLng?, LatLng?) onLocationConfirmed;
  final Map<String, dynamic>? driverData;

  LocationInputPage({
    required this.onLocationConfirmed,
    this.driverData,
  });

  @override
  _LocationInputPageState createState() => _LocationInputPageState();
}

class _LocationInputPageState extends State<LocationInputPage> {
  // Controllers and focus nodes
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  final FocusNode _pickupFocusNode = FocusNode();
  final FocusNode _destinationFocusNode = FocusNode();

  // Coordinates for the selected locations
  LatLng? _pickupCoordinates;
  LatLng? _destinationCoordinates;

  // State flags
  bool _isLoadingDestination = false;
  bool _loadingCurrentLocation = false;

  // Place predictions
  List<LocalPrediction> _pickupPredictions = [];
  List<LocalPrediction> _destinationPredictions = [];
  Timer? _debounce;

  // For location tracking
  StreamSubscription<Position>? _positionStream;

  // Get fixed data from service
  final List<LocalPrediction> _popularPlaces =
      LocationSuggestionService.getPopularPlaces();
  List<LocalPrediction> _recentPlaces = [];

  @override
  void initState() {
    super.initState();
    print("🚀 LocationInputPage initialized");
    _startLocationTracking();
    _fetchRideHistory();
    _setupTextFieldListeners();

    // Add default recent places
    _recentPlaces = LocationSuggestionService.getDefaultRecentPlaces();

    // Ensure predictions display properly by checking after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print("📱 Widget built, ready to show predictions");
    });
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _pickupFocusNode.dispose();
    _destinationFocusNode.dispose();
    _debounce?.cancel();
    _positionStream?.cancel();
    super.dispose();
  }

  // MARK: - Setup Methods

  void _setupTextFieldListeners() {
    // Destination input field listener with reduced debounce time
    _destinationController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), () {
        if (_destinationController.text.length > 1) {
          // Reduced minimum length to 2 characters
          print("Searching for: ${_destinationController.text}");
          _searchDestination(_destinationController.text);
        } else {
          setState(() {
            _destinationPredictions = [];
          });
        }
      });
    });

    _pickupController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        if (_pickupController.text.length > 2 &&
            _pickupController.text != "Current Location") {
          _searchPickup(_pickupController.text);
        } else {
          setState(() {
            _pickupPredictions = [];
          });
        }
      });
    });

    // Focus management
    _pickupFocusNode.addListener(() {
      if (!_pickupFocusNode.hasFocus) {
        setState(() {
          // Hide predictions when focus is lost
          _pickupPredictions = [];
        });
      }
    });

    _destinationFocusNode.addListener(() {
      if (_destinationFocusNode.hasFocus) {
        // Show recent and popular places when field gets focus
        if (_destinationController.text.length <= 1) {
          _showRecentAndPopularPlaces();
        } else {
          // Or filter based on current text
          _searchDestination(_destinationController.text);
        }
      }
      if (!_destinationFocusNode.hasFocus) {
        // Delay hiding predictions to allow for selection
        Future.delayed(Duration(milliseconds: 200), () {
          if (!_destinationFocusNode.hasFocus) {
            setState(() {
              _destinationPredictions = [];
            });
          }
        });
      }
    });

    // Set initial focus to the destination field after a short delay
    Future.delayed(Duration(milliseconds: 500), () {
      if (_pickupController.text.isNotEmpty &&
          _destinationController.text.isEmpty) {
        FocusScope.of(context).requestFocus(_destinationFocusNode);
      }
    });
  }

  // MARK: - Ride History Methods

  void _fetchRideHistory() async {
    final dbRef = FirebaseDatabase.instance.ref('ride_history');
    final snapshot = await dbRef.get();

    if (snapshot.exists) {
      final data = snapshot.value as Map<dynamic, dynamic>;
      final List<LocalPrediction> loadedHistory = [];
      int id = 100;

      data.forEach((key, value) {
        if (value['destination'] != null && value['destination'].isNotEmpty) {
          loadedHistory.add(
            LocalPrediction(
              placeId: "h${id++}",
              mainText: value['destination'] ?? '',
              secondaryText: "Recent trip",
              description: value['destination'] ?? '',
              coordinates: value['destination_lat'] != null &&
                      value['destination_lng'] != null
                  ? LatLng(value['destination_lat'], value['destination_lng'])
                  : LocationSearchService.defaultCoordinates,
              isRecent: true,
            ),
          );
        }
      });

      setState(() {
        if (loadedHistory.isNotEmpty) {
          _recentPlaces.addAll(loadedHistory);
          // Limit to most recent 5
          if (_recentPlaces.length > 5) {
            _recentPlaces = _recentPlaces.sublist(0, 5);
          }
        }
      });
    }
  }

  // MARK: - Location Methods

  Future<void> _startLocationTracking() async {
    setState(() {
      _loadingCurrentLocation = true;
    });

    try {
      // Check for location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _setDefaultPickupLocation();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _setDefaultPickupLocation();
        return;
      }

      // Get initial position
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      // Update location with initial position
      _updateLocationFromPosition(position);

      // Start listening to position updates
      _positionStream = Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen(_updateLocationFromPosition);
    } catch (e) {
      print("Error getting current location: $e");
      _setDefaultPickupLocation();
    }
  }

  void _updateLocationFromPosition(Position position) async {
    try {
      // Get address from coordinates
      List<Placemark> placemarks =
          await placemarkFromCoordinates(position.latitude, position.longitude);

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = _formatPickupAddress(place);

        setState(() {
          if (_pickupController.text == "Current Location" ||
              _pickupController.text.contains("Current Location") ||
              _pickupController.text.isEmpty) {
            _pickupController.text = address;
          }
          _pickupCoordinates = LatLng(position.latitude, position.longitude);
          _loadingCurrentLocation = false;
        });
      }
    } catch (e) {
      print("Error updating location: $e");
    }
  }

  String _formatPickupAddress(Placemark place) {
    List<String> addressParts = [];

    if (place.street != null && place.street!.isNotEmpty)
      addressParts.add(place.street!);

    if (place.subLocality != null && place.subLocality!.isNotEmpty)
      addressParts.add(place.subLocality!);

    if (place.locality != null && place.locality!.isNotEmpty)
      addressParts.add(place.locality!);

    return addressParts.isNotEmpty
        ? "Current Location: ${addressParts.join(", ")}"
        : "Current Location";
  }

  void _setDefaultPickupLocation() {
    setState(() {
      _pickupController.text = "Current Location";
      _pickupCoordinates = LocationSearchService.defaultCoordinates;
      _loadingCurrentLocation = false;
    });
  }

  void _useCurrentLocation() {
    setState(() {
      _loadingCurrentLocation = true;
    });

    _startLocationTracking();
  }

  // MARK: - Place Search Methods

  void _showRecentAndPopularPlaces() {
    setState(() {
      _isLoadingDestination = true;
    });

    // Simulate network delay for a more natural feel
    Future.delayed(Duration(milliseconds: 300), () {
      setState(() {
        // First show recent places, then popular places
        _destinationPredictions = [..._recentPlaces];

        // Add some popular places if we don't have enough recents
        if (_destinationPredictions.length < 5) {
          // Get random popular places to simulate variety
          final random = math.Random();
          final shuffledPopular = List<LocalPrediction>.from(_popularPlaces)
            ..shuffle(random);

          _destinationPredictions
              .addAll(shuffledPopular.take(5 - _destinationPredictions.length));
        }

        // Add a "search more" option at the end
        _destinationPredictions
            .add(LocationSuggestionService.getSearchMoreOption());

        _isLoadingDestination = false;
      });
    });
  }

  Future<void> _searchDestination(String query) async {
    setState(() {
      _isLoadingDestination = true;
    });

    // Step 1: Check local suggestions first (fast response)
    List<LocalPrediction> localResults =
        LocationSuggestionService.filterLocalSuggestions(
            query, _recentPlaces, _popularPlaces);

    // Limit to top results from local suggestions
    if (localResults.length > 3) {
      localResults = localResults.sublist(0, 3);
    }

    setState(() {
      _destinationPredictions = localResults;
    });

    // Step 2: Search online for more results
    try {
      List<LocalPrediction> searchResults =
          await LocationSearchService.searchLocations(query);

      setState(() {
        _destinationPredictions = localResults;
        if (searchResults.isNotEmpty) {
          _destinationPredictions.addAll(searchResults);
        }

        // Cap at 7 total results for UX
        if (_destinationPredictions.length > 7) {
          _destinationPredictions = _destinationPredictions.sublist(0, 7);
        }

        _isLoadingDestination = false;
      });

      print(
          "📍 Found ${_destinationPredictions.length} combined predictions for '$query'");
    } catch (e) {
      print("❌ Error searching locations: $e");
      setState(() {
        _isLoadingDestination = false;
      });
    }
  }

  Future<void> _searchPickup(String query) async {
    setState(() {
      _isLoadingDestination = true;
    });

    // Step 1: Check local suggestions first
    List<LocalPrediction> localResults =
        LocationSuggestionService.filterLocalSuggestions(
            query, _recentPlaces, _popularPlaces);

    // Limit to top results
    if (localResults.length > 3) {
      localResults = localResults.sublist(0, 3);
    }

    setState(() {
      _pickupPredictions = localResults;
    });

    // Step 2: Search online for more results
    try {
      List<LocalPrediction> searchResults =
          await LocationSearchService.searchLocations(query);

      setState(() {
        _pickupPredictions = localResults;
        if (searchResults.isNotEmpty) {
          _pickupPredictions.addAll(searchResults);
        }

        // Cap at 7 total results
        if (_pickupPredictions.length > 7) {
          _pickupPredictions = _pickupPredictions.sublist(0, 7);
        }

        _isLoadingDestination = false;
      });
    } catch (e) {
      print("❌ Error searching: $e");
      setState(() {
        _isLoadingDestination = false;
      });
    }
  }

  void _selectPickupPlace(LocalPrediction prediction) {
    setState(() {
      _pickupController.text =
          "${prediction.mainText}, ${prediction.secondaryText}";
      _pickupCoordinates = prediction.coordinates;
      _pickupPredictions = [];
    });

    // Stop location tracking when a manual location is selected
    _positionStream?.cancel();
  }

  void _selectDestinationPlace(LocalPrediction prediction) {
    // Check if this is the "Search more" option
    if (prediction.isSearchMore) {
      // Just focus on the input field to let user search more specific location
      FocusScope.of(context).requestFocus(_destinationFocusNode);
      return;
    }

    setState(() {
      _destinationController.text =
          "${prediction.mainText}, ${prediction.secondaryText}";
      _destinationCoordinates = prediction.coordinates;
      _destinationPredictions = [];
    });

    print(
        "Destination coordinates set: ${prediction.coordinates.latitude}, ${prediction.coordinates.longitude}");
  }

  // MARK: - Action Methods

  void _confirmLocation() async {
    if (_destinationController.text.isNotEmpty) {
      // Make sure coordinates are set
      if (_destinationCoordinates == null) {
        await _geocodeDestination(_destinationController.text);
      }

      // Make sure we have pickup coordinates
      if (_pickupCoordinates == null && _pickupController.text.isNotEmpty) {
        await _geocodePickup(_pickupController.text);
      }

      // Call the callback with the location data including coordinates
      widget.onLocationConfirmed(
        _pickupController.text,
        _destinationController.text,
        _pickupCoordinates,
        _destinationCoordinates,
      );
    } else {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a destination'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _geocodeDestination(String address) async {
    // Try to match text with our local predictions first
    LatLng? coordinates = LocationSearchService.matchTextWithPredictions(
        address, [..._recentPlaces, ..._popularPlaces]);

    if (coordinates != null) {
      setState(() {
        _destinationCoordinates = coordinates;
      });
      return;
    }

    // If no match found, try geocoding
    coordinates = await LocationSearchService.geocodeAddress(address);

    setState(() {
      _destinationCoordinates =
          coordinates ?? LocationSearchService.defaultCoordinates;
    });
  }

  Future<void> _geocodePickup(String address) async {
    // Try to match with local places first
    LatLng? coordinates = LocationSearchService.matchTextWithPredictions(
        address, [..._recentPlaces, ..._popularPlaces]);

    if (coordinates != null) {
      setState(() {
        _pickupCoordinates = coordinates;
      });
      return;
    }

    // If no match found, try geocoding
    coordinates = await LocationSearchService.geocodeAddress(address);

    setState(() {
      _pickupCoordinates =
          coordinates ?? LocationSearchService.defaultCoordinates;
    });
  }

  // MARK: - UI Components

  Widget _buildLocationInput({
    required TextEditingController controller,
    required FocusNode focusNode,
    required IconData icon,
    required Color iconColor,
    required String hintText,
    required bool isLoading,
    Widget? trailingButton,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        // Add subtle shadow for better UI
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 15),
          decoration: InputDecoration(
            border: InputBorder.none,
            prefixIcon: isLoading
                ? Container(
                    width: 20,
                    height: 20,
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                    ),
                  )
                : Icon(icon, color: iconColor),
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400),
            contentPadding: EdgeInsets.symmetric(vertical: 16),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      controller.clear();
                      setState(() {
                        if (controller == _pickupController) {
                          _pickupPredictions = [];
                          _pickupCoordinates = null;
                        } else {
                          _destinationPredictions = [];
                          _destinationCoordinates = null;
                        }
                      });
                    },
                  )
                : null,
          ),
          onTap: () {
            // When destination field is tapped, show recent/popular places
            if (controller == _destinationController) {
              if (controller.text.length <= 1) {
                _showRecentAndPopularPlaces();
              } else {
                _searchDestination(controller.text);
              }
            } else if (controller == _pickupController &&
                controller.text.length > 2) {
              _searchPickup(controller.text);
            }
          },
          onSubmitted: (value) async {
            if (value.isEmpty) return;

            if (controller == _destinationController) {
              _searchDestination(value);
              // Hide keyboard
              FocusScope.of(context).unfocus();
            } else if (controller == _pickupController) {
              _searchPickup(value);
              // Move focus to destination field
              FocusScope.of(context).requestFocus(_destinationFocusNode);
            }
          },
        ),
      ),
    );
  }

  Widget _buildMapPreview() {
    if (_destinationCoordinates == null || _pickupCoordinates == null) {
      return SizedBox.shrink();
    }

    return FadeIn(
      duration: Duration(milliseconds: 500),
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    (_pickupCoordinates!.latitude +
                            _destinationCoordinates!.latitude) /
                        2,
                    (_pickupCoordinates!.longitude +
                            _destinationCoordinates!.longitude) /
                        2,
                  ),
                  zoom: 12,
                ),
                markers: {
                  Marker(
                    markerId: MarkerId('pickup'),
                    position: _pickupCoordinates!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueBlue),
                  ),
                  Marker(
                    markerId: MarkerId('destination'),
                    position: _destinationCoordinates!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed),
                  ),
                },
                polylines: {
                  Polyline(
                    polylineId: PolylineId('route'),
                    points: [_pickupCoordinates!, _destinationCoordinates!],
                    color: Colors.blue,
                    width: 5,
                  ),
                },
                myLocationEnabled: false,
                compassEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                liteModeEnabled: true,
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Preview',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      ),
      // Set a max height constraint with extra space for predictions
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Stack(
        clipBehavior: Clip.none, // Important: Allow content to overflow
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Where do you want to go?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      constraints:
                          BoxConstraints.tightFor(width: 32, height: 32),
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.close, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Location inputs - with minimal padding
              Flexible(
                fit: FlexFit.loose,
                child: SingleChildScrollView(
                  padding:
                      EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 0),
                  physics: ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pickup location field with current location button
                      FadeInLeft(
                        duration: Duration(milliseconds: 300),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: _buildLocationInput(
                                controller: _pickupController,
                                focusNode: _pickupFocusNode,
                                icon: Icons.my_location,
                                iconColor: Colors.blue,
                                hintText: 'Pickup location',
                                isLoading: _loadingCurrentLocation,
                              ),
                            ),
                            // Current location button
                            Container(
                              margin: EdgeInsets.only(left: 8),
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: IconButton(
                                constraints: BoxConstraints.tightFor(
                                    width: 36, height: 36),
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                icon:
                                    Icon(Icons.gps_fixed, color: Colors.white),
                                onPressed: _useCurrentLocation,
                                tooltip: 'Use current location',
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Pickup predictions - Shown normally
                      if (_pickupPredictions.isNotEmpty)
                        LocationSuggestionWidget(
                          predictions: _pickupPredictions,
                          onTap: _selectPickupPlace,
                          iconColor: Colors.blue,
                        ),

                      // Dotted line connector
                      Padding(
                        padding: const EdgeInsets.only(left: 20),
                        child: SizedBox(
                          height: 20,
                          width: 2,
                          child: Column(
                            children: List.generate(
                              4,
                              (index) => Container(
                                width: 2,
                                height: 2,
                                margin: EdgeInsets.symmetric(vertical: 1),
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Destination field
                      FadeInLeft(
                        duration: Duration(milliseconds: 400),
                        delay: Duration(milliseconds: 100),
                        child: _buildLocationInput(
                          controller: _destinationController,
                          focusNode: _destinationFocusNode,
                          icon: Icons.location_on,
                          iconColor: Colors.red,
                          hintText: 'Where to?',
                          isLoading: _isLoadingDestination,
                        ),
                      ),

                      // This SizedBox creates space for the predictions to appear
                      // The height will depend on whether predictions are showing
                      SizedBox(
                          height: _destinationPredictions.isNotEmpty
                              ? (_destinationPredictions.length > 3
                                  ? 230
                                  : _destinationPredictions.length * 75)
                              : 0),

                      SizedBox(height: 16),

                      // Map preview
                      _buildMapPreview(),

                      SizedBox(height: 16),

                      // Confirm button
                      FadeInUp(
                        duration: Duration(milliseconds: 400),
                        child: ElevatedButton(
                          onPressed: _confirmLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            minimumSize: Size(double.infinity, 46),
                          ),
                          child: Text(
                            'CONFIRM RIDE',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Destination predictions dropdown - Positioned as an overlay
          if (_destinationPredictions.isNotEmpty)
            Positioned(
              top: 180, // Position right below the destination input field
              left: 16,
              right: 16,
              child: LocationSuggestionWidget(
                predictions: _destinationPredictions,
                onTap: _selectDestinationPlace,
                iconColor: Colors.red,
              ),
            ),

          // Loading indicator overlay
          if (_isLoadingDestination)
            Positioned(
              top: 180,
              left: 20,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 3,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading suggestions...',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
