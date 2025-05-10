import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class UserDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> contact;
  final FirebaseDatabase database;

  const UserDetailsDialog({
    Key? key,
    required this.contact,
    required this.database,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (contact["uid"] != null) {
      return FutureBuilder<DatabaseEvent>(
        future: database.ref("users/${contact["uid"]}").once(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AlertDialog(
              content: Container(
                height: 100,
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.redAccent),
                  ),
                ),
              ),
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return _buildBasicInfoDialog(context);
          }

          var userData =
              snapshot.data!.snapshot.value as Map<dynamic, dynamic>?;
          if (userData == null) {
            return _buildBasicInfoDialog(context);
          }

          return _buildFullDetailsDialog(context, userData);
        },
      );
    } else {
      return _buildBasicInfoDialog(context);
    }
  }

  Widget _buildFullDetailsDialog(
      BuildContext context, Map<dynamic, dynamic> userData) {
    // Extract location data if available
    double? latitude;
    double? longitude;

    if (userData["current_location"] != null) {
      latitude = userData["current_location"]["latitude"];
      longitude = userData["current_location"]["longitude"];
    }

    return AlertDialog(
      title: Column(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.redAccent,
            child: Text(
              contact["name"][0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            contact["name"],
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(Icons.person, "First Name", userData["firstName"]),
            _buildInfoRow(
                Icons.person_outline, "Last Name", userData["lastName"]),
            _buildInfoRow(Icons.email, "Email", userData["email"]),
            _buildInfoRow(Icons.phone, "Phone", userData["mobile"]),
            _buildInfoRow(Icons.location_on, "Address", userData["address"]),
            if (userData["birthday"] != null)
              _buildInfoRow(Icons.cake, "Birthday", userData["birthday"]),
            if (userData["bloodType"] != null)
              _buildInfoRow(
                  Icons.water_drop, "Blood Type", userData["bloodType"]),
            if (userData["gender"] != null)
              _buildInfoRow(Icons.wc, "Gender", userData["gender"]),

            // Add map if location is available
            if (latitude != null && longitude != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                "Current Location",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(latitude, longitude),
                      zoom: 15,
                    ),
                    markers: {
                      Marker(
                        markerId: MarkerId('user_location'),
                        position: LatLng(latitude, longitude),
                        infoWindow: InfoWindow(
                          title: contact["name"],
                          snippet: userData["address"] ?? 'Current Location',
                        ),
                      ),
                    },
                    mapType: MapType.hybrid,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    myLocationButtonEnabled: false,
                    scrollGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                  ),
                ),
              ),
              if (userData["current_location"]["speed"] != null) ...[
                const SizedBox(height: 8),
                _buildInfoRow(Icons.speed, "Speed",
                    "${userData["current_location"]["speed"]} km/h"),
              ],
              if (userData["current_location"]["timestamp"] != null) ...[
                _buildInfoRow(
                    Icons.access_time,
                    "Last Updated",
                    _formatTimestamp(
                        userData["current_location"]["timestamp"])),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (latitude != null && longitude != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openFullMap(context, latitude!, longitude!, contact["name"],
                  userData["address"]);
            },
            child: const Text("View Full Map"),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }

  Widget _buildBasicInfoDialog(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.redAccent,
            child: Text(
              contact["name"][0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            contact["name"],
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow(Icons.phone, "Phone", contact["phone"]),
          _buildInfoRow(Icons.check_circle, "Status",
              contact["status_activate"] ? "Active" : "Inactive"),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("Close"),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, dynamic value) {
    if (value == null || value.toString().isEmpty)
      return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.redAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return "N/A";
    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp as int);
    return "${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute}";
  }

  void _openFullMap(BuildContext context, double latitude, double longitude,
      String name, String? address) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _FullMapView(
          latitude: latitude,
          longitude: longitude,
          name: name,
          address: address,
        ),
      ),
    );
  }
}

class _FullMapView extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String name;
  final String? address;

  const _FullMapView({
    required this.latitude,
    required this.longitude,
    required this.name,
    this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$name's Location"),
        backgroundColor: Colors.redAccent,
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(latitude, longitude),
          zoom: 15,
        ),
        markers: {
          Marker(
            markerId: MarkerId('user_location'),
            position: LatLng(latitude, longitude),
            infoWindow: InfoWindow(
              title: name,
              snippet: address ?? 'Current Location',
            ),
          ),
        },
        mapType: MapType.hybrid,
        myLocationButtonEnabled: false,
        compassEnabled: true,
        zoomControlsEnabled: true,
      ),
    );
  }
}
