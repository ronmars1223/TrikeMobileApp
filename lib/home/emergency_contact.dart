import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class EmergencyContactsPage extends StatefulWidget {
  @override
  _EmergencyContactsPageState createState() => _EmergencyContactsPageState();
}

class _EmergencyContactsPageState extends State<EmergencyContactsPage> {
  final FirebaseDatabase _database = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL:
        'https://capstone-33ff5-default-rtdb.asia-southeast1.firebasedatabase.app/',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> contacts = [];
  final _formKey = GlobalKey<FormState>();
  final _connectFormKey = GlobalKey<FormState>();

  // Controllers for text fields
  final TextEditingController nameController = TextEditingController();
  final TextEditingController numberController = TextEditingController();
  final TextEditingController connectPhoneController = TextEditingController();

  // Get current user
  User? get user => _auth.currentUser;
  bool _isLoading = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    nameController.dispose();
    numberController.dispose();
    connectPhoneController.dispose();
    super.dispose();
  }

  // Load contacts from Firebase using UID as the key
  Future<void> _loadContacts() async {
    if (user == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Reference directly to the user's emergency contacts
      final ref = _database.ref("emergency_contacts/${user!.uid}");
      final snapshot = await ref.get();

      List<Map<String, dynamic>> loadedContacts = [];

      if (snapshot.exists) {
        Map<dynamic, dynamic>? values = snapshot.value as Map?;
        if (values != null) {
          values.forEach((contactKey, contactValue) {
            if (contactValue is Map) {
              loadedContacts.add({
                'id': contactKey,
                'name': contactValue['name'] ?? '',
                'phone': contactValue['phone'] ?? '',
                'status_activate': contactValue['status_activate'] ?? true,
                'is_connected_user': contactValue['is_connected_user'] ?? false,
                'connected_uid': contactValue['connected_uid'],
              });
            }
          });
        }
      }

      setState(() {
        contacts = loadedContacts;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading contacts: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load contacts: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  // This helper method should be added outside the _showConnectedUserDetails method
  Widget _buildLocationMap(double latitude, double longitude) {
    // Define the initial camera position using the provided coordinates
    final CameraPosition initialPosition = CameraPosition(
      target: LatLng(latitude, longitude),
      zoom: 15.0,
    );

    // Create a set for map markers
    final Set<Marker> markers = {
      Marker(
        markerId: MarkerId('userLocation'),
        position: LatLng(latitude, longitude),
        infoWindow: InfoWindow(title: 'Current Location'),
      ),
    };

    // Return the map widget
    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GoogleMap(
          initialCameraPosition: initialPosition,
          markers: markers,
          mapType: MapType.normal,
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
        ),
      ),
    );
  }

  // Helper method to format timestamp
  String _formatTimestamp(String timestamp) {
    try {
      final int? milliseconds = int.tryParse(timestamp);
      if (milliseconds != null) {
        // Convert to DateTime
        final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
        );
        // Format the date and time
        return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
      }
      return timestamp;
    } catch (e) {
      return timestamp;
    }
  }

  Future<void> _showConnectedUserDetails(String connectedUid) async {
    if (connectedUid == null || connectedUid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No connected user information available'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Reference to the user in Firebase
      final userRef = _database.ref("users/$connectedUid");
      final snapshot = await userRef.get();

      if (snapshot.exists) {
        Map<dynamic, dynamic>? userData = snapshot.value as Map?;

        if (userData != null) {
          // Extract user details
          String? firstName =
              userData['firstName'] ??
              userData['first_name'] ??
              (userData['emergency_alerts'] is Map
                  ? userData['emergency_alerts']['firstName']
                  : null);

          String? lastName =
              userData['lastName'] ??
              userData['last_name'] ??
              (userData['emergency_alerts'] is Map
                  ? userData['emergency_alerts']['lastName']
                  : null);

          String? email = userData['email'];

          String? mobile;
          // Try to find mobile number in different possible locations
          if (userData.containsKey('mobile')) {
            mobile = userData['mobile'];
          } else if (userData.containsKey('current_location') &&
              userData['current_location'] is Map &&
              userData['current_location'].containsKey('mobile')) {
            mobile = userData['current_location']['mobile'];
          }

          String? fullAddress;
          // Try to find address in different possible locations
          if (userData.containsKey('full_address')) {
            fullAddress = userData['full_address'];
          } else if (userData.containsKey('current_location') &&
              userData['current_location'] is Map &&
              userData['current_location'].containsKey('full_address')) {
            fullAddress = userData['current_location']['full_address'];
          }

          // Extract location data
          double? latitude;
          double? longitude;
          double? accuracy;
          double? speed;
          String? timestamp;

          if (userData.containsKey('current_location') &&
              userData['current_location'] is Map) {
            final locationData = userData['current_location'];

            // Parse latitude and longitude
            if (locationData.containsKey('latitude')) {
              latitude = double.tryParse(locationData['latitude'].toString());
            }

            if (locationData.containsKey('longitude')) {
              longitude = double.tryParse(locationData['longitude'].toString());
            }

            // Parse additional location data
            if (locationData.containsKey('accuracy')) {
              accuracy = double.tryParse(locationData['accuracy'].toString());
            }

            if (locationData.containsKey('speed')) {
              speed = double.tryParse(locationData['speed'].toString());
            }

            if (locationData.containsKey('timestamp')) {
              timestamp = locationData['timestamp'].toString();
            }
          }

          // Show dialog with user details
          showDialog(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: Text(
                    'User Details',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (firstName != null || lastName != null)
                          ListTile(
                            leading: Icon(Icons.person, color: Colors.blue),
                            title: Text('Name'),
                            subtitle: Text(
                              '${firstName ?? ''} ${lastName ?? ''}',
                            ),
                            dense: true,
                          ),
                        if (mobile != null)
                          ListTile(
                            leading: Icon(Icons.phone, color: Colors.green),
                            title: Text('Phone'),
                            subtitle: Text(mobile),
                            dense: true,
                          ),
                        if (email != null)
                          ListTile(
                            leading: Icon(Icons.email, color: Colors.red),
                            title: Text('Email'),
                            subtitle: Text(email),
                            dense: true,
                          ),
                        if (fullAddress != null)
                          ListTile(
                            leading: Icon(
                              Icons.location_on,
                              color: Colors.orange,
                            ),
                            title: Text('Address'),
                            subtitle: Text(fullAddress),
                            dense: true,
                          ),

                        // Add location map and details
                        if (latitude != null && longitude != null) ...[
                          Divider(),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Current Location',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),

                          // Map widget
                          _buildLocationMap(latitude, longitude),

                          SizedBox(height: 8),

                          // Location details in tiles
                          ListTile(
                            leading: Icon(Icons.place, color: Colors.red),
                            title: Text('Coordinates'),
                            subtitle: Text(
                              '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                            ),
                            dense: true,
                          ),

                          if (accuracy != null)
                            ListTile(
                              leading: Icon(
                                Icons.my_location,
                                color: Colors.blue,
                              ),
                              title: Text('Accuracy'),
                              subtitle: Text(
                                '${accuracy.toStringAsFixed(2)} meters',
                              ),
                              dense: true,
                            ),

                          if (speed != null)
                            ListTile(
                              leading: Icon(Icons.speed, color: Colors.green),
                              title: Text('Speed'),
                              subtitle: Text('${speed.toStringAsFixed(2)} m/s'),
                              dense: true,
                            ),

                          if (timestamp != null)
                            ListTile(
                              leading: Icon(
                                Icons.access_time,
                                color: Colors.orange,
                              ),
                              title: Text('Last Updated'),
                              subtitle: Text(_formatTimestamp(timestamp)),
                              dense: true,
                            ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'CLOSE',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('User data is not available'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error fetching user details: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load user details: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Add a new contact using user UID as the key
  Future<void> _addContact() async {
    if (_formKey.currentState!.validate() && user != null) {
      try {
        setState(() {
          _isLoading = true;
        });

        // Reference directly to the user's emergency contacts node using UID
        DatabaseReference contactsRef = _database.ref(
          "emergency_contacts/${user!.uid}",
        );

        // Use push() to get a new unique key
        DatabaseReference newContactRef = contactsRef.push();

        // Get the key that push() created
        String? contactId = newContactRef.key;

        if (contactId == null) {
          throw Exception("Failed to generate a contact ID");
        }

        // Create the data to save
        Map<String, dynamic> contactData = {
          'name': nameController.text.trim(),
          'phone': numberController.text.trim(),
          'status_activate': true,
          'uid': user!.uid,
          'timestamp': ServerValue.timestamp,
        };

        // Set the data at the specific location
        await contactsRef.child(contactId).set(contactData);

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Emergency contact added successfully'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        nameController.clear();
        numberController.clear();

        // Close the dialog
        Navigator.pop(context);

        // Reload contacts
        await _loadContacts();
      } catch (e) {
        print('Error adding contact: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add contact: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // New method to connect with a user by phone number
  Future<void> _connectWithUser() async {
    if (_connectFormKey.currentState!.validate() && user != null) {
      try {
        setState(() {
          _isConnecting = true;
        });

        final phoneNumber = connectPhoneController.text.trim();

        // Reference to users in Firebase
        final usersRef = _database.ref("users");

        // Query to find users with matching phone number
        final usersSnapshot = await usersRef.get();

        if (usersSnapshot.exists) {
          Map<dynamic, dynamic>? usersData = usersSnapshot.value as Map?;
          String? foundUserId;
          String? foundUserName;

          if (usersData != null) {
            // Check each user
            for (var entry in usersData.entries) {
              final userId = entry.key;
              final userData = entry.value;

              // Check if this user has the mobile number we're looking for
              if (userData is Map) {
                // Try different paths where mobile might be stored based on your screenshot
                var mobileNumber = userData['mobile'];

                // If not found at the top level, check if it's in a nested structure
                if (mobileNumber == null &&
                    userData.containsKey('current_location')) {
                  final currentLocation = userData['current_location'];
                  if (currentLocation is Map &&
                      currentLocation.containsKey('mobile')) {
                    mobileNumber = currentLocation['mobile'];
                  }
                }

                if (mobileNumber == phoneNumber) {
                  foundUserId = userId.toString();

                  // Try to get the user's name from various possible locations
                  foundUserName =
                      userData['firstName'] ??
                      userData['first_name'] ??
                      (userData['emergency_alerts'] is Map
                          ? userData['emergency_alerts']['firstName']
                          : null) ??
                      'User';
                  break;
                }
              }
            }
          }

          if (foundUserId != null) {
            // User found - add as an emergency contact
            DatabaseReference contactsRef = _database.ref(
              "emergency_contacts/${user!.uid}",
            );

            // Create a new contact entry
            DatabaseReference newContactRef = contactsRef.push();
            String? contactId = newContactRef.key;

            if (contactId == null) {
              throw Exception("Failed to generate a contact ID");
            }

            // Create the contact data
            Map<String, dynamic> contactData = {
              'name': foundUserName ?? 'Connected User',
              'phone': phoneNumber,
              'status_activate': true,
              'uid': user!.uid,
              'connected_uid': foundUserId,
              'timestamp': ServerValue.timestamp,
              'is_connected_user': true,
            };

            // Add the contact
            await contactsRef.child(contactId).set(contactData);

            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('User connected successfully'),
                backgroundColor: Colors.green,
              ),
            );

            // Clear form and close dialog
            connectPhoneController.clear();
            Navigator.pop(context);

            // Reload contacts
            await _loadContacts();
          } else {
            // User not found
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('No user found with this phone number'),
                backgroundColor: Colors.orange,
              ),
            );
            setState(() {
              _isConnecting = false;
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('No users found in the database'),
              backgroundColor: Colors.red,
            ),
          );
          setState(() {
            _isConnecting = false;
          });
        }
      } catch (e) {
        print('Error connecting with user: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect with user: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isConnecting = false;
        });
      }
    }
  }

  // Delete a contact
  Future<void> _deleteContact(String contactId) async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Delete directly using the UID structure
      await _database
          .ref("emergency_contacts/${user!.uid}/$contactId")
          .remove();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contact deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Reload contacts
      await _loadContacts();
    } catch (e) {
      print('Error deleting contact: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete contact: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Build the contact form
  Widget _buildContactForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Name *',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: numberController,
            decoration: const InputDecoration(
              labelText: 'Phone Number *',
              prefixIcon: Icon(Icons.phone),
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a phone number';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  // Build the connect user form
  Widget _buildConnectUserForm() {
    return Form(
      key: _connectFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: connectPhoneController,
            decoration: const InputDecoration(
              labelText: 'Phone Number *',
              prefixIcon: Icon(Icons.phone),
              hintText: 'Enter user phone number',
            ),
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a phone number';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the phone number of the user you want to connect with.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Emergency Contacts',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white, // back button color
        ),
        backgroundColor: Colors.red,
      ),

      body:
          _isLoading
              ? Center(child: CircularProgressIndicator())
              : user == null
              ? Center(child: Text('Please log in to view emergency contacts'))
              : contacts.isEmpty
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.contact_phone,
                      size: 60,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No emergency contacts added yet',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap the + button to add a contact',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  final bool isConnectedUser =
                      contact['is_connected_user'] ?? false;
                  final String? connectedUid = contact['connected_uid'];

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    elevation: 2,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            isConnectedUser
                                ? Colors.blue[100]
                                : Colors.red[100],
                        child: Icon(
                          isConnectedUser ? Icons.people : Icons.person,
                          color: isConnectedUser ? Colors.blue : Colors.red,
                        ),
                      ),
                      title: Text(
                        contact['name'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.phone,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(contact['phone']),
                            ],
                          ),
                          if (isConnectedUser)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      'Connected User',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      // Add onTap to show user details if this is a connected user
                      onTap:
                          isConnectedUser && connectedUid != null
                              ? () => _showConnectedUserDetails(connectedUid)
                              : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder:
                                (context) => AlertDialog(
                                  title: const Text('Delete Contact'),
                                  content: Text(
                                    'Are you sure you want to delete ${contact['name']} from your emergency contacts?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('CANCEL'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        _deleteContact(contact['id']);
                                        Navigator.pop(context);
                                      },
                                      child: const Text(
                                        'DELETE',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),

      floatingActionButton:
          user == null || _isLoading
              ? null
              : Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Connect Users Button
                  FloatingActionButton.extended(
                    onPressed: () {
                      // Clear controller
                      connectPhoneController.clear();

                      // Show dialog with phone input
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder:
                            (context) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: const Text(
                                'Connect with a User',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 20,
                              ),
                              content: SingleChildScrollView(
                                child: _buildConnectUserForm(),
                              ),
                              actionsPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              actionsAlignment: MainAxisAlignment.end,
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child: const Text('CANCEL'),
                                ),
                                ElevatedButton(
                                  onPressed:
                                      _isConnecting ? null : _connectWithUser,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child:
                                      _isConnecting
                                          ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                          : const Text('CONNECT'),
                                ),
                              ],
                            ),
                      );
                    },
                    icon: const Icon(Icons.people, color: Colors.white),
                    label: const Text(
                      'Connect',
                      style: TextStyle(color: Colors.white),
                    ),
                    backgroundColor: Colors.blue,
                    heroTag: 'connectUsers',
                  ),
                  const SizedBox(width: 10), // Space between buttons
                  // Original Add Contact Button
                  FloatingActionButton(
                    onPressed: () {
                      nameController.clear();
                      numberController.clear();
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder:
                            (context) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: const Text(
                                'Add Emergency Contact',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 20,
                              ),
                              content: SingleChildScrollView(
                                child: _buildContactForm(),
                              ),
                              actionsPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              actionsAlignment: MainAxisAlignment.end,
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child: const Text('CANCEL'),
                                ),
                                ElevatedButton(
                                  onPressed: _addContact,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  child: const Text('ADD'),
                                ),
                              ],
                            ),
                      );
                    },
                    backgroundColor: Colors.red,
                    child: const Icon(Icons.add, color: Colors.white),
                    heroTag: 'addContact',
                  ),
                ],
              ),
    );
  }
}
