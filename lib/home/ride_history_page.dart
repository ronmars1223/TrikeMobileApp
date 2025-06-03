import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';

class RideHistoryPage extends StatefulWidget {
  @override
  _RideHistoryPageState createState() => _RideHistoryPageState();
}

class _RideHistoryPageState extends State<RideHistoryPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        "https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/",
  );

  List<Map<String, dynamic>> _rideHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRideHistory();
  }

  Future<void> _loadRideHistory() async {
    setState(() {
      _isLoading = true;
    });

    User? user = _auth.currentUser;
    if (user != null) {
      try {
        List<Map<String, dynamic>> allHistory = [];

        // Load regular ride history from users/{uid}/ride_history
        DatabaseReference userHistoryRef = _database.ref(
          "users/${user.uid}/ride_history",
        );

        final userEvent = await userHistoryRef.orderByChild("timestamp").once();
        if (userEvent.snapshot.value != null) {
          Map<dynamic, dynamic> userValues = userEvent.snapshot.value as Map<dynamic, dynamic>;
          userValues.forEach((key, value) {
            if (value is Map) {
              Map<String, dynamic> ride = {};
              Map<dynamic, dynamic> valueMap = value as Map<dynamic, dynamic>;
              
              // Safely convert each field
              valueMap.forEach((k, v) {
                if (k != null) {
                  ride[k.toString()] = v;
                }
              });
              
              ride['id'] = key?.toString() ?? '';
              ride['source'] = 'user_history'; // Mark source for deletion logic
              allHistory.add(ride);
            }
          });
        }

        // Load emergency alerts from main ride_history node
        DatabaseReference mainHistoryRef = _database.ref("ride_history");
        final mainEvent = await mainHistoryRef.orderByChild("uid").equalTo(user.uid).once();
        
        if (mainEvent.snapshot.value != null) {
          Map<dynamic, dynamic> mainValues = mainEvent.snapshot.value as Map<dynamic, dynamic>;
          mainValues.forEach((key, value) {
            if (value is Map) {
              Map<String, dynamic> entry = {};
              Map<dynamic, dynamic> valueMap = value as Map<dynamic, dynamic>;
              
              // Safely convert each field
              valueMap.forEach((k, v) {
                if (k != null) {
                  entry[k.toString()] = v;
                }
              });
              
              entry['id'] = key?.toString() ?? '';
              entry['source'] = 'main_history'; // Mark source for deletion logic
              allHistory.add(entry);
            }
          });
        }

        // Sort by timestamp (descending order - newest first)
        allHistory.sort((a, b) {
          int timestampA = 0;
          int timestampB = 0;
          
          // Safely get timestamp values
          if (a['timestamp'] is int) {
            timestampA = a['timestamp'] as int;
          } else if (a['timestamp'] is String) {
            timestampA = int.tryParse(a['timestamp'] as String) ?? 0;
          }
          
          if (b['timestamp'] is int) {
            timestampB = b['timestamp'] as int;
          } else if (b['timestamp'] is String) {
            timestampB = int.tryParse(b['timestamp'] as String) ?? 0;
          }
          
          return timestampB.compareTo(timestampA);
        });

        setState(() {
          _rideHistory = allHistory;
          _isLoading = false;
        });
      } catch (e) {
        print("Error loading ride history: $e");
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Updated delete method to handle both sources
  Future<void> _deleteRideHistory(String rideId, String source) async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        DatabaseReference rideRef;
        
        if (source == 'user_history') {
          // Delete from users/{uid}/ride_history
          rideRef = _database.ref("users/${user.uid}/ride_history/$rideId");
        } else {
          // Delete from main ride_history
          rideRef = _database.ref("ride_history/$rideId");
        }

        await rideRef.remove();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('History entry deleted'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        await _loadRideHistory();
      } catch (e) {
        print("Error deleting ride history: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting history entry'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Updated confirmation dialog
  void _showDeleteConfirmation(String rideId, String source, String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${type == 'emergency_alert' ? 'Emergency Alert' : 'Ride History'}'),
        content: Text('Are you sure you want to delete this ${type == 'emergency_alert' ? 'emergency alert' : 'ride history'}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteRideHistory(rideId, source);
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Method to launch Google Maps
  Future<void> _launchMaps(String? mapsUrl) async {
    if (mapsUrl != null && mapsUrl.isNotEmpty) {
      try {
        final Uri url = Uri.parse(mapsUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open Google Maps')),
          );
        }
      } catch (e) {
        print('Error launching maps: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening Google Maps')),
        );
      }
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    int timestampInt = 0;
    
    if (timestamp is int) {
      timestampInt = timestamp;
    } else if (timestamp is String) {
      timestampInt = int.tryParse(timestamp) ?? 0;
    } else if (timestamp != null) {
      timestampInt = int.tryParse(timestamp.toString()) ?? 0;
    }
    
    if (timestampInt == 0) {
      return 'Unknown time';
    }
    
    DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(timestampInt);
    return DateFormat('MMM dd, yyyy - hh:mm a').format(dateTime);
  }

  // Helper method to build contacts details
  Widget _buildContactsDetails(Map<String, dynamic> contactsNotified) {
    List<dynamic> successfulContacts = [];
    List<dynamic> failedContacts = [];
    
    try {
      if (contactsNotified['successful'] is List) {
        successfulContacts = contactsNotified['successful'] as List<dynamic>;
      }
      if (contactsNotified['failed'] is List) {
        failedContacts = contactsNotified['failed'] as List<dynamic>;
      }
    } catch (e) {
      print('Error parsing contact details: $e');
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.only(left: 16),
      title: Text(
        'Contact Details',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade700,
        ),
      ),
      children: [
        // Successfully notified contacts
        if (successfulContacts.isNotEmpty) ...[
          Text(
            'Successfully Notified (${successfulContacts.length}):',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade700,
            ),
          ),
          SizedBox(height: 4),
          ...successfulContacts.map((contact) => Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(
                  contact['isAdmin'] == true ? Icons.admin_panel_settings : Icons.person,
                  size: 12,
                  color: Colors.green.shade600,
                ),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${contact['name']} (${contact['phone']})',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.green.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )).toList(),
          SizedBox(height: 8),
        ],
        
        // Failed contacts
        if (failedContacts.isNotEmpty) ...[
          Text(
            'Failed to Notify (${failedContacts.length}):',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
            ),
          ),
          SizedBox(height: 4),
          ...failedContacts.map((contact) => Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 12,
                  color: Colors.red.shade600,
                ),
                SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${contact['name']} (${contact['phone']}) - ${contact['message']}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.red.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ],
    );
  }

  // Helper method to safely get values from maps
  dynamic _getSafeValue(Map<String, dynamic>? map, String key, dynamic defaultValue) {
    if (map == null) return defaultValue;
    try {
      return map[key] ?? defaultValue;
    } catch (e) {
      return defaultValue;
    }
  }

  // Helper method to safely format coordinates
  String _formatCoordinate(dynamic coordinate) {
    if (coordinate == null) return 'Unknown';
    
    if (coordinate is double) {
      return coordinate.toStringAsFixed(6);
    } else if (coordinate is int) {
      return coordinate.toDouble().toStringAsFixed(6);
    } else if (coordinate is String) {
      double? parsed = double.tryParse(coordinate);
      return parsed?.toStringAsFixed(6) ?? 'Unknown';
    }
    
    return 'Unknown';
  }

  // Method to get appropriate icon for entry type
  IconData _getEntryIcon(Map<String, dynamic> entry) {
    String type = entry['type'] ?? 'regular_ride';
    switch (type) {
      case 'emergency_alert':
        return Icons.emergency;
      default:
        return Icons.car_rental;
    }
  }

  // Method to get appropriate color for entry type
  Color _getEntryColor(Map<String, dynamic> entry) {
    String type = entry['type'] ?? 'regular_ride';
    switch (type) {
      case 'emergency_alert':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          "Ride History",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue,
        centerTitle: true,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _rideHistory.isEmpty
              ? _buildEmptyState()
              : _buildHistoryList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 80, color: Colors.grey.shade300),
          SizedBox(height: 16),
          Text(
            'No history yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your ride history and emergency alerts will appear here',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(Icons.car_rental),
            label: Text("Book a Ride"),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      itemCount: _rideHistory.length,
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemBuilder: (context, index) {
        Map<String, dynamic> entry = _rideHistory[index];
        String entryType = entry['type'] ?? 'regular_ride';
        bool isEmergency = entryType == 'emergency_alert';
        
        return FadeInUp(
          duration: Duration(milliseconds: 300),
          delay: Duration(milliseconds: 50 * index),
          child: GestureDetector(
            onLongPress: () {
              _showDeleteConfirmation(
                entry['id'], 
                entry['source'], 
                entryType
              );
            },
            child: Card(
              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    colors: isEmergency 
                        ? [Colors.white, Colors.red.shade50]
                        : [Colors.white, Colors.blue.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: EdgeInsets.all(16),
                child: isEmergency 
                    ? _buildEmergencyAlert(entry)
                    : _buildRegularRide(entry),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmergencyAlert(Map<String, dynamic> alert) {
    // Safely extract nested maps with proper null checking
    Map<String, dynamic>? location;
    Map<String, dynamic>? smsResults;
    Map<String, dynamic>? user;
    Map<String, dynamic>? contactsNotified;
    
    // Safe extraction of location data
    try {
      if (alert['location'] != null && alert['location'] is Map) {
        location = Map<String, dynamic>.from(alert['location'] as Map);
      }
    } catch (e) {
      print('Error parsing location data: $e');
      location = null;
    }
    
    // Safe extraction of SMS results
    try {
      if (alert['sms_results'] != null && alert['sms_results'] is Map) {
        smsResults = Map<String, dynamic>.from(alert['sms_results'] as Map);
      }
    } catch (e) {
      print('Error parsing SMS results: $e');
      smsResults = null;
    }
    
    // Safe extraction of user data
    try {
      if (alert['user'] != null && alert['user'] is Map) {
        user = Map<String, dynamic>.from(alert['user'] as Map);
      }
    } catch (e) {
      print('Error parsing user data: $e');
      user = null;
    }

    // Safe extraction of contacts notified data
    try {
      if (alert['contacts_notified'] != null && alert['contacts_notified'] is Map) {
        contactsNotified = Map<String, dynamic>.from(alert['contacts_notified'] as Map);
      }
    } catch (e) {
      print('Error parsing contacts notified data: $e');
      contactsNotified = null;
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with emergency icon and timestamp
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.emergency,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                ),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMERGENCY ALERT',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _formatTimestamp(alert['timestamp']),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                alert['status'] ?? 'Completed',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        SizedBox(height: 16),

        // User information
        if (user != null && user['fullName'] != null && user['fullName'].toString().isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.person, color: Colors.grey.shade600, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alert sent by: ${user['fullName'].toString()}',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
        ],

        // SMS Results and Contact Details
        if (smsResults != null || contactsNotified != null) ...[
          Row(
            children: [
              Icon(Icons.sms, color: Colors.grey.shade600, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contacts notified: ${_getSafeValue(smsResults, 'sent_count', 0)} of ${_getSafeValue(smsResults, 'total_contacts', 0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          
          // Show detailed contact information if available
          if (contactsNotified != null) ...[
            SizedBox(height: 8),
            _buildContactsDetails(contactsNotified),
          ],
          
          SizedBox(height: 12),
        ],

        // Location information
        if (location != null) ...[
          Row(
            children: [
              Icon(Icons.location_on, color: Colors.red.shade600, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Location: ${_formatCoordinate(location['latitude'])}, ${_formatCoordinate(location['longitude'])}',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          
          if (_getSafeValue(location, 'maps_url', '').toString().isNotEmpty) ...[
            SizedBox(height: 8),
            Center(
              child: ElevatedButton.icon(
                onPressed: () => _launchMaps(_getSafeValue(location!, 'maps_url', '').toString()),
                icon: Icon(Icons.map, size: 16),
                label: Text('View on Google Maps'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],

        SizedBox(height: 12),
        Divider(color: Colors.grey.shade300),
        Text(
          'Long press to delete',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildRegularRide(Map<String, dynamic> ride) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date and Status
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                SizedBox(width: 6),
                Text(
                  _formatTimestamp(ride['timestamp']),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                ride['status'] ?? 'Completed',
                style: TextStyle(
                  color: Colors.green.shade800,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        SizedBox(height: 12),

        // Driver information (if available)
        if (_getSafeValue(ride, 'driverName', '').toString().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
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
                    size: 16,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _getSafeValue(ride, 'driverName', '').toString(),
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // From location
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
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
                    ride['pickup'] ?? 'Unknown location',
                    style: TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),

        // Dotted line connector
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: SizedBox(
            height: 20,
            width: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (index) => Container(
                  width: 2,
                  height: 3,
                  margin: EdgeInsets.symmetric(vertical: 1),
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ),
        ),

        // To location
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                shape: BoxShape.circle,
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
                    ride['destination'] ?? 'Unknown location',
                    style: TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: 12),
        Divider(color: Colors.grey.shade300),
        Text(
          'Long press to delete',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}