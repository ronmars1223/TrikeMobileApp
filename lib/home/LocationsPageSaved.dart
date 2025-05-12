import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';

class LocationsPageSaved extends StatefulWidget {
  @override
  _LocationsPageSavedState createState() => _LocationsPageSavedState();
}

class _LocationsPageSavedState extends State<LocationsPageSaved> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: FirebaseDatabase.instance.app,
    databaseURL:
        'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );

  // Blue color palette
  final Color primaryBlue = Color(0xFF2962FF); // Primary blue
  final Color lightBlue = Color(0xFF82B1FF); // Light blue
  final Color darkBlue = Color(0xFF0039CB); // Dark blue
  final Color accentBlue = Color(0xFF448AFF); // Accent blue
  final Color backgroundBlue = Color(
    0xFFE3F2FD,
  ); // Very light blue for backgrounds

  List<Map<String, dynamic>> _savedLocations = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchSavedLocations();
  }

  Future<void> _fetchSavedLocations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      User? user = _auth.currentUser;
      if (user != null) {
        DatabaseReference locationsRef = _database.ref(
          'saved_locations/${user.uid}',
        );
        final snapshot = await locationsRef.get();

        List<Map<String, dynamic>> locations = [];
        if (snapshot.exists) {
          Map<dynamic, dynamic>? locationsMap =
              snapshot.value as Map<dynamic, dynamic>?;

          if (locationsMap != null) {
            locationsMap.forEach((key, value) {
              if (value is Map<dynamic, dynamic>) {
                locations.add({
                  'id': key,
                  'name': value['name'] ?? 'Unnamed Location',
                  'address': value['address'] ?? '',
                  'latitude': value['latitude'] ?? 0.0,
                  'longitude': value['longitude'] ?? 0.0,
                  'timestamp':
                      value['timestamp'] ??
                      DateTime.now().millisecondsSinceEpoch,
                  'type': value['type'] ?? 'other',
                  'isFavorite': value['isFavorite'] ?? false,
                });
              }
            });
          }
        }

        // Sort locations: favorites first, then by recency
        locations.sort((a, b) {
          if (a['isFavorite'] && !b['isFavorite']) return -1;
          if (!a['isFavorite'] && b['isFavorite']) return 1;
          return (b['timestamp'] as int).compareTo(a['timestamp'] as int);
        });

        setState(() {
          _savedLocations = locations;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'You must be logged in to view saved locations.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading saved locations: ${e.toString()}';
        _isLoading = false;
      });
      print('Error loading saved locations: $e');
    }
  }

  void _showAddLocationDialog() async {
    try {
      // First, get the current location
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Create a controller for name with a generic name
      TextEditingController nameController = TextEditingController(
        text: 'Saved Location',
      );
      String selectedLocationType = 'home';

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(
                  'Add Current Location',
                  style: TextStyle(
                    color: primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Location Name',
                          hintText: 'e.g. My Home, Office',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: lightBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(
                              color: primaryBlue,
                              width: 2,
                            ),
                          ),
                          prefixIcon: Icon(
                            Icons.edit_location_alt,
                            color: primaryBlue,
                          ),
                          labelStyle: TextStyle(color: primaryBlue),
                        ),
                      ),
                      SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: selectedLocationType,
                        decoration: InputDecoration(
                          labelText: 'Location Type',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(color: lightBlue),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide(
                              color: primaryBlue,
                              width: 2,
                            ),
                          ),
                          labelStyle: TextStyle(color: primaryBlue),
                        ),
                        iconEnabledColor: primaryBlue,
                        items: [
                          DropdownMenuItem(child: Text('Home'), value: 'home'),
                          DropdownMenuItem(child: Text('Work'), value: 'work'),
                          DropdownMenuItem(
                            child: Text('School'),
                            value: 'school',
                          ),
                          DropdownMenuItem(
                            child: Text('Favorite'),
                            value: 'favorite',
                          ),
                          DropdownMenuItem(
                            child: Text('Other'),
                            value: 'other',
                          ),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            selectedLocationType = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  ElevatedButton(
                    child: Text('Save Location'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      _saveCurrentLocation(
                        nameController.text,
                        selectedLocationType,
                        position,
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } catch (e) {
      // Handle location retrieval error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error retrieving current location: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _saveCurrentLocation(
    String name,
    String locationType,
    Position position,
  ) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Create address with coordinates
      String address =
          'Coordinates: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';

      // Try to get more detailed address if possible
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address =
              '${place.street}, ${place.subLocality}, ${place.locality}, ${place.administrativeArea}';
        }
      } catch (e) {
        // If geocoding fails, keep the coordinate-based address
        print('Geocoding error: $e');
      }

      // Save to Firebase
      User? user = _auth.currentUser;
      if (user != null) {
        DatabaseReference locationsRef = _database.ref(
          'saved_locations/${user.uid}',
        );

        // Generate a unique key
        DatabaseReference newLocationRef = locationsRef.push();

        await newLocationRef.set({
          'name': name.isNotEmpty ? name : 'Saved Location',
          'address': address,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'type': locationType,
          'isFavorite': locationType == 'favorite',
        });

        // Refresh the list
        _fetchSavedLocations();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 10),
                Expanded(child: Text('Location saved successfully')),
              ],
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'You must be logged in to save locations.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error saving location: ${e.toString()}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save location: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      print('Error saving location: $e');
    }
  }

  void _showLocationDetailsDialog(Map<String, dynamic> location) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                boxShadow: [
                  BoxShadow(
                    color: primaryBlue.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 50,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              location['name'],
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: darkBlue,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundBlue,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: lightBlue),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getIconForLocationType(location['type']),
                              size: 18,
                              color: primaryBlue,
                            ),
                            SizedBox(width: 8),
                            Text(
                              _getLocationTypeLabel(location['type']),
                              style: TextStyle(
                                fontSize: 14,
                                color: primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Address',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: darkBlue,
                        ),
                      ),
                      SizedBox(height: 6),
                      Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: backgroundBlue.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: lightBlue.withOpacity(0.5)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: accentBlue,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                location['address'],
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 24),
                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: lightBlue),
                          boxShadow: [
                            BoxShadow(
                              color: primaryBlue.withOpacity(0.1),
                              blurRadius: 8,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(
                                  location['latitude'],
                                  location['longitude'],
                                ),
                                zoom: 15,
                              ),
                              markers: {
                                Marker(
                                  markerId: MarkerId('selected_location'),
                                  position: LatLng(
                                    location['latitude'],
                                    location['longitude'],
                                  ),
                                  icon: BitmapDescriptor.defaultMarkerWithHue(
                                    BitmapDescriptor.hueAzure,
                                  ),
                                ),
                              },
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                              myLocationButtonEnabled: false,
                            ),
                            Positioned(
                              top: 10,
                              right: 10,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    Icons.fullscreen,
                                    color: primaryBlue,
                                  ),
                                  onPressed: () {
                                    // Expand map view
                                  },
                                  tooltip: 'Expand Map',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 18),
                      Center(
                        child: TextButton.icon(
                          icon: Icon(Icons.delete, color: Colors.red),
                          label: Text(
                            'Delete Location',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _showDeleteConfirmationDialog(location);
                          },
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openInMaps(Map<String, dynamic> location) {
    // This would typically use a plugin like url_launcher
    // to open the coordinates in a maps application
    print(
      'Opening location in maps: ${location['latitude']}, ${location['longitude']}',
    );

    // Example implementation:
    // final url = 'https://www.google.com/maps/search/?api=1&query=${location['latitude']},${location['longitude']}';
    // launch(url);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.map, color: Colors.white),
            SizedBox(width: 10),
            Text('Opening location in maps...'),
          ],
        ),
        backgroundColor: primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _bookRideToLocation(Map<String, dynamic> location) {
    // This would navigate to your ride booking screen with
    // the destination pre-filled using this location
    print(
      'Booking ride to: ${location['name']} at ${location['latitude']}, ${location['longitude']}',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.local_taxi, color: Colors.white),
            SizedBox(width: 10),
            Text('Redirecting to ride booking...'),
          ],
        ),
        backgroundColor: primaryBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showDeleteConfirmationDialog(Map<String, dynamic> location) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Delete Location',
            style: TextStyle(color: darkBlue, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_forever, color: Colors.red, size: 60),
              SizedBox(height: 16),
              Text(
                'Are you sure you want to delete "${location['name']}"?',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'This action cannot be undone.',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          actions: [
            TextButton(
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteLocation(location['id']);
              },
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteLocation(String locationId) async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        await _database.ref('saved_locations/${user.uid}/$locationId').remove();

        // Update local list
        setState(() {
          _savedLocations.removeWhere(
            (location) => location['id'] == locationId,
          );
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location deleted successfully'),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete location: ${e.toString()}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      print('Error deleting location: $e');
    }
  }

  IconData _getIconForLocationType(String type) {
    switch (type) {
      case 'home':
        return Icons.home;
      case 'work':
        return Icons.work;
      case 'school':
        return Icons.school;
      case 'favorite':
        return Icons.favorite;
      default:
        return Icons.place;
    }
  }

  String _getLocationTypeLabel(String type) {
    switch (type) {
      case 'home':
        return 'Home';
      case 'work':
        return 'Work';
      case 'school':
        return 'School';
      case 'favorite':
        return 'Favorite';
      default:
        return 'Other';
    }
  }

  Color _getLocationTypeColor(String type) {
    // Return different blue shades based on location type
    switch (type) {
      case 'home':
        return Color(0xFF1565C0); // Dark blue
      case 'work':
        return Color(0xFF0288D1); // Medium blue
      case 'school':
        return Color(0xFF039BE5); // Light blue
      case 'favorite':
        return Color(0xFF00B0FF); // Bright blue
      default:
        return Color(0xFF0277BD); // Default blue
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Saved Locations',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryBlue,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
        // Make back button white
        iconTheme: IconThemeData(color: Colors.white),
        // For Android back button
        leading:
            Navigator.canPop(context)
                ? IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                )
                : null,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchSavedLocations,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          image: DecorationImage(
            image: AssetImage(
              'assets/map_pattern.png',
            ), // Add this asset to your project
            opacity: 0.05,
            fit: BoxFit.cover,
          ),
        ),
        child:
            _isLoading
                ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(primaryBlue),
                        strokeWidth: 3,
                      ),
                      SizedBox(height: 16),
                      Text(
                        'Loading your locations...',
                        style: TextStyle(
                          color: darkBlue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
                : _errorMessage.isNotEmpty
                ? _buildErrorState()
                : _savedLocations.isEmpty
                ? _buildEmptyState()
                : _buildLocationsList(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLocationDialog,
        icon: Icon(Icons.add_location_alt),
        label: Text('Add Location'),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 56,
                color: Colors.red[700],
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: darkBlue,
              ),
            ),
            SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _fetchSavedLocations,
              icon: Icon(Icons.refresh),
              label: Text(
                'Try Again',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: backgroundBlue,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.location_off,
                size: 80,
                color: primaryBlue.withOpacity(0.7),
              ),
            ),
            SizedBox(height: 32),
            Text(
              'No Saved Locations',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: darkBlue,
              ),
            ),
            SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                'Your saved locations will appear here. Save your favorite places for quick access anytime!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  height: 1.5,
                ),
              ),
            ),
            SizedBox(height: 40),
            ElevatedButton.icon(
              icon: Icon(Icons.add_location, size: 22),
              label: Text(
                'Add Current Location',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              onPressed: _showAddLocationDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 3,
                shadowColor: primaryBlue.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationsList() {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        80,
      ), // Add bottom padding for FAB
      itemCount: _savedLocations.length,
      itemBuilder: (context, index) {
        final location = _savedLocations[index];
        final bool isFavorite = location['isFavorite'] as bool;
        final locationType = location['type'] as String;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: primaryBlue.withOpacity(0.08),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showLocationDetailsDialog(location),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _getLocationTypeColor(
                                locationType,
                              ).withOpacity(0.7),
                              _getLocationTypeColor(locationType),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _getLocationTypeColor(
                                locationType,
                              ).withOpacity(0.3),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          _getIconForLocationType(locationType),
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    location['name'],
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: darkBlue,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isFavorite)
                                  Container(
                                    padding: EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.favorite,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: accentBlue,
                                ),
                                SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    location['address'],
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  icon: Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: accentBlue,
                                  ),
                                  label: Text(
                                    'Details',
                                    style: TextStyle(
                                      color: accentBlue,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                  onPressed:
                                      () =>
                                          _showLocationDetailsDialog(location),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 0,
                                    ),
                                    minimumSize: Size(0, 0),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
